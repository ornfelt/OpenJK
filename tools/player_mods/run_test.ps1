# Runs the fork's freshly built JA SP / MP / dedicated binaries against a throwaway homepath with
# the player mods installed, executes a cfg of test commands and scans the console log.
# The PowerShell twin of run_test.sh (same layout of the home, same cvars, same checks).
#
# The home gets base\ (the mods, via install_player_mods.ps1 -Dest), bin\ (copies of the built
# engine and renderers, which load from the binary's dir) and playermods_test\ (the built game
# modules, loaded through +set fs_game playermods_test, plus the test cfg and the console log).
# The retail data comes in read only through fs_basepath. No master servers, LAN only.
#
# Usage examples:
#   dedicated MP server, bots added from a cfg (one command per line):
#     .\run_test.ps1 ded -Cfg bots.cfg
#   MP client, commands inline (separated by ';'):
#     .\run_test.ps1 mp -Exec "devmap mp/duel1; wait 600; model kyle; wait 300; screenshot kyle; quit"
#   SP client in a given home, kept for inspection, without (re)installing the mods:
#     .\run_test.ps1 sp -HomeDir $env:TEMP\ojk_home -NoInstall -Exec "devmap t1_surprise; wait 600; quit"
#   no mods at all, then only the error lines that run did not print:
#     .\run_test.ps1 ded -NoMods -HomeDir $env:TEMP\h0 -Cfg bots.cfg
#     .\run_test.ps1 ded -Baseline $env:TEMP\h0\playermods_test\qconsole.log -Cfg bots.cfg
#   only some mods, own error filter, case-sensitive:
#     .\run_test.ps1 ded -Only T_Yoda,grievousvm -Grep "G2|Couldn't" -CaseSensitive -Cfg bots.cfg
#   extra cvars set on the command line, before the cfg:
#     .\run_test.ps1 ded -Set @{ net_port = 29170; rconpassword = 'test' } -Exec "map mp/ffa1; wait 4000; quit"
#   remove the home afterwards / print the equivalent commands only:
#     .\run_test.ps1 ded -Clean -Cfg bots.cfg
#     .\run_test.ps1 mp -DebugCmd -Exec "devmap mp/duel1; quit"

param(
	[string]$Mode,
	[string]$Cfg,
	[string]$Exec,
	[string]$HomeDir,
	[string]$Game,
	[string]$Baseline,
	[string[]]$Only = @(),
	[string[]]$Exclude = @(),
	[string]$Grep,
	[int]$Timeout = 300,
	[hashtable]$Set = @{},
	[switch]$NoInstall,
	[switch]$NoMods,
	[switch]$CaseSensitive,
	[switch]$Clean,
	[switch]$DebugCmd
)

$ErrorActionPreference = 'Stop'

function Write-Header([string]$t) { Write-Host $t -ForegroundColor Cyan }
function Write-Ok([string]$t)     { Write-Host $t -ForegroundColor Green }
function Write-Warn([string]$t)   { Write-Host $t -ForegroundColor Yellow }
function Write-Err([string]$t)    { Write-Host $t -ForegroundColor Red }
function Write-Key([string]$k, [string]$v) { Write-Host "  ${k}:" -ForegroundColor Blue -NoNewline; Write-Host " $v" }

$ScriptDir     = $PSScriptRoot
$RepoDir       = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$BuildDir      = Join-Path $RepoDir 'build'
$TestGame      = 'playermods_test'
$CfgName       = 'autotest.cfg'
$LogName       = 'qconsole.log'
$InstallSubdir = 'JediAcademy'
$OnWindows     = ($env:OS -eq 'Windows_NT')
$Arch          = 'x86_64'          # OpenJK's ARCH_STRING on 64-bit Windows and Linux
$ExeExt        = if ($OnWindows) { '.exe' } else { '' }
$DllExt        = if ($OnWindows) { '.dll' } else { '.so' }
$DefaultGrep   = "couldn't|can't|cannot|warning|error|failed|not found|g2|ghoul|missing|default model|bad |exceeded|overflow"
# the engine probes other extensions (sound .wav before .mp3, image .tga/.jpg/.png, optional .surf,
# the .ste twin of each .str string file, a skin's sounds_<skin>.cfg before sounds.cfg, every
# model dir's PlayerChoice.txt in the MP UI)
$ProbeRe       = "^Can't find (.*\.(wav|jpg|png|tga|surf|ste)|models/players/[^/]*/(sounds_[^/]*\.cfg|PlayerChoice\.txt))$"
# com_maxfps pins `wait` to 60 per second: the server takes at most 3 userinfo changes per 6 s
$WindowCvars   = @('+set', 'com_maxfps', '60', '+set', 'in_mouse', '0', '+set', 'r_fullscreen', '0', '+set', 'r_mode', '-1',
                   '+set', 'r_customwidth', '1280', '+set', 'r_customheight', '720', '+set', 's_volume', '0', '+set', 's_musicvolume', '0')
