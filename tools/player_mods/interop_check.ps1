# Checks that the fork and a stock OpenJK MP still play together with the player mods installed.
# The PowerShell twin of interop_check.sh (same homes, cfgs and checks):
#
#   fork-server   the fork's dedicated server (run_test.ps1 ded, g_modelScale on) and a stock client
#                 (the install's openjk.x86_64.exe and base\ modules, i.e. the retail protocol)
#                 joining it: a scaled model, /modelscale, moving, crouching, `rcon modelscales`,
#                 t_yoda (the stock cgame draws Kyle for a custom skeleton).
#   stock-server  the install's openjkded.x86_64.exe with its stock jampgame and a fork client
#                 (run_test.ps1 mp): no scaling, no /modelscale on the server, t_yoda as Kyle.
#
# The stock side's home holds only base\ (no modules), so the install's modules are the ones
# found; Windows has no LD_DEBUG, so that is the proof. No master servers, LAN only, 127.0.0.1.
# Prints the client log's prediction misses and error lines.
#
# Usage examples:
#   both directions in a new temp dir:
#     .\interop_check.ps1
#   one direction, homes under a given dir (kept), another port:
#     .\interop_check.ps1 fork-server -HomeDir $env:TEMP\ojk_interop -Port 29180
#   the stock build from another install dir, homes removed afterwards:
#     .\interop_check.ps1 -Game 'C:\Games\Jedi Academy\GameData' -Clean
#   print the equivalent commands instead of running them:
#     .\interop_check.ps1 -DebugCmd

param(
	[string]$Direction = 'both',
	[string]$HomeDir,
	[string]$Game,
	[int]$Port = 29170,
	[switch]$Clean,
	[switch]$DebugCmd
)

$ErrorActionPreference = 'Stop'

function Write-Header([string]$t) { Write-Host $t -ForegroundColor Cyan }
function Write-Ok([string]$t)     { Write-Host $t -ForegroundColor Green }
function Write-Warn([string]$t)   { Write-Host $t -ForegroundColor Yellow }
function Write-Err([string]$t)    { Write-Host $t -ForegroundColor Red }
function Write-Key([string]$k, [string]$v) { Write-Host "  ${k}:" -ForegroundColor Blue -NoNewline; Write-Host " $v" }

$ScriptDir = $PSScriptRoot
$RepoDir = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$BuildDir = Join-Path $RepoDir 'build'
$InstallSubdir = 'JediAcademy'
$Arch = 'x86_64'
$TestGame = 'playermods_test'
$CfgName = 'interop.cfg'
$LogName = 'qconsole.log'
$RconPassword = 'playermods_interop'
$ServerTimeout = 360
$ClientTimeout = 300
$ServerStartWait = 60
$ServerReadyRe = 'Hitch warning|------- Game Initialization -------|InitGame'
$ServerHoldWait = 12000
$ModelWait = 330
$ScaledModel = 'grievous'
$CmdScale = 50
$SkeletonModel = 't_yoda'
$BotName = 'Darth Malgus'
$WindowCvars = @('+set', 'com_maxfps', '60', '+set', 'in_mouse', '0', '+set', 'r_fullscreen', '0', '+set', 'r_mode', '-1',
	'+set', 'r_customwidth', '1280', '+set', 'r_customheight', '720', '+set', 's_volume', '0', '+set', 's_musicvolume', '0')
$NetCvars = @('+set', 'sv_master1', '""', '+set', 'sv_master2', '""', '+set', 'sv_master3', '""', '+set', 'sv_master4', '""',
	'+set', 'sv_master5', '""', '+set', 'net_enabled', '1', '+set', 'sv_lanForceRate', '1', '+set', 'dedicated_lan', '1')
$ErrorRe = "couldn't|can't|cannot|warning|error|failed|not found|g2|ghoul|missing|default model|bad |exceeded|overflow"
$MissRe = 'prediction (miss|error)'

$Direction = $Direction.ToLower()
if ($Direction -notin @('fork-server', 'stock-server', 'both')) { Write-Err 'direction: fork-server, stock-server or both'; exit 1 }
if (-not $Game) {
	$cache = Join-Path $BuildDir 'CMakeCache.txt'
	$prefix = if (Test-Path -LiteralPath $cache) { (Select-String -LiteralPath $cache -Pattern '^CMAKE_INSTALL_PREFIX:[A-Z]*=(.*)$' | Select-Object -First 1).Matches.Groups[1].Value } else { '' }
	$Game = Join-Path $prefix $InstallSubdir
}
foreach ($f in @("openjk.$Arch.exe", "openjkded.$Arch.exe", "base\cgame$Arch.dll", "base\jampgame$Arch.dll", 'base\assets0.pk3')) {
	if (-not (Test-Path -LiteralPath (Join-Path $Game $f))) { Write-Err "no $f in $Game (-Game <install dir>)"; exit 1 }
}
if (-not $HomeDir) { $HomeDir = Join-Path ([IO.Path]::GetTempPath()) ("ojk_interop." + [IO.Path]::GetRandomFileName()) }

