# Player mods and model size - status

Ledger of the `openjk-player-mods` work: every Jedi Academy player model mod in
`$HOME/Downloads/star_wars_ja_mods/players` working in JA SP and MP, and a configurable player
model size (JA++-style, built in). Tools in `tools/player_mods/`.

## Last run

2026-11-26 (run 7, Linux): step 9, the final pass - done. The work is finished; later runs only
handle new mods in `players/` or what the user asks for.

- The inventory is unchanged (26 mods, 35 pk3s). Full matrix again with every fix and the default
  `modelscale.cfg`: 31 MP bots (dedicated, no new error lines), 146 MP model skins, 76 MP npcs, 76
  SP npcs and `playermodel`s (screenshots of each). Every cell still holds; see the matrix notes.
- Found and fixed: SP `playermodel` left the new model in its bind pose (the "T-pose" leftover)
  while an anim timer ran - `G_ChangePlayerModel` re-set the current anim without
  `SETANIM_FLAG_OVERRIDE`. Stock bug (also with stock npcs); after the fix the SP pass has no
  T-pose left. The one remaining odd pose, a stormtrooper holding Maul's staff level, is stock
  behaviour (`RebornMasterStaff` then `stormtrooper` does the same; `saberattackcycle` ends it).
- The MP npc check is visual now: `inventory.py --test-cfg mp-npcs` kills each npc before the next
  and looks from the side with `notarget` (before, npcs piled up, fought and killed the player).
- New finding: T_AnaVader's `t_anakin` / `t_vader` sabers name hilt models
  (`saber_anakinEp3`, `saber_VaderEp5`) that it does not ship and its readme does not mention.
- `/modelscale` at the range ends, MP and SP: 19 -> 20, 250 -> 200 (MP grows to a -30..30 x
  -24..104 box, view height 96; SP under the t1_surprise ledge refuses 200 % for lack of room, as
  designed), `default` resets, moving / jumping / crouching at both ends without a prediction miss;
  SP save at 60 %, `default`, load: 60 % again. The override models `babyyoda` and `dindjarin_gp`
  load as MP player models.
- Interop (`interop_check.sh`, new) with the stock OpenJK build in the install dir (OpenJK
  "latest" of 2025-12-26, retail protocol, its own base modules - proven loaded): a stock client on
  the fork server sees and plays scaled players (Grievous 123 % from the cfg, `/modelscale 50`
  handled by the fork server, `rcon modelscales`), its camera stays at the standard height, one
  prediction miss at the join (spawn) and at most a sub-unit one later; `t_yoda` is refused by the
  stock cgame ("unsupported multiplayer model") and drawn as Kyle. A fork client on the stock
  server: no scaling, "Unknown command modelscale", `t_yoda` falls back to Kyle (no
  `g_customSkeletons` key), the same single join miss. Both directions exit cleanly.
- Without mods SP, MP (`g_modelScale 0`) and the dedicated server start, load a map and quit
  cleanly (the only new log line is the `modelscale.cfg` file probe).
- README: a "Player mods (this fork)" section (install script, cvars, commands, `modelscale.cfg`,
  precedence, tools). Throwaway homes removed (`/tmp` had filled up mid-run with them).

## Next

Nothing - the steps are done. A later run: re-run `inventory.py` for new mods in `players/` (then
install, matrix rows, a size in `modelscale.cfg`), or what the user asks. Optional leftovers, only
on request: the ui model preview showing the scale, Revan's ghost skins not looking translucent,
`inventory.py` reading the override recipes, the untested `.ps1` scripts on Windows.

## Waiting for the user

Nothing.

## Steps

