# find-lidar.ps1 - znajduje S2E w sieci i zapamietuje jego adres.
#
# Wypisuje znaleziony adres jako OSTATNIA linie (reszta idzie na konsole),
# zeby dalo sie go wziac z potoku:  $ip = (.\find-lidar.ps1 | Select-Object -Last 1)

param([string]$Ip = '', [switch]$Quiet)

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\s2e.ps1"

function Say($t) { if (-not $Quiet) { Info $t } }

# Adresy warte sprawdzenia: podany, zapamietany, fabryczny, a na koncu x.y.z.2
# kazdej podsieci, w ktorej siedzi ta maszyna - czujnik fabrycznie jest na .2.
$cands = New-Object System.Collections.Generic.List[string]
foreach ($c in @($Ip, (Load-Ip), $script:LidarIp)) {
    if ($c -and -not $cands.Contains($c)) { [void]$cands.Add($c) }
}
foreach ($a in Get-LocalIPv4) {
    $p = $a.IPAddress -split '\.'
    if ($p.Count -ne 4) { continue }
    $guess = ($p[0..2] -join '.') + '.2'
    if ($guess -ne $a.IPAddress -and -not $cands.Contains($guess)) { [void]$cands.Add($guess) }
}

Say ("sprawdzam: " + ($cands -join ', '))

$found = $null
foreach ($c in $cands) {
    $link = $null
    try {
        $link = Connect-S2E $c $script:LidarPort 700
        $info = Get-S2EInfo $link
        if ($info) {
            $found = [pscustomobject]@{ Ip = $c; Info = $info }
            break
        }
    } catch {
    } finally {
        if ($link) { Close-S2E $link }
    }
}

if ($found) {
    if (-not $Quiet) { Ok ("$($found.Ip) -> $($found.Info.Name), firmware $($found.Info.Firmware)") }
    Save-Ip $found.Ip
    Write-Output $found.Ip
} else {
    if (-not $Quiet) {
        Warn "Nie znalazlem czujnika pod zadnym z tych adresow."
        Info "Najczesciej: karta sieciowa nie ma adresu w podsieci czujnika."
        Info "Uruchom INSTALUJ.bat - ustawi $($script:HostIp) na karcie z wpietym kablem."
    }
    Write-Output ''
}
