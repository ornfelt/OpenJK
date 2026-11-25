# Player mods and model size - status

Ledger of the `openjk-player-mods` work: every Jedi Academy player model mod in
`$HOME/Downloads/star_wars_ja_mods/players` working in JA SP and MP, and a configurable player
model size (JA++-style, built in). Tools in `tools/player_mods/`.

## Last run

2026-11-25 (run 1, Linux): step 0 (setup) done, step 1 (baseline) done except the menu columns,
step 2 started with its first fix.

- Configured and built the fork in `build/` (RelWithDebInfo, Ninja): every target builds,
  302 pre-existing warnings (kept in `build/warnings_baseline.txt`, gitignored, to spot new ones;
  the run's changes add none).
- `tools/player_mods/`: `inventory.py`, `player_mods.conf`, `install_player_mods.sh` / `.ps1`,
  `run_test.sh` / `.ps1`, `log_report.py` (see Tools).
- Baseline with the unchanged build: MP dedicated (every mod bot joins), MP client (every model and
  skin, screenshots), MP npcs (only 55 of 76 spawn), SP npcs + playermodel (hung at the first
  `playermodel`). Cause of both: Seven's `quigon.npc` (see Decisions).
- Step 2, fix 1: `.npc` brace repair in both games (`g_playermods.c` / `.cpp`) and the end of the
  SP `playermodel` fallback recursion. After it: 75 of 76 mod npcs spawn in MP and SP and work as
  SP `playermodel` (`babyyoda` is the BabyYoda / YodaVM clash); no mods: unchanged, no warning.

## Next

1. Ask / apply the user's decisions on the clashes (BabyYoda vs YodaVM, DinDjarin vs themando,
   the two `kylo.bot`) - see "Waiting for the user".
2. Step 2 continued: the SP `MENUS.str` merge (every pk3's copy of a string file merged, later
   entries winning per key, so all the `JEDI_*` character menu names survive); then the tolerant
   loaders worth doing: SWTOR Revan's shader file (one stray `}` rejects the whole file in
   OpenJK), themando's `sounds.cfg` (first token only). Re-run the affected cells.
3. The visual npc checks (`--test-cfg mp-npcs|sp-npcs --shots`, the cfgs now look past the
   player) and the menu columns (step 7 work, but the baseline wants them: MP player model menu
   lists, SP character creation species).

## Waiting for the user

- **BabyYoda vs YodaVM** both ship `models/players/yodavm/` and `ext_data/npcs/yodavm.npc`;
  YodaVM wins every shared file (pk3 order), so Grogu never shows and the `babyyoda` npc does not
  exist. Recommended: an override pk3 the install script builds from BabyYoda.pk3 with the model
  dir renamed to `babyyoda` (its skin's paths and its npc entry rewritten to match, the recipe
  committed in `tools/player_mods/override/`, no mod file committed). Alternative: install only
  one of the two.
- **DinDjarin vs themando_doughnuts** both ship `models/players/dindjarin/`; themando wins the
  glm, skin and sounds, so GustavoPredador's Din never shows. Same choice (rename DinDjarin's to
  e.g. `dindjarin_gp`, or pick one).
- **The two `scripts/kylo.bot`**: KyloRenTFAUpdated's replaces kyloV.1.02's and its bot points at
  a model that does not exist (`KyloRen_Hood`). Recommended: an override `.bot` naming both bots
  with distinct names and the existing models.
- **SP skin limit**: a level holds 64 player skins; spawning more different models than that in
  one SP map ends it with `G_FindConfigstringIndex: overflow`. Raising it changes the SP
  configstring layout (and so savegames): leave it unless you want it raised.

## Steps

| # | Step | Status |
| --- | --- | --- |
| 0 | Setup: ledger, build, inventory, install script, mod table | done |
| 1 | Baseline matrix with the unchanged build | done except the menu columns and the npc screenshots (see Next) |
| 2 | Loading fixes (limits, SP string merge, conflicts, ...) | in progress: done - `.npc` brace repair (MP, SP), SP playermodel recursion; left - MENUS.str merge, the clashes (user), Revan shader, themando sounds.cfg |
| 3 | MP model scale - game | todo |
| 4 | MP model scale - cgame and ui | todo |
| 5 | SP model scale | todo |
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

