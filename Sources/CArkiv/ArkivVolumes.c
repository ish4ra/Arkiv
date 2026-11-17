#include "include/ArkivArchive.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>
#define VMAX 128
struct arkiv_volumes { int parent, fds[VMAX]; unsigned count; char *directory,*stem; struct stat stamps[VMAX], parent_stamp; uint64_t total; };
static int error(char *e,size_t n,int code,const char *s){if(e&&n)snprintf(e,n,"%s",s);return code;}
static int directory_open(const char *path) {
    if(!path||path[0]!='/')return -1;
    int fd=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC);char *copy=strdup(path+1),*save=NULL;
    if(!copy){if(fd>=0)close(fd);return -1;}
    for(char *p=strtok_r(copy,"/",&save);p&&fd>=0;p=strtok_r(NULL,"/",&save)) {
        if(!strcmp(p,".")||!strcmp(p,"..")){close(fd);fd=-1;break;}
        int next=openat(fd,p,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);close(fd);fd=next;
    }
    free(copy);return fd;
}
static int same(const struct stat *a,const struct stat *b) {
#ifdef __APPLE__
#define MT st_mtimespec
#define CT st_ctimespec
#else
#define MT st_mtim
#define CT st_ctim
#endif
    return a->st_dev==b->st_dev&&a->st_ino==b->st_ino&&a->st_size==b->st_size&&a->st_mode==b->st_mode&&a->st_nlink==b->st_nlink&&a->MT.tv_sec==b->MT.tv_sec&&a->MT.tv_nsec==b->MT.tv_nsec&&a->CT.tv_sec==b->CT.tv_sec&&a->CT.tv_nsec==b->CT.tv_nsec;
}
void arkiv_volumes_free(arkiv_volumes *v){if(!v)return;for(unsigned i=0;i<VMAX;i++)if(v->fds[i]>=0)close(v->fds[i]);if(v->parent>=0)close(v->parent);free(v->directory);free(v->stem);free(v);}
static int scan(arkiv_volumes *v,unsigned char seen[VMAX],arkiv_cancel *token,char *e,size_t cap) {
    int fd=openat(v->parent,".",O_RDONLY|O_DIRECTORY|O_CLOEXEC);DIR *d=fd<0?NULL:fdopendir(fd);
    if(!d){if(fd>=0)close(fd);return error(e,cap,1,"Cannot read the volume directory. Grant access to its containing folder.");}
    size_t prefix=strlen(v->stem);unsigned visited=0;int result=0;struct dirent *entry;
    errno=0;
    while((entry=readdir(d))) {
        if(arkiv_cancel_is_set(token)){result=2;break;}
        if(++visited>100000){result=error(e,cap,8,"Volume directory exceeds the discovery limit.");break;}
        const char *name=entry->d_name;
        if(strncasecmp(name,v->stem,prefix))continue;
        const char *suffix=name+prefix;size_t n=strlen(suffix);int numeric=n>0;
        for(size_t j=0;j<n;j++)if(suffix[j]<'0'||suffix[j]>'9')numeric=0;
        if(!numeric)continue;
        unsigned number=n==3?(unsigned)((suffix[0]-'0')*100+(suffix[1]-'0')*10+suffix[2]-'0'):0;
        if(n!=3||!number||number>VMAX||strncmp(name,v->stem,prefix)||seen[number-1]) {result=error(e,cap,8,"Unsupported or ambiguous split 7z numbering (use exact .7z.001 through .128 names).");break;}
        seen[number-1]=1;errno=0;
    }
    if(!result&&errno)result=error(e,cap,1,"Cannot enumerate the volume directory.");
    closedir(d);return result;
}
int arkiv_volumes_validate(arkiv_volumes *v,arkiv_cancel *token,char *e,size_t cap) {
    if(!v)return 1;
    int fd=directory_open(v->directory);struct stat p;
    int good=fd>=0&&!fstat(fd,&p)&&p.st_dev==v->parent_stamp.st_dev&&p.st_ino==v->parent_stamp.st_ino;
    if(fd>=0)close(fd);
    if(!good)return error(e,cap,1,"Volume directory changed. Reopen the archive.");
    unsigned char seen[VMAX]={0};int code=scan(v,seen,token,e,cap);if(code)return code;
    for(unsigned i=0;i<VMAX;i++) {
        if(arkiv_cancel_is_set(token))return 2;
        if(seen[i]!=(i<v->count))return error(e,cap,1,"Volume sequence changed. Reopen the archive.");
        if(i>=v->count)continue;
        char name[512];snprintf(name,sizeof(name),"%s%03u",v->stem,i+1);struct stat held,now;
        if(fstat(v->fds[i],&held)||fstatat(v->parent,name,&now,AT_SYMLINK_NOFOLLOW)||!same(&held,&v->stamps[i])||!same(&now,&v->stamps[i]))return error(e,cap,1,"A volume changed during the operation. Reopen the archive.");
    }
    return 0;
}
static uint64_t le64(const unsigned char *p){uint64_t n=0;for(int i=7;i>=0;i--)n=(n<<8)|p[i];return n;}
static uint32_t le32(const unsigned char *p){return (uint32_t)le64((const unsigned char[8]){p[0],p[1],p[2],p[3],0,0,0,0});}
uint64_t arkiv_volumes_size(arkiv_volumes *v){return v?v->total:0;}
int arkiv_volumes_reconstruct(const char *path,const char *output,uint64_t limit,arkiv_cancel *token,arkiv_progress_callback progress,void *ctx,arkiv_volumes **retained,char *e,size_t cap) {
    *retained=NULL;
    if(limit<32||limit>(4ULL<<30))return error(e,cap,8,"Invalid physical-input budget.");
    int result=1,out=-1;arkiv_volumes *v=calloc(1,sizeof(*v));if(!v)return 1;
    v->parent=-1;for(unsigned i=0;i<VMAX;i++)v->fds[i]=-1;
    char *copy=strdup(path);if(!copy)goto done;char *leaf=strrchr(copy,'/');
    if(!leaf||!leaf[1]){free(copy);goto done;}*leaf++=0;
    size_t n=strlen(leaf);unsigned chosen=0;
    if(n<8||strncasecmp(leaf+n-7,".7z.",4)){free(copy);result=error(e,cap,8,"Unsupported multipart convention.");goto done;}
    for(size_t i=n-3;i<n;i++){if(leaf[i]<'0'||leaf[i]>'9'){free(copy);result=8;goto done;}chosen=chosen*10+(unsigned)(leaf[i]-'0');}
    v->stem=strndup(leaf,n-3);v->directory=strdup(*copy?copy:"/");free(copy);
    if(!v->stem||!v->directory||strlen(v->stem)>250||!chosen||chosen>VMAX){result=error(e,cap,8,"Unsupported split volume number.");goto done;}
    v->parent=directory_open(v->directory);
    if(v->parent<0||fstat(v->parent,&v->parent_stamp)){result=error(e,cap,1,"Volume directory unavailable or linked. Choose an accessible containing folder.");goto done;}
    unsigned char seen[VMAX]={0};result=scan(v,seen,token,e,cap);if(result)goto done;
    v->count=chosen;for(unsigned i=0;i<VMAX;i++)if(seen[i])v->count=i+1>v->count?i+1:v->count;
    for(unsigned i=0;i<v->count;i++) {
        char name[512];snprintf(name,sizeof(name),"%s%03u",v->stem,i+1);
        if(!seen[i]){if(e&&cap)snprintf(e,cap,"Missing %svolume: %s",i==0?"first ":"",name);result=10;goto done;}
        v->fds[i]=openat(v->parent,name,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
        struct stat *s=&v->stamps[i];
        if(v->fds[i]<0||fstat(v->fds[i],s)||!S_ISREG(s->st_mode)||s->st_nlink!=1){result=error(e,cap,1,"Volume unreadable, linked, or not a regular file.");goto done;}
        for(unsigned j=0;j<i;j++)if(s->st_dev==v->stamps[j].st_dev&&s->st_ino==v->stamps[j].st_ino){result=error(e,cap,8,"Duplicate volume identity.");goto done;}
        if(s->st_size<=0||(uint64_t)s->st_size>limit-v->total){result=error(e,cap,8,"Split archive exceeds the physical-input budget or contains an empty volume.");goto done;}
        v->total+=(uint64_t)s->st_size;
    }
    unsigned char header[32];
    if(pread(v->fds[0],header,32,0)!=32||memcmp(header,"7z\xbc\xaf\x27\x1c",6)||header[6]!=0||crc32(0,header+12,20)!=le32(header+8)){result=error(e,cap,6,"Corrupt or unsupported split 7z start header.");goto done;}
    uint64_t offset=le64(header+12),size=le64(header+20);
    if(offset>limit||size>limit-offset||offset+size>limit-32){result=error(e,cap,8,"Reconstructed 7z exceeds the physical-input limit.");goto done;}
    if(v->total!=32+offset+size){result=error(e,cap,6,"Incomplete or corrupt split 7z input; final volume may be missing or truncated.");goto done;}
    if(v->count<2){result=error(e,cap,8,"A split archive must contain at least two numbered volumes.");goto done;}
    for(unsigned i=1;i<v->count;i++)if(v->stamps[i].st_size>v->stamps[0].st_size||(i+1<v->count&&v->stamps[i].st_size!=v->stamps[0].st_size)){result=error(e,cap,8,"Inconsistent split volume sizes.");goto done;}
    out=open(output,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(out<0){result=error(e,cap,1,"Cannot create private volume spool.");goto done;}
    uint64_t copied=0;unsigned char buffer[65536];result=0;
    for(unsigned i=0;i<v->count&&!result;i++)for(off_t p=0;p<v->stamps[i].st_size;) {
        if(arkiv_cancel_is_set(token)){result=2;break;}
        size_t want=(uint64_t)(v->stamps[i].st_size-p)<sizeof(buffer)?(size_t)(v->stamps[i].st_size-p):sizeof(buffer);
        if(pread(v->fds[i],buffer,want,p)!=(ssize_t)want){result=error(e,cap,1,"Volume changed or became unreadable.");break;}
        size_t w=0;while(w<want){ssize_t k=write(out,buffer+w,want-w);if(k<=0){result=error(e,cap,1,"Insufficient space or private volume spool write failure.");break;}w+=(size_t)k;}
        if(result)break;
        p+=(off_t)want;copied+=want;if(progress)progress(ctx,i+1,copied);
    }
    if(!result&&fsync(out))result=1;
    if(!result)result=arkiv_volumes_validate(v,token,e,cap);
    if(!result){*retained=v;v=NULL;}
done:
    if(out>=0){close(out);if(result)unlink(output);}
    arkiv_volumes_free(v);return result;
}
