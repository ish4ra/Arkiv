/* Narrow single-volume RAR envelope admission. No compression/encoding algorithm.
   Layout reference: RAR technical notes and libarchive's BSD RAR readers. */
#include "ArkivRAR.h"
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
static uint16_t u16(const unsigned char *p) { return p[0] | (uint16_t)p[1]<<8; }
static uint32_t u32(const unsigned char *p) { return u16(p) | (uint32_t)u16(p+2)<<16; }
static int vint(const unsigned char *b,size_t n,size_t *p,uint64_t *v) {
    *v=0;
    for(unsigned shift=0;shift<64;shift+=7) {
        if(*p>=n)return 0;
        unsigned c=b[(*p)++];if(shift==63 && c>1)return 0;
        *v|=(uint64_t)(c&127)<<shift;if(!(c&128))return 1;
    }
    return 0;
}
#define V(value) do { if(!vint(h,hs,&p,&(value)))goto corrupt; } while(0)
int arkiv_rar_scan(int fd,arkiv_limits limits,arkiv_cancel *token,int *version,int *missing,
                   arkiv_rar_item **items,size_t *count) {
    unsigned char signature[8];struct stat st;
    *version=0;*missing=0;*count=0;if(items)*items=NULL;
    ssize_t got=pread(fd,signature,8,0);
    if(got<7 || memcmp(signature,"Rar!\x1a\x07",6))return 0;
    if(signature[6]==0)*version=4;
    else if(got==8 && signature[6]==1 && signature[7]==0)*version=5;
    else return 8;
    if(fstat(fd,&st)||st.st_size<0)return 6;
    uint64_t size=(uint64_t)st.st_size,offset=*version==4?7:8,total=0;
    uint64_t header_bytes=0;unsigned blocks=0,main_seen=0;int result=6;unsigned char *h=NULL;
    while(offset<size) {
        if(arkiv_cancel_is_set(token)){result=2;goto done;}
        if(++blocks>200000){result=8;goto done;}
        unsigned char prefix[16];size_t length=(size_t)(size-offset<16?size-offset:16);
        if(pread(fd,prefix,length,(off_t)offset)!=(ssize_t)length)goto done;
        uint64_t header=0,data=0,flags=0,type=0,extra=0,unpacked=0;size_t p=0,hs=0;
        arkiv_rar_item item={-1,-1,-1,-1,0,(unsigned)*version,0};int file=0;
        if(*version==4) {
            if(length<7)goto done;
            header=u16(prefix+5);if(header<7 || header>size-offset)goto done;
        } else {
            p=4;if(!vint(prefix,length,&p,&header)||header>2*1024*1024 || header<2 || header>size-offset-p)goto done;
            header+=p;
        }
        hs=(size_t)header;header_bytes+=header;if(header_bytes>(64ULL<<20)){result=8;goto done;}h=malloc(hs);if(!h){result=8;goto done;}
        if(pread(fd,h,hs,(off_t)offset)!=(ssize_t)hs)goto done;
        if(*version==4) {
            if((crc32(0,h+2,(uInt)hs-2)&0xffff)!=u16(h))goto done;
            type=h[2];flags=u16(h+3);
            if(flags&0x8000){if(hs<11)goto done;data=u32(h+7);}
            if(type==0x73) {
                if(main_seen++ || hs<13)goto done;
                if(flags&1){result=10;goto done;}
                if(flags&(0x80|8)){result=8;goto done;} // header encryption / solid
            } else if(type==0x74) {
                if(!main_seen || hs<32)goto done;
                file=1;
                if(flags&3){result=10;goto done;}
                if(flags&(4|16)){result=8;goto done;} // data encryption / solid
                data=u32(h+7);unpacked=u32(h+11);
                if(flags&0x100){if(hs<40)goto done;data|=(uint64_t)u32(h+32)<<32;unpacked|=(uint64_t)u32(h+36)<<32;}
                size_t base=(flags&0x100)?40:32;
                if(u16(h+26)>hs-base)goto done;
                item.directory=(flags&0xe0)==0xe0;item.method=h[25]-0x30;
                if(h[25]<0x30 || h[25]>0x35 || h[24]>29){result=8;goto done;}
                item.crc=u32(h+16);if(h[15]==3)item.mode=u32(h+28);else item.attributes=u32(h+28);
            } else if(type==0x7b) {
                if(flags&1){result=10;goto done;}
                if(main_seen && offset+header==size){result=0;goto done;}goto done;
            } else { result=8;goto done; } // service/recovery/opaque headers deferred
        } else {
            p=4;uint64_t ignored;V(ignored);
            if(crc32(0,h+4,(uInt)hs-4)!=u32(h))goto done;
            V(type);V(flags);if(flags&1)V(extra);if(flags&2)V(data);
            if(flags&0x18){result=10;goto done;}
            if(extra>hs-p)goto done;
            size_t extras=hs-(size_t)extra;
            if(type==1) {
                uint64_t mf;V(mf);if(main_seen++)goto done;
                if(mf&3){result=10;goto done;}if(mf&4){result=8;goto done;}
            } else if(type==2) {
                uint64_t ff,attr,compression,host,name;file=1;
                if(!main_seen)goto done;
                V(ff);V(unpacked);V(attr);if(ff&~7ULL){result=8;goto done;}
                item.directory=(ff&1)!=0;
                if(ff&2){if(hs-p<4)goto done;p+=4;}
                if(ff&4){if(hs-p<4)goto done;item.crc=u32(h+p);p+=4;}else if(!item.directory)*missing=1;
                V(compression);V(host);V(name);
                if(p>extras || name>extras-p)goto done;
                p+=(size_t)name;
                item.method=(unsigned)(compression>>7)&7;
                if((compression&~0x3f80ULL) || item.method>5 || ((compression>>10)&15)>7){result=8;goto done;} // version 0, non-solid, <=16 MiB window
                if(host==1)item.mode=(int64_t)attr;else if(host==0)item.attributes=(int64_t)attr;
                while(extra && extras<hs) {
                    p=extras;uint64_t es,et;V(es);if(es>hs-p || !es)goto done;
                    extras=p+(size_t)es;V(et);if(p>extras)goto done;
                    if(et==1){result=8;goto done;} // encryption record
                    if(et!=2 && et!=3 && et!=5 && et!=6){result=8;goto done;} // checksums, times, redirects, owner
                }
            } else if(type==4) {result=8;goto done;}
            else if(type==5) {
                uint64_t end;V(end);if(end&1){result=10;goto done;}
                if(main_seen && !data && offset+header==size){result=0;goto done;}goto done;
            } else {result=8;goto done;}
        }
        if(data>size-offset-header)goto done;
        if(file) {
            if(*count>=limits.max_entries || unpacked>limits.max_bytes-total){result=8;goto done;}
            total+=unpacked;item.packed=(int64_t)data;
            if(items){arkiv_rar_item *next=realloc(*items,(*count+1)*sizeof(item));if(!next){result=8;goto done;}*items=next;next[*count]=item;}
            (*count)++;
        }
        offset+=header+data;free(h);h=NULL;
    }
    goto done;
corrupt: result=6;
done: free(h);if(result && items){free(*items);*items=NULL;}return result;
}
