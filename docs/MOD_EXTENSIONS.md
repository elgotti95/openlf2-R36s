# Optional mod gameplay extensions

Place `modcompatibility.ini` in the root of a mod folder, for example
`mods/JE3/modcompatibility.ini`, alongside its `DATAxbox` folder. The launcher
loads this file into the selected mod profile. Restart the game after editing it.
The example [JE3 configuration](examples/je3-modcompatibility.ini) contains the
support templates from an early JE3 build.

```ini
[Mods]
faction_support=1
impact_stun_ammo=1
extra_grenade_slot=1

[SupportFactions]
template_sam_crate_COALITION=allies
template_sup_crate_COALITION=allies

[ImpactStunAmmo]
template_amm_STUNGRENADELAUNCHER=1
```

Each switch defaults to `0` and can be enabled independently. Keep
`extended_graphics_memory=1` and `expanded_world_properties=1` entries as well.
The switches do not create assets, crates, weapons, or catalog entries;
those still come from the mod's data.

## Supplier factions and support prices

With `faction_support=1`, `[SupportFactions]` associates an item with its supplier.
Use the exact ammo template identifier for world pickups and smoke activation.
For an item offered in the PDA, also map its catalog `Template_object_name`
(the support weapon template), not its localized display name. In the example,
`template_sam_crate_COALITION` is the ammo and `template_sup_crate_COALITION` is
the weapon. Different items can belong to different factions in the same mod.

Accepted faction values are `nk`, `sk`, `mafia`, `china`, `allies`, and `civilian`.
Identifiers and faction names are case-insensitive. A mapped supplier refuses
when its standing toward the player is hostile (at or below the retail `-0.6`
threshold). Unfriendly, neutral, and friendly standings allow the item, subject
to the normal money, inventory, and gameplay checks. Eligibility is checked on
pickup and use; collecting support before becoming hostile does not grant
permission to activate it afterward. NPC inventories and faction behavior are
not replaced.

Mapped non-Mafia support uses its authored base price without the Mafia
relationship multiplier. Map both ammo and catalog identifiers to keep world
and PDA prices consistent. Mapped Mafia support retains retail price adjustment.
Unmapped world items retain their existing behavior; unmapped PDA items retain
Mafia eligibility. The PDA can offer an eligible mapped supplier even while the
Mafia is hostile, but that does not unlock hostile suppliers' orders or alter bribes.

Scripts that implement their own purchase transactions need to apply their own
supplier condition; these hooks cover the retail item and support paths.

## Impact stun ammo

With `impact_stun_ammo=1`, list each desired ammo template under
`[ImpactStunAmmo]` with value `1`. Value `0` leaves that entry unchanged.
The selected projectile uses the retail nonlethal stun effect, with direct and
splash damage zeroed, and detonates on a collision instead of bouncing until its
normal delayed detonation. Ordinary stun grenades remain unchanged unless
explicitly listed. Authored trajectory and radius values remain in effect.

The example maps JE3's `template_amm_STUNGRENADELAUNCHER`, whose supplied data
otherwise uses an explosive effect. A mod author still needs to provide a weapon
that fires this ammo and place or distribute that weapon in the game.

## Third grenade/support slot

`extra_grenade_slot=1` increases the player's secondary inventory capacity from
two items to three. The existing grenade selection controls cycle through those
items. The additional slot accepts ordinary grenade or support items; it is not
a separate key binding or a slot reserved exclusively for support. Normal
replacement behavior applies once all three slots are occupied.

Only the player receives expanded storage. Soldiers retain two slots. Inventory
serialization uses the existing per-slot save fields and count, without changing
the file format. Loading a three-slot inventory with this option disabled limits
the restored secondary inventory to two slots. Use the launcher's separate saves
option so mod-only item identifiers stay in the mod save set.

## Configuration handling

The mod loader resolves `modcompatibility.ini` as a whole file: the last enabled
mod providing it wins. Sections from multiple mods are not merged. For a combined
mod setup, put the complete desired configuration in the winning mod's file.
Launching vanilla uses the installation's normal configuration instead.

The original SupportFactions and ImpactStunAmmo mappings accept printable ASCII
identifiers without spaces, up to 255 characters. Each supports 512 entries and
must fit within 64 KiB. New feature sections described below use letters, digits,
underscores, periods, and hyphens; template keys are at most 127 characters.
VoicePacks and ThrowableC4 support 256 mappings and 32 KiB per section.
Invalid values, duplicate identifier hashes, or oversized enabled sections stop
startup with a `[MOD-COMPATIBILITY]` diagnostic rather than silently bypassing a
supplier restriction. Mapping sections for disabled features are ignored.

