# common.ps1 - wspolne funkcje skryptow paczki RPLIDAR S2E
# (dot-source: . "$PSScriptRoot\common.ps1")

$script:Root = Split-Path -Parent $PSScriptRoot

# Fabryczne ustawienia S2E. Czujnik ma adres na stale, dopoki ktos go nie zmieni
# programem Slamteca - dlatego to komputer dopasowuje sie do czujnika, a nie odwrotnie.
$script:LidarIp   = '192.168.11.2'
$script:LidarPort = 8089
$script:HostIp    = '192.168.11.5'
$script:HostMask  = 24

function Step($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Info($t) { Write-Host "       $t" }

function Pause-End {
    Write-Host ""
    Read-Host "Nacisnij Enter, aby zamknac okno" | Out-Null
}

function Fail($t) {
    Write-Host ""
    Write-Host "  [BLAD] $t" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    Pause-End
    exit 1
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ask-YesNo([string]$Question, [bool]$Default = $true) {
    $hint = if ($Default) { '[T/n]' } else { '[t/N]' }
    $a = Read-Host "$Question $hint"
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    $a = $a.Trim().ToLower()
    return $a.StartsWith('t') -or $a.StartsWith('y')
}

# Folder, w ktorym paczka zapisuje wykryty adres (czyta go komponent w TouchDesignerze).
function Get-StateDir {
    $d = Join-Path $env:LOCALAPPDATA 'RPLidarS2E'
    New-Item -ItemType Directory -Force $d | Out-Null
    return $d
}

function Save-Ip([string]$Ip) {
    [IO.File]::WriteAllText((Join-Path (Get-StateDir) 'ip.txt'), $Ip)
}

function Load-Ip {
    $f = Join-Path (Get-StateDir) 'ip.txt'
    if (Test-Path $f) { return ([IO.File]::ReadAllText($f)).Trim() }
    return $null
}

# ------------------------------------------------------------------- siec

# Adresy IPv4 tego komputera, bez loopbacka.
function Get-LocalIPv4 {
    return @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -notlike '127.*' })
}

# Czy komputer ma adres w tej samej podsieci /24 co czujnik?
function Test-SameSubnet([string]$Ip = $script:LidarIp) {
    $want = ($Ip -split '\.')[0..2] -join '.'
    foreach ($a in Get-LocalIPv4) {
        if ((($a.IPAddress -split '\.')[0..2] -join '.') -eq $want) { return $a }
    }
    return $null
}

# Karty Ethernet, ktore maja wpiety kabel. 169.254.* to adres "nie dostalem DHCP",
# czyli dokladnie to, co widac na karcie wpietej prosto w czujnik.
function Get-EthernetAdapters {
    return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
             Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|Bluetooth' })
}

function Test-LidarPing([string]$Ip = $script:LidarIp) {
    try { return [bool](Test-Connection -ComputerName $Ip -Count 2 -Quiet -ErrorAction SilentlyContinue) }
    catch { return $false }
}
