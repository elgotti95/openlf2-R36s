/* Guest-thread-only adapter using the retail Lua ABI; all CPU/VM stacks are
 * restored. No callbacks run in a renderer or file-I/O thread. */
#include "mod_gameplay.h"
extern uint32_t recomp_title_heap_allocate(uint32_t);
extern void recomp_title_heap_free(uint32_t);
static int mod_running_script;
static int mod_run_lua(uint32_t vm,const char *text)
{
    if(mod_running_script || !dev_guest_address(vm,0xA0) || g_esp<0x20000u || g_esp>=0x4000000u)return 0;
    recomp_saved_guest_cpu_context saved;
    recomp_save_guest_cpu_context(&saved);
    mod_running_script=1;
    size_t length=strlen(text);
    uint32_t buffer=recomp_title_heap_allocate((uint32_t)length+64u);
    int success=0;
    if(buffer) {
        uint32_t name=buffer+(uint32_t)length+1u;
        memcpy(guest_ptr(buffer),text,length+1u);strcpy(guest_ptr(name),"mod compatibility");
        uint32_t stack=(g_esp-0x4000u)&~15u;
        uint32_t top=dev_call(stack,0x001DC970u,0,1,&vm);
        uint32_t load[]={vm,buffer,(uint32_t)length,name};
        uint32_t error=dev_call(stack,0x001DC480u,0,4,load);
        if(!error){uint32_t args[]={vm,0,0,0};error=dev_call(stack,0x001DD5A0u,0,4,args);}
        if(error)recomp_lua_pcall_checkpoint(vm,error,name);
        uint32_t restore[]={vm,top};dev_call(stack,0x001DC980u,0,2,restore);
        success=!error;
        recomp_title_heap_free(buffer);
    }
    recomp_restore_guest_cpu_context(&saved);
    mod_running_script=0;
    return success;
}
void recomp_mod_lua_init(uint32_t vm)
{
    const char *script=recomp_mod_gameplay_script();
    if(*script) {
        if(!mod_run_lua(vm,script))fprintf(stderr,"[mod-compatibility] Could not initialize the optional script API.\n");
        else fprintf(stderr,"[mod-compatibility] Optional gameplay API installed in Lua VM %08X.\n",vm);
    }
}
static void mod_c4_menu_tick(void)
{
    if(!recomp_mod_c4_menu_dirty() || guest_u32(0x413F6Cu)!=0x4249D707u ||
       guest_u32(0x413F68u)!=0xC2CBD863u || *(uint8_t *)guest_ptr(0x403384u))return;
    recomp_saved_guest_cpu_context saved;recomp_save_guest_cpu_context(&saved);
    uint32_t stack=(g_esp-0x4000u)&~15u,name=0x660E4490u;
    uint32_t player=dev_call(stack,0x0008ECE0u,0,1,&name);
    if(dev_guest_address(player,0x100) && guest_u32(player)==0x2E32B8u) {
        if(recomp_mod_c4_active())dev_call(stack,0x0005B120u,player,0,NULL);
        else if(!guest_u32(0x3146B4u))dev_call(stack,0x0005CAF0u,player,0,NULL);
        recomp_mod_c4_menu_done();
    }
    recomp_restore_guest_cpu_context(&saved);
}
void recomp_mod_gameplay_tick(void)
{
    static ULONGLONG next_followers;
    if(mod_running_script||!g_xbox_mem_offset||g_esp<0x20000u||g_esp>=0x4000000u)return;
    mod_c4_menu_tick();
    uint32_t vm=guest_u32(0x3717BCu);
    if(!dev_guest_address(vm,0xA0)||*(uint8_t *)guest_ptr(0x3717D6u))return;
    if(recomp_mod_take_death()) {
        int deleted=recomp_mod_delete_latest_save();
        if(!mod_run_lua(vm,"Utility_ResetToShell()"))recomp_mod_player_died();
        if(!deleted)MessageBoxA(NULL,"The last tracked save could not be removed. It may have been changed by another profile or be in use. No other save was deleted.","Permadeath save error",MB_OK|MB_ICONERROR);
        return;
    }
    if(*recomp_mod_gameplay_script() && guest_u32(0x413F6Cu)==0x4249D707u && guest_u32(0x413F68u)==0xC2CBD863u && GetTickCount64()>=next_followers) {
        next_followers=GetTickCount64()+500;
        mod_run_lua(vm,"if Recomp_UpdateFollowers then Recomp_UpdateFollowers() end");
    }
}
