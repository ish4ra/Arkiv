/* Bounded, single-stream decompression. TAR validation remains in the existing reader. */
#include "ArkivArchive.h"
#include <zlib.h>
#define ZSTD_STATIC_LINKING_ONLY
#include <zstd.h>
#include <zstd_errors.h>
#include <stddef.h>
#include "vendor/bzlib.h"
#include "vendor/xz/lzma.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* Account for all codec heap allocations, including context and stream buffers.
   The advanced allocator/header APIs are from our pinned static Zstandard source. */
typedef struct { size_t used, limit; int denied; } zstd_budget;
typedef union { max_align_t alignment; size_t size; } zstd_allocation;
static void *zstd_alloc(void *opaque, size_t size) {
    zstd_budget *b = opaque;
    if (size > b->limit - b->used || sizeof(zstd_allocation) > b->limit - b->used - size) { b->denied = 1; return NULL; }
    zstd_allocation *allocation = malloc(sizeof(*allocation) + size);
    if (!allocation) { b->denied = 1; return NULL; }
    allocation->size = sizeof(*allocation) + size; b->used += allocation->size;
    return allocation + 1;
}
static void zstd_free(void *opaque, void *address) {
    if (!address) return;
    zstd_budget *b = opaque; zstd_allocation *allocation = (zstd_allocation *)address - 1;
    b->used -= allocation->size; free(allocation);
}
int arkiv_compression_kind(const char *path) {
    int fd=open(path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
    if(fd<0)return 0;
    unsigned char b[6]; ssize_t n=read(fd,b,6);close(fd);
    if(n>=2 && b[0]==31 && b[1]==139)return 1;
    if(n>=3 && !memcmp(b,"BZh",3))return 2;
    if(n==6 && !memcmp(b,"\xfd" "7zXZ\0",6))return 3;
    if(n>=4 && ((!memcmp(b,"\x28\xb5\x2f\xfd",4)) ||
       (b[0]>=0x50 && b[0]<=0x5f && b[1]==0x2a && b[2]==0x4d && b[3]==0x18)))return 4;
    return 0;
}
/* 0 success, 2 cancelled, 6 corrupt, 8 unsupported/resource limit.
   No output survives any unsuccessful return. Concatenated streams are rejected. */
/* Preserve trusted macOS temporary aliases, without following arbitrary links. */
static arkiv_file_pin *stream_pin(const char *path) {
#ifdef __APPLE__
    if (!strncmp(path,"/var/",5) || !strncmp(path,"/tmp/",5)) {
        char *physical=NULL;
        if (asprintf(&physical,"/private%s",path)<0) return NULL;
        arkiv_file_pin *pin=arkiv_file_pin_begin(physical); free(physical); return pin;
    }
#endif
    return arkiv_file_pin_begin(path);
}
static int tar_end(int fd, uint64_t size) {
    unsigned char tail[1024];
    if (size < sizeof(tail) || size % 512 || pread(fd, tail, sizeof(tail), (off_t)(size-sizeof(tail))) != sizeof(tail)) return 0;
    for (size_t i=0; i<sizeof(tail); i++) if (tail[i]) return 0;
    return 1;
}
int arkiv_tar_terminated(const char *path) {
    arkiv_file_pin *pin = stream_pin(path); if (!pin) return 0;
    int fd = arkiv_file_pin_descriptor(pin); struct stat st;
    int valid = !fstat(fd, &st) && st.st_size >= 0 && tar_end(fd, (uint64_t)st.st_size) && arkiv_file_pin_valid(pin);
    arkiv_file_pin_end(pin); return valid;
}
static int decompress_stream(const char *path,const char *output,uint64_t limit,arkiv_cancel *token,
                             int require_tar, arkiv_progress_callback progress, void *context, int *has_checksum) {
    if (has_checksum) *has_checksum = -1;
    if (limit > (20ULL << 30)) return 8;
    if(arkiv_cancel_is_set(token))return 2;
    int kind=arkiv_compression_kind(path), in=-1,out=-1,result=6,initialized=0,input_eof=0;
    z_stream z={0}; bz_stream bz={0}; lzma_stream x=LZMA_STREAM_INIT;
    ZSTD_DCtx *zs = NULL; ZSTD_inBuffer zi = {0};
    zstd_budget budget = {0, 80ULL << 20, 0};
    int checksum = kind == 4 ? 0 : 1;
    struct stat before,after;
    arkiv_file_pin *pin = NULL;
    unsigned char input[65536],buffer[65536];size_t available=0;uint64_t total=0;
    pin=stream_pin(path);
    in=arkiv_file_pin_descriptor(pin);
    if(!kind||in<0||fstat(in,&before)||!S_ISREG(before.st_mode))goto done;
    out=open(output,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(out<0)goto done;
    if(kind==1)initialized=inflateInit2(&z,31)==Z_OK;
    if(kind==2)initialized=BZ2_bzDecompressInit(&bz,0,0)==BZ_OK;
    if(kind==3)initialized=lzma_stream_decoder(&x,64ULL*1024*1024,LZMA_TELL_NO_CHECK|LZMA_TELL_UNSUPPORTED_CHECK)==LZMA_OK;
    if(kind==4) {
        unsigned char header[ZSTD_FRAMEHEADERSIZE_MAX]; ZSTD_FrameHeader frame;
        ssize_t n = pread(in, header, sizeof(header), 0);
        if(n<0 || ZSTD_getFrameHeader(&frame,header,(size_t)n)!=0)goto done;
        if(frame.frameType!=ZSTD_frame || frame.dictID || frame.windowSize>(64ULL<<20) ||
           (frame.frameContentSize!=ZSTD_CONTENTSIZE_UNKNOWN && frame.frameContentSize>limit)) {result=8;goto done;}
        checksum=(int)frame.checksumFlag;
        zs=ZSTD_createDCtx_advanced((ZSTD_customMem){zstd_alloc,zstd_free,&budget});
        initialized=zs && !ZSTD_isError(ZSTD_DCtx_setParameter(zs,ZSTD_d_windowLogMax,26));
    }
    if(!initialized){result=8;goto done;}
    for(;;) {
        if(arkiv_cancel_is_set(token)){result=2;break;}
        if(!available && !input_eof){ssize_t n=read(in,input,sizeof(input));if(n<0)break;if(!n)input_eof=1;available=(size_t)n;
            if(kind==1){z.next_in=input;z.avail_in=(uInt)available;}
            if(kind==2){bz.next_in=(char*)input;bz.avail_in=(unsigned)available;}
            if(kind==3){x.next_in=input;x.avail_in=available;}
            if(kind==4)zi=(ZSTD_inBuffer){input,available,0};}
        size_t prior=available,produced=0;int ended=0,ok=0;
        if(kind==1){z.next_out=buffer;z.avail_out=sizeof(buffer);int r=inflate(&z,Z_NO_FLUSH);available=z.avail_in;produced=sizeof(buffer)-z.avail_out;ended=r==Z_STREAM_END;ok=r==Z_OK||ended;}
        if(kind==2){bz.next_out=(char*)buffer;bz.avail_out=sizeof(buffer);int r=BZ2_bzDecompress(&bz);available=bz.avail_in;produced=sizeof(buffer)-bz.avail_out;ended=r==BZ_STREAM_END;ok=r==BZ_OK||ended;}
        if(kind==3){x.next_out=buffer;x.avail_out=sizeof(buffer);lzma_ret r=lzma_code(&x,input_eof ? LZMA_FINISH : LZMA_RUN);available=x.avail_in;produced=sizeof(buffer)-x.avail_out;ended=r==LZMA_STREAM_END;ok=r==LZMA_OK||ended;if(r==LZMA_MEMLIMIT_ERROR||r==LZMA_UNSUPPORTED_CHECK||r==LZMA_NO_CHECK)result=8;}
        if(kind==4) {
            ZSTD_outBuffer zo={buffer,sizeof(buffer),0};
            size_t r=ZSTD_decompressStream(zs,&zo,&zi);
            available=zi.size-zi.pos;produced=zo.pos;ended=r==0;ok=!ZSTD_isError(r);
            if(budget.denied || (ZSTD_isError(r) && ZSTD_getErrorCode(r)==ZSTD_error_frameParameter_windowTooLarge))result=8;
        }
        if(!ok||(!produced&&prior==available&&!ended))break;
        if(produced>limit-total){result=8;break;}total+=produced;
        size_t offset=0;while(offset<produced){ssize_t n=write(out,buffer+offset,produced-offset);if(n<=0)goto done;offset+=(size_t)n;}
        if(progress)progress(context,1,total);
        if(ended) {
            unsigned char extra;
            if(!available && read(in,&extra,1)==0 && (!require_tar || tar_end(out,total)) &&
               !fstat(in,&after) && before.st_size==after.st_size && before.st_mtime==after.st_mtime &&
               arkiv_file_pin_valid(pin)) result=0;
            break;
        }
    }
 done:
    if(arkiv_cancel_is_set(token))result=2;
    if(initialized){if(kind==1)inflateEnd(&z);if(kind==2)BZ2_bzDecompressEnd(&bz);if(kind==3)lzma_end(&x);}
    ZSTD_freeDCtx(zs);
    arkiv_file_pin_end(pin);
    if(out>=0){if(close(out)&&result==0)result=6;if(result)unlink(output);}
    if(result==0 && has_checksum)*has_checksum=checksum;
    return result;
}

int arkiv_decompress_tar(const char *path,const char *output,uint64_t limit,arkiv_cancel *token) {
    return decompress_stream(path,output,limit,token,1,NULL,NULL,NULL);
}
int arkiv_decompress_stream(const char *path,const char *output,uint64_t limit,arkiv_cancel *token) {
    return decompress_stream(path,output,limit,token,0,NULL,NULL,NULL);
}
int arkiv_decompress_stream_progress(const char *path,const char *output,uint64_t limit,arkiv_cancel *token,
                                    arkiv_progress_callback progress,void *context) {
    return decompress_stream(path,output,limit,token,0,progress,context,NULL);
}

int arkiv_decompress_stream_inspect(const char *path,const char *output,uint64_t limit,arkiv_cancel *token,
                                   arkiv_progress_callback progress,void *context,int *has_checksum) {
    return decompress_stream(path,output,limit,token,0,progress,context,has_checksum);
}

/* Fixed, interoperable creation settings: gzip 6, bzip2 9, XZ 6/CRC64, ZSTD 3/checksum.
   Input/output descriptors belong to the creator's private staging directory. */
int arkiv_compress_stream_fd(int in, int out, int kind, uint64_t limit, arkiv_cancel *token,
                             arkiv_progress_callback progress, void *context) {
    if (kind < 1 || kind > 4 || limit > (20ULL << 30)) return 8;
    z_stream z = {0}; bz_stream bz = {0}; lzma_stream x = LZMA_STREAM_INIT;
    ZSTD_CCtx *zs = NULL; ZSTD_inBuffer zi = {0};
    zstd_budget budget = {0, 128ULL << 20, 0};
    unsigned char input[65536], buffer[65536];
    int initialized = 0, result = 6, eof = 0;
    size_t available = 0; uint64_t consumed = 0, written = 0;
    if (lseek(in, 0, SEEK_SET) < 0) return 6;
    if (kind == 1) initialized = deflateInit2(&z, 6, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY) == Z_OK;
    if (kind == 2) initialized = BZ2_bzCompressInit(&bz, 9, 0, 30) == BZ_OK;
    if (kind == 3 && lzma_easy_encoder_memusage(6) <= (128ULL << 20) &&
        lzma_easy_decoder_memusage(6) <= (64ULL << 20))
        initialized = lzma_easy_encoder(&x, 6, LZMA_CHECK_CRC64) == LZMA_OK;
    if (kind == 4) {
        zs=ZSTD_createCCtx_advanced((ZSTD_customMem){zstd_alloc,zstd_free,&budget});
        initialized=zs && !ZSTD_isError(ZSTD_CCtx_setParameter(zs,ZSTD_c_compressionLevel,3)) &&
            !ZSTD_isError(ZSTD_CCtx_setParameter(zs,ZSTD_c_windowLog,23)) &&
            !ZSTD_isError(ZSTD_CCtx_setParameter(zs,ZSTD_c_nbWorkers,0)) &&
            !ZSTD_isError(ZSTD_CCtx_setParameter(zs,ZSTD_c_checksumFlag,1));
    }
    if (!initialized) { result = 8; goto done; }
    for (;;) {
        if (arkiv_cancel_is_set(token)) { result = 2; break; }
        if (!available && !eof) {
            ssize_t n = read(in, input, sizeof(input));
            if (n < 0) break;
            if (!n) eof = 1;
            if ((uint64_t)n > limit - consumed) { result = 8; break; }
            consumed += (uint64_t)n; available = (size_t)n;
            if (kind == 1) { z.next_in = input; z.avail_in = (uInt)available; }
            if (kind == 2) { bz.next_in = (char *)input; bz.avail_in = (unsigned)available; }
            if (kind == 3) { x.next_in = input; x.avail_in = available; }
            if (kind == 4) zi=(ZSTD_inBuffer){input,available,0};
        }
        size_t prior = available, produced = 0; int ended = 0, ok = 0;
        if (kind == 1) {
            z.next_out = buffer; z.avail_out = sizeof(buffer);
            int r = deflate(&z, eof ? Z_FINISH : Z_NO_FLUSH);
            available = z.avail_in; produced = sizeof(buffer) - z.avail_out;
            ended = r == Z_STREAM_END; ok = r == Z_OK || ended;
        }
        if (kind == 2) {
            bz.next_out = (char *)buffer; bz.avail_out = sizeof(buffer);
            int r = BZ2_bzCompress(&bz, eof ? BZ_FINISH : BZ_RUN);
            available = bz.avail_in; produced = sizeof(buffer) - bz.avail_out;
            ended = r == BZ_STREAM_END; ok = r == BZ_RUN_OK || r == BZ_FINISH_OK || ended;
        }
        if (kind == 3) {
            x.next_out = buffer; x.avail_out = sizeof(buffer);
            lzma_ret r = lzma_code(&x, eof ? LZMA_FINISH : LZMA_RUN);
            available = x.avail_in; produced = sizeof(buffer) - x.avail_out;
            ended = r == LZMA_STREAM_END; ok = r == LZMA_OK || ended;
        }
        if (kind == 4) {
            ZSTD_outBuffer zo={buffer,sizeof(buffer),0};
            size_t r=ZSTD_compressStream2(zs,&zo,&zi,eof ? ZSTD_e_end : ZSTD_e_continue);
            available=zi.size-zi.pos;produced=zo.pos;ended=eof && r==0;ok=!ZSTD_isError(r);
            if(budget.denied)result=8;
        }
        if (!ok || (!produced && available == prior && !ended)) break;
        /* Allow bounded framing overhead for incompressible input. */
        if (produced > limit + limit / 100 + (1 << 20) - written) { result = 8; break; }
        written += produced;
        size_t offset = 0;
        while (offset < produced) {
            ssize_t n = write(out, buffer + offset, produced - offset);
            if (n <= 0) goto done;
            offset += (size_t)n;
        }
        if (progress) progress(context,1,consumed);
        if (ended) { result = fsync(out) ? 6 : 0; break; }
    }
done:
    if (initialized) {
        if (kind == 1) deflateEnd(&z);
        if (kind == 2) BZ2_bzCompressEnd(&bz);
        if (kind == 3) lzma_end(&x);
    }
    ZSTD_freeCCtx(zs);
    if (arkiv_cancel_is_set(token)) result = 2;
    return result;
}

int arkiv_compress_tar_fd(int in,int out,int kind,uint64_t limit,arkiv_cancel *token) {
    return arkiv_compress_stream_fd(in,out,kind,limit,token,NULL,NULL);
}