$NetCvars      = @('+set', 'sv_master1', '""', '+set', 'sv_master2', '""', '+set', 'sv_master3', '""', '+set', 'sv_master4', '""',
                   '+set', 'sv_master5', '""', '+set', 'net_enabled', '1', '+set', 'sv_lanForceRate', '1', '+set', 'dedicated_lan', '1')

if ($Mode -notin @('sp', 'mp', 'ded')) { Write-Err 'first argument: sp, mp or ded'; exit 1 }
if (-not $Cfg -and -not $Exec) { Write-Err 'give -Cfg <file> or -Exec "cmd; cmd"'; exit 1 }
if (-not $Grep) { $Grep = $DefaultGrep }
if (-not $Game) {
	$cache = Join-Path $BuildDir 'CMakeCache.txt'
	$line = if (Test-Path -LiteralPath $cache) { Select-String -LiteralPath $cache -Pattern '^CMAKE_INSTALL_PREFIX:[A-Z]*=(.*)$' | Select-Object -First 1 }
	if ($line) { $Game = Join-Path $line.Matches[0].Groups[1].Value $InstallSubdir }
}
if (-not $Game -or -not (Test-Path -LiteralPath (Join-Path $Game 'base\assets0.pk3'))) { Write-Err "no retail data in $Game\base (-Game <dir>)"; exit 1 }
if (-not $HomeDir) { $HomeDir = Join-Path ([IO.Path]::GetTempPath()) ("ojk_playermods_" + [IO.Path]::GetRandomFileName()) }

switch ($Mode) {
	'sp'  { $exe = "openjk_sp.$Arch$ExeExt"; $modules = @("jagame$Arch$DllExt"); $renderers = @("rdsp-vanilla_$Arch$DllExt") }
	'mp'  { $exe = "openjk.$Arch$ExeExt"; $modules = @("jampgame$Arch$DllExt", "cgame$Arch$DllExt", "ui$Arch$DllExt")
	        $renderers = @("rd-vanilla_$Arch$DllExt", "rd-rend2_$Arch$DllExt") }
	'ded' { $exe = "openjkded.$Arch$ExeExt"; $modules = @("jampgame$Arch$DllExt"); $renderers = @() }
}

# the build layout differs per generator (build\Release\..., build\codemp\game\Release\...): search it
function Find-Built([string]$name) {
	$hit = Get-ChildItem -LiteralPath $BuildDir -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -notmatch '[\\/]CMakeFiles[\\/]' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
	if (-not $hit) { Write-Err "not built: $name"; exit 1 }
	$hit.FullName
}

function Quote([string]$s) { "'" + ($s -replace "'", "''") + "'" }
function Invoke-Step([string]$cmd, [scriptblock]$action) { if ($DebugCmd) { Write-Output $cmd } else { & $action } }