| # | Step | Status |
| --- | --- | --- |
| 0 | Setup: ledger, build, inventory, install script, mod table | done |
| 1 | Baseline matrix with the unchanged build | done (the MP npc screenshots too, run 7) |
| 2 | Loading fixes (limits, SP string merge, conflicts, ...) | done: `.npc` brace repair, SP playermodel recursion, string file merge + species fallback, override pk3 for the clashes, MP shader stray brace, MP `sounds.cfg` |
| 3 | MP model scale - game | done (run 3) |
| 4 | MP model scale - cgame and ui | done (run 3); the ui model preview does not show the scale (optional, left) |
| 5 | SP model scale | done (run 4) |
| 6 | Custom skeletons in MP (T_Yoda) | done (run 5) |
| 7 | Menus | done (run 6) |
| 8 | Sizes for every mod | done (run 6) |
| 9 | Final pass, README section | done (run 7) |

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
  `sp_menu_check.sh --hilts`: one more Next click, the SP saber menu's single hilt names.
  `mp_menu_check.sh --species`: the MP custom character menu (`ui_openmenu ingame_player2`), one
  click on its species button per species (the item does not follow `ui_char_model` while open).
- `measure_heights.py` (`python3 -I`): each model's LOD 0 base-pose height (drawn surfaces, the
  copy the engine loads) against Kyle's; `--target heights.txt` proposes `modelscale.cfg` factors,
  `--sizes` prints `<model> <percent>` (the proposal or `--cfg <file>`), `--json`, `--all`.
- `size_check.sh` / `.ps1`: every model at 100 % and at its size (proposal or `--cfg`) next to a
  Kyle npc, side camera at a fixed distance, one contact sheet; no GUI input. `.ps1` untested.
- `interop_check.sh` / `.ps1`: `fork-server` (the fork's dedicated server and the install's stock
  client), `stock-server` (the install's stock dedicated server and the fork's client) or `both`;
  each side its own home with the mods, port 29170 on 127.0.0.1, `rcon quit` at the end; prints
  which modules were loaded (LD_DEBUG "calling init"), the client's prediction misses and error
  lines, a contact sheet. Needs a display. `.ps1` untested.
- `run_test.sh --set <cvar> <value>` (`run_test.ps1 -Set @{...}`): extra `+set`s before the cfg.

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
- Never edit a script while a run of it is going: bash reads scripts as it goes (run 7 lost a
  run that way).
- The throwaway homes hold a copy of every mod (~300 MB each) and `/tmp` is a small tmpfs: remove
  them after a pass, or put them under `~/.cache`.
- MP `npc spawn` is a client command: the `mp-npcs` cfg needs `run_test.sh mp`, not `ded`.

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
Checked on Linux, 2026-11-25, with the unchanged build (fork `0eb6dfb7`) and all mods installed;
rechecked on Linux 2026-11-26 (run 7, fork `ecae7a49`) with every fix and the default
`modelscale.cfg`: every SP, MP model, MP bot and MP npc cell below as written.

Fixes referred to: fix1 `.npc` brace repair (run 1), fix2 string file merge + species name fallback,
fix3 stray `}` in MP shader files, fix4 `sounds.cfg` sound dir (run 2), fix5 SP `playermodel` anim
override (run 7); "override" = the override pk3.
"ok (listed)" in MP menu: the model's icons are in the MP player model grid (`mp_menu_check.sh`
contact sheet, 2026-11-25, rechecked 2026-11-26 with all 17 pages). SP menu names rechecked
2026-11-26 (`sp_menu_check.sh`, MP custom character menu `mp_menu_check.sh --species`: the same
names); "names" = the override pk3's `MENUS.str` (run 6).

Columns: SP playermodel (`playermodel <npc>`), SP menu (character creation), SP npc
(`npc spawn`), MP model (`model <m>/<skin>`, every skin, screenshots), MP menu, MP bot (`addbot`,
dedicated server), MP npc (`npc spawn`), saber, sounds. "fix1" = with this run's `.npc` brace
repair (the baseline had every npc / playermodel cell after the Qui-Gon file broken, see Decisions).
MP npc cells: log plus screenshots since run 7 (one npc at a time, side view). SP cells: log plus
screenshots of the player after `playermodel` (front view, npcs killed first); since run 7 no
`playermodel` T-pose (fix5).

