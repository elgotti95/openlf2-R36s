#!/bin/bash
# PortMaster launcher for OpenLF2. Sits next to the openlf2/ folder in the port's zip:
#   OpenLF2.sh
#   openlf2/openlf2.aarch64, openlf2/scripts/, openlf2/libs.aarch64/, openlf2/licenses/

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# Find PortMaster on whichever firmware this is.
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi



source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/openlf2"
# config.json and the original game's installer (LF2_v2.0a.exe) live here, so they survive
# updates of the port.
CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR"
cd "$GAMEDIR" || exit 1

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

export XDG_DATA_HOME="$CONFDIR"





/opt/system/Tools/PortMaster/gptokeyb2 "openlf2.${DEVICE_ARCH}" -c "$GAMEDIR/controls.gptk" -k "openlf2.${DEVICE_ARCH}" &
sleep 2   # hagyd a gptokeyb2-nek, hogy betöltse az SDL2-t
pm_platform_helper "$GAMEDIR/openlf2.${DEVICE_ARCH}"
# vagy
# /opt/system/Tools/PortMaster/gptokeyb2 "openlf2.${DEVICE_ARCH}" -c "$GAMEDIR/controls.gptk" -k "openlf2.${DEVICE_ARCH}" -sudokill &










# The bundled SDL3 is loaded alongside the device's SDL2. Both export the same
# SDL_* symbols with incompatible return conventions, which makes
# dlsym(RTLD_DEFAULT, "SDL_*") resolve to the wrong library and crash.
# Preloading libSDL3.so.0 lets ELF interposition shadow SDL2 - this is exactly
# the mitigation the [sdl3forsdl2] shim asks for.
if [ -f "$GAMEDIR/libs.${DEVICE_ARCH}/libSDL3.so.0" ]; then
  #export LD_PRELOAD="$GAMEDIR/libs.${DEVICE_ARCH}/libSDL3.so.0${LD_PRELOAD:+:$LD_PRELOAD}"
  export LD_PRELOAD="$GAMEDIR/libs.${DEVICE_ARCH}/libSDL3.so.0"
else
  echo "WARN: libSDL3.so.0 not found in $GAMEDIR/libs.${DEVICE_ARCH}; SDL3/SDL2 interposition skipped."
fi






# A szkript legelején, a control.txt betöltése előtt:
# export LD_PRELOAD="/roms/ports/openlf2/libs.aarch64/libSDL3.so.0"
# Make sure the port's own libraries win over the system ones, so that the
# LD_PRELOAD below actually resolves the bundled libSDL3.so.0.
# export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
# vagy
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:/opt/system/Tools/PortMaster:$LD_LIBRARY_PATH"













# Gombok beállítása:
# export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
# vagy
# export SDL_GAMECONTROLLERCONFIG="190000004b4800000011000000010000,GO-Super Gamepad,x:b2,a:b0,b:b1,y:b3,back:b6,start:b7,guide:b8,leftshoulder:b4,rightshoulder:b5,lefttrigger:a2,righttrigger:a5,leftx:a0,lefty:a1,rightx:a3,righty:a4,dpup:b8,dpdown:b9,dpleft:b10,dpright:b11"
# vagy
# export SDL_GAMECONTROLLERCONFIG_FILE="$GAMEDIR/gamecontrollerdb.txt"
# vagy
# A gptokeyb2 indítása a konfigurációs fájllal
#$GPTOKEYB2 "openlf2.${DEVICE_ARCH}" -c "$GAMEDIR/controls.ini" &
#pm_platform_helper "$GAMEDIR/openlf2.${DEVICE_ARCH}"
# vagy

# OpenLF2 reads the controller through SDL itself; gptokeyb2 only provides the exit hotkey
# (Select + Start). We override $GPTOKEYB because the aarch64 binary has no extension.
# /opt/system/Tools/PortMaster/gptokeyb2 "openlf2.${DEVICE_ARCH}" -c "$GAMEDIR/controls.gptk" &
# pm_platform_helper "$GAMEDIR/openlf2.${DEVICE_ARCH}"




# The game needs the original installer. It can download it itself when the device is online;
# otherwise copy LF2_v2.0a.exe into $CONFDIR (see README.md).
if [ ! -f "$CONFDIR/LF2_v2.0a.exe" ]; then
  echo "LF2_v2.0a.exe not found in $CONFDIR; the game will offer to download it."
fi












# OpenLF2 reads the controller through SDL itself; gptokeyb only provides the exit hotkey
# (hotkey + start), so it has no key map.
#  vagy
# $GPTOKEYB "openlf2.${DEVICE_ARCH}" &   # kommenteld ki
# $GPTOKEYB "openlf2.${DEVICE_ARCH}" &
pm_platform_helper "$GAMEDIR/openlf2.${DEVICE_ARCH}"









# The bundled libSDL3.so.0 runs on the device's own SDL2, whose GLES renderer is the one that
# works everywhere; set OPENLF2_RENDERER (e.g. software) to try another.
#
# SDL_VIDEODRIVER override: on some R36S firmwares the autodetected video driver
# fails with "Unknown pixel format". kmsdrm is the safest default; override with
# SDL_VIDEODRIVER=wayland (or x11) if your firmware needs that instead.
# export SDL_VIDEODRIVER=...  # hagyd kommentben
# export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-kmsdrm}"
# export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}"
# export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"






# A játék indítása úgy, hogy az SDL ne ismerje fel a gamepadet
# (a gptokeyb2 továbbra is látja, mert az egy másik folyamat)
SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT="00000000000000000000000000000000" \
  ./openlf2.${DEVICE_ARCH} \
  --config-dir "$CONFDIR" \
  --default-controller \
  --renderer "${OPENLF2_RENDERER:-opengles2}"


# ./openlf2.${DEVICE_ARCH} \
#   --config-dir "$CONFDIR" \
#   --default-controller \
#   --renderer "${OPENLF2_RENDERER:-opengles2}"

pm_finish