#ifndef MERC_MOD_GAMEPLAY_H
#define MERC_MOD_GAMEPLAY_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void recomp_mod_gameplay_config(const char *path);
const char *recomp_mod_gameplay_script(void);
const char *recomp_mod_save_profile(void);
int recomp_mod_permadeath(void);
void recomp_mod_saves_init(const char *root);
void recomp_mod_player_died(void);
int recomp_mod_take_death(void);
int recomp_mod_delete_latest_save(void);
int recomp_mod_c4_for_template(uint32_t key);
uint32_t recomp_mod_voice_for_template(uint32_t key);
void recomp_mod_lua_init(uint32_t vm);
void recomp_mod_gameplay_tick(void);
#ifdef __cplusplus
}
#endif
#endif