Write-Header "player mods test: $Mode"
Write-Key 'home' $HomeDir
Write-Key 'game data' $Game
$binDir = Join-Path $HomeDir 'bin'; $testDir = Join-Path $HomeDir $TestGame; $baseDir = Join-Path $HomeDir 'base'
foreach ($d in @($baseDir, $binDir, $testDir)) {
	Invoke-Step "New-Item -ItemType Directory -Force -Path $(Quote $d) | Out-Null" { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}
$installer = Join-Path $ScriptDir 'install_player_mods.ps1'
if (-not $NoMods -and -not $NoInstall) {
	$ia = @{ Dest = $baseDir; Game = $Game }
	if ($Only.Count) { $ia.Only = $Only }
	if ($Exclude.Count) { $ia.Exclude = $Exclude }
	if ($DebugCmd) { $ia.DebugCmd = $true; & $installer @ia } else { & $installer @ia | Select-Object -Last 1 }
} elseif ($NoMods -and (Test-Path -LiteralPath (Join-Path $baseDir 'player_mods_manifest.txt'))) {
	& $installer -Dest $baseDir -Uninstall -DebugCmd:$DebugCmd
}
foreach ($f in @($exe) + $renderers) {
	$src = Find-Built $f
	Invoke-Step "Copy-Item -Force -LiteralPath $(Quote $src) -Destination $(Quote $binDir)" { Copy-Item -Force -LiteralPath $src -Destination $binDir }
}
foreach ($f in $modules) {
	$src = Find-Built $f
	Invoke-Step "Copy-Item -Force -LiteralPath $(Quote $src) -Destination $(Quote $testDir)" { Copy-Item -Force -LiteralPath $src -Destination $testDir }
}

$cfgFile = Join-Path $testDir $CfgName
if ($DebugCmd) {
	Write-Output "# then $cfgFile gets the test commands, one per line"
} elseif ($Cfg) {
	Copy-Item -Force -LiteralPath $Cfg -Destination $cfgFile
} else {
	$lines = $Exec -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
	[IO.File]::WriteAllText($cfgFile, (($lines -join "`n") + "`n"))
}
$log = Join-Path $testDir $LogName
if (-not $DebugCmd -and (Test-Path -LiteralPath $log)) { Remove-Item -LiteralPath $log }

$gameArgs = @('+set', 'fs_homepath', $HomeDir, '+set', 'fs_basepath', $Game, '+set', 'fs_cdpath', '""', '+set', 'fs_game', $TestGame,
	'+set', 'developer', '1', '+set', 'logfile', '2', '+set', 'com_hunkmegs', '512', '+set', 'bot_enable', '1') + $NetCvars
if ($Mode -eq 'ded') { $gameArgs += @('+set', 'dedicated', '1') } else { $gameArgs += $WindowCvars }
foreach ($k in $Set.Keys) { $gameArgs += @('+set', [string]$k, [string]$Set[$k]) }
$gameArgs += @('+exec', $CfgName)
$exePath = Join-Path $binDir $exe
Write-Key 'run' "$exe (timeout ${Timeout}s)"
if ($DebugCmd) {
	Write-Output "Push-Location $(Quote $binDir); & $(Quote $exePath) $(($gameArgs | ForEach-Object { Quote $_ }) -join ' '); Pop-Location"
	Write-Output "Select-String -LiteralPath $(Quote $log) -Pattern $(Quote $Grep)$(if ($CaseSensitive) { ' -CaseSensitive' })"
	exit 0
}
$proc = Start-Process -FilePath $exePath -ArgumentList ($gameArgs | ForEach-Object { if ($_ -match '\s' -or $_ -eq '""') { if ($_ -eq '""') { '""' } else { '"' + $_ + '"' } } else { $_ } }) `
	-WorkingDirectory $binDir -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $HomeDir 'stdout.log') -RedirectStandardError (Join-Path $HomeDir 'stderr.log')
$status = 0
if (-not $proc.WaitForExit($Timeout * 1000)) { $proc.Kill(); $status = 124; Write-Warn "timed out after ${Timeout}s (killed)" }
elseif ($proc.ExitCode -ne 0) { $status = $proc.ExitCode; Write-Err "exit status $status" }
else { Write-Ok 'exited cleanly' }

# which modules were used: the fork's copies are the only ones in the home
foreach ($m in $modules) {
	if (Test-Path -LiteralPath (Join-Path $testDir $m)) { Write-Ok "the fork's $m is in $TestGame\ (searched first through fs_game)" }
}
if (-not (Test-Path -LiteralPath $log)) { $log = Join-Path $HomeDir 'stdout.log' }
$strip = { param($l) $l -replace '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} )+', '' }
$lines = Get-Content -LiteralPath $log | ForEach-Object { & $strip $_ } | Where-Object { $_ -notmatch $ProbeRe -and $_ -notmatch '^GL_' }  # ^GL_: the extension list (GL_KHR_no_error)
$hits = if ($CaseSensitive) { $lines | Where-Object { $_ -cmatch $Grep } } else { $lines | Where-Object { $_ -match $Grep } }
if ($Baseline -and (Test-Path -LiteralPath $Baseline)) {
	$base = New-Object 'System.Collections.Generic.HashSet[string]'
	foreach ($l in Get-Content -LiteralPath $Baseline) { [void]$base.Add((& $strip $l)) }
	$hits = $hits | Where-Object { -not $base.Contains($_) }
}
if ($hits) { Write-Header "log lines matching the error filter ($(@($hits).Count)):"; $hits | ForEach-Object { Write-Host $_ } }
else { Write-Ok 'no log lines match the error filter' }
$shots = Join-Path $testDir 'screenshots'
if (Test-Path -LiteralPath $shots) { Write-Key 'screenshots' "$shots ($(@(Get-ChildItem -LiteralPath $shots).Count))" }
Write-Key 'log' $log
if ($Clean) { Remove-Item -Recurse -Force -LiteralPath $HomeDir; Write-Key 'removed' $HomeDir }
exit $status