## Implementation and validation

The configuration reader and native helpers are in
`ports/mercenaries/src/mod_compatibility.c` and `mod_extensions.c`.
`ports/mercenaries/scripts/Mod-Extensions-Patches.py` installs the hooks at retail
instruction boundaries during generated-code patching. Edit that patch source,
not the disposable generated C files.

Run the focused tests from the repository root after generating and patching the
retail code:

```powershell
python -m unittest tools.recomp.test_mod_extensions_native -v
```

They exercise enabled/disabled configurations, faction thresholds, denied weapon
activation, player-only inventory capacity, retail add/select/cycle/clear methods,
retail stun collision dispatch, and patch round trips. A playable JE3 check should
also cover HQ pickup, hostile smoke refusal, delivery and charging, grenade
cycling, save/load, and the stun launcher's visual effect on soldiers.


## Additional optional features

These require a recomp build containing the optional gameplay extensions; older
public builds do not gain them simply by adding the INI. Add keys to the existing
`[Mods]` section, rather than creating a second `[Mods]` section. All five default
to `0`. Configuration changes take effect after restarting the game.

```ini
[Mods]
custom_voice_packs=0
exops_followers=1
permanent_contract_failure=1
throwable_c4=1
permadeath=0

[Permadeath]
save_profile=je3

[PermanentContractFailure]
sw_allies3=1

[ThrowableC4]
template_amm_THROWABLEC4=1
```

The mission and projectile names above illustrate the format. Authors must check
that they are the intended assets in their build. No feature is enabled by a mod display name, or by recognizing an archive name.

### Permadeath: delete the last save for an explicit profile

```ini
[Mods]
permadeath=1

[Permadeath]
save_profile=je3
```

`save_profile` is an author-chosen stable ID (1–62 ASCII letters/digits, `.`, `_`,
or `-`; case-insensitive). Rename the mod folder freely: the same ID continues
tracking the same profile within the selected save directory. Different mods
should use different IDs. Mods deliberately sharing an ID share this tracking.
Permadeath refuses to start without an explicit profile.

While this configuration is active, successful save writes record the most
recent slot. On player death, the recomp removes **only that recorded slot** and
requests a return to the main menu. It does not remove all JE3 saves, delete the
whole multi-slot save container, or delete the slot merely loaded at startup.
Older slots, other save containers, and game options remain intact. There is no
fallback that starts deleting older saves on subsequent deaths.

Tracking continues with `permadeath=0` if `save_profile` remains configured. This
lets a mod track its saves before a player switches permadeath on. Saves made
before profile tracking existed cannot safely be identified as belonging to that
mod; make a new save with the profile configured first. If there is no recorded
save, death returns to the menu without deleting anything. If the recorded slot
has been overwritten or its contents no longer match, deletion is refused and
an error is shown. Another profile's save is not substituted.

The small tracking record lives under `<active save directory>/mod-state/`,
outside `mod-cache`; rebuilding the mod cache does not remove it. The launcher's
separate-save selection still determines which save directory is active. Changing
that selection changes the save directory and its tracking records.

This is deliberately "delete my latest save" behavior: older saves remain
loadable. It does not enforce a single-save campaign or prevent manual backups.

### Permanent contract failure: an explicit mission list

```ini
[Mods]
permanent_contract_failure=1

[PermanentContractFailure]
sw_allies3=1
ne_china2=1
```

Keys are exact **mission asset IDs**, not localized mission titles or faction
sequence numbers. `0` disables an entry. Unlisted missions retain retail retry
behavior. Ace missions and playable intro missions are always excluded, even if
listed. Supported standard faction arcs are `allies`, `china`, `mafia`, and `sk`.

For a listed standard contract, the failure/death callback takes the retail
cancel/respawn route instead of showing Retry, advances that faction's current
mission sequence by one, and records `recomp_failed_<mission asset ID> = 1` in
scribble memory. It does not grant the mission payout, intel, success flag, or
completion tally. Ordinary saving persists the result; this extension does not
force a disk autosave. If permadeath is also enabled, player death takes the
permadeath route instead.

A custom mission with its own failure implementation must call this public Lua
helper from its failure handler and stop its normal Retry path when it returns
true:

```lua
if Recomp_FailContractPermanently and Recomp_FailContractPermanently() then
    return
end
-- Existing retry handling follows here.
```