function Quote([string]$s) { "'" + ($s -replace "'", "''") + "'" }
function Format-Args([string[]]$a) { $a | ForEach-Object { if ($_ -eq '""') { '""' } elseif ($_ -match '\s') { '"' + $_ + '"' } else { $_ } } }

function Get-ServerCfg {
	@('map mp/ffa1', 'wait 200', "addbot `"$BotName`" 1", "wait $ServerHoldWait", 'quit') -join "`n"
}

function Get-ClientCfg([string]$p) {
	@('set cg_thirdPerson 1', 'set cg_thirdPersonAngle 180', 'set cg_thirdPersonRange 110', 'set con_notifytime 0', 'set cg_showmiss 1',
		"connect 127.0.0.1:$Port", 'wait 1200', 'team free', 'wait 120', 'togglemenu', 'wait 300',
		'echo @@ interop: stock model', "screenshot ${p}_0_kyle", 'wait 20',
		"echo @@ interop: model $ScaledModel", "model $ScaledModel", "wait $ModelWait", "screenshot ${p}_1_$ScaledModel", 'wait 20',
		'echo @@ interop: move, jump, crouch', '+forward', 'wait 90', '-forward', '+moveup', 'wait 30', '-moveup', 'wait 60',
		'+movedown', 'wait 90', "screenshot ${p}_2_crouch", '-movedown', 'wait 60',
		"echo @@ interop: modelscale $CmdScale", "modelscale $CmdScale", 'wait 120', "screenshot ${p}_3_modelscale$CmdScale", 'wait 20',
		'+back', 'wait 60', '-back', 'wait 30',
		'echo @@ interop: rcon modelscales', "rconpassword $RconPassword", 'rcon modelscales', 'wait 120',
		"echo @@ interop: model $SkeletonModel", 'modelscale default', "model $SkeletonModel", "wait $ModelWait",
		"screenshot ${p}_4_$SkeletonModel", 'wait 20', 'echo @@ interop: done', 'rcon quit', 'wait 120', 'quit') -join "`n"
}

function Wait-Server([string]$log) {
	for ($i = 0; $i -lt $ServerStartWait; $i++) {
		if ((Test-Path -LiteralPath $log) -and (Select-String -LiteralPath $log -Pattern $ServerReadyRe -Quiet)) { Start-Sleep 3; return $true }
		Start-Sleep 1
	}
	$false
}

function Show-Client([string]$log) {
	if (-not $log -or -not (Test-Path -LiteralPath $log)) { Write-Err "no client log $log"; return }
	$lines = Get-Content -LiteralPath $log | ForEach-Object { $_ -replace '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} )+', '' }
	$misses = @($lines | Where-Object { $_ -match $MissRe })
	Write-Key 'prediction misses' $misses.Count
	Write-Header 'client log, per check (@@) error lines and server replies:'
	$lines | Where-Object { ($_ -match "^@@|$ErrorRe|modelscale|unknown|scale|skeleton") -and $_ -notmatch $MissRe } | ForEach-Object { Write-Output $_ }
}

function Start-Game([string]$exe, [string[]]$gameArgs, [string]$outDir) {
	Start-Process -FilePath (Join-Path $Game $exe) -ArgumentList (Format-Args $gameArgs) -WorkingDirectory $Game -PassThru -NoNewWindow `
		-RedirectStandardOutput (Join-Path $outDir 'stdout.log') -RedirectStandardError (Join-Path $outDir 'stderr.log')
}

function Invoke-ForkServer {
	$sh = Join-Path $HomeDir 'fork_server'; $ch = Join-Path $HomeDir 'stock_client'
	Write-Header "fork server, stock client (port $Port)"
	$clientArgs = @('+set', 'fs_homepath', $ch, '+set', 'fs_basepath', $Game, '+set', 'fs_cdpath', '""', '+set', 'developer', '1',
		'+set', 'logfile', '2') + $WindowCvars + $NetCvars + @('+exec', $CfgName)
	$serverCfg = Join-Path $HomeDir 'fork_server.cfg'
	if ($DebugCmd) {
		Write-Output "& $(Quote (Join-Path $ScriptDir 'run_test.ps1')) ded -HomeDir $(Quote $sh) -Timeout $ServerTimeout -Set @{ net_port = $Port; rconpassword = '$RconPassword' } -Cfg $(Quote $serverCfg)   # in its own window"
		Write-Output "& $(Quote (Join-Path $ScriptDir 'install_player_mods.ps1')) -Dest $(Quote (Join-Path $ch 'base')) -Game $(Quote $Game)"
		Write-Output "Push-Location $(Quote $Game); & .\openjk.$Arch.exe $((Format-Args $clientArgs) -join ' '); Pop-Location"
		return
	}
	New-Item -ItemType Directory -Force -Path (Join-Path $ch 'base') | Out-Null
	[IO.File]::WriteAllText($serverCfg, (Get-ServerCfg) + "`n")
	$job = Start-Job -ScriptBlock { param($s, $h, $t, $p, $r, $c) & $s ded -HomeDir $h -Timeout $t -Set @{ net_port = $p; rconpassword = $r } -Cfg $c *>&1 } `
		-ArgumentList (Join-Path $ScriptDir 'run_test.ps1'), $sh, $ServerTimeout, $Port, $RconPassword, $serverCfg
	& (Join-Path $ScriptDir 'install_player_mods.ps1') -Dest (Join-Path $ch 'base') -Game $Game | Select-Object -Last 1
	if (-not (Wait-Server (Join-Path $sh "$TestGame\$LogName"))) { Write-Err 'the fork server did not come up'; Stop-Job $job; return }
	[IO.File]::WriteAllText((Join-Path $ch "base\$CfgName"), (Get-ClientCfg 'fork_server') + "`n")
	$proc = Start-Game "openjk.$Arch.exe" $clientArgs $ch
	if (-not $proc.WaitForExit($ClientTimeout * 1000)) { $proc.Kill(); Write-Warn 'stock client timed out (killed)' } else { Write-Ok "stock client exit code $($proc.ExitCode)" }
	Wait-Job $job -Timeout $ServerTimeout | Out-Null
	Write-Header 'fork server (run_test.ps1):'; Receive-Job $job | Select-Object -Last 12 | ForEach-Object { Write-Output $_ }
	if (Get-ChildItem -LiteralPath $ch -Recurse -Filter "*$Arch.dll" -ErrorAction SilentlyContinue) { Write-Err 'the stock client home holds modules' }
	else { Write-Ok "the stock client home holds no modules: the install's base\ ones were used" }
	Show-Client (Get-ChildItem -LiteralPath $ch -Recurse -Filter $LogName | Select-Object -First 1).FullName
}

function Invoke-StockServer {
	$sh = Join-Path $HomeDir 'stock_server'; $ch = Join-Path $HomeDir 'fork_client'
	Write-Header "stock server, fork client (port $Port)"
	$serverArgs = @('+set', 'fs_homepath', $sh, '+set', 'fs_basepath', $Game, '+set', 'fs_cdpath', '""', '+set', 'fs_game', $TestGame,
		'+set', 'dedicated', '1', '+set', 'net_port', "$Port", '+set', 'rconpassword', $RconPassword, '+set', 'developer', '1',
		'+set', 'logfile', '2', '+set', 'bot_enable', '1') + $NetCvars + @('+exec', $CfgName)
	$clientCfg = Join-Path $HomeDir 'fork_client.cfg'
	if ($DebugCmd) {
		Write-Output "& $(Quote (Join-Path $ScriptDir 'install_player_mods.ps1')) -Dest $(Quote (Join-Path $sh 'base')) -Game $(Quote $Game)"
		Write-Output "Push-Location $(Quote $Game); & .\openjkded.$Arch.exe $((Format-Args $serverArgs) -join ' '); Pop-Location   # in its own window"
		Write-Output "& $(Quote (Join-Path $ScriptDir 'run_test.ps1')) mp -HomeDir $(Quote $ch) -Timeout $ClientTimeout -Cfg $(Quote $clientCfg)"
		return
	}
	New-Item -ItemType Directory -Force -Path (Join-Path $sh 'base'), (Join-Path $sh $TestGame) | Out-Null
	& (Join-Path $ScriptDir 'install_player_mods.ps1') -Dest (Join-Path $sh 'base') -Game $Game | Select-Object -Last 1
	[IO.File]::WriteAllText((Join-Path $sh "$TestGame\$CfgName"), (Get-ServerCfg) + "`n")
	$log = Join-Path $sh "$TestGame\$LogName"
	if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log }
	$proc = Start-Game "openjkded.$Arch.exe" $serverArgs $sh
	if (-not (Wait-Server $log)) { Write-Err 'the stock server did not come up'; $proc.Kill(); return }
	[IO.File]::WriteAllText($clientCfg, (Get-ClientCfg 'stock_server') + "`n")
	& (Join-Path $ScriptDir 'run_test.ps1') mp -HomeDir $ch -Timeout $ClientTimeout -Cfg $clientCfg
	if (-not $proc.WaitForExit($ServerTimeout * 1000)) { $proc.Kill(); Write-Warn 'stock server timed out (killed)' }
	if (Get-ChildItem -LiteralPath $sh -Recurse -Filter "*$Arch.dll" -ErrorAction SilentlyContinue) { Write-Err 'the stock server home holds modules' }
	else { Write-Ok "the stock server home holds no modules: the install's base\ jampgame was used" }
	Show-Client (Join-Path $ch "$TestGame\$LogName")
	Write-Header 'stock server log, modelscale lines:'
	Select-String -LiteralPath $log -Pattern 'modelscale|unknown' | Select-Object -First 10 | ForEach-Object { Write-Output $_.Line }
}

Write-Header "player mods interop check: $Direction"
Write-Key 'homes' $HomeDir
Write-Key 'stock build' $Game
switch ($Direction) {
	'fork-server'  { Invoke-ForkServer }
	'stock-server' { Invoke-StockServer }
	'both'         { Invoke-ForkServer; Invoke-StockServer }
}
if ($Clean -and -not $DebugCmd) { Remove-Item -Recurse -Force -LiteralPath $HomeDir; Write-Key 'removed' $HomeDir }