| Mod | SP playermodel | SP menu | SP npc | MP model | MP menu | MP bot | MP npc | Saber | Sounds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ashuras_clones | ok (fix1) | n/a | ok (fix1) | ok, 4 skins | ok (listed) | ok | ok (fix1) | stock | broken: no `sounds.cfg` (generic sounds) |
| BabyYoda | ok via override: `babyyoda`, npc scale 37 | n/a | ok via override | ok via override: `babyyoda` (Grogu); `yodavm` stays YodaVM's | ok (listed) | ok via override: "Baby Yoda" | ok via override (log) | its `yoda.sab` = YodaVM's | = yodavm's |
| darth_sidious | ok (fix1) | n/a | ok (fix1) | ok, 2 skins | ok (listed) | n/a (no `.bot`, readme says bots) | ok (fix1) | stock | ok |
| DinDjarin | ok via override: `dindjarin_gp` | n/a | ok via override | ok via override: `dindjarin_gp` (GustavoPredador's, caped) | ok (listed) | n/a | ok via override (log) | n/a | ok (`boba`) |
| DT_Maul | ok (fix1; readme: "SP: No") | n/a | ok (fix1) | ok, 5 skins | ok (listed) | ok | ok (fix1) | ok (red single and staff, SP shots) | ok |
| DT_Stormie_EP7 | ok (fix1; readme: "SP: No") | n/a | ok (fix1) | ok, 5 skins | ok (listed) | ok | ok (fix1) | stock | ok |
| grievousvm | ok (fix1), npc scale 135 | n/a | ok (fix1) | ok, 4 skins; 123 % from `modelscale.cfg` since run 6 | ok (listed) | ok | ok (fix1) | ok (`greeveeb` / `greeveeg`, SP shots) | ok |
| hs_anakin | ok (fix1) | ok (fix2, names): "Anakin (HapSlash)" | ok (fix1) | ok, all 6 model dirs (`anakinvm`, `anavader` have no icons: not in the menu) | ok (listed) | ok | ok (fix1) | broken: npcs name saber `hs_anakin`, not defined | ok |
| hs_dookuja | ok (fix1) | n/a | ok (fix1) | ok, 5 skins | ok (listed) | ok | ok (fix1) | ok (`.sab` typos `saberOn`, `munberBlades` ignored) | ok |
| hs_kenobi_rots | ok (fix1) | ok (fix2): "Obi-Wan Kenobi" | ok (fix1) | ok, 6 skins (`jedi_kenobi` untextured if forced) | ok (listed) | ok | ok (fix1) | ok (same `.sab` typos) | ok |
| KyloRenTFAUpdated | ok (fix1) | ok (names): "Kylo Ren (TFA)" (the mod has no MENUS entry) | ok (fix1) | ok | ok (listed) | ok via override: "Kylo Ren TFA" on `kylo_ren` | ok | broken: `sith_unstable` not installed (needs jkhub 2218) | partial set |
| kyloV.1.02 | ok (fix1) | ok (names): "Kylo Ren" | ok (fix1) | ok, 4 skins | ok (listed) | ok via override: "Kylo Ren" on `Kylo` | ok (fix1) | broken: `ren` not installed (DarthMartyr's saber) | partial set |
| PSKDarthMalgus | ok (fix1) | ok (names): "Darth Malgus" | ok (fix1) | ok | ok (listed) | ok | ok (fix1) | broken: npc saber `malgus`, the `.sab` defines `darth_malgus`; hilt menu entry has no string | ok |
| Seven-Qui-Gon_Jinn | ok (fix1) | n/a | ok (fix1) - its `quigon.npc` was the cause | ok, 7 skins | ok (listed) | n/a | ok | ok | ok |
| ST_Finn_Poe_V2.1 | ok (fix1) | ok (fix2): "Finn", "Poe Dameron" | ok (fix1) | ok, 10 skins (`jedi_st_*` untextured if forced) | ok (listed) | ok | ok | stock | ok |
| ST_REY_V2.3 | ok (fix1) | ok (fix2): "Rey" | ok (fix1) | ok, 6 skins | ok (listed) | ok | ok | stock | ok |
| SWTORRevanV1-04 | ok (fix1) | ok (names): "Revan" | ok (fix1) | ok, 15 skins; its shader file loads since fix3 (stray `}` blanked); the ghost skins do not look translucent - todo | ok (listed) | ok | ok | broken: npc saber `revan` not defined | partial set |
| T_Anavader | ok (fix1) | ok (fix2, names): "Anakin (Toshi)", "Darth Vader" | ok (fix1) | ok, 12 skins | ok (listed) | ok | ok | broken: `t_anakin` / `t_vader` name hilts `saber_anakinEp3` / `saber_VaderEp5`, not shipped (run 7) | ok |
| T_luke_rotj_V2 | ok (fix1) | ok (fix2): "Luke ROTJ" | ok (fix1) | ok, 9 skins | ok (listed) | ok | ok | ok | ok |
| T_Yoda | ok (fix1): own `.gla`, npc scale 45 | n/a | ok (fix1) | `t_yoda_mp`: ok, 34 % from `modelscale.cfg` since run 6; `t_yoda` (SP glm, own `.gla`): ok on its own skeleton since run 5 (`g_customSkeletons`), Kyle before | ok (`t_yoda_mp` listed) | ok | ok | ok (short green blade, SP shot swinging) | ok |
| themando_doughnuts | ok (fix1) | n/a | ok (fix1) | ok | ok (listed) | ok | ok | n/a | ok since fix4 (`sound/chars/themando`) |
| vaderepiii | ok (fix1), scale 120 | n/a | ok (fix1) | ok, 3 skins; 111 % since run 6 | ok (listed) | ok | ok | ok (`vadervmm`, SP shots) | ok |
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
- MP: the custom character species list (the MP UI's "Custom" model) shows the same names as SP
  (seen on screen in run 6).
- SP `t1_surprise`'s start spot hides a small player behind a rock ledge in the front view (YodaVM
  at 50 % is out of sight with or without model scaling): take the step 8 shots elsewhere.
- SP `playermodel` T-pose (run 7, fix5): the new model stood in its bind pose for seconds when an
  anim timer was running at the switch (`G_ChangePlayerModel` without `SETANIM_FLAG_OVERRIDE`);
  fixed. A model switched to from a staff saber user (DT_StormTrooper_EP7 after DT_Maul_robed)
  holds the staff level with its arms out: stock behaviour (`RebornMasterStaff` -> `stormtrooper`
  without mods), `saberattackcycle` ends it - left as is.

## Sizes

Approved by the user on 2026-11-26 ("in-universe" for every model). Every humanoid model stands as
tall as Kyle at 1.0 (`measure_heights.py`: base-pose mesh heights within 4 % of Kyle's; Yoda meshes
+7 to +11 %), so: scale = target height / 1.80 m (Kyle) / mesh ratio. Targets in
`tools/player_mods/heights.txt` (commonly quoted character or actor heights); the factors in
`tools/player_mods/base/modelscale.cfg`. Players and bots get these; npcs keep their own `.npc`
scale where they have one (T_yoda 45, yodavm 50, babyyoda 37, grievous 135, the Vaders 120,
kyloren 120, Darth_Malgus 115).

| Model(s) | Target | Scale |
| --- | --- | --- |
| hs_anakin, hs_anakin2, anakinvm, jedi_anakin, jedi_anakint / hs_anakin_e2 / t_anakin | 1.85 m | 1.02 / 1.01 / 1.04 |
| anavader / jedi_vader, t_vader / vadervmm | 2.02 m | 1.12 / 1.08 / 1.11 |
| yodavm, yodaflee / t_yoda, t_yoda_mp | 0.66 m | 0.33 / 0.34 |
| babyyoda (Grogu) | 0.41 m | 0.22 |
| hs_kenobi_rots, jedi_kenobi | 1.82 m | 1.01 |
| quigon | 1.93 m | 1.07 |
| t_luke_rotj, luke_trainer / jedi_luke / luke_bobble | 1.72 m | 0.95 / 0.94 / 0.88 |
| jtempleg (no canon height) | 1.85 m | 1.01 |
| swtorrevan | 1.83 m | 1.01 |
| hs_dooku | 1.93 m | 1.07 |
| sid | 1.73 m | 0.97 |
| dt_maul | 1.75 m | 0.97 |
| psdarthmalgus (no canon height; its `.npc` 115) | 2.07 m | 1.17 |
| kylo, kylorenk / kylo_ren | 1.89 m | 1.04 / 1.06 |
| grievous | 2.16 m | 1.23 |
| st_rey, jedi_st_rey | 1.70 m | 0.95 |
| st_finn, jedi_st_finn | 1.78 m | 1.00 |
| st_poe / jedi_st_poe | 1.73 m | 0.97 / 0.96 |
| cloneii / dt_stormtrooper_ep7 | 1.83 m | 1.01 / 1.02 |
| dindjarin / dindjarin_gp | 1.85 m | 1.01 / 0.99 |
| JA++ stock entries (chewbacca 1.18, desann 1.15, jan 0.94, jawa 0.8, monmothma 0.84, tavion(_new) 0.95), `japp.diff` yoda 0.5 | - | kept |

## Decisions

- Model scale names (run 3): cvars `g_modelScale` (default 1, serverinfo, archived),
  `g_modelScaleCmd` (default 1, as in `japp.diff`), `g_modelScaleRange` (default `"30 200"`, `"20 200"` since run 6 for
  Grogu's 22 %: Grogu to past Grievous; the range only clamps the command; hard limits 10-250, 250 keeping the stand view height inside
  `ps.viewheight`'s signed 8 bits), cgame `cg_thirdPersonModelScale` (default 1); commands
  `/modelscale [n|default]` (`0` also resets), `modelscale <client> <n|default>` and `modelscales`
  on the server console / rcon. On a listen server `modelscale <n>` (one argument) goes on to the
  local player. JA++'s names had the `japp_` prefix; ours follow OpenJK's `g_` / `cg_`.
- `modelscale.cfg`: JA++'s format plus `model/skin` keys (the skin entry wins); a factor is
  rounded to whole percent (JA++ floors: its 1.18 gives 117, ours 118); bad pairs are skipped with
  a warning; up to 512 models, 64 KB; the topmost copy wins (no merge across pk3s).
- Precedence (players and bots): `/modelscale` (only while `g_modelScaleCmd` is on, clamped to the
  range), the cfg, the `.npc` scale (SP `playermodel <npc>`), 100. Npcs (the user, 2026-11-25,
  changing the skill's "cfg before `.npc`"): their own `.npc` scale wins, the cfg sizes only npcs
  without one, then 100 - so the default cfg's JA++ entries (tuned for MP player models) don't
  resize stock SP npcs that have a scale (Desann 135, chewie 122, the jawas 75 stay); Mon Mothma,
  Jan / JediF and the Tavions (no `.npc` scale) take JA++'s 84 / 94 / 95. A `.npc` `scale 100`
  can't be told from none. A `/modelscale` value lives until
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

- Custom skeletons in MP (run 5): a player model may sit on a `.gla` other than `_humanoid` when
  that skeleton is **humanoid-compatible** - the same bone count, names (case-insensitive) and
  parents in the same order as `_humanoid.gla`, read from the file's header and skeleton (at most
  32 KB, before `ofsFrames`). Its `animation.cfg` (next to the `.gla`) gets its own `bgAllAnims`
  index (> 1) as before, so its frames are its own, and `BG_HumanoidAnimIndex()` maps it to 0 at the
  "is it humanoid" checks. The server gives such a client its own ghoul2 instance
  (`G_PlayerHasCustomSkeleton`, the hook the commented-out siege custom skeletons used), found from
  the userinfo model's `model.glm` header (`animName`). Npcs on such a skeleton (the MP T_yoda npc)
  are humanoid now too (pmove, broken limbs, ragdoll, head / lumbar angles).
- `g_customSkeletons` (run 5): default 1, serverinfo, archived, **latched** (the anim set flags and
  the server ghoul2 instances are set up per level). The cgame reads the serverinfo key: on a server
  without it (retail, JA+, JA++) a fork client falls back to Kyle exactly as before. A retail / JA++
  client on a fork server that picks `t_yoda` sees itself as Kyle and predicts with the stock
  frames, while the server runs Yoda's (31 remapped animations: small prediction misses for that
  client only); other clients see what their cgame supports. Without mods nothing changes: no stock
  MP model uses a custom skeleton.
- Left on the stock humanoid table (no change needed for a compatible skeleton, recorded for
  later): the getup timing check in `BG_InKnockDownOnGround` (`BG_AnimLength( 0, ... )`), the IK base pose
  frames (`BG_IK_MoveArm`), the one-frame anim re-set after a client model change in
  `CG_NewClientInfo`, the first-person weapon frame map. The `t_yoda` saber is whatever the player
  picks (`saber1`); its `.npc` `saberstyle 7` only applies to the npc.

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
- `.npc` file name list (run 6): run 1 counted 146 names in 2036 bytes; the override pk3's
  renamed npc made it 147 / 2049 and `FS_GetFileList` dropped the last one, the stock `z-95.npc`.
  `npcExtensionListBuf` is `PLAYERMODS_NPC_LIST_SIZE` (16384) in SP and MP now, and the MP ui
  model grid's `models/players` dir list `Q3MODEL_DIR_LIST_SIZE` (16384; 158 dirs took 1914 of
  2048). Other lists that grow with mods are far from full (bots 295 / 1024, sabers 421 / 2048,
  model dirs in the species lists already 16384).
- Menu names (the user, 2026-11-26): through the override pk3 (`override/menu_names.recipe`, a
  partial `MENUS.str`, no `needs`), see Last run run 6. Skins without an `icon_<skin>` stay out of
  the MP grid (the mods ship none; no generated icons).

- SP `playermodel` (run 7): `G_ChangePlayerModel` re-applies the current legs / torso anim with
  `SETANIM_FLAG_OVERRIDE` - the new ghoul2 model has no anim yet, so a running anim timer must not
  keep it from getting one. Stock bug, fixed because every mod `playermodel` showed it.
- Interop (run 7): checked against the stock OpenJK build of 2025-12-26 in both directions
  (`interop_check.sh`), as the Decisions above predict: scaled players are drawn by any cgame, only
  the fork's predicts the scaled box; a stock cgame refuses `t_yoda`. A retail `jamp.exe` (Windows)
  was not available.

- T_AnaVader's missing hilts (the user, 2026-11-26): left as is - the mod is used as shipped, its
  `t_anakin` / `t_vader` sabers stay without a hilt unless the hilt mod they need turns up.

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
- `3bb6d8d8` `[Tools] player mods: ledger run 4` - `PLAYER_MODS_STATUS.md` only.
- `3ad38732` `[Shared] player mods: an npc's own .npc scale wins over modelscale.cfg` -
  `G_ModelScaleNPC` (`codemp/game/g_modelscale.c`) and the npc branch of `G_ModelScaleSetModel`
  (`code/game/g_modelscale.cpp`): scale = the `.npc` scale when it is not 100, else the cfg's,
  else 100; comments, the default cfg's header.
- `5aa43bf9` `[Tools] player mods: ledger, the npc precedence` - `PLAYER_MODS_STATUS.md`.
- `a5aeb1f9` `[MP] player mods: the icon name loop leaves room for the terminator` -
  `codemp/cgame/cg_players.c` (`CG_RegisterClientModelname`: the `icon_<skin>` copy stops at
  `sizeof(iconName) - 1`). The Rust port: just bound the copy.
- `8e8cb164` `[MP] player mods: player models on a humanoid-compatible custom skeleton` - new
  `codemp/game/bg_playerskel.c` / `.h` (game and cgame: `bgCustomSkeletons`; `.gla` header /
  skeleton reader - ident `2LGA`, version 6, `ofsFrames` @80, `numBones` @84, bone offsets after
  the 100-byte header relative to it, bone name[64] then flags then parent @68; little endian;
  `BG_HumanoidCompatibleGLA` (`players/_humanoid/` always, else compare with
  `models/players/_humanoid/_humanoid.gla`, 32-entry cache), `BG_CustomHumanoidGLA`,
  `BG_ModelHasCustomHumanoidGLA` (`model.glm` header: ident `2LGM`, `animName` @72),
  `BG_PlayerSkelAnimSetLoaded` (first `.gla` in the anim cfg's dir via `FS_GetFileList`),
  `BG_HumanoidAnimIndex`), new `codemp/game/g_playerskel.c` / `.h` (per-client flag and model,
  init from the cvar, userinfo hook returning "reload the server ghoul2", disconnect reset).
  Edits: `bg_panimate.c` (`BG_ParseAnimationFile` flags new sets > 1), `g_utils.c`
  (`G_PlayerHasCustomSkeleton` returns the flag), `g_client.c` (userinfo after the model block,
  disconnect), `g_main.c` (init before `G_ModelScaleInit`), `g_xcvar.h`; the humanoid checks in
  `NPC_AI_Rancor.c`, `g_weapon.c`, `g_client.c` (6), `NPC_AI_GalakMech.c`, `g_active.c` (2),
  `g_combat.c` (3), `w_saber.c` (3), `bg_pmove.c`, `cg_ents.c` (2), `cg_predict.c` (player only,
  not the vehicle), `cg_players.c` (13); `cg_players.c` `CG_RegisterClientModelname` accepts the
  skeleton; `cg_servercmds.c` (serverinfo key, `CG_KillCEntityInstances` keeps a client's anim set);
  game / cgame CMake lists. In the Rust port: one `is_humanoid_anim_set` helper used wherever the
  C compares `localAnimIndex` with 0 / 1.
- `a6be163f` `[Tools] player mods: ledger run 5` - `PLAYER_MODS_STATUS.md`.
- `fc5b1b29` `[Shared] player mods: room for more .npc files and player model dirs` -
  `PLAYERMODS_NPC_LIST_SIZE` 16384 in `code/game/g_playermods.h` and `codemp/game/g_playermods.h`
  for `npcExtensionListBuf` in both `NPC_stats` files; `Q3MODEL_DIR_LIST_SIZE` 16384 in
  `codemp/ui/ui_local.h` for `UI_BuildQ3Model_List`'s `dirlist` (`ui_main.c`, the
  `FS_GetFileList` call takes `sizeof`). The Rust port: whatever list type it uses must not cap
  these at 2048 bytes.
- `dbe71c1f` `[Tools] player mods: mp_menu_check.sh --species ...` - tools only.
- `9d542600` `[Tools] player mods: menu names the mods do not ship, in the override pk3` - tools
  and override data only; nothing to port (the pk3 is data).
- `9fc0eb0e` `[Tools] player mods: sp_menu_check.sh --hilts ...` - tools only.
- `651a502a` `[Tools] player mods: ledger run 6` - `PLAYER_MODS_STATUS.md`.
- `499214b5` `[Tools] player mods: model heights and an in-game size check` - tools only
  (`measure_heights.py`, `heights.txt`, `size_check.sh` / `.ps1`).
- `d4c15c70` `[Shared] player mods: /modelscale may go down to 20 %` - `MODELSCALE_RANGE_DEFAULT`
  `"20 200"` in `shared/qcommon/q_modelscale.h` (both games' `g_modelScaleRange` default).
- `dcb159cb` `[Tools] player mods: in-universe sizes for every mod model in modelscale.cfg` - the
  default `tools/player_mods/base/modelscale.cfg` only (data; `//` comments after values).
- `d877ef09` `[Tools] player mods: ledger run 6, step 8` - `PLAYER_MODS_STATUS.md`.
- `ecae7a49` `[SP] player mods: playermodel no longer leaves the new model in its bind pose` -
  `code/game/g_client.cpp` `G_ChangePlayerModel`: the two `NPC_SetAnim` calls after
  `G_AddWeaponModels` get `SETANIM_FLAG_OVERRIDE` added. The Rust port: the same flag there.
- `d8db5e27` `[Tools] player mods: interop check against a stock OpenJK, MP npc checks one at a
  time` - tools only; nothing to port.
- (this commit) `[Tools] player mods: README section, ledger run 7, step 9` - `README.md` (docs:
  the Rust port's README may want the same section), `PLAYER_MODS_STATUS.md`.
