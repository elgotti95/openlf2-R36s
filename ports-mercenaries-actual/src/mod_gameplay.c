#include "mod_gameplay.h"
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "mod_gameplay_script.h"
static int perma;
static unsigned c4_count;
static uint32_t c4_templates[256];
static unsigned char c4_values[256];
int recomp_mod_c4_for_template(uint32_t key) { for(unsigned i=0;i<c4_count;++i)if(c4_templates[i]==key)return c4_values[i];return 0; }
static unsigned voice_count;
static struct { uint32_t key, effect; } voices[256];
static uint32_t hash_name(const char *s) { uint32_t h=2166136261u; while(*s)h=(h^((unsigned char)*s++|32u))*16777619u; return h; }
uint32_t recomp_mod_voice_for_template(uint32_t key) { for(unsigned i=0;i<voice_count;++i)if(voices[i].key==key)return voices[i].effect;return 0; }
static LONG died;
static char profile[64];
static char script[100000];
static void bad(const char *message) {
    fprintf(stderr,"[mod-compatibility] %s\n",message);exit(86);
}
static int enabled(const char *path,const char *key) {
    char value[16];GetPrivateProfileStringA("Mods",key,"0",value,sizeof(value),path);
    if(strcmp(value,"0")&&strcmp(value,"1"))bad("Gameplay feature switches must be 0 or 1.");
    return value[0]=='1';
}
static int identifier(const char *s) {
    if(!*s||!strcmp(s,".")||!strcmp(s,".."))return 0;
    for(;*s;++s)if((unsigned char)*s>=127||(!isalnum((unsigned char)*s)&&*s!='_'&&*s!='-'&&*s!='.'))return 0;
    return 1;
}
void recomp_mod_gameplay_config(const char *path) {
    char section[32768];size_t used=0;
    uint32_t contract_keys[512];unsigned contract_count=0;
    InterlockedExchange(&died,0);
    c4_count=0;
    if(enabled(path,"throwable_c4")) {
        DWORD n=GetPrivateProfileSectionA("ThrowableC4",section,sizeof(section),path);
        if(n>=sizeof(section)-2)bad("[ThrowableC4] is too large.");
        for(char *entry=section;*entry;entry+=strlen(entry)+1) {
            char key[128], *eq=strchr(entry,'=');
            if(!eq||eq==entry||(size_t)(eq-entry)>=sizeof(key)||(strcmp(eq+1,"0")&&strcmp(eq+1,"1")))bad("ThrowableC4 requires template_name=0 or 1.");
            memcpy(key,entry,eq-entry);key[eq-entry]=0;
            if(!identifier(key)||c4_count==256)bad("Invalid or excessive throwable C4 mappings.");
            uint32_t hash=hash_name(key);
            for(unsigned i=0;i<c4_count;++i)if(c4_templates[i]==hash)bad("Duplicate throwable C4 template/hash.");
            c4_templates[c4_count]=hash;c4_values[c4_count++]=eq[1]=='1';
        }
    }
    voice_count=0;
    if(enabled(path,"custom_voice_packs")) {
        DWORD n=GetPrivateProfileSectionA("VoicePacks",section,sizeof(section),path);
        if(n>=sizeof(section)-2)bad("[VoicePacks] is too large.");
        for(char *entry=section;*entry;entry+=strlen(entry)+1) {
            char key[128], *eq=strchr(entry,'=');
            if(!eq||eq==entry||(size_t)(eq-entry)>=sizeof(key)||!identifier(eq+1))bad("VoicePacks requires template_name=effect_set_name.");
            memcpy(key,entry,eq-entry);key[eq-entry]=0;
            if(!identifier(key)||voice_count==256)bad("Invalid or excessive voice pack mappings.");
            uint32_t hash=hash_name(key);
            for(unsigned i=0;i<voice_count;++i)if(voices[i].key==hash)bad("Duplicate voice template/hash.");
            voices[voice_count].key=hash;voices[voice_count++].effect=hash_name(eq+1);
        }
    }
    perma=enabled(path,"permadeath");
    int contracts=enabled(path,"permanent_contract_failure"),followers=enabled(path,"exops_followers");
    GetPrivateProfileStringA("Permadeath","save_profile","",profile,sizeof(profile),path);
    if(profile[0]&&(!identifier(profile)||strlen(profile)>=sizeof(profile)-1))bad("Invalid [Permadeath] save_profile (1-62 ASCII letters/digits/._-).");
    for(char *p=profile;*p;++p)*p=(char)tolower((unsigned char)*p);
    if(perma&&!profile[0])bad("permadeath=1 requires [Permadeath] save_profile.");
    if(!contracts&&!followers){script[0]=0;return;}
    used=(size_t)snprintf(script,sizeof(script),"RecompModConfig={permadeath=%s,followers=%s,contracts={",perma?"true":"false",followers?"true":"false");
    if(contracts) {
        DWORD n=GetPrivateProfileSectionA("PermanentContractFailure",section,sizeof(section),path);
        if(n>=sizeof(section)-2)bad("[PermanentContractFailure] is too large.");
        for(char *entry=section;*entry;entry+=strlen(entry)+1) {
            char key[128],*eq=strchr(entry,'=');
            if(!eq||eq==entry||(size_t)(eq-entry)>=sizeof(key))bad("Invalid contract entry.");
            memcpy(key,entry,eq-entry);key[eq-entry]=0;
            for(char *p=key;*p;++p)*p=(char)tolower((unsigned char)*p);
            if(!identifier(key)|| (strcmp(eq+1,"0")&&strcmp(eq+1,"1")))bad("Contracts require an exact mission asset ID and 0 or 1.");
            uint32_t hash=hash_name(key);
            for(unsigned i=0;i<contract_count;++i)if(contract_keys[i]==hash)bad("Duplicate contract identifier/hash.");
            if(contract_count==512)bad("Too many contract entries.");
            contract_keys[contract_count++]=hash;
            if(used+strlen(key)+20>=sizeof(script))bad("Too many contract entries.");
            used+=(size_t)sprintf(script+used,"['%s']=%s,",key,eq[1]=='1'?"true":"false");
        }
    }
    used+=(size_t)sprintf(script+used,"}}\n");
    if(used+sizeof(mod_gameplay_script)>sizeof(script))bad("Gameplay script exceeds configured limit.");
    memcpy(script+used,mod_gameplay_script,sizeof(mod_gameplay_script));
}
const char *recomp_mod_gameplay_script(void) { return script; }
const char *recomp_mod_save_profile(void) { return profile; }
int recomp_mod_permadeath(void) { return perma; }
void recomp_mod_player_died(void) { if(perma)InterlockedExchange(&died,1); }
int recomp_mod_take_death(void) { return InterlockedExchange(&died,0)!=0; }
