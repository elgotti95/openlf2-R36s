#ifndef MERCENARIES_MOD_EXTENSIONS_H
#define MERCENARIES_MOD_EXTENSIONS_H
#include <stdint.h>
void recomp_mod_player_inventory_begin(uint32_t player);
void recomp_mod_player_inventory_end(uint32_t player);
uint32_t recomp_mod_secondary_base(uint32_t actor);
uint32_t recomp_mod_secondary_capacity(uint32_t actor);
int recomp_mod_weapon_allowed(uint32_t weapon, uint32_t actor);
int recomp_mod_weapon_fixed_price(uint32_t weapon);
int recomp_mod_pda_allowed(uint32_t shop, uint32_t index);
int recomp_mod_pda_fixed_price(uint32_t shop, uint32_t index);
int recomp_mod_pda_has_available_supplier(uint32_t shop);
int recomp_mod_projectile_impact_stun(uint32_t projectile);
uint32_t recomp_mod_human_voice(uint32_t actor, uint32_t original);
int recomp_mod_projectile_c4(uint32_t projectile);
/* -1: retail projectile, 0: wait for remote, 1: detonate. */
int recomp_mod_c4_update(uint32_t projectile);
void recomp_mod_c4_remove(uint32_t projectile);
void recomp_mod_c4_broadcast(uint32_t trigger);
int recomp_mod_c4_active(void);
int recomp_mod_c4_menu_dirty(void);
void recomp_mod_c4_menu_done(void);
void recomp_mod_projectile_init(uint32_t projectile);
#endif
