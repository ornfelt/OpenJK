# Player model sizes

How to make a player model (or an npc) bigger or smaller in this fork, in SP and MP. There are
three tools, from the most permanent to the most temporary:

| Tool | Who it changes | How long it lasts |
| --- | --- | --- |
| `modelscale.cfg` | everyone using that model (players, bots, npcs without their own scale) | until you edit it again |
| an npc's `scale` (override recipe) | that npc only | until you edit the recipe again |
| `/modelscale <percent>` | you (or one client, from the server console) | MP: until a map change or disconnect; SP: kept in the savegame |

Sizes are percent in the game and factors in the file: `0.5` in `modelscale.cfg` is `50` on the
command line, half of Kyle's height. Every humanoid mod model is about Kyle's height at 1.0, so a
factor is simply "target height / 1.80 m".

## modelscale.cfg - a size per model

### Where it is

- **The one the game reads:** `base/modelscale.cfg` in the OpenJK homepath
  (`~/.local/share/openjk/base/` on Linux, `Documents/My Games/OpenJK/base/` on Windows), put
  there by `tools/player_mods/install_player_mods.sh`. Edit this one to change your game.
- **The default in the repo:** `tools/player_mods/base/modelscale.cfg`. The install script copies
  it, and later installs keep a copy you have edited ("changed since it was installed, kept"), so
  your edits are safe. To start over from the default, delete the installed file and run the
  install script again.

A `modelscale.cfg` inside a pk3 works too; the topmost copy wins (there is no merge between
copies). JA++'s own `modelscale.cfg` loads unchanged.

### Format

```
// comments like this, or /* ... */
<model>          <factor>
<model>/<skin>   <factor>    // only that skin; wins over the plain <model> line
```

- `<model>` is the model dir name under `models/players/` (what `model <name>` / the MP player
  menu uses), case-insensitive.
- `<factor>`: `1.0` is normal, `0.5` half, `1.2` 20 % taller. It is rounded to whole percent and
  limited to 0.10 - 2.50.
- A later line for the same model replaces an earlier one, so you can also append overrides at
  the end of the file.

### When it takes effect

The file is read when a map loads. After editing it:

- **MP:** `map_restart`, or load a map (`map <name>` / `devmap <name>`).
- **SP:** load a map or a savegame.

`modelscales` (console) prints the table the game has loaded and everyone's current size.

## Example: smaller Yoda and Grogu

The Yoda and Grogu models and their default sizes:

| Model | Mod | Default | Height at the default |
| --- | --- | --- | --- |
| `babyyoda` (Grogu) | BabyYoda (renamed by the override pk3) | `0.22` | 0.41 m |
| `yodavm`, `yodaflee` | YodaVM | `0.33` | 0.66 m |
| `t_yoda`, `t_yoda_mp` | T_Yoda | `0.34` | 0.66 m |
| `yoda` | (JA++'s entry, no mod ships it) | `0.5` | - |

To make Grogu and Yoda smaller, change their lines in the installed `base/modelscale.cfg`, for
example:

```
babyyoda        0.18    // Grogu, ~0.33 m
yodavm          0.28    // Yoda, ~0.56 m
yodaflee        0.28
t_yoda          0.29
t_yoda_mp       0.29
```

Then `map_restart` (MP) or reload the map (SP), and pick the model (`model babyyoda` in MP,
`playermodel babyyoda` in SP).

To make one skin smaller only, add a skin line: `yodavm/default_epfive 0.30`.

## /modelscale - your own size, right now

| Command | Where | What it does |
| --- | --- | --- |
| `/modelscale 15` | MP client, SP console | sets your size to 15 % (clamped to `g_modelScaleRange`) |
| `/modelscale` | MP client, SP console | prints your size and where it comes from |
| `/modelscale default` (or `0`) | MP client, SP console | back to `modelscale.cfg` / the model's default |
| `modelscale <client> <n\|default>` | MP server console / rcon | sets one client's size (client number from `status`) |
| `modelscales` | MP server console / rcon, SP console | lists the table and everyone's size |

- The command beats `modelscale.cfg` for as long as it is set. It survives respawns and model
  changes; in MP it ends at a map change or disconnect, in SP it is saved with the game.
- SP needs no cheats for it.
- The range is `g_modelScaleRange "20 200"` by default (Grogu at 22 % fits). For a tinier Grogu by
  command, lower it on the server / in SP: `set g_modelScaleRange "10 200"`, then
  `/modelscale 12`. `modelscale.cfg` is not limited by this range (only by 10 - 250).
- Growing is refused while the bigger body would start inside a wall or another player
  ("no room for ... here"); move to open floor and try again.

## Npcs - their own `scale` wins

An npc whose `.npc` file has a `scale` keeps it; `modelscale.cfg` only sizes npcs without one.
The Yoda npcs all have one: `babyyoda` 37, `yodavm` / `yodaoz` / `yodaepit` / `yodapack` 50,
`T_yoda` 45. When *you* use such a model, `modelscale.cfg` decides: MP `model babyyoda` takes the
cfg size (or 100 without a line); SP `playermodel babyyoda` takes the cfg size, and the `.npc`
scale only when the cfg has no line for the model.

To change the Grogu npc's size, add a `set` line to its recipe,
`tools/player_mods/override/babyyoda.recipe`:

```
set     ext_data/npcs/babyyoda.npc babyyoda scale 30
```

and run the install script again (it rebuilds `~playermods_overrides.pk3`), then `npc spawn
babyyoda`. Npcs of other mods (e.g. YodaVM's `yodavm`) need a recipe of their own in the same
style - `needs`, `from <mod>/<pk3>`, `copy` of the `.npc` file to the same path, `set ... scale` -
see the comment at the top of `build_overrides.py`. The mods themselves are never edited.

## Turning sizes off

| Cvar | Default | |
| --- | --- | --- |
| `g_modelScale` | `1` | `0`: everyone back to the stock size (npcs keep their `.npc` scale, as in the stock game) |
| `g_modelScaleCmd` | `1` | `0`: players can no longer use `/modelscale` |
| `g_modelScaleRange` | `"20 200"` | the percent range `/modelscale` is clamped to |
| `cg_thirdPersonModelScale` | `1` | `0`: the third-person camera no longer follows your size |

In MP these are server cvars (set them on the server or the listen server's console), except
`cg_thirdPersonModelScale`, which is yours.

## Checking sizes side by side

`tools/player_mods/size_check.sh --cfg <your modelscale.cfg>` puts every model at its size next to
a Kyle npc and makes one contact sheet (Linux; needs the built fork and a display), e.g.
`./size_check.sh --model yoda --cfg ~/.local/share/openjk/base/modelscale.cfg`.