Columns: SP playermodel (`playermodel <npc>`), SP menu (character creation), SP npc
(`npc spawn`), MP model (`model <m>/<skin>`, every skin, screenshots), MP menu, MP bot (`addbot`,
dedicated server), MP npc (`npc spawn`), saber, sounds. "fix1" = with this run's `.npc` brace
repair (the baseline had every npc / playermodel cell after the Qui-Gon file broken, see Decisions).
MP npc cells are checked by the log (spawned or not); their screenshots were taken from the wrong
side (fixed in the cfg generator) - the visual MP npc check is still todo. SP cells: log plus
screenshots of the player after `playermodel` (front view, npcs killed first).

| Mod | SP playermodel | SP menu | SP npc | MP model | MP menu | MP bot | MP npc | Saber | Sounds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ashuras_clones | ok (fix1) | n/a | ok (fix1) | ok, 4 skins | todo | ok | ok (fix1) | stock | broken: no `sounds.cfg` (generic sounds) |
| BabyYoda | broken: `babyyoda` npc hidden (YodaVM's `yodavm.npc` wins) | n/a | broken: same | broken: its `models/players/yodavm/` glm / skin / icon lose to YodaVM.pk3 - shows YodaVM's Yoda | todo | = yodavm's (same names, YodaVM's files win) | broken: `babyyoda` not found | its `yoda.sab` = YodaVM's | - |
| darth_sidious | ok (fix1) | n/a | ok (fix1) | ok, 2 skins | todo | n/a (no `.bot`, readme says bots) | ok (fix1) | stock | ok |
| DinDjarin | shows themando's model | n/a | ok (fix1), themando's model | broken: `dindjarin/` glm / skin / sounds lose to themando | todo | n/a | ok (fix1) | n/a | = themando's |
| DT_Maul | ok (fix1; readme: "SP: No") | n/a | ok (fix1) | ok, 5 skins | todo | ok | ok (fix1) | todo | ok |
| DT_Stormie_EP7 | ok (fix1; readme: "SP: No") | n/a | ok (fix1) | ok, 5 skins | todo | ok | ok (fix1) | stock | ok |
| grievousvm | ok (fix1), npc scale 135 | n/a | ok (fix1) | ok, 4 skins (no scale: human size) | todo | ok | ok (fix1) | todo | ok |
| hs_anakin | ok (fix1) | todo: `JEDI_ANAKIN` key lost (MENUS.str) | ok (fix1) | ok, all 6 model dirs (`anakinvm`, `anavader` have no icons) | todo | ok | ok (fix1) | broken: npcs name saber `hs_anakin`, not defined | ok |
| hs_dookuja | ok (fix1) | n/a | ok (fix1) | ok, 5 skins | todo | ok | ok (fix1) | ok (`.sab` typos `saberOn`, `munberBlades` ignored) | ok |
| hs_kenobi_rots | ok (fix1) | todo: `JEDI_KENOBI` key lost | ok (fix1) | ok, 6 skins (`jedi_kenobi` untextured if forced) | todo | ok | ok (fix1) | ok (same `.sab` typos) | ok |
| KyloRenTFAUpdated | ok (fix1) | todo | ok (fix1) | ok | todo | broken: bot model `KyloRen_Hood` does not exist (Kyle) | ok | broken: `sith_unstable` not installed (needs jkhub 2218) | partial set |
| kyloV.1.02 | ok (fix1) | todo | ok (fix1) | ok, 4 skins | todo | broken: its `kylo.bot` replaced by KyloRenTFAUpdated's | ok (fix1) | broken: `ren` not installed (DarthMartyr's saber) | partial set |
| PSKDarthMalgus | ok (fix1) | todo | ok (fix1) | ok | todo | ok | ok (fix1) | broken: npc saber `malgus`, the `.sab` defines `darth_malgus`; hilt menu entry has no string | ok |
| Seven-Qui-Gon_Jinn | ok (fix1) | n/a | ok (fix1) - its `quigon.npc` was the cause | ok, 7 skins | todo | n/a | ok | ok | ok |
| ST_Finn_Poe_V2.1 | ok (fix1) | todo: `JEDI_ST_*` keys lost | ok (fix1) | ok, 10 skins (`jedi_st_*` untextured if forced) | todo | ok | ok | stock | ok |
| ST_REY_V2.3 | ok (fix1) | todo: keys lost | ok (fix1) | ok, 6 skins | todo | ok | ok | stock | ok |
| SWTORRevanV1-04 | ok (fix1) | todo | ok (fix1) | ok, 15 skins, but `swtorrevan.shader` is rejected (unbalanced `}` at line 392): its shader effects are lost | todo | ok | ok | broken: npc saber `revan` not defined | partial set |
| T_Anavader | ok (fix1) | todo: `JEDI_ANAKINT` / `JEDI_VADER` keys lost | ok (fix1) | ok, 12 skins | todo | ok | ok | ok | ok |
| T_luke_rotj_V2 | ok (fix1) | todo (its MENUS.str is the one that wins; `jedi_luke/PlayerChoice.txt` has parse errors in the MP UI) | ok (fix1) | ok, 9 skins | todo | ok | ok | ok | ok |
| T_Yoda | ok (fix1): own `.gla`, npc scale 45 | n/a | ok (fix1) | `t_yoda_mp`: ok but human size; `t_yoda` (SP glm, own `.gla`): Kyle | todo | ok | ok | todo | ok |
| themando_doughnuts | ok (fix1) | n/a | ok (fix1) | ok | todo | ok | ok | n/a | broken: `sounds.cfg` starts with `breathes "0"`, MP takes that line as the sound dir |
| vaderepiii | ok (fix1), scale 120 | n/a | ok (fix1) | ok, 3 skins (human size) | todo | ok | ok | todo | ok |
| yodavm | ok (fix1), scale 50 | n/a | ok (fix1) | ok, 6 skins incl. `yodaflee` (human size) | todo | ok | ok | ok | ok |
| zKyloRenKv2 | ok (fix1) | n/a | ok (fix1) | ok | todo | ok | ok | broken: `kylo_ren` not installed (needs jkhub 2214) | ok |
| ZZ- Luke Skywalker Trainer v1.5 | ok (fix1), 3 skins | n/a | ok (fix1) | ok, 3 skins | todo | n/a | ok | stock | ok |
| zzJTempleGv3 | ok (fix1) | n/a | ok (fix1) | ok | todo | n/a | ok | ok | ok |

