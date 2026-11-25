# Player mods and model size - status

Ledger of the `openjk-player-mods` work: every Jedi Academy player model mod in
`$HOME/Downloads/star_wars_ja_mods/players` working in JA SP and MP, and a configurable player
model size (JA++-style, built in). Tools in `tools/player_mods/`.

## Last run

2026-11-25 (run 4, Linux): step 5 done - the player model size in SP.

- The `modelscale.cfg` parser moved to `shared/qcommon/q_modelscale.c` (MP game, MP cgame and the
  SP game build it; not in `SharedCommonFiles`).
- SP: `code/game/g_modelscale.cpp` - the same cvars plus `g_modelScaleSaved` (`CVAR_SAVEGAME`,
  the command's value), console commands `modelscale [n|default]` (no cheats) and `modelscales`
  (table, player, npcs). Hooks in `NPC_ParseParms`, `G_ChangePlayerModel`, `ClientSpawn`,
  `InitGame`, `G_RunFrame` and the svcmds table; SP pmove needed no change. The SP camera follows
  the player's size (`code/cgame/cg_modelscale.cpp`, `cg_thirdPersonModelScale`).
- The npc bbox rule, in both games: width, stand and crouch height each rescale from the scale they
  belong to (the `.npc` scale for a value the file set, 100 for a default one).
- Tested: SP `playermodel` yodavm / T_yoda / greeveevm, `modelscale` refused for lack of room and
  applied, crouching, save / load keeping the value, `g_modelScale` off / on, six npcs spawned in
  SP and MP with and without `g_modelScale`, saves made by the pre-change module (built from
  `a448e217`) loading in the new one, no-mods SP / MP / dedicated, no new warnings.

## Next

1. The user's answer on the stock SP npcs the default cfg resizes (Waiting for the user); then
   apply it (default cfg data or one precedence line in both games).
2. Step 6, custom skeletons in MP (T_Yoda's `_humanoid_yoda.gla`): read how MP picks the
   animation set per client (`bgAllAnims`, `localAnimIndex`, `BG_ParseAnimationFile`,
   `G_PlayerHasCustomSkeleton`, `CG_RegisterClientModelname`) and whether a client model on its own
   `.gla` can be animated on both server and cgame without a protocol change; ask the user before
   anything that isn't protocol- and ABI-neutral. If it can't be done neutrally, record that and
   go on to step 7.
3. Small leftovers, when convenient: the SP `playermodel` T-pose, Revan's ghost skins, the MP npc
   screenshots, the MP custom-character species names, `inventory.py` knowing the override
   recipes, the ui model preview showing the scale (optional).

## Waiting for the user

- The default `modelscale.cfg` has JA++'s entries, and the cfg wins over a `.npc` scale (the
  precedence asked for), so 11 stock SP npcs change size: Desann 135 -> 115, chewie 122 -> 118,
  jawa / jawa_armed 75 -> 80, MonMothma 100 -> 84, Jan / JediF 100 -> 94, Tavion (4 npcs)
  100 -> 95. Asked at the end of run 4 (see Decisions once answered).

## Steps

| # | Step | Status |
| --- | --- | --- |
| 0 | Setup: ledger, build, inventory, install script, mod table | done |
| 1 | Baseline matrix with the unchanged build | done (the MP npc screenshots are a leftover, see Next) |
| 2 | Loading fixes (limits, SP string merge, conflicts, ...) | done: `.npc` brace repair, SP playermodel recursion, string file merge + species fallback, override pk3 for the clashes, MP shader stray brace, MP `sounds.cfg` |
| 3 | MP model scale - game | done (run 3) |
| 4 | MP model scale - cgame and ui | done (run 3); the ui model preview does not show the scale (optional, left) |
| 5 | SP model scale | done (run 4) |
| 6 | Custom skeletons in MP (T_Yoda) | todo |
| 7 | Menus | todo |
| 8 | Sizes for every mod | todo |
| 9 | Final pass, README section | todo |

## Build

Linux (this PC, Debian 13, gcc 14.2, cmake 3.31, ninja):

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=$HOME/.local/share/openjk
TMPDIR=$HOME/.cache/tmp_build ninja -C build
```

`CMAKE_INSTALL_PREFIX` only tells the tools where the retail data is (`<prefix>/JediAcademy/base`);
nothing is installed from `build/`. Every CMake option is left at the tree's default.

Windows (not done yet): `cmake -S . -B build -G "Visual Studio 17 2022" -A x64` then
`cmake --build build --config RelWithDebInfo`; set `CMAKE_INSTALL_PREFIX` to the dir holding
`JediAcademy\base\assets*.pk3` (or pass `-Game` to the scripts).

## Tools

All in `tools/player_mods/`; every script has a usage block at its top and a debug option that
prints the equivalent shell commands.

- `inventory.py` (`python3 -I`): per mod its pk3s, model dirs and skins, npc / bot / jkb / saber
  names, custom `.gla`, SP menu files, npc size keys, stock overrides, files shared with other mods
  and which pk3 wins them (the engine's `FS_PathCmp` order: case-folded, last wins), cross checks
  (npc / bot names defined twice, models and sabers referenced but shipped by nothing). `--markdown`
  prints the table below, `--json` everything, `--test-cfg mp-bots|mp-models|mp-npcs|sp-npcs`
  writes a test cfg with an `echo @@ <kind> <mod>: <what> [<shot>]` marker before each check.
- `player_mods.conf`: `skip` (alternative variants not installed), `extra` (loose files for
  `base/`), `ignore` (extracted copies). Read by the inventory and both install scripts.
- `install_player_mods.sh` / `.ps1`: copies the chosen pk3s, the extras and the fork's own
  `tools/player_mods/base/*` (none yet; the default `modelscale.cfg` goes there) into `base/` -
  the OpenJK homepath's by default, `--dest` for a throwaway one. Writes
  `player_mods_manifest.txt` (sha256, file, source); never overwrites a file it did not install
  or one changed since; `--uninstall` removes exactly what is in the manifest (and unchanged);
  `--only` / `--exclude` take mod dirs, `mod/pk3` or pk3 names; lists the pk3s that replace stock
  files. Tested on Linux (install, rerun, foreign file, changed file, `--only`, `--exclude`,
  `--uninstall --only`, names with spaces); the `.ps1` is untested (no PowerShell on this PC).
- `run_test.sh` / `.ps1`: `sp|mp|ded` with `--cfg` / `--exec`; builds a throwaway home (mods in
  `base/`, built engine and renderers copied to `bin/`, built modules in `playermods_test/` loaded
  through `fs_game`), runs with `developer 1`, `logfile 2`, blank masters, LAN, a 1280x720 window,
  `in_mouse 0` (never grabs the mouse), `com_maxfps 60`; proves which `.so` files were loaded with
  `LD_DEBUG=files` (Linux; the `.ps1` relies on the `fs_game` search order); scans the log minus
  extension probes and minus a `--baseline` log. `.ps1` untested.
- `log_report.py`: per `@@` check the new error lines; `--sheets <dir>` labelled contact sheets of
  the screenshots (ImageMagick `montage`).
- `build_overrides.py` + `override/*.recipe`: the override pk3 for mod clashes (see Decisions);
  recipe keywords `needs`, `from`, `rename`, `copy`, `set`, `file`; `--list`, `--mods`.
- `sp_menu_check.sh` / `mp_menu_check.sh`: the SP character menu species names and the MP player
  model grid on one contact sheet each. GUI input (two clicks in SP, wheel notches in MP) goes only
  to the game window, verified by title, by its process holding the throwaway home and by being the
  active window before each input; `run_test.sh --mouse` reads the mouse without grabbing it. Linux
  only (xdotool, ImageMagick); no `.ps1` twins - on Windows the menus are checked by hand.

Testing notes (learned the hard way):

- OpenJK's screenshot command is `screenshot [name]` (JPEG); there is no `screenshotJPEG`.
- The MP server accepts at most 3 userinfo changes per 6 s (`INFO_CHANGE_MAX_COUNT` in
  `codemp/server/sv_client.cpp`, release builds) and a `model` change sends more than one - the
  model cfg waits 330 frames at 60 fps per change.
- MP: after `devmap` the player is a spectator in the join menu: `team free`, then `togglemenu`
  (sends Escape) closes it. `mp/duel1` puts the player on open floor; `cg_thirdPersonAngle 180`
  shows the model from the front.
- SP: `devmap` maps start with a cinematic; `exitview` skips it (`Svcmd_ExitView_f`).
- Dedicated: bots need `bot_enable 1`; stock bot names are full names (`Desann`, not `kyle`).
- The MP server gives every client the shared Kyle ghoul2 (`d_perPlayerGhoul2 0`), so a client
  model is only checked by the client (cgame falls back to Kyle silently: screenshots needed).
- Some log lines carry the timestamp twice; the scanners strip repeats.

## Mods

Inventory of 2026-11-25 (`inventory.py --markdown`, struck-through pk3s are skipped variants), plus
what the readmes say.

| Mod | pk3 installed | Models (skins) | NPCs (scale) | Bots | Sabers | Provides | Overrides | Shared with |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ashuras_clones | clone_adx.pk3 | cloneii (blue,clean,default,red) | Clone_adx, Clone_clean_adx, Clone_blue_adx, Clone_red_adx | Phase II Clonetrooper, Phase II Clonetrooper2 | - | MP menu, bots, npcs | - | - |
| BabyYoda | BabyYoda.pk3 | yodavm (default) | babyyoda (37) | yodavm, yodaoz, yodaepit, yoda_refugee | yoda | MP menu, bots, npcs, sabers | - | yodavm (43, loses) |
| darth_sidious | Darth_Sidious.pk3 | sid (default,default_tfu) | Sidious, Palpatine | - | - | MP menu, npcs | Darth_Sidious.pk3: 3 | - |
| DinDjarin | The_Mandalorian_Din_Djarin.pk3 | dindjarin (default) | Din_Djarin | - | - | MP menu, npcs | - | themando_doughnuts (3, loses) |
| DT_Maul | DT_Maul.pk3 | dt_maul (blue,default,default_hooded,default_robed,red) | DT_Maul, DT_Maul_hooded, DT_Maul_robed | Darth Maul | saber_maul, saber_maul2 | MP menu, bots, npcs, sabers | - | - |
| DT_Stormie_EP7 | zzzz_DT_Stormie_EP7.pk3 | dt_stormtrooper_ep7 (blue_pauldron,default,default_pauldron,default_vest,red_pauldron) | DT_StormTrooper_EP7 | DT Stormtrooper_EP7 | - | MP menu, bots, npcs | - | - |
| grievousvm | GrievousVM.pk3 | grievous (blue,default,default_nocape,red) | greeveevm (135), playergreevee (135) | grievousvm | greeveeb, greeveeg | MP menu, bots, npcs, sabers | - | - |
| hs_anakin | HS-anakin_saber-SP.pk3, HS_anakin.pk3 | anakinvm (default,default_sithana), anavader (default), hs_anakin (battle,blue,default,hood,red,robe,s-battle,s-hood,vmhair), hs_anakin2 (battle,blue,default,hood,red,robe,s-battle,s-hood,vmhair), hs_anakin_e2 (blue,default,red), jedi_anakin (default,seige) | hs_anakin, hs_anakin-robe, hs_anakin-hood, hs_anakin-battle | Anakin Skywalker | e3_anakin | MP menu, bots, npcs, sabers, SP menu, MENUS.str | HS-anakin_saber-SP.pk3: 2, HS_anakin.pk3: 3 | PSKDarthMalgus, ST_Finn_Poe_V2.1, ST_REY_V2.3, T_Anavader, T_luke_rotj_V2, hs_kenobi_rots (1, loses) |
| hs_dookuja | HS_rots-dooku.pk3, hs_dooku-saber_SP.pk3 | hs_dooku (aotc,blue,default,imperial,red) | hs_dooku | Count_Dooku | Dooku | MP menu, bots, npcs, sabers | hs_dooku-saber_SP.pk3: 2 | - |
| hs_kenobi_rots | hs_kenobi3-saber_SP.pk3, hs_rots-kenobi.pk3, hs_rots-kenobi_SP.pk3 | hs_kenobi_rots (battleworn,blue,default,red,robe,robehood), jedi_kenobi (no skin) | hs_kenobi_rots | General Kenobi | hs_kenobi3 | MP menu, bots, npcs, sabers, SP menu, MENUS.str | hs_kenobi3-saber_SP.pk3: 2, hs_rots-kenobi_SP.pk3: 1 | PSKDarthMalgus, ST_Finn_Poe_V2.1, ST_REY_V2.3, T_Anavader, T_luke_rotj_V2, hs_anakin (1, loses) |
| KyloRenTFAUpdated | zz_EPVII_KYLO_REN.pk3 | kylo_ren (default) | kyloren (120) | Kylo Ren | - | MP menu, bots, npcs, SP menu | - | kyloV.1.02 (2, wins) |
| kyloV.1.02 | kylo v.1.02.pk3 | kylo (blue,default,default_nocape,red) | Kylo, Kylo_nocape | Kylo Ren | - | MP menu, bots, npcs, SP menu | - | KyloRenTFAUpdated (2, loses) |
| PSKDarthMalgus | PskDarthMalgus.pk3, PskDarthMalgus_Hilt.pk3 | psdarthmalgus (default) | Darth_Malgus (115) | Darth Malgus | darth_malgus | MP menu, bots, npcs, sabers, SP menu, MENUS.str | PskDarthMalgus_Hilt.pk3: 2 | ST_Finn_Poe_V2.1, ST_REY_V2.3, T_Anavader, T_luke_rotj_V2, hs_anakin, hs_kenobi_rots (1, loses) |
| Seven-Qui-Gon_Jinn | Seven_-_Qui-Gon_Jinn.pk3 | quigon (battleworn,blue,default,hood,poncho,red,robe) | quigon, quigon_robe | - | quigon | MP menu, npcs, sabers | - | - |
| ST_Finn_Poe_V2.1 | st_finn.pk3, st_poe.pk3 | jedi_st_finn (no skin), jedi_st_poe (no skin), st_finn (blue,default,default_resistance,red), st_poe (blue,default,default_helmet,default_officer,default_resistance,red) | st_finn, st_finn_resistance, st_finn_saber, st_poe, st_poe_officer, st_poe_resistance | Finn, Poe Dameron | - | MP menu, bots, npcs, SP menu, MENUS.str | st_finn.pk3: 1, st_poe.pk3: 1 | PSKDarthMalgus, ST_REY_V2.3, T_Anavader, T_luke_rotj_V2, hs_anakin, hs_kenobi_rots (2, loses) |
| ST_REY_V2.3 | st_rey.pk3 | jedi_st_rey (no skin), st_rey (blue,default,default_jedi,default_resistance,default_scavenger,red) | st_rey, st_rey_jedi, st_rey_resistance, st_rey_scavenger | Rey | - | MP menu, bots, npcs, SP menu, MENUS.str | st_rey.pk3: 1 | PSKDarthMalgus, ST_Finn_Poe_V2.1, T_Anavader, T_luke_rotj_V2, hs_anakin, hs_kenobi_rots (1, loses) |
| SWTORRevanV1-04 | swtorrevanV.1.04.pk3, ~~MPSWTORRevan(noshader)V.1.04.pk3~~, ~~swtorrevan(noshader)V.1.04.pk3~~ | swtorrevan (blue,cape,default,default_2,default_clonewars,default_ghost,default_kotor,default_starforge,ghost,jedi,kotor,maelstrom,red,starforge,timeline) | revanreborn, kotorrevan, swtorrevan, revanmaelstrom, starforgerevan, darthrevan, revantimeline, revanjedi, revanghost | Revan, Revan Reborn, Darth Revan | - | MP menu, bots, npcs, SP menu | - | - |
| T_Anavader | T_AnaVader.pk3 | jedi_anakint (no skin), jedi_vader (no skin), t_anakin (blue,default,default_robehdn,default_robehup,default_sith,default_sithburned,default_srobehdn,default_srobehup,red), t_vader (default,default_breather,default_mask) | t_anakin, t_anakin-sith, t_anakin-hoodup, t_anakin-hooddn, t_anakin-shoodup, t_anakin-shooddn, t_anakin-sithburned, T_vader (120), T_vader-mask (120), T_vader-reveal (120) | AT_nakin, T_Vader | t_anakin, t_vader | MP menu, bots, npcs, sabers, SP menu, MENUS.str | T_AnaVader.pk3: 1 | PSKDarthMalgus, ST_Finn_Poe_V2.1, ST_REY_V2.3, T_luke_rotj_V2, hs_anakin, hs_kenobi_rots (1, loses) |
| T_luke_rotj_V2 | T_luke_rotj_V2.pk3 | jedi_luke (no skin), luke_bobble (default), t_luke_rotj (blue,default,default_endor,default_fd,default_robedn,default_robeup,default_tunic,red) | Luke, Luke_fd, Luke_tunic, Luke_robeup, Luke_robedn, Luke_endor, Luke_bobble | ROTJ Luke, ROTJ Luke FD, ROTJ Luke Tunic, ROTJ Luke Hood, ROTJ Luke Robe, ROTJ Luke Endor | Luke_ROTJ | MP menu, bots, npcs, sabers, SP menu, MENUS.str | T_luke_rotj_V2.pk3: 2 | PSKDarthMalgus, ST_Finn_Poe_V2.1, ST_REY_V2.3, T_Anavader, hs_anakin, hs_kenobi_rots (1, wins) |
| T_Yoda | T_Yoda.pk3 | _humanoid_yoda (no skin), t_yoda (default), t_yoda_mp (default) | T_yoda (45) | Yoda | T_yoda | MP menu, bots, npcs, sabers, gla | T_Yoda.pk3: 2 | - |
| themando_doughnuts | zzzzzz_themando.pk3 | dindjarin (default) | dindjarin | Din Djarin | - | MP menu, bots, npcs | zzzzzz_themando.pk3: 4 | DinDjarin (3, wins) |
| vaderepiii | VaderEp3.pk3 | vadervmm (blue,default,red) | vadervmm (120), vadersingle (120) | vadervmm | vadervmm | MP menu, bots, npcs, sabers | - | - |
| yodavm | YodaVM.pk3 | yodaflee (default), yodavm (blue,default,default_epfive,default_eptwo,red) | yodavm (50), yodaoz (50), yodaepit (50), yodapack (50) | yodavm, yodaoz, yodaepit, yoda_refugee | yoda | MP menu, bots, npcs, sabers | - | BabyYoda (43, wins) |
| zKyloRenKv2 | zzzzzzkylorenk.pk3 | kylorenk (default) | KyloRenK, KyloRenKEnemy | Kylo Ren | - | MP menu, bots, npcs | - | - |
| ZZ- Luke Skywalker Trainer v1.5 | ZZ- Luke Skywalker (Trainer).pk3, ~~ZZ- Luke Skywalker (Trainer, TOSHI).pk3~~ | luke_trainer (default,grogu,robe) | Luke_trainer, Luke_trainer/robe, Luke_trainer/grogu | - | - | MP menu, npcs | - | - |
| zzJTempleGv3 | zzzzJTempleGK.pk3 | jtempleg (default) | JediTempleGuard | - | templeg, templeg2 | MP menu, npcs, sabers | - | - |

Readme claims and choices:

| Mod | SP / MP per readme | Variant / notes | Extra dependencies |
| --- | --- | --- | --- |
| ashuras_clones | both; the hi-res version "will require OpenJK" in SP | the readme mentions a hi-res and a low-res pk3; only `clone_adx.pk3` is in the dir | - |
| BabyYoda | SP npc `BabyYoda` | ships `models/players/yodavm/` and yodavm's npc / bot / saber files: loses all 43 shared files to `YodaVM.pk3` (sorts later) | - |
| darth_sidious | bots, npcs `Sidious`, `Palpatine` | its `ext_data/weapons.dat`, `items.dat`, `dms.dat` are byte-identical to stock (harmless) | - |
| DinDjarin | npc / playermodel `Din_Djarin` | ships `models/players/dindjarin/` like themando_doughnuts: its glm / skin / sounds lose to `zzzzzz_themando.pk3` | - |
| DT_Maul | MP, bot, npc; "SP: No" | - | - |
| DT_Stormie_EP7 | MP, bot, npc; "SP: No" | - | - |
| grievousvm | SP + MP, npcs `greeveevm`, `playergreevee` | `.npc` scale 135 | - |
| hs_anakin | MP skins + SP hilt #2 replacement | `HS-anakin_saber-SP.pk3` replaces stock SP hilt `saber_2` (by design); its npcs name saber `hs_anakin`, which no `.sab` defines (it ships `e3_anakin`) | - |
| hs_dookuja | MP; SP hilt #3 replacement | `hs_dooku-saber_SP.pk3` replaces stock `saber_3` | "mystery skin" textures not in the pack (readme) |
| hs_kenobi_rots | MP; SP hilt #1 replacement; SP menu pk3 | `hs_kenobi3-saber_SP.pk3` replaces stock `saber_1` | - |
| KyloRenTFAUpdated | npc / playermodel `kyloren` | its `scripts/kylo.bot` + `botfiles/kylo.jkb` replace kyloV's (same names, sorts later) and its bot names model `KyloRen_Hood`, which no pk3 has; npc saber `sith_unstable` undefined | two saber mods (jkhub 2214 Kylo Ren's lightsaber ADX, 2218 Sith unstable saber) |
| kyloV.1.02 | SP, MP, bot, npc (`Kylo`, `Kylo_nocape`) | its bot file is overridden by KyloRenTFAUpdated's; npc saber `ren` undefined | DarthMartyr's Kylo Ren lightsaber (readme) |
| PSKDarthMalgus | bot (dark side), npc `darth_malgus` | `PskDarthMalgus_Hilt.pk3` replaces `ui/saber.menu` (adds `@MENUS_SINGLE_HILT10 "darth_malgus"`, but no `MENUS.str` key for it) and `MENUS.str`; npc saber `malgus` undefined (the .sab defines `darth_malgus`) | - |
| Seven-Qui-Gon_Jinn | npcs `quigon`, `quigon_robe` | no bot | - |
| ST_Finn_Poe_V2.1 | SP, npc, bot | SP menu keys `JEDI_ST_FINN`, `JEDI_ST_POE`, `JEDI_ST_REY` | - |
| ST_REY_V2.3 | SP, npc, bot | SP menu keys as above | - |
| SWTORRevanV1-04 | SP, MP, bot, npc | full `swtorrevanV.1.04.pk3` installed (readme default; `(noshader)` "if you experience problems", `MP...(noshader)` without npcs); npc saber `revan` undefined | - |
| T_Anavader | SP menu (`JEDI_ANAKINT`, `JEDI_VADER`), npcs, bots | - | - |
| T_luke_rotj_V2 | SP incl. character creation, bot, npc | replaces stock `ext_data/npcs/luke.npc` (Luke in SP cutscenes becomes ROTJ Luke, by design); its `MENUS.str` is the one that wins | - |
| T_Yoda | SP (own `.gla`), MP model `T_Yoda_MP` on `_humanoid` ("huge" unless scaled), bot | `Yoda.cfg` (bind home "playermodel t_yoda; cg_thirdpersonvertoffset -10") installed as an extra; replaces stock `sound/weapons/force/pull.mp3` / `push.mp3`; `T_Yoda - kopia/` is the pk3 extracted with `body.tga` renamed `body.png` (ignored) | - |
| themando_doughnuts | MP; SP via `playermodel dindjarin` | replaces stock `blaster_pistol` and `disruptor` weapon models; wins the `dindjarin` model dir over DinDjarin | - |
| vaderepiii | SP + MP npcs | `.npc` scale 120 | - |
| yodavm | SP + MP | `.npc` scale 50; shares its model dir and files with BabyYoda (wins) | - |
| zKyloRenKv2 | npcs `kylorenk`, `kylorenkenemy` | npc saber `kylo_ren` undefined | AshuraDX's Kylo Ren lightsaber (jkhub 2214) |
| ZZ- Luke Skywalker Trainer v1.5 | npc + model, no bot | `(Trainer)` installed (the readme's); `(Trainer, TOSHI)` swaps in Toshi's Luke head (glm, skins, shader, head textures) | - |
| zzJTempleGv3 | npc `jeditempleguard` | - | - |

## Compatibility matrix

Cells: `ok`, `broken: <what>`, `n/a` (the mod does not support it), `todo` (not checked yet).
Checked on Linux, 2026-11-25, with the unchanged build (fork `0eb6dfb7`) and all mods installed.

Fixes referred to: fix1 `.npc` brace repair (run 1), fix2 string file merge + species name fallback,
fix3 stray `}` in MP shader files, fix4 `sounds.cfg` sound dir (run 2); "override" = the override pk3.
"ok (listed)" in MP menu: the model's icons are in the MP player model grid (`mp_menu_check.sh`
contact sheet, 2026-11-25; the run lost focus after 14 pages, all mod pages were covered).

Columns: SP playermodel (`playermodel <npc>`), SP menu (character creation), SP npc
(`npc spawn`), MP model (`model <m>/<skin>`, every skin, screenshots), MP menu, MP bot (`addbot`,
dedicated server), MP npc (`npc spawn`), saber, sounds. "fix1" = with this run's `.npc` brace
repair (the baseline had every npc / playermodel cell after the Qui-Gon file broken, see Decisions).
MP npc cells are checked by the log (spawned or not); their screenshots were taken from the wrong
side (fixed in the cfg generator) - the visual MP npc check is still todo. SP cells: log plus
screenshots of the player after `playermodel` (front view, npcs killed first).

| Mod | SP playermodel | SP menu | SP npc | MP model | MP menu | MP bot | MP npc | Saber | Sounds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ashuras_clones | ok (fix1) | n/a | ok (fix1) | ok, 4 skins | ok (listed) | ok | ok (fix1) | stock | broken: no `sounds.cfg` (generic sounds) |
| BabyYoda | ok via override: `babyyoda`, npc scale 37 | n/a | ok via override | ok via override: `babyyoda` (Grogu); `yodavm` stays YodaVM's | ok (listed) | ok via override: "Baby Yoda" | ok via override (log) | its `yoda.sab` = YodaVM's | = yodavm's |
| darth_sidious | ok (fix1) | n/a | ok (fix1) | ok, 2 skins | ok (listed) | n/a (no `.bot`, readme says bots) | ok (fix1) | stock | ok |
| DinDjarin | ok via override: `dindjarin_gp` | n/a | ok via override | ok via override: `dindjarin_gp` (GustavoPredador's, caped) | ok (listed) | n/a | ok via override (log) | n/a | ok (`boba`) |
| DT_Maul | ok (fix1; readme: "SP: No") | n/a | ok (fix1) | ok, 5 skins | ok (listed) | ok | ok (fix1) | todo | ok |
| DT_Stormie_EP7 | ok (fix1; readme: "SP: No") | n/a | ok (fix1) | ok, 5 skins | ok (listed) | ok | ok (fix1) | stock | ok |
| grievousvm | ok (fix1), npc scale 135 | n/a | ok (fix1) | ok, 4 skins; 135 % from `modelscale.cfg` since run 3 | ok (listed) | ok | ok (fix1) | todo | ok |
| hs_anakin | ok (fix1) | ok (fix2): "Anakin Skywalker" | ok (fix1) | ok, all 6 model dirs (`anakinvm`, `anavader` have no icons: not in the menu) | ok (listed) | ok | ok (fix1) | broken: npcs name saber `hs_anakin`, not defined | ok |
| hs_dookuja | ok (fix1) | n/a | ok (fix1) | ok, 5 skins | ok (listed) | ok | ok (fix1) | ok (`.sab` typos `saberOn`, `munberBlades` ignored) | ok |
| hs_kenobi_rots | ok (fix1) | ok (fix2): "Obi-Wan Kenobi" | ok (fix1) | ok, 6 skins (`jedi_kenobi` untextured if forced) | ok (listed) | ok | ok (fix1) | ok (same `.sab` typos) | ok |
| KyloRenTFAUpdated | ok (fix1) | ok (fix2): "kylo_ren" (dir name, the mod has no MENUS entry) | ok (fix1) | ok | ok (listed) | ok via override: "Kylo Ren TFA" on `kylo_ren` | ok | broken: `sith_unstable` not installed (needs jkhub 2218) | partial set |
| kyloV.1.02 | ok (fix1) | ok (fix2): "kylo" (dir name) | ok (fix1) | ok, 4 skins | ok (listed) | ok via override: "Kylo Ren" on `Kylo` | ok (fix1) | broken: `ren` not installed (DarthMartyr's saber) | partial set |
| PSKDarthMalgus | ok (fix1) | ok (fix2): "psdarthmalgus" (dir name) | ok (fix1) | ok | ok (listed) | ok | ok (fix1) | broken: npc saber `malgus`, the `.sab` defines `darth_malgus`; hilt menu entry has no string | ok |
| Seven-Qui-Gon_Jinn | ok (fix1) | n/a | ok (fix1) - its `quigon.npc` was the cause | ok, 7 skins | ok (listed) | n/a | ok | ok | ok |
| ST_Finn_Poe_V2.1 | ok (fix1) | ok (fix2): "Finn", "Poe Dameron" | ok (fix1) | ok, 10 skins (`jedi_st_*` untextured if forced) | ok (listed) | ok | ok | stock | ok |
| ST_REY_V2.3 | ok (fix1) | ok (fix2): "Rey" | ok (fix1) | ok, 6 skins | ok (listed) | ok | ok | stock | ok |
| SWTORRevanV1-04 | ok (fix1) | ok (fix2): "swtorrevan" (dir name) | ok (fix1) | ok, 15 skins; its shader file loads since fix3 (stray `}` blanked); the ghost skins do not look translucent - todo | ok (listed) | ok | ok | broken: npc saber `revan` not defined | partial set |
| T_Anavader | ok (fix1) | ok (fix2): "Anakin Skywalker", "Darth Vader" | ok (fix1) | ok, 12 skins | ok (listed) | ok | ok | ok | ok |
| T_luke_rotj_V2 | ok (fix1) | ok (fix2): "Luke ROTJ" | ok (fix1) | ok, 9 skins | ok (listed) | ok | ok | ok | ok |
| T_Yoda | ok (fix1): own `.gla`, npc scale 45 | n/a | ok (fix1) | `t_yoda_mp`: ok, 45 % from `modelscale.cfg` since run 3; `t_yoda` (SP glm, own `.gla`): Kyle | ok (`t_yoda_mp` listed) | ok | ok | todo | ok |
| themando_doughnuts | ok (fix1) | n/a | ok (fix1) | ok | ok (listed) | ok | ok | n/a | ok since fix4 (`sound/chars/themando`) |
| vaderepiii | ok (fix1), scale 120 | n/a | ok (fix1) | ok, 3 skins; 120 % since run 3 | ok (listed) | ok | ok | todo | ok |
| yodavm | ok (fix1), scale 50 | n/a | ok (fix1) | ok, 6 skins incl. `yodaflee`; `yodavm` 50 % since run 3 (`yodaflee` has no entry) | ok (listed) | ok | ok | ok | ok |
| zKyloRenKv2 | ok (fix1) | n/a | ok (fix1) | ok | ok (listed) | ok via override: "Kylo Ren K" | ok | broken: `kylo_ren` not installed (needs jkhub 2214) | ok |
| ZZ- Luke Skywalker Trainer v1.5 | ok (fix1), 3 skins | n/a | ok (fix1) | ok, 3 skins | ok (listed) | n/a | ok | stock | ok |
| zzJTempleGv3 | ok (fix1) | n/a | ok (fix1) | ok | ok (listed) | n/a | ok | ok | ok |

Other findings:

- SP: a level has 64 skin configstrings (`G_FindConfigstringIndex` "overflow adding
  models/players/t_yoda/model_default.skin to set 1097-64" after ~60 different models in one map,
  an `ERR_DROP`). The test cfgs now reload the map every 20 checks. Raising the limit would change
  the SP configstring layout (savegames) - only after asking.
- MP shows every skin of every model; since run 3 the models in `modelscale.cfg` are drawn,
  boxed and predicted at their size.
- MP: the custom character species list (the MP UI's "Custom" model) gets the same names merge
  and fallback, not seen on screen yet.
- SP `t1_surprise`'s start spot hides a small player behind a rock ledge in the front view (YodaVM
  at 50 % is out of sight with or without model scaling): take the step 8 shots elsewhere.
- SP `playermodel`: several shots taken ~1.7 s after the switch show the new model in a T-pose
  (greeveevm, DT_StormTrooper_EP7, st_rey_scavenger, T_vader*, Luke_robeup / robedn / bobble,
  KyloRenK, JediTempleGuard) while other npcs of the same model animate. Timing or a missing
  animation after `G_ChangePlayerModel`? To check before calling those cells ok for good.

## Sizes

Not measured yet (step 8). The default `tools/player_mods/base/modelscale.cfg` holds the starting
points marked "cfg"; the `.npc` values apply to npcs only where the cfg has no entry. Not approved.

| Model | Scale | Source | In cfg | Approved |
| --- | --- | --- | --- | --- |
| chewbacca | 1.18 | JA++ `modelscale.cfg` | yes | no |
| desann | 1.15 | JA++ | yes | no |
| jan | 0.94 | JA++ | yes | no |
| jawa | 0.8 | JA++ | yes | no |
| monmothma | 0.84 | JA++ | yes | no |
| tavion, tavion_new | 0.95 | JA++ | yes | no |
| yoda, yodavm, babyyoda | 0.5 | `japp.diff` | yes | no |
| yodavm (npc yodavm / yodaoz / yodaepit / yodapack) | 0.50 | `.npc` | (yodavm) | no |
| babyyoda (npc babyyoda) | 0.37 | `.npc`; the cfg's `japp.diff` 0.5 wins over it for now - ask in step 8 | 0.5 | no |
| t_yoda, t_yoda_mp (npc T_yoda) | 0.45 | `.npc` | yes | no |
| grievous (npc greeveevm / playergreevee) | 1.35 | `.npc` | yes | no |
| psdarthmalgus (npc Darth_Malgus) | 1.15 | `.npc` | yes | no |
| t_vader (npc T_vader*) | 1.20 | `.npc` | yes | no |
| kylo_ren (npc kyloren) | 1.20 | `.npc` | yes | no |
| vadervmm (npc vadervmm / vadersingle) | 1.20 | `.npc` | yes | no |

## Decisions

- Model scale names (run 3): cvars `g_modelScale` (default 1, serverinfo, archived),
  `g_modelScaleCmd` (default 1, as in `japp.diff`), `g_modelScaleRange` (default `"30 200"`:
  Grogu to past Grievous; hard limits 10-250, 250 keeping the stand view height inside
  `ps.viewheight`'s signed 8 bits), cgame `cg_thirdPersonModelScale` (default 1); commands
  `/modelscale [n|default]` (`0` also resets), `modelscale <client> <n|default>` and `modelscales`
  on the server console / rcon. On a listen server `modelscale <n>` (one argument) goes on to the
  local player. JA++'s names had the `japp_` prefix; ours follow OpenJK's `g_` / `cg_`.
- `modelscale.cfg`: JA++'s format plus `model/skin` keys (the skin entry wins); a factor is
  rounded to whole percent (JA++ floors: its 1.18 gives 117, ours 118); bad pairs are skipped with
  a warning; up to 512 models, 64 KB; the topmost copy wins (no merge across pk3s).
- Precedence (players and bots): `/modelscale` (only while `g_modelScaleCmd` is on, clamped to the
  range), the cfg, 100. Npcs: the cfg, the `.npc` `scale`, 100. A `/modelscale` value lives until
  `default`, a disconnect or a map change (no session field - the game module reloads per map).
- The bbox (run 3): the feet stay at `MINS_Z` (-24), as every JA cgame raises a scaled model by
  `24 * (s - 1)`; width `15 * s`, stand / crouch / dead heights and view heights scaled above the
  feet. pmove computes them from `ps.iModelScale` (networked) when `pmove_t.modelScaleBBox` is set
  - by `g_modelScale` on the server, by the serverinfo key `g_modelScale` in the cgame (OpenJK
  asks forks not to add legacy-fix bits). `ps.standheight` / `crouchheight` stay unscaled (they
  go out as unsigned 10 bits; a scaled crouch height is negative below 60 %).
  A retail / JA++ client on a fork server predicts the standard box and view height for a scaled
  player (small misses at ceilings and walls, its own camera at the standard height); a fork client
  on a JA++ server predicts the standard box like that server (the key is missing).
- Growing (`/modelscale`, a model change, a cvar change) is refused while the bigger box would
  start in solid, with a message; it then applies at the next spawn. Spawning does not check.
- Npc bbox (run 4, both games): width, stand height and crouch height each rescale on their own; a
  value the `.npc` file set belongs to the `.npc` scale, a default one to 100, so at the `.npc`
  scale the file's values stay and a cfg / command scale resizes them proportionally (heights
  above the feet). A file value equal to the default can't be told apart and counts as a default
  (SP: kyloren's `width 16` = SP's default 16, so it scales). The player in SP follows the same
  rule from what `NPC_ParseParms` gave it (`playermodel <npc>`), or the default box (a plain
  model). (Run 3's MP rule left a box untouched as soon as the file set any key - T_Yoda kept
  Kyle's stand height.)
- SP (run 4): no pmove change - SP pmove takes the width from the entity's mins / maxs and the
  heights (and the view height, height - 4) from `client->standheight / crouchheight`, all of them
  already in the savegame, and the SP cgame raises a scaled model by `24 * (s - 1)` like MP's. SP
  keeps 1.0 in `s.modelScale` for 100. The `modelscale` value lives in `g_modelScaleSaved`
  (`CVAR_SAVEGAME`, so it is in the savegame and survives level changes; an old save without it
  keeps the current value). The game module reloads per level, so the player's model, `.npc`
  scale and base box are taken again at every model setup (`NPC_ParseParms`,
  `G_ChangePlayerModel`'s `model|skin` path, the `ClientSpawn` paths that keep `NPC_type
  "player"`), the model name from the ghoul2 file name when nothing else gives it. A `model|a|b|c`
  (head / torso / legs) skin has no table key: such players match on the model only.
  `g_modelScale 0` puts back the `.npc` scale and the box exactly as parsed.
- The parser is shared (run 4): `shared/qcommon/q_modelscale.c`, plain C with a print callback,
  compiled into jampgame, cgame and jagame explicitly (not through `SharedCommonFiles`, which the
  engines and renderers link too).
- Server ghoul2 (run 3): the saber bolts / render bolts (`properOrigin` in
  `WP_SaberPositionUpdate`) and the ghoul2 hit origin (`G_G2TraceCollide`) are raised by the same
  `24 * (s - 1)` the cgame draws with; checked within 1 unit. Other server-side bolt users (npc AI
  bolts, dismemberment, `g_combat` limb positions) still use the plain origin.
- Saber length is not scaled: the blade comes from the `.sab` file (YodaVM's and T_Yoda's sabers
  are already short), and a longer reach for big models would change the fight.
- The third-person camera's range and offsets scale with the viewed player (cosmetic, any server).

- The override pk3 is named `~playermods_overrides.pk3`: `FS_PathCmp` folds letters to upper
  case, so `_` (0x5F) beats `z`; only a leading `~` sorts after every mod pk3 (`zzzzzz_themando`,
  `zz_EPVII_...`). One pk3 for all recipes; a recipe applies only when all its mods are installed.
  Both kylo bots use `botfiles/kylo.jkb`, which KyloRenTFAUpdated wins (personality only).
- String files (run 2): every pk3's copy is merged, lower priority first, so the top copy still wins
  per key; done in SP and MP (`FS_ForEachFileCopy` in each `files.cpp`, the MP one skipping pk3s a
  pure server forbids). A species without a `MENUS_<SPECIES>` string shows its dir name.
- Shader files (run 2, MP renderers only): a `}` where a shader name is expected is blanked with a
  warning; anything else wrong still drops the file (OpenJK's existing check). rdsp-vanilla has no
  check (retail behaviour: Revan's `cape` shader is eaten there) - left as is.
- `sounds.cfg` (run 2, MP cgame): the first one-word line longer than one letter is the sound dir.
- Mod clashes (the user, 2026-11-25): **override pk3s**, built by the install script from the mods'
  own files and a committed recipe, for BabyYoda vs YodaVM (BabyYoda's model renamed `babyyoda`)
  and DinDjarin vs themando_doughnuts (DinDjarin's renamed, e.g. `dindjarin_gp`); a committed
  override `.bot` giving the three "Kylo Ren" bots distinct names on their real models.
- SP skin limit (64 per level, `MAX_CHARSKINS`): **left as is** (the user, 2026-11-25) - raising
  it would change the SP configstring layout and old savegames.

- `.npc` files are repaired when loaded (run 1): entries are flat, so a nested `{` becomes `}`, a
  `}` outside an entry is dropped and an entry open at the end of a file is closed, with a warning
  naming the file. Needed by Seven-Qui-Gon_Jinn's `quigon.npc` (three `{` typed for `}`), which hid
  every npc stored after it in the concatenated buffer. Balanced files are untouched; no format,
  protocol or ABI change.
- SP `G_ChangePlayerModel` no longer recurses when its `stormtrooper` fallback is missing too.
- The suspected `.npc` file-name list overflow (`npcExtensionListBuf[2048]`) is not one: the
  146 names take 2036 bytes. It is close, so a few more npc mods will overflow it - raise it when
  that happens (or before, with the next loader fix).

- Default variants: SWTOR Revan full version, Luke Trainer `(Trainer)`; T_Yoda's loose copy
  ignored, its `Yoda.cfg` installed (`player_mods.conf`).
- Stock overrides (SP hilts 1-3, `ui/saber.menu`, `MENUS.str`, `luke.npc`, force push / pull
  sounds, blaster pistol / disruptor models) are installed by default and listed by the install
  script; each can be left out with `--exclude <mod>/<pk3>`.
- The test harness and tools never touch the real homepath; the install script writes there only
  when run without `--dest`.

## For openjk-rs

One line per commit of this skill: hash, subject, files, what the Rust port must know.

- `d1c0cb70` `[Tools] player mods: inventory, install and test scripts` - `tools/player_mods/*`
  only; nothing to port.
- `4b021dcf` `[MP] player mods: repair unbalanced braces in .npc files` - new
  `codemp/game/g_playermods.c` / `.h` (`G_RepairNPCBraces`), one call in `NPC_LoadParms`
  (`codemp/game/NPC_stats.c`) after `COM_Compress`, before the strcat; CMake source list. Behaviour:
  scan outside quotes, nested `{` -> `}`, `}` at depth 0 -> space, returns open depth (0/1), the
  caller appends `}`; warning `ext_data/NPCs/<file>: repaired N misplaced brace(s)`.
- `13a83f9a` `[SP] player mods: repair .npc braces, no endless playermodel fallback` - new
  `code/game/g_playermods.cpp` / `.h` (same function, `gi.Printf`), the call in `NPC_LoadParms`
  (`code/game/NPC_stats.cpp`), and in `G_ChangePlayerModel` (`code/game/g_client.cpp`) the
  stormtrooper fallback only when the name is not already `stormtrooper`.
- `8e9ed33c` `[Tools] player mods: status ledger` - `PLAYER_MODS_STATUS.md` only.
- `7be9c02d` `[Tools] player mods: ledger - the user's decisions` - `PLAYER_MODS_STATUS.md` only.
- `7dc9bb1b` `[Tools] player mods: override pk3 for mod clashes, SP menu check` - `tools/player_mods/`
  only (`build_overrides.py`, `override/`, `sp_menu_check.sh`, install scripts, `run_test.sh
  --mouse`); nothing to port.
- `9274d046` `[SP] player mods: merge every pk3's copy of a string file` - `code/qcommon/files.cpp`
  (new `FS_ForEachFileCopy`: walk `fs_searchpaths`, collect pak / dir matches, call back
  lowest priority first, optionally skipping the top one; data 0-terminated), `qcommon.h`
  prototype, `stringed_ingame.cpp` (`SE_ParseLoadedData` split out of `SE_Load_Actual`,
  `SE_MergeCopy` callback, `SE_Load` merges lower copies first), `code/ui/ui_shared.cpp`
  (species name falls back to the dir name when `SE_GetString` returns "").
- `d06b5fc8` `[MP] player mods: merge every pk3's copy of a string file` - the same in
  `codemp/qcommon/files.cpp` (plus `FS_PakIsPure` skip), `qcommon.h`, `stringed_ingame.cpp`,
  `codemp/ui/ui_shared.c` (fallback through `trap->SE_GetStringTextString`).
- `0dfe223c` `[MP] player mods: a stray '}' no longer drops a whole shader file` -
  `ScanAndLoadShaderFiles` in `codemp/rd-vanilla/tr_shader.cpp` and `codemp/rd-rend2/tr_shader.cpp`:
  a `}` token where a shader name is expected is overwritten with a space, warning, continue.
- `4909f4cc` `[MP] player mods: tolerate an extra first line in sounds.cfg` - new
  `codemp/cgame/cg_playermods.c` / `.h` (`CG_PickSoundsCfgDir`), one call in `CG_LoadCISounds`
  (`cg_players.c`) right after reading the file; cgame CMake list.
- `852bd794` `[Tools] player mods: ledger, run 2` - `PLAYER_MODS_STATUS.md`, `mp_menu_check.sh`.
- `84dbd93b` `[MP] player mods: modelscale.cfg table, /modelscale and the scaled player bbox` -
  new `codemp/game/bg_modelscale.c` / `.h` (in game and cgame: constants, `BG_ModelScaleParse` -
  whitespace tokens, `//` and `/* */` anywhere, factor -> `floor(f * 100 + 0.5)`, digits and one
  dot only, hard clamp 10-250, later key replaces, 512 max; `BG_ModelScaleLookup` "model/skin"
  then "model", case-insensitive; range parse; `BG_ModelScaleFactor` 1 unless enabled, clientNum <
  MAX_CLIENTS and iModelScale not 0 / 100; `BG_ModelScaleZ` = MINS_Z + (z - MINS_Z) * f; view
  height rounded half up; half width 15 * f; draw offset -MINS_Z * (f - 1)), new
  `codemp/game/g_modelscale.c` / `.h` (table, per-client model / command scale, apply with the fit
  trace, npc rule, cvar callback, `/modelscale`, console `modelscale` (argc 3, else falls through
  on a listen server) / `modelscales`). Edits: `pmove_t.modelScaleBBox` (`bg_public.h`), every
  bbox / view height site of `PM_NoclipMove`, the roll check, `PM_CheckFixMins`, `PM_CanStand`,
  `PM_CheckDuck` and the roll in `PM_Footsteps` (`bg_pmove.c`); `g_active.c` sets the flag;
  `g_client.c` (`ClientUserinfoChanged` before the configstring, `ClientSpawn` before the first
  `ClientThink`, `ClientDisconnect`), `g_cmds.c` table, `g_svcmds.c` `ConsoleCommand`, `g_main.c`
  init after `NPC_InitGame`, `g_xcvar.h` (3 cvars) + `g_cvar.c` include, `NPC_stats.c` (before
  `SetupGameGhoul2Model`, not vehicles), `w_saber.c` (`properOrigin`, `g2HitOrigin`), cgame
  `cgs.modelScaleBBox` from serverinfo (`cg_servercmds.c`, `cg_local.h`) into `cg_pmove`
  (`cg_predict.c`); CMake lists.
- `fd6b367c` `[MP] player mods: third-person camera and head sprites follow the model scale` - new
  `codemp/cgame/cg_modelscale.c` / `.h` (`CG_ModelScaleCameraFactor` from
  `cg.predictedPlayerState.iModelScale`, 1 on a vehicle or with `cg_thirdPersonModelScale 0`;
  `CG_ModelScaleAboveOrigin` = height * `cent->modelScale[2]`), `cg_view.c` (vert offset, range,
  horz offset multiplied), `cg_players.c` (`CG_PlayerFloatSprite` +48), `cg_xcvar.h`, CMake list.
- `a448e217` `[Tools] player mods: default modelscale.cfg, ledger run 3` -
  `tools/player_mods/base/modelscale.cfg`, `PLAYER_MODS_STATUS.md`; nothing to port (the cfg is
  data the Rust port reads the same way).
- `16ada1e1` `[Shared] player mods: the modelscale.cfg parser moves to shared/qcommon` - new
  `shared/qcommon/q_modelscale.c` / `.h` (`Q_ModelScaleParse(table, text, fileName, print)`,
  `Q_ModelScaleLookup`, `Q_ModelScaleParseRange`, `Q_ModelScaleClamp`, the `MODELSCALE_*`
  constants, `MODELSCALE_MODEL_SIZE` 64; same behaviour as before, warnings through the callback),
  `codemp/game/bg_modelscale.c` / `.h` keep only the bbox helpers and the serverinfo key,
  `g_modelscale.c` calls the `Q_` names; the MP game / cgame CMake lists name the shared file. In
  the Rust port: one shared parser module used by both games.
- `2b65efec` `[MP] player mods: an npc's bbox follows its model scale part by part` -
  `codemp/game/g_modelscale.c` (`G_ModelScaleNPC`: per-part base scale, see Decisions; early out
  only when both scales are 100; `modelscales` lists `ET_NPC` entities) and its header comment.
- `131f5da6` `[SP] player mods: modelscale.cfg, the modelscale command and the scaled bbox` - new
  `code/game/g_modelscale.cpp` / `.h` (cvars incl. `g_modelScaleSaved`, table, player state,
  `G_ModelScaleSetModel(ent, model|NULL, skin, npcScale, bboxFromNpc)`, the per-part box,
  fit trace, restore, `G_ModelScaleRunFrame` (cvar modification counts), `Svcmd_ModelScale_f`,
  `Svcmd_ModelScales_f`), new `code/cgame/cg_modelscale.cpp` (`CG_ModelScaleCameraFactor` from
  `g_entities[0].s.modelScale[2]`); edits: `NPC_stats.cpp` (after `G_SetG2PlayerModel` in the
  normal model branch, npc scale from `s.modelScale[0]`), `g_client.cpp` (`G_ChangePlayerModel`
  `|` branch; the two `G_SetSkin` branches of `ClientSpawn`), `g_main.cpp` (`InitGame` after
  `NPC_InitGame`, top of `G_RunFrame`), `g_svcmds.cpp` (table), `cg_main.cpp` / `cg_local.h`
  (`cg_thirdPersonModelScale`), `cg_view.cpp` (vert offset, range, horz offset), SP CMake list
  (+ the shared parser).
- (this commit) `[Tools] player mods: ledger run 4` - `PLAYER_MODS_STATUS.md` only.
