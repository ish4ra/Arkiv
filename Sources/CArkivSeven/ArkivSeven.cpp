#include "ArkivSeven.h"
#include "CPP/Common/MyInitGuid.h"
#include "CPP/Common/MyCom.h"
#include "CPP/Common/UTFConvert.h"
#include "CPP/Windows/PropVariant.h"
#include "CPP/7zip/Archive/7z/7zHandler.h"
#include "CPP/7zip/IPassword.h"
#include "archive.h"
#include "archive_entry.h"
#include <vector>
#include <string>
#include <unistd.h>
#include <sys/stat.h>
#include <cstdio>
#include <dlfcn.h>
#include <algorithm>
using NWindows::NCOM::CPropVariant;
static const uint64_t Budget = uint64_t(20)*1024*1024*1024;
struct State {
 State(const char*p,arkiv_seven_cancel c,void*x):password(p),cancel(c),context(x){}
 const char *password; arkiv_seven_cancel cancel; void *context; bool asked=false; int error=0;
 arkiv_seven_progress progress=nullptr; void *progressContext=nullptr;
 bool stopped() { return cancel && cancel(context); }
 HRESULT tick() { return stopped() ? E_ABORT : S_OK; }
 HRESULT secret(BSTR *p) { asked=true; if (!password) {error=4;return E_ABORT;} UString u; if(!ConvertUTF8ToUnicode(AString(password),u))return E_FAIL; *p=SysAllocString(u);return *p?S_OK:E_OUTOFMEMORY; }
 int result(HRESULT h) {if(stopped())return 2;if(error)return error;if(h==S_OK)return 0;return asked&&password?5:1;}
};
class In: public IInStream, public CMyUnknownImp {
public:
 Z7_COM_UNKNOWN_IMP_1(IInStream)
public:
 int fd; uint64_t start=0,pos=0,size; State *s;
 In(int f,State *st,uint64_t begin=0,uint64_t length=UINT64_MAX):fd(f),start(begin),size(length),s(st) { if(size==UINT64_MAX){struct stat b;if(fstat(f,&b))size=0;else size=b.st_size;} }
 Z7_COM7F_IMF(Read(void *data,UInt32 n,UInt32 *done)) {if(done)*done=0;if(s->stopped())return E_ABORT;n=UInt32(std::min<uint64_t>(n,size-pos));ssize_t r=pread(fd,data,n,start+pos);if(r<0)return E_FAIL;pos+=r;if(done)*done=UInt32(r);return S_OK;}
 Z7_COM7F_IMF(Seek(Int64 off,UInt32 origin,UInt64 *out)) {int64_t base=origin==0?0:origin==1?pos:origin==2?size:-1;if(base<0||off < -base)return E_FAIL;uint64_t p=base+off;if(p>size)return E_FAIL;pos=p;if(out)*out=pos;return S_OK;}
};
class Out: public IOutStream, public CMyUnknownImp {
public:
 Z7_COM_UNKNOWN_IMP_1(IOutStream)
public:
 int fd;State*s;Out(int f,State*st):fd(f),s(st){}
 Z7_COM7F_IMF(Write(const void *data,UInt32 n,UInt32 *done)) {if(done)*done=0;if(s->stopped())return E_ABORT;ssize_t r=write(fd,data,n);if(r<0)return E_FAIL;if(done)*done=r;return S_OK;}
 Z7_COM7F_IMF(Seek(Int64 off,UInt32 origin,UInt64 *out)) {off_t p=lseek(fd,off,origin);if(p<0)return E_FAIL;if(out)*out=p;return S_OK;}
 Z7_COM7F_IMF(SetSize(UInt64 n)) {return ftruncate(fd,n)?E_FAIL:S_OK;}
};
struct Item {UString name;std::string utf8;uint64_t size=0,offset=0;bool dir=false;};
static bool safe(const std::string &p) {
 if(p.empty()||p.size()>4096||p[0]=='/')return false;unsigned depth=0;size_t start=0;
 for(size_t i=0;i<=p.size();i++){unsigned char c=i<p.size()?p[i]:0;if(c=='\\'||c==':'||(c&&c<32))return false;if(c=='/'||!c){auto part=p.substr(start,i-start);if(part.empty()||part=="."||part==".."||++depth>256)return false;start=i+1;if(i+1==p.size())break;}}return true;
}
class Update: public IArchiveUpdateCallback, public ICryptoGetTextPassword2, public CMyUnknownImp {
public:
 Z7_COM_UNKNOWN_IMP_2(IArchiveUpdateCallback,ICryptoGetTextPassword2)
public:
 State*s;int fd;std::vector<Item> items;
 Update(State*st,int f):s(st),fd(f){}
 Z7_COM7F_IMF(SetTotal(UInt64)) {return s->tick();}
 Z7_COM7F_IMF(SetCompleted(const UInt64*n)) {if(s->progress&&n)s->progress(s->progressContext,0,*n);return s->tick();}
 Z7_COM7F_IMF(GetUpdateItemInfo(UInt32,Int32*d,Int32*p,UInt32*i)){*d=1;*p=1;*i=UInt32(-1);return s->tick();}
 Z7_COM7F_IMF(GetProperty(UInt32 i,PROPID id,PROPVARIANT*v)){if(i>=items.size())return E_FAIL;CPropVariant p;auto &a=items[i];switch(id){case kpidPath:p=a.name;break;case kpidIsDir:p=a.dir;break;case kpidSize:p=UInt64(a.size);break;case kpidAttrib:p=UInt32(a.dir?0x10:0x20);break;}p.Detach(v);return s->tick();}
 Z7_COM7F_IMF(GetStream(UInt32 i,ISequentialInStream**out)){*out=nullptr;if(i>=items.size())return E_FAIL;auto&a=items[i];if(!a.dir){CMyComPtr<IInStream> in=new In(fd,s,a.offset,a.size);*out=in.Detach();}return s->tick();}
 Z7_COM7F_IMF(SetOperationResult(Int32 r)){return r?E_FAIL:s->tick();}
 Z7_COM7F_IMF(CryptoGetTextPassword2(Int32*defined,BSTR*p)){*defined=s->password!=nullptr;*p=nullptr;return *defined?s->secret(p):S_OK;}
};
class Open: public IArchiveOpenCallback, public ICryptoGetTextPassword, public CMyUnknownImp {
public:
 Z7_COM_UNKNOWN_IMP_2(IArchiveOpenCallback,ICryptoGetTextPassword)
public: State*s;Open(State*st):s(st){}
 Z7_COM7F_IMF(SetTotal(const UInt64*,const UInt64*)){return s->tick();}
 Z7_COM7F_IMF(SetCompleted(const UInt64*,const UInt64*)){return s->tick();}
 Z7_COM7F_IMF(CryptoGetTextPassword(BSTR*p)){return s->secret(p);}
};
class ZipOut: public ISequentialOutStream, public CMyUnknownImp {
public:
 Z7_COM_UNKNOWN_IMP_1(ISequentialOutStream)
public:archive*a;State*s;uint64_t remaining;ZipOut(archive*z,State*st,uint64_t n):a(z),s(st),remaining(n){}
 Z7_COM7F_IMF(Write(const void*p,UInt32 n,UInt32*done)){if(done)*done=0;if(s->stopped())return E_ABORT;if(n>remaining){s->error=1;return E_FAIL;}auto r=archive_write_data(a,p,n);if(r<0)return E_FAIL;remaining-=r;if(done)*done=r;return S_OK;}
};
class Extract: public IArchiveExtractCallback, public ICryptoGetTextPassword, public CMyUnknownImp {
public:
 Z7_COM_UNKNOWN_IMP_2(IArchiveExtractCallback,ICryptoGetTextPassword)
public: State*s;archive*zip;std::vector<Item>items;CMyComPtr<ISequentialOutStream> active; ZipOut *activeRaw=nullptr;
 Extract(State*st,archive*z):s(st),zip(z){}
 Z7_COM7F_IMF(SetTotal(UInt64 n)){if(n>Budget){s->error=1;return E_FAIL;}return s->tick();}
 Z7_COM7F_IMF(SetCompleted(const UInt64*)){return s->tick();}
 Z7_COM7F_IMF(GetStream(UInt32 i,ISequentialOutStream**out,Int32 mode)){*out=nullptr;if(i>=items.size()||mode!=0)return E_FAIL;auto&a=items[i];archive_entry*e=archive_entry_new();archive_entry_set_pathname_utf8(e,a.utf8.c_str());archive_entry_set_size(e,a.size);archive_entry_set_filetype(e,a.dir?AE_IFDIR:AE_IFREG);archive_entry_set_perm(e,a.dir?0700:0600);int r=archive_write_header(zip,e);archive_entry_free(e);if(r!=ARCHIVE_OK)return E_FAIL;activeRaw=new ZipOut(zip,s,a.size);active=activeRaw;if(!a.dir){active->AddRef();*out=active;}return s->tick();}
 Z7_COM7F_IMF(PrepareOperation(Int32)){return s->tick();}
 Z7_COM7F_IMF(SetOperationResult(Int32 r)){if(r){s->error=s->asked&&s->password?5:1;return E_FAIL;}if(active&&activeRaw->remaining)return E_FAIL;active.Release();return archive_write_finish_entry(zip)==ARCHIVE_OK?s->tick():E_FAIL;}
 Z7_COM7F_IMF(CryptoGetTextPassword(BSTR*p)){return s->secret(p);}
};
static int decode(int input,int output,State&s) {
 CMyComPtr<IInArchive> handler=new NArchive::N7z::CHandler;CMyComPtr<IInStream>in=new In(input,&s);CMyComPtr<IArchiveOpenCallback>cb=new Open(&s);
 CMyComPtr<ISetProperties> props;handler.QueryInterface(IID_ISetProperties,&props);
 const wchar_t*names[]={L"memuse",L"mt"};CPropVariant values[2];values[0]=UInt64(256)*1024*1024;values[1]=UInt32(2);if(!props||props->SetProperties(names,values,2)!=S_OK)return 1;
 HRESULT h=handler->Open(in,nullptr,cb);if(h!=S_OK)return s.result(h);
 UInt32 count=0;if(handler->GetNumberOfItems(&count)!=S_OK||count>100000)return 1;
 archive*z=archive_write_new();if(!z)return 1;
 struct Guard {archive*z;~Guard(){archive_write_free(z);}}guard{z};
 if(archive_write_set_format_zip(z)!=ARCHIVE_OK||archive_write_set_format_option(z,"zip","compression","store")!=ARCHIVE_OK||archive_write_set_format_option(z,"zip","hdrcharset","UTF-8")!=ARCHIVE_OK||archive_write_open_fd(z,output)!=ARCHIVE_OK)return 1;
 auto ex=new Extract(&s,z);CMyComPtr<IArchiveExtractCallback> exRef=ex;uint64_t total=0;
 for(UInt32 i=0;i<count;i++){
  if(s.stopped())return 2;Item item;CPropVariant p;
  if(handler->GetProperty(i,kpidPath,&p)!=S_OK||p.vt!=VT_BSTR)return 1;item.name=p.bstrVal;AString a;ConvertUnicodeToUTF8(item.name,a);item.utf8=a.Ptr();if(!safe(item.utf8))return 1;
  p.Clear();if(handler->GetProperty(i,kpidIsDir,&p)!=S_OK||p.vt!=VT_BOOL)return 1;item.dir=p.boolVal!=0;
  p.Clear();if(handler->GetProperty(i,kpidSize,&p)!=S_OK)return 1;if(p.vt==VT_UI8)item.size=p.uhVal.QuadPart;else if(p.vt!=VT_EMPTY)return 1;
  if(item.size>Budget-total||(item.dir&&item.size))return 1;total+=item.size;
  // 7z stores POSIX type in the upper 16 attribute bits. Reject links/specials before normalizing metadata.
  p.Clear();if(handler->GetProperty(i,kpidAttrib,&p)!=S_OK)return 1;if(p.vt==VT_UI4){unsigned attr=p.ulVal;unsigned type=(attr>>16)&S_IFMT;if((attr&0x400)||(type&&type!=(item.dir?S_IFDIR:S_IFREG)))return 1;}
  for(PROPID id:{kpidSymLink,kpidHardLink}){p.Clear();if(handler->GetProperty(i,id,&p)!=S_OK)return 1;if(p.vt!=VT_EMPTY)return 1;}
  ex->items.push_back(item);
 }
 h=handler->Extract(nullptr,UInt32(-1),0,ex);if(h!=S_OK||s.error)return s.result(h);
 return archive_write_close(z)==ARCHIVE_OK?0:1;
}
extern "C" int arkiv_seven_decode(int input,int output,const char*password,arkiv_seven_cancel cancel,void*context){State s{password,cancel,context};try{return decode(input,output,s);}catch(...){return s.stopped()?2:1;}}
extern "C" int arkiv_seven_encode(int input,int output,const char*password,int headers,arkiv_seven_cancel cancel,void*context,arkiv_seven_progress progress,void*progressContext){State s{password,cancel,context};s.progress=progress;s.progressContext=progressContext;try{
 if(s.stopped())return 2;
 FILE*tmp=tmpfile();if(!tmp)return 1;struct Temp{FILE*f;~Temp(){fclose(f);}}t{tmp};
 auto cb=new Update(&s,fileno(tmp));CMyComPtr<IArchiveUpdateCallback> cbRef=cb;archive*r=archive_read_new();struct Reader{archive*a;~Reader(){archive_read_free(a);}}rg{r};
 if(!r||archive_read_support_format_zip(r)!=ARCHIVE_OK||archive_read_open_fd(r,input,65536)!=ARCHIVE_OK)return 1;
 archive_entry*e;int result;uint64_t total=0;char buffer[65536];
 while((result=archive_read_next_header(r,&e))==ARCHIVE_OK){
  if(s.stopped())return 2;if(cb->items.size()>=100000)return 1;Item a;const char*p=archive_entry_pathname_utf8(e);if(!p||!safe(p)||!ConvertUTF8ToUnicode(AString(p),a.name))return 1;a.utf8=p;a.dir=archive_entry_filetype(e)==AE_IFDIR;
  if(archive_entry_symlink(e)||archive_entry_hardlink(e)||(!a.dir&&archive_entry_filetype(e)!=AE_IFREG))return 1;
  int64_t size=archive_entry_size(e);if(size<0||uint64_t(size)>Budget-total)return 1;a.size=size;a.offset=total;total+=a.size;uint64_t read=0;ssize_t n;
  while((n=archive_read_data(r,buffer,sizeof(buffer)))>0){if(s.stopped())return 2;if(uint64_t(n)>a.size-read||fwrite(buffer,1,n,tmp)!=size_t(n))return 1;read+=n;}if(n<0||read!=a.size)return 1;cb->items.push_back(a);
 }
 if(result!=ARCHIVE_EOF||fflush(tmp))return 1;
 auto raw=new NArchive::N7z::CHandler; CMyComPtr<IOutArchive>handler=raw;
 const wchar_t*names[]={L"0",L"x",L"s",L"mt",L"he"};CPropVariant values[5];values[0]=L"LZMA2";values[1]=UInt32(5);values[2]=false;values[3]=UInt32(2);values[4]=bool(password&&headers);
 HRESULT h=static_cast<ISetProperties*>(raw)->SetProperties(names,values,5);if(h!=S_OK)return 1;CMyComPtr<IOutStream>out=new Out(output,&s);h=handler->UpdateItems(out,cb->items.size(),cb);return s.result(h);
 }catch(...){return s.stopped()?2:1;}}

extern "C" const char *arkiv_seven_library_path(){Dl_info info;return dladdr((void*)&arkiv_seven_library_path,&info)&&info.dli_fname?info.dli_fname:"";}
