# OpenJK

OpenJK is a community effort to maintain and improve the game and engine powering Jedi Academy and Jedi Outcast, while maintaining _full backwards compatibility_ with the existing games and mods.  
This project does not intend to add major features, rebalance, or otherwise modify core gameplay.

Our aims are to:

- Improve the stability of the engine by fixing bugs and improving performance.
- Support more hardware (x86_64, Arm, Apple Silicon) and software platforms (Linux, macOS)
- Provide a clean base from which new code modifications can be made.

[![discord](https://img.shields.io/badge/discord-join-7289DA.svg?logo=discord&longCache=true&style=flat)](https://discord.gg/dPNCfeQ)
[![forum](https://img.shields.io/badge/forum-JKHub.org%20OpenJK-brightgreen.svg)](https://jkhub.org/forums/forum/49-openjk/)

[![build](https://github.com/JACoders/OpenJK/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/JACoders/OpenJK/actions/workflows/build.yml?query=branch%3Amaster)
[![coverity](https://scan.coverity.com/projects/1153/badge.svg)](https://scan.coverity.com/projects/1153)

## Supported Games

| Game | Single Player | Multi Player |
| - | - | - |
| Jedi Academy | ✅ Stable | ✅ Stable |
| Jedi Outcast | 😧 Works, needs attention | 🙅 Not supported - consider [JK2MV](https://jk2mv.org) |

Please direct support queries, discussions and feature requests to the JKHub sub-forum or Discord linked above.

## License

OpenJK is licensed under GPLv2 as free software. You are free to use, modify and redistribute OpenJK following the terms in [LICENSE.txt](https://github.com/JACoders/OpenJK/blob/master/LICENSE.txt)

## For players

To install OpenJK, you will first need Jedi Academy installed. If you don't already own the game you can buy it from online stores such as [Steam](https://store.steampowered.com/app/6020/), [Amazon](https://www.amazon.com/Star-Wars-Jedi-Knight-Academy-Pc/dp/B0000A2MCN) or [GOG](https://www.gog.com/game/star_wars_jedi_knight_jedi_academy).

Download the [latest build](https://github.com/JACoders/OpenJK/releases/tag/latest) ([alt link](https://builds.openjk.org)) for your operating system.

Installing and running OpenJK:

1. Extract the contents of the file into the Jedi Academy `GameData/` folder. For Steam users, this will be in `<Steam Folder>/steamapps/common/Jedi Academy/GameData/`.
1. Run `openjk.x86.exe` (Windows), `openjk.i386` (Linux 32-bit), `openjk.x86_64` (Linux 64-bit) or the `OpenJK` app bundle (macOS), depending on your operating system.

### Linux Instructions

If you do not have an existing JKA installation and need to download the base game:

1. Download and Install SteamCMD [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD#Linux).
1. Set the download path using steamCMD: `force_install_dir /path/to/install/jka/`
1. Using SteamCMD Set the platform to windows to download any windows game on steam. @sSteamCmdForcePlatformType "windows"
1. Using SteamCMD download the game, `app_update 6020`.

Extract the contents of the file into the Jedi Academy `GameData/` folder. For Steam users, this will be in `<Steam Folder>/steamapps/common/Jedi Academy/GameData/`.

### macOS Instructions

If you have the Mac App Store Version of Jedi Academy, follow these steps to get OpenJK runnning under macOS:

1. Install [Homebrew](https://brew.sh/) if you don't have it.
1. Open the Terminal app, and enter the command `brew install sdl2`.
1. Extract the contents of the OpenJK DMG into the game directory `/Applications/Star Wars Jedi Knight: Jedi Academy.app/Contents/`
1. Run `OpenJK.app` or `OpenJK SP.app`
1. Savegames, Config Files and Log Files are stored in `/Users/$USER/Library/Application Support/OpenJK/`

## Player mods (this fork)

This fork loads Jedi Academy player model mods (made for retail, JA+ or JA++) in SP and MP and
makes the player model size configurable, JA++-style but built into the game code (no Lua).
Without mods and with `g_modelScale 0` the game behaves as stock OpenJK; the network protocol, the
module ABI and the SP savegame format are unchanged. The status, every decision and the tested
mods are in [PLAYER_MODS_STATUS.md](PLAYER_MODS_STATUS.md).

### Installing the mods

`tools/player_mods/install_player_mods.sh` (bash) or `install_player_mods.ps1` (PowerShell)
copies the mods from a players dir (one dir per mod, default `~/Downloads/star_wars_ja_mods/players`)
into `base/` of the OpenJK homepath (`~/.local/share/openjk`, `Documents/My Games/OpenJK`):

```sh
./tools/player_mods/install_player_mods.sh                          # everything
./tools/player_mods/install_player_mods.sh --exclude BabyYoda       # leave a mod (or mod/pk3) out
./tools/player_mods/install_player_mods.sh --only T_Yoda,grievousvm # only some
./tools/player_mods/install_player_mods.sh --dest /tmp/test/base    # another base/ dir
./tools/player_mods/install_player_mods.sh --uninstall              # remove what it installed
./tools/player_mods/install_player_mods.sh --debug                  # print the commands only
```

It picks one variant where a mod ships alternatives (`tools/player_mods/player_mods.conf`), adds
the default `modelscale.cfg` and `~playermods_overrides.pk3` (built from the mods' own files and
the recipes in `tools/player_mods/override/`: renamed models / bots and menu names where mods
clash), lists the pk3s that replace stock files, writes `player_mods_manifest.txt` and never
overwrites a file it did not install. The mods themselves are never changed.

### Model size

| Cvar | Default | |
| --- | --- | --- |
| `g_modelScale` | `1` | scale players, bots and npcs by `modelscale.cfg` / `/modelscale` (MP: serverinfo; the fork's cgame predicts the scaled box only when the server has it on) |
| `g_modelScaleCmd` | `1` | players may use `/modelscale` |
| `g_modelScaleRange` | `"20 200"` | percent range `/modelscale` is clamped to (hard limits 10 - 250) |
| `cg_thirdPersonModelScale` | `1` | the third-person camera's range and height follow the player's scale |
| `g_customSkeletons` | `1` | MP, latched: player models on a humanoid-compatible custom `.gla` (T_Yoda) use it instead of falling back to Kyle |

Commands:

- `/modelscale [n|default]` - with a number, the own scale in percent (clamped to the range);
  without one, print it; `default` or `0` goes back to the table. Kept over respawns and model
  changes (MP until a map change or disconnect, SP in the savegame). SP needs no cheats.
- `modelscale <client> <n|default>` (MP server console / rcon) - set a client's scale.
- `modelscales` (server console / rcon, SP console) - list the table and the current scales.

`modelscale.cfg` (in `base/` or a pk3) is JA++'s format, and JA++'s own file loads unchanged:
whitespace-separated `model scale` pairs, the scale a factor (`0.5` is half size), `model/skin`
for one skin only, `//` and `/* */` comments. The default one (`tools/player_mods/base/modelscale.cfg`)
has JA++'s entries plus an in-universe size for every tested mod model. How to change sizes (the
file, the commands, npcs; a smaller Yoda / Grogu as the example): [docs/player-mod-sizes.md](docs/player-mod-sizes.md).

Precedence for players and bots: `/modelscale`, then `modelscale.cfg`, then the `.npc` file's
`scale` (SP `playermodel <npc>`), then 100. Npcs keep their own `.npc` scale where they have one,
else the table's. The bounding box (standing, crouched, dead), the view heights, the saber and hit
bolts and the camera scale with the model; the saber blade does not.

### Tools

`tools/player_mods/` also holds `inventory.py` (what each mod ships, its overrides and clashes,
test cfgs), `run_test.sh` (SP / MP / dedicated runs in a throwaway homepath), `log_report.py`,
`measure_heights.py` and `size_check.sh` (model heights), `sp_menu_check.sh` /
`mp_menu_check.sh` (menu contact sheets) and `interop_check.sh` (a fork server with a stock
OpenJK client and the other way round). Each script has a usage block at its top.

## For Developers

### Building OpenJK

- [Compilation guide](https://github.com/JACoders/OpenJK/wiki/Compilation-guide)
- [Debugging guide](https://github.com/JACoders/OpenJK/wiki/Debugging)

### Contributing to OpenJK

- [Fork](https://github.com/JACoders/OpenJK/fork) the project on GitHub
- Create a new branch and make your changes
- Send a [pull request](https://help.github.com/articles/creating-a-pull-request) to upstream (JACoders/OpenJK)

### Using OpenJK as a base for a new mod

- [Fork](https://github.com/JACoders/OpenJK/fork) the project on GitHub
- Change the JK_VERSION define in codemp/qcommon/game_version.h from "OpenJK" to your project name
- If you make a nice change, please consider back-porting to upstream via pull request as described above. This is so everyone benefits without having to reinvent the wheel for every project.

## Maintainers (full list: [@JACoders](https://github.com/orgs/JACoders/people))

Leads:

- [Ensiform](https://github.com/ensiform)
- [razor](https://github.com/Razish)
- [Xycaleth](https://github.com/xycaleth)

## Significant contributors ([full list](https://github.com/JACoders/OpenJK/graphs/contributors))

- [bibendovsky](https://github.com/bibendovsky) (save games, platform support)
- [BobaFett](https://github.com/Lrns123)
- [BSzili](https://github.com/BSzili) (JK2, platform support)
- [Cat](https://github.com/deepy) (infra)
- [Didz](https://github.com/dionrhys)
- [eezstreet](https://github.com/eezstreet)
- exidl (SDL2, platform support)
- [ImperatorPrime](https://github.com/ImperatorPrime) (JK2)
- [mrwonko](https://github.com/mrwonko)
- [redsaurus](https://github.com/redsaurus)
- [Scooper](https://github.com/xScooper)
- [Sil](https://github.com/TheSil)
- [smcv](https://github.com/smcv) (debian packaging)
- [Tristamus](https://tristamus.com>) (icon)