The standard `mission.lua` failure and hero-death handlers are wrapped
automatically. Missions replacing those handlers should use the explicit helper.
For mod-specific unlocks or cleanup, define:

```lua
function Recomp_OnPermanentContractFailure(missionAssetID)
    -- Apply this mission's authored failure consequences here.
    -- Do not call the failure helper recursively.
end
```

Advancing a sequence is not equivalent to satisfying every story prerequisite.
The author must playtest each listed mission's successor and implement necessary
failure-specific unlocks in the callback. Keep Ace prerequisites and end-of-arc
requirements in mind when choosing the allowlist.

### ExOps followers

```ini
[Mods]
exops_followers=1
```

Living human NPCs within 40 world units whose faction equals the player's faction
receive the retail follow/wait interaction. They initially wait; the player uses
the normal interaction prompt to tell them to follow and again to stop. The
recomp checks nearby actors twice per second during normal gameplay.

This does not turn ordinary friendly Allied, SK, Chinese, or Mafia soldiers into
ExOps. Set the desired NPCs' faction in the mod's data. Existing mission-managed
follower registrations are left alone; death or a faction change removes the
extension's registration. Retail AI priorities, pathfinding, and mission control
still apply. To offer the same interaction explicitly from a script, call
`Recomp_EnableFollower(actor)`; the feature switch and faction check still apply.

### Throwable C4

```ini
[Mods]
throwable_c4=1

[ThrowableC4]
template_amm_THROWABLEC4=1
```

Map the **ammo projectile template**, not the pickup/weapon template. Author it
as a grenade-style projectile with the desired model, throw velocity, bounce,
gravity, splash radius, force, and damage. Connect it to a throwable weapon or
grenade item using the mod's normal weapon data. No new weapon-class string is
required. The mapping does not create a pickup or grant ammunition.

A mapped projectile keeps its authored flight and bounce, but waits for the
retail `C4Trigger` broadcast instead of exploding when its fuse expires or when
it stops. The C4 detonator becomes available in the existing support menu while
charges are active. Use that detonator to explode the thrown charges, including
ones still airborne. The blast uses the retail C4 sound, large explosion visual,
and C4 damage category, with the mod's splash values.

Normal placed C4 still works with that detonator. The detonator remains available
while either placed or thrown charges remain. Unmapped frag/stun grenades keep
their normal behavior. Do not map the same ammo as impact-stun ammo and throwable
C4. Thrown projectiles use the retail projectile lifetime/streaming model; this
feature does not add sticky attachment or persistence of thrown charges across
save/load or map transitions.

### Custom NPC voice packs

```ini
[Mods]
custom_voice_packs=1

[VoicePacks]
template_my_exops_soldier=my_exops_human_sound
```

The right-hand value names a **human sound-effect set**, not a directory of WAVs.
The extension overrides the mapped NPC template's `soundEffect` at initialization.
Unmapped NPCs retain their authored sound effect. Template and set names are
case-insensitive. The template's ODF can also set `soundEffect` directly when the
author already controls that asset; the mapping makes the override optional.

The underlying game already dispatches human speech through data-driven
`human_set` configurations. Supply a human effect configuration with a `movement`
set and `speech_set`, and a speech configuration mapping events such as `curse`,
`cheer`, `alert`, `respond`, `death`, `death_ragdoll`, and `acknowledgement` to the
mod's compiled cues. Preserve a suitable movement set so footstep sounds remain.

Audio must still be authored in the game's Xbox sound-bank format. Include the
compiled sound/wave banks and cue/effect data in the mod, and register new banks
in its `rsm_xbox.ini` using the existing `SoundBanks`, `ResidentWaveBanks`, or
`StreamingWaveBanks` format as appropriate. Preserve the required retail entries.
Raw files in the editor's `sound/banks/vo` folder are authoring inputs; copying
those files alone into a mod does not register playable voice cues. This switch
is not a WAV importer, a sound-bank compiler, or a replacement for authored cues.

## Additional validation

```powershell
python -m unittest tools.recomp.test_mod_optional_gameplay tools.recomp.test_mod_extensions_native -v
```

The disposable-save test checks last-slot deletion, preservation of other slots
and profiles, restart tracking, and refusal after a slot changes. Native tests
check the C4 broadcast/lifecycle and retail blast argument layout, while Lua tests
check the per-mission allowlist and follower ownership. These checks do not replace
in-game testing of a mod's authored voice banks, mission progression, and weapons.
