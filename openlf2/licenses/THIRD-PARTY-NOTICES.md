<!-- SPDX-License-Identifier: MIT -->
<!--
  Notice inventory for dist/collect-licenses.py. Keep version strings in sync
  with conanfile.py and the per-platform toolchain documentation. Per-target
  release review still needs to check linked transitive libraries.

  Platform keys: appimage, deb, flatpak, windows, apple, ios, android, web, switch, vita.
  A row is required on a platform when that platform appears in its "Platforms" cell.
  "Notice source" records where the verbatim license text comes from at build time;
  the build scripts pass those paths to the collector.
-->

# Third-party notices

OpenLF2's own code, scripts and documentation are MIT-licensed ([LICENSE](LICENSE)). This
file inventories the licenses of the third-party components that artifacts may carry.
It is not itself a collection of their verbatim license texts. The original Little
Fighter 2 installer, executable and assets are **not** redistributed and carry no license
here; players supply `LF2_v2.0a.exe` themselves, or Flatpak downloads the pinned
archive.org snapshot of the lf2.net installer as extra data during installation.

Verbatim license texts are never transcribed here. The package scripts stage
direct dependency notices through `dist/collect-licenses.py`; remaining
transitive-library and static-linking checks are tracked separately.

The Debian package links separate Debian dependency packages, which carry their own
copyright files. Its own `/usr/share/doc/openlf2/copyright` includes the MIT license.
The Flatpak bundles LuaJIT and installs its upstream `COPYRIGHT` under
`/app/share/licenses/luajit/`; OpenLF2's license is under `/app/share/licenses/openlf2/`.
Other dependencies are supplied separately by the Freedesktop 26.08 runtime.
The AppImage uses PulseAudio only while building SDL3; its packaging script rejects
bundled PulseAudio libraries or a direct SDL3 link to one, so PulseAudio is not a
distributed component in the notice table below.

