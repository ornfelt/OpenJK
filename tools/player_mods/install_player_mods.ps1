# Installs the Jedi Academy player model mods into an OpenJK base/ dir.
#
# Copies every mod's pk3(s) from the players dir (one dir per mod) into base/, minus the
# alternative variants player_mods.conf skips, plus the loose files it lists as `extra` and the
# fork's own files in tools/player_mods/base/ (the default modelscale.cfg ...). It writes a
# manifest (player_mods_manifest.txt in base/) so -Uninstall removes exactly what it installed,
# never overwrites a file it did not install, and lists the pk3s that replace stock files.
# The mods themselves are never changed; pk3s are only copied (and listed as zips).
# Same behaviour and manifest format as install_player_mods.sh.
#
# Usage examples:
#   install everything into the OpenJK homepath's base/ (Documents\My Games\OpenJK\base):
#     .\install_player_mods.ps1
#   players dir given positionally / by name:
#     .\install_player_mods.ps1 $env:USERPROFILE\Downloads\star_wars_ja_mods\players
#     .\install_player_mods.ps1 -Players $env:USERPROFILE\Downloads\star_wars_ja_mods\players
#   a throwaway base/ for tests:
#     .\install_player_mods.ps1 -Dest $env:TEMP\ojk_test\base
#   leave mods (or single pk3s) out / add only some (comma separated, case-insensitive):
#     .\install_player_mods.ps1 -Exclude BabyYoda,hs_anakin/HS-anakin_saber-SP.pk3
#     .\install_player_mods.ps1 -Only T_Yoda,grievousvm
#   case-sensitive matching of -Only / -Exclude:
#     .\install_player_mods.ps1 -Only T_Yoda -CaseSensitive
#   remove what was installed (all, or only some mods):
#     .\install_player_mods.ps1 -Uninstall
#     .\install_player_mods.ps1 -Uninstall -Only BabyYoda
#   print the equivalent PowerShell commands instead of running them:
#     .\install_player_mods.ps1 -DebugCmd -Dest $env:TEMP\ojk_test\base

