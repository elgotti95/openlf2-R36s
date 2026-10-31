/* Optional per-profile save-slot tracking. The retail container holds eight
 * slots; never delete the container or infer ownership from a mod folder. */
#include "mod_gameplay.h"
#include "kernel/file_observer.h"
#include <filesystem>
#include <map>
#include <mutex>
#include <vector>
#include <cstdio>
#include <cstring>
namespace {
namespace fs=std::filesystem;
constexpr DWORD header_size=512, block_size=0xde00, container_size=1024+8*block_size;
struct Record { char magic[8]; wchar_t relative[MAX_PATH]; unsigned slot; unsigned char token[44]; uint64_t digest; };
struct Pending { fs::path path; int slot=-1; uint64_t digest=0; bool committed=false; };
std::map<HANDLE,Pending> pending;
std::mutex guard;
fs::path root, marker;
bool initialized=false;
uint32_t u32(const void *p) { uint32_t v; memcpy(&v,p,4); return v; }
uint32_t crc(const unsigned char *p,size_t n) {
    uint32_t h=2166136261u;
    for(size_t i=4;i<n;++i)h=(h^(uint32_t)(int32_t)(int8_t)p[i])*16777619u;
    return h;
}
uint64_t digest(const unsigned char *p,size_t n) {
    uint64_t h=14695981039346656037ull;
    for(size_t i=0;i<n;++i)h=(h^p[i])*1099511628211ull;
    return h;
}
void token(const unsigned char *header,unsigned slot,unsigned char *out) {
    memcpy(out,header+4+slot*4,4);
    memcpy(out+4,header+0x24+slot*8,8);
    memcpy(out+12,header+0x64+slot*32,32);
}
bool same_path(const fs::path &a,const fs::path &b) {
    auto x=a.lexically_normal().native(),y=b.lexically_normal().native();
    return CompareStringOrdinal(x.c_str(),-1,y.c_str(),-1,TRUE)==CSTR_EQUAL;
}
bool safe_path(const fs::path &p) {
    if(!same_path(p.filename(),L"Mercenaries Saves") || !same_path(p.parent_path().parent_path(),root/L"UserData"))return false;
    for(auto q=p; !same_path(q,root); q=q.parent_path()) {
        if(q.empty()||q==q.parent_path())return false;
        auto a=GetFileAttributesW(q.c_str());
        if(a==INVALID_FILE_ATTRIBUTES || (a&FILE_ATTRIBUTE_REPARSE_POINT))return false;
    }
    return !(GetFileAttributesW(root.c_str())&FILE_ATTRIBUTE_REPARSE_POINT);
}
void report(const char *s) { fprintf(stderr,"[mod-permadeath] %s\n",s); }
bool read_all(HANDLE h,void *data,DWORD bytes) {
    LARGE_INTEGER zero{}; DWORD got=0;
    return SetFilePointerEx(h,zero,nullptr,FILE_BEGIN)&&ReadFile(h,data,bytes,&got,nullptr)&&got==bytes;
}
bool atomic_write(const fs::path &path,const void *data,DWORD bytes) {
    auto temp=path; temp+=L".pending";
    HANDLE h=CreateFileW(temp.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(h==INVALID_HANDLE_VALUE)return false;
    DWORD written=0; bool ok=WriteFile(h,data,bytes,&written,nullptr)&&written==bytes&&FlushFileBuffers(h);
    CloseHandle(h);
    if(ok)ok=MoveFileExW(temp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)!=0;
    if(!ok) { fprintf(stderr,"[mod-permadeath] Atomic save replacement failed (%lu).\n",GetLastError());DeleteFileW(temp.c_str()); }
    return ok;
}
void on_write(HANDLE handle,long long offset,const void *buffer,DWORD size) {
    try {
        std::lock_guard<std::mutex> lock(guard);
        if(!initialized)return;
        const auto *data=static_cast<const unsigned char *>(buffer);
        if(size==block_size && offset>=512 && (offset-512)%block_size==0 && (offset-512)/block_size<8) {
            wchar_t path[32768]; DWORD n=GetFinalPathNameByHandleW(handle,path,32768,FILE_NAME_NORMALIZED);
            if(!n||n>=32768)return;
            std::wstring normalized(path); if(normalized.rfind(L"\\\\?\\",0)==0)normalized.erase(0,4);
            fs::path file(normalized); file=file.lexically_normal();
            if(!safe_path(file)||u32(data)!=crc(data,size))return;
            if(pending.size()>=32 && !pending.count(handle))return;
            auto &p=pending[handle]; p={}; p.path=file;p.slot=int((offset-512)/block_size);p.digest=digest(data,size);
            p.committed=FlushFileBuffers(handle)!=0;
        }
    } catch(...) { report("Save tracking failed; no save was deleted."); }
}
void on_close(HANDLE handle) {
    try {
        std::lock_guard<std::mutex> lock(guard);
        auto it=pending.find(handle);if(it==pending.end())return;
        Pending p=it->second;pending.erase(it);
        if(!p.committed)return;
        // Retail writes the header BEFORE the game block, often on separate
        // handles. Validate the finished container after the payload closes.
        HANDLE h=CreateFileW(p.path.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(h==INVALID_HANDLE_VALUE){report("Could not verify the completed save.");return;}
        std::vector<unsigned char> data(container_size);LARGE_INTEGER bytes{};
        bool ok=GetFileSizeEx(h,&bytes)&&bytes.QuadPart==container_size&&read_all(h,data.data(),container_size);CloseHandle(h);
        auto block=data.data()+512+p.slot*block_size;
        uint32_t reference=crc(block+4,0x400c)^crc(block+4+0x400c,0x9c5c)^crc(block+4+0x400c+0x9c5c,0x54);
        if(!ok||u32(data.data())!=crc(data.data(),512)||!data[0x64+p.slot*32]||
           u32(data.data()+4+p.slot*4)!=reference||digest(block,block_size)!=p.digest) {
            report("Incomplete or changed save; latest-save record was not advanced.");return;
        }
        Record record{};memcpy(record.magic,"MCPDSV1",8);
        auto relative=(fs::path(L"UserData")/p.path.parent_path().filename()/p.path.filename()).wstring();
        if(relative.size()>=MAX_PATH)return;
        wcscpy_s(record.relative,MAX_PATH,relative.c_str());record.slot=p.slot;
        token(data.data(),p.slot,record.token);record.digest=p.digest;
        if(!atomic_write(marker,&record,sizeof(record)))report("Could not persist the latest-save record.");
    } catch(...) { report("Could not persist the latest-save record."); }
}
}
extern "C" void recomp_mod_saves_init(const char *directory) {
    try {
        if(!directory||!recomp_mod_save_profile()[0])return;
        root=fs::absolute(fs::u8path(directory)).lexically_normal();
        auto state=root/L"mod-state";fs::create_directories(state);
        if(GetFileAttributesW(state.c_str())&FILE_ATTRIBUTE_REPARSE_POINT)return;
        marker=state/(std::string(recomp_mod_save_profile())+".latest-save");
        initialized=true;xbox_file_observe(on_write,on_close);
    } catch(...) { report("Save tracking could not initialize."); }
}
extern "C" int recomp_mod_delete_latest_save(void) {
    try {
        std::lock_guard<std::mutex> lock(guard);
        if(!initialized)return 0;
        Record r{};
        HANDLE mh=CreateFileW(marker.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(mh==INVALID_HANDLE_VALUE)return GetLastError()==ERROR_FILE_NOT_FOUND ? 1:0;
        LARGE_INTEGER size{};bool ok=GetFileSizeEx(mh,&size)&&size.QuadPart==sizeof(r)&&read_all(mh,&r,sizeof(r));CloseHandle(mh);
        if(!ok||memcmp(r.magic,"MCPDSV1",8)||r.slot>=8||r.relative[MAX_PATH-1]){report("Invalid latest-save record.");return 0;}
        fs::path relative(r.relative);auto file=(root/relative).lexically_normal();
        if(relative.is_absolute()||!safe_path(file)){report("Tracked save path is outside the permitted container location.");return 0;}
        HANDLE h=CreateFileW(file.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(h==INVALID_HANDLE_VALUE)return 0;
        std::vector<unsigned char> data(container_size);
        ok=GetFileSizeEx(h,&size)&&size.QuadPart==container_size&&read_all(h,data.data(),container_size);
        unsigned char current[44]{};
        if(ok)token(data.data(),r.slot,current);
        if(!ok||u32(data.data())!=crc(data.data(),512)||memcmp(current,r.token,44)||
           digest(data.data()+512+r.slot*block_size,block_size)!=r.digest) {
            CloseHandle(h);report("Tracked slot changed or is invalid; preserving the container.");return 0;
        }
        /* Same logical deletion as the retail save browser. Only this header
         * entry changes; other slot metadata, payloads, and options stay intact. */
        memset(data.data()+4+r.slot*4,0,4);
        memset(data.data()+0x24+r.slot*8,0,8);
        memset(data.data()+0x64+r.slot*32,0,32);
        auto sum=crc(data.data(),512);memcpy(data.data(),&sum,4);
        CloseHandle(h);
        ok=atomic_write(file,data.data(),container_size);
        if(ok) { DeleteFileW(marker.c_str());report("Removed the last recorded save slot for the configured profile."); }
        return ok?1:0;
    } catch(...) { report("Save deletion failed; returning an error.");return 0; }
}