| Key | Component | Conan reference | Other versions | License | Platforms | Notice source |
| --- | --- | --- | --- | --- | --- | --- |
| ffmpeg | FFmpeg (libavformat, libavcodec, libavutil, libswresample) | ffmpeg/7.1.5 | 7.1.5 (Conan, web, Switch 7.1, Vita 9.0.1); system packages: Debian 13 7.1.5, Ubuntu 24.04 6.1.1 | LGPL-2.1-or-later (AppImage, Windows, Apple, Android, Switch, Vita and web builds) or GPL-2.0-or-later (Debian and Ubuntu system packages) | appimage, windows, apple, ios, android, switch, vita, web | upstream `COPYING.LGPLv2.1` from the versioned source archive, plus the archive itself and the build recipe |
| sdl3 | SDL3 | sdl/3.4.14 | 3.4.14 (Conan, Android, Switch), 3.4.16 (VitaSDK), 3.2.22 (Emscripten port) | Zlib | appimage, windows, apple, ios, android, web, switch, vita | upstream `LICENSE.txt`; Android also ships the `org/libsdl.app` Java glue from the same release |
| luajit | LuaJIT | luajit/2.1.0-20260908 | 2.1.0-20260908 (commit `c6ffc141a8762b41703f9287d63d93622a13dd8f`) | MIT | appimage, flatpak, windows, apple, ios, android, switch, vita | upstream `COPYRIGHT` |
| lua | Lua (web port only; LuaJIT has no WebAssembly target there) | — | 5.2.4 | MIT | web | upstream `doc/readme.html` license notice in the source archive |
| zlib | zlib | zlib/1.3.2 | 1.3.2 (Conan, Vita), 1.3.1 (Emscripten port, Switch portlibs) | Zlib | appimage, windows, apple, ios, android, web, switch, vita | upstream `LICENSE` from the source archive, or the distribution package's copyright file |
| bzip2 | bzip2 | bzip2/1.0.8 | 1.0.8 (Conan, Vita), 1.0.6 (Emscripten port) | bzip2-1.0.6 | appimage, windows, apple, ios, android, web, switch, vita | upstream `LICENSE` from the source archive, or the distribution package's copyright file |
| openssl | OpenSSL libcrypto | openssl/3.5.7 | 3.5.7 (Conan), 1.1.1t-dev (VitaSDK) | Apache-2.0 (Conan); OpenSSL/SSLeay dual license (VitaSDK 1.1.1t) | appimage, android, windows, apple, ios, vita | upstream `LICENSE.txt` or `LICENSE` from the matching source archive |
| libcurl | libcurl | libcurl/8.21.0 | 8.21.0 (Conan), 7.69.1 (Switch portlibs), 8.22.0 (VitaSDK `curl-mbedtls`) | curl | appimage, android, windows, apple, ios, switch, vita | upstream `COPYING` from the source archive, or the distribution package's copyright file |
| mbedtls | mbedTLS (replaces OpenSSL behind the SHA-256 adapter on Switch, and libcurl's TLS backend on Vita) | — | 2.28.10 (Switch portlibs), 3.6.5 (VitaSDK) | Apache-2.0 | switch, vita | portlib or package copyright file |
| ca-certificates | Mozilla CA trust bundle from the pinned VitaSDK image | — | 20260601~24.04.1 | MPL-2.0 for Mozilla source data | vita | `/usr/share/doc/ca-certificates/copyright` from the same image; includes notices for package tools that are not shipped |
| alsa | ALSA (libasound and its `alsa.conf` configuration tree) | — | distribution package | LGPL-2.1-or-later | appimage | `/usr/share/doc/libasound2-data/copyright` |
| ndk-runtime | Android NDK `libc++_shared.so` | — | 28.2.13676358 (r28c) | Apache-2.0 WITH LLVM-exception | android | the NDK's own license file in the pinned toolchain |
| mpg123 | mpg123 (VitaSDK runtime) | — | 1.33.7 | LGPL-2.1-or-later | vita | upstream `COPYING` from the versioned source archive |
| egl | Mesa EGL (Switch portlibs) | — | 20.1.0-rc3 | mixed Mesa notices | switch | upstream `docs/license.html` from the versioned source archive |
| system-libs | Shared system libraries bundled by `linuxdeploy` (X11, Wayland, Mesa, ALSA and their transitive dependencies) | — | as resolved in the build container | per package | appimage | `/usr/share/doc/<package>/copyright`, discovered per bundled library by `dist/audit-appimage-libs.sh` |
| appimage-runtime | AppImage type2-runtime (the startup stub embedded in every AppImage) | — | 20251108 | MIT | appimage | `LICENSE` from the pinned runtime tag, verified by SHA-256 |
| build-tools | `linuxdeploy`, `appimagetool`, Conan 2, CMake, devkitPro, VitaSDK, Emscripten, Android SDK/NDK, Gradle | — | as pinned in the project's build tooling | MIT, Apache-2.0, BSD-3-Clause, EPL-2.0 and others | _(none)_ | Build-time tools that are not shipped inside any artifact, so no notice is bundled. |

## Why these are the obligations

- **LGPL-2.1-or-later (FFmpeg, ALSA, mpg123).** Static linking is allowed under the LGPL
  with its section 6 distribution conditions. FFmpeg's checklist recommends shared
  linking as one practical route, along with corresponding source, build instructions
  and license text. AppImage and Android build shared FFmpeg; both stage its license text,
  while only AppImage currently bundles the corresponding source archive.
  Switch, Vita, web and iOS use static FFmpeg and need a relinking plan and corresponding
  materials before distribution.
- **GPL-2.0-or-later (Debian's and Ubuntu's FFmpeg).** The `deb` and local system builds link
  a GPL FFmpeg, which makes the combined work GPL-2.0-or-later as a whole. The `deb` package
  says so in its generated `copyright` file; the project stays MIT for its own
  code. Redistributing the `deb` therefore requires the complete corresponding source.
- **Apache-2.0 (OpenSSL 3, mbedTLS, the NDK runtime).** Redistribution must carry a copy of the license
  and any `NOTICE` content, and must state changes.
- **zlib, bzip2-1.0.6, curl and the MIT licenses (SDL3, LuaJIT, Lua, Mesa).** Redistribution
  must reproduce the notice text; these require no source offer and no relinkability.