Other findings:

- SP: a level has 64 skin configstrings (`G_FindConfigstringIndex` "overflow adding
  models/players/t_yoda/model_default.skin to set 1097-64" after ~60 different models in one map,
  an `ERR_DROP`). The test cfgs now reload the map every 20 checks. Raising the limit would change
  the SP configstring layout (savegames) - only after asking.
- MP shows every skin of every model; the Yodas, Grievous and Vader are human size (no scaling in
  MP yet - steps 3-4).
- SP `playermodel`: several shots taken ~1.7 s after the switch show the new model in a T-pose
  (greeveevm, DT_StormTrooper_EP7, st_rey_scavenger, T_vader*, Luke_robeup / robedn / bobble,
  KyloRenK, JediTempleGuard) while other npcs of the same model animate. Timing or a missing
  animation after `G_ChangePlayerModel`? To check before calling those cells ok for good.

## Sizes

Not measured yet (step 8). Starting points, not approved:

| Model | Scale | Source | Approved |
| --- | --- | --- | --- |
| chewbacca | 1.18 | JA++ `modelscale.cfg` | no |
| desann | 1.15 | JA++ | no |
| jan | 0.94 | JA++ | no |
| jawa | 0.8 | JA++ | no |
| monmothma | 0.84 | JA++ | no |
| tavion, tavion_new | 0.95 | JA++ | no |
| yoda, yodavm, babyyoda | 0.5 | `japp.diff` | no |
| yodavm (npc yodavm / yodaoz / yodaepit / yodapack) | 0.50 | `.npc` | no |
| yodavm (npc babyyoda) | 0.37 | `.npc` | no |
| t_yoda (npc T_yoda) | 0.45 | `.npc` | no |
| grievous (npc greeveevm / playergreevee) | 1.35 | `.npc` | no |
| psdarthmalgus (npc Darth_Malgus) | 1.15 | `.npc` | no |
| t_vader (npc T_vader*) | 1.20 | `.npc` | no |
| kylo_ren (npc kyloren) | 1.20 | `.npc` | no |
| vadervmm (npc vadervmm / vadersingle) | 1.20 | `.npc` | no |

## Decisions

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
- (this commit) `[Tools] player mods: status ledger` - `PLAYER_MODS_STATUS.md` only.