param(
	[string]$Players,
	[string]$Dest,
	[string]$Game,
	[string[]]$Only = @(),
	[string[]]$Exclude = @(),
	[switch]$CaseSensitive,
	[switch]$Uninstall,
	[switch]$DebugCmd
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- colored prints
function Write-Header([string]$t) { Write-Host $t -ForegroundColor Cyan }
function Write-Ok([string]$t)     { Write-Host $t -ForegroundColor Green }
function Write-Warn([string]$t)   { Write-Host $t -ForegroundColor Yellow }
function Write-Err([string]$t)    { Write-Host $t -ForegroundColor Red }
function Write-Key([string]$k, [string]$v) { Write-Host "  ${k}:" -ForegroundColor Blue -NoNewline; Write-Host " $v" }

# ---------------------------------------------------------------- constants
$ScriptDir     = $PSScriptRoot
$RepoDir       = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$ConfFile      = Join-Path $ScriptDir 'player_mods.conf'
$ForkBaseDir   = Join-Path $ScriptDir 'base'
$ManifestName  = 'player_mods_manifest.txt'
$ForkSource    = 'fork'          # manifest source tag of the fork's own files
$InstallSubdir = 'JediAcademy'   # OpenJK's JKAInstallDir under CMAKE_INSTALL_PREFIX
$OnWindows     = ($env:OS -eq 'Windows_NT')
if ($OnWindows) {
	$UserHome = $env:USERPROFILE
	$DefaultHomepath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\OpenJK'
} else {
	$UserHome = $env:HOME
	$DefaultHomepath = Join-Path $env:HOME '.local/share/openjk'
}
$DefaultPlayers = Join-Path $UserHome 'Downloads/star_wars_ja_mods/players'

Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---------------------------------------------------------------- arguments
function Split-List([string[]]$items) { @($items | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' }) }
$Only = Split-List $Only
$Exclude = Split-List $Exclude
if (-not $Players) { $Players = $DefaultPlayers }
if (-not $Dest) { $Dest = Join-Path $DefaultHomepath 'base' }
if (-not $Game) {
	$cache = Join-Path $RepoDir 'build/CMakeCache.txt'
	if (Test-Path -LiteralPath $cache) {
		$line = Select-String -LiteralPath $cache -Pattern '^CMAKE_INSTALL_PREFIX:[A-Z]*=(.*)$' | Select-Object -First 1
		if ($line) { $Game = Join-Path $line.Matches[0].Groups[1].Value $InstallSubdir }
	}
	if (-not $Game -or -not (Test-Path -LiteralPath (Join-Path $Game 'base'))) { $Game = Join-Path $DefaultHomepath $InstallSubdir }
}
$Manifest = Join-Path $Dest $ManifestName

# ---------------------------------------------------------------- helpers
function Norm([string]$s) { if ($CaseSensitive) { $s } else { $s.ToLowerInvariant() } }

function Test-Match([string]$mod, [string]$rel, [string[]]$list) {
	$m = Norm $mod; $r = Norm ($rel -replace '\\', '/'); $leaf = ($r -split '/')[-1]
	foreach ($item in $list) {
		$i = Norm ($item -replace '\\', '/')
		if ($i -ceq $m -or $i -ceq "$m/$r" -or $i -ceq $leaf) { return $true }
	}
	return $false
}

function Test-Selected([string]$mod, [string]$rel) {
	if ($Only.Count -gt 0 -and -not (Test-Match $mod $rel $Only)) { return $false }
	if ($Exclude.Count -gt 0 -and (Test-Match $mod $rel $Exclude)) { return $false }
	return $true
}

function Get-ConfEntries([string]$keyword) {
	if (-not (Test-Path -LiteralPath $ConfFile)) { return @() }
	@(Get-Content -LiteralPath $ConfFile | ForEach-Object {
		$t = $_.Trim()
		if ($t -and -not $t.StartsWith('#')) {
			$parts = $t -split '\s+', 2
			if ($parts.Count -eq 2 -and $parts[0].ToLowerInvariant() -eq $keyword) { $parts[1].Trim() -replace '\\', '/' }
		}
	})
}

function Get-Sha([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Quote([string]$s) { "'" + ($s -replace "'", "''") + "'" }

function Invoke-Step([string]$cmd, [scriptblock]$action) {
	if ($DebugCmd) { Write-Output $cmd } else { & $action }
}

$skipSet = @{}
foreach ($e in Get-ConfEntries 'skip') { $skipSet[$e.ToLowerInvariant()] = $true }
$ignoreSet = @{}
foreach ($e in Get-ConfEntries 'ignore') { $ignoreSet[$e.ToLowerInvariant()] = $true }

# manifest: <sha256> TAB <file> TAB <source>; keys compared case-insensitively like the file system
$manSha = @{}; $manSrc = @{}
if (Test-Path -LiteralPath $Manifest) {
	foreach ($l in Get-Content -LiteralPath $Manifest) {
		if (-not $l -or $l.StartsWith('#')) { continue }
		$f = $l -split "`t"
		if ($f.Count -ge 3) { $manSha[$f[1]] = $f[0]; $manSrc[$f[1]] = $f[2] }
	}
}

function Save-Manifest {
	if ($DebugCmd) { Write-Output "# then $Manifest is rewritten: <sha256> TAB <file> TAB <source> per installed file"; return }
	if ($manSha.Count -eq 0) { if (Test-Path -LiteralPath $Manifest) { Remove-Item -LiteralPath $Manifest }; return }
	$lines = @('# written by tools/player_mods/install_player_mods.sh - do not edit')
	foreach ($name in ($manSha.Keys | Sort-Object)) { $lines += "$($manSha[$name])`t$name`t$($manSrc[$name])" }
	[IO.File]::WriteAllText($Manifest, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
}

# ---------------------------------------------------------------- uninstall
if ($Uninstall) {
	Write-Header "uninstalling player mods from $Dest"
	if ($manSha.Count -eq 0) { Write-Warn "no $ManifestName in ${Dest}: nothing installed"; exit 0 }
	$removed = 0; $kept = 0
	foreach ($name in @($manSha.Keys | Sort-Object)) {
		$src = $manSrc[$name]; $slash = $src.IndexOf('/')
		if (-not (Test-Selected $src.Substring(0, $slash) $src.Substring($slash + 1))) { continue }
		$file = Join-Path $Dest $name
		if (-not (Test-Path -LiteralPath $file)) {
			Write-Warn "  already gone: $name"
		} elseif ((Get-Sha $file) -ne $manSha[$name]) {
			Write-Warn "  changed since it was installed, kept: $name"; $kept++; continue
		} else {
			Invoke-Step "Remove-Item -LiteralPath $(Quote $file)" { Remove-Item -LiteralPath $file }
			$removed++
		}
		$manSha.Remove($name); $manSrc.Remove($name)
	}
	Save-Manifest
	Write-Ok "removed $removed file(s), kept $kept"
	exit 0
}

# ---------------------------------------------------------------- install
if (-not (Test-Path -LiteralPath $Players -PathType Container)) { Write-Err "players dir not found: $Players"; exit 1 }
Write-Header 'installing player mods'
Write-Key 'from' $Players
Write-Key 'into' $Dest
Write-Key 'stock' (Join-Path $Game 'base')

$sources = New-Object System.Collections.Generic.List[object]
foreach ($modDir in Get-ChildItem -LiteralPath $Players -Directory | Sort-Object Name) {
	$mod = $modDir.Name
	$pk3s = Get-ChildItem -LiteralPath $modDir.FullName -Recurse -File | Where-Object { $_.Extension -ieq '.pk3' } | Sort-Object FullName
	foreach ($pk3 in $pk3s) {
		$rel = $pk3.FullName.Substring($modDir.FullName.Length).TrimStart('\', '/') -replace '\\', '/'
		if ($skipSet.ContainsKey("$mod/$rel".ToLowerInvariant())) { continue }
		if ($rel.Contains('/') -and $ignoreSet.ContainsKey("$mod/$(($rel -split '/')[0])".ToLowerInvariant())) { continue }
		if (-not (Test-Selected $mod $rel)) { continue }
		$sources.Add([pscustomobject]@{ Path = $pk3.FullName; Tag = "$mod/$rel" })
	}
}
foreach ($e in Get-ConfEntries 'extra') {
	$path = Join-Path $Players $e
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Warn "extra file not found: $e"; continue }
	$slash = $e.IndexOf('/')
	if (-not (Test-Selected $e.Substring(0, $slash) $e.Substring($slash + 1))) { continue }
	$sources.Add([pscustomobject]@{ Path = (Resolve-Path -LiteralPath $path).Path; Tag = $e })
}
if ((Test-Path -LiteralPath $ForkBaseDir) -and $Only.Count -eq 0) {
	foreach ($f in Get-ChildItem -LiteralPath $ForkBaseDir -File | Sort-Object Name) {
		$sources.Add([pscustomobject]@{ Path = $f.FullName; Tag = "$ForkSource/$($f.Name)" })
	}
}
if ($sources.Count -eq 0) { Write-Warn 'nothing selected'; exit 0 }

Invoke-Step "New-Item -ItemType Directory -Force -Path $(Quote $Dest) | Out-Null" { New-Item -ItemType Directory -Force -Path $Dest | Out-Null }
$taken = @{}
$installed = 0; $updated = 0; $same = 0; $refused = 0
foreach ($s in $sources) {
	$name = Split-Path -Leaf $s.Path
	if ($taken.ContainsKey($name)) {
		Write-Err "  two sources for ${name}: $($taken[$name]) and $($s.Tag) - skipped the second"; $refused++; continue
	}
	$taken[$name] = $s.Tag
	$target = Join-Path $Dest $name
	$newSha = Get-Sha $s.Path
	if (Test-Path -LiteralPath $target) {
		if (-not $manSha.ContainsKey($name)) { Write-Warn "  not installed by this script, left alone: $name"; $refused++; continue }
		$curSha = Get-Sha $target
		if ($curSha -eq $newSha) { $same++; $manSrc[$name] = $s.Tag; continue }
		if ($curSha -ne $manSha[$name]) { Write-Warn "  changed since it was installed, left alone: $name"; $refused++; continue }
		$updated++
	} else {
		$installed++
	}
	$src = $s.Path
	Invoke-Step "Copy-Item -LiteralPath $(Quote $src) -Destination $(Quote $target)" { Copy-Item -LiteralPath $src -Destination $target }
	$manSha[$name] = $newSha; $manSrc[$name] = $s.Tag
}
Save-Manifest

# ---------------------------------------------------------------- pk3s replacing stock files
function Get-ZipNames([string]$path) {
	$z = [IO.Compression.ZipFile]::OpenRead($path)
	try { @($z.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object { ($_.FullName -replace '\\', '/').ToLowerInvariant() }) }
	finally { $z.Dispose() }
}
$stockPaks = @(Get-ChildItem -LiteralPath (Join-Path $Game 'base') -Filter 'assets*.pk3' -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($stockPaks.Count -gt 0) {
	Write-Header 'pk3s that replace stock files (exclude with -Exclude <mod>/<pk3>)'
	$stock = New-Object 'System.Collections.Generic.HashSet[string]'
	foreach ($p in $stockPaks) { foreach ($n in Get-ZipNames $p.FullName) { [void]$stock.Add($n) } }
	foreach ($s in $sources) {
		if ($s.Path -notmatch '\.pk3$') { continue }
		$hits = @(Get-ZipNames $s.Path | Where-Object { $stock.Contains($_) } | Sort-Object -Unique)
		if ($hits.Count -gt 0) {
			$more = if ($hits.Count -gt 4) { ' ...' } else { '' }
			Write-Host "  $($s.Tag): $($hits.Count): $(($hits | Select-Object -First 4) -join ', ')$more"
		}
	}
} else {
	Write-Warn "no assets*.pk3 in $(Join-Path $Game 'base'): stock overrides not listed (-Game <dir>)"
}

Write-Ok "installed $installed, updated $updated, unchanged $same, left alone $refused - manifest $Manifest"
