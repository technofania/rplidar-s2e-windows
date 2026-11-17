# uninstall.ps1 - cofa to, co zrobil instalator (uruchamiany przez odinstaluj.bat).
#
# Paczka nic nie instaluje w systemie, wiec do cofniecia sa trzy rzeczy:
# skroty, zapamietany adres i adres dodany na karte sieciowa. Ten ostatni
# wymaga administratora (okno UAC) - tak samo jak jego dodanie.

. "$PSScriptRoot\common.ps1"

$Host.UI.RawUI.WindowTitle = 'RPLIDAR S2E - odinstalowanie'
Write-Host ""
Write-Host "  RPLIDAR S2E - cofanie zmian" -ForegroundColor White

Step "Skroty na pulpicie"
$desk = [Environment]::GetFolderPath('Desktop')
$n = 0
foreach ($name in @('RPLIDAR S2E - projekt TouchDesigner', 'RPLIDAR S2E - sprawdz czujnik',
                    'RPLIDAR S2E - folder')) {
    $p = Join-Path $desk ($name + '.lnk')
    if (Test-Path $p) { Remove-Item $p -Force; $n++ }
}
Ok "usunieto skrotow: $n"

Step "Zapamietany adres czujnika"
$d = Join-Path $env:LOCALAPPDATA 'RPLidarS2E'
if (Test-Path $d) {
    Remove-Item $d -Recurse -Force
    Ok "usunieto $d"
} else {
    Info "nic nie bylo zapisane"
}

Step "Adres na karcie sieciowej"
$mine = Get-LocalIPv4 | Where-Object { $_.IPAddress -eq $script:HostIp }
if (-not $mine) {
    Info "nie ma adresu $($script:HostIp) na zadnej karcie - nic do cofania"
} else {
    foreach ($a in $mine) {
        Info ("jest $($a.IPAddress) na karcie '" + $a.InterfaceAlias + "'")
    }
    Info "Usuniecie wymaga administratora (okno UAC). Inne adresy karty zostaja."
    if (Ask-YesNo "Usunac?" $false) {
        foreach ($a in $mine) {
            $psargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                        ('"' + (Join-Path $PSScriptRoot 'net-setup.ps1') + '"'),
                        '-Alias', ('"' + $a.InterfaceAlias + '"'),
                        '-Ip', $script:HostIp, '-Remove')
            try {
                Start-Process -FilePath 'powershell.exe' -ArgumentList $psargs -Verb RunAs -Wait | Out-Null
            } catch {
                Warn ("Nie udalo sie: " + $_.Exception.Message)
            }
        }
        Start-Sleep -Milliseconds 400
        if (Get-LocalIPv4 | Where-Object { $_.IPAddress -eq $script:HostIp }) {
            Warn "Adres dalej jest. Szczegoly: $env:TEMP\rplidar-s2e-net.log"
        } else {
            Ok "usuniety"
        }
    } else {
        Info "Zostawiony. Nie przeszkadza - to dodatkowy adres obok istniejacych."
    }
}

Write-Host ""
Info "Caly folder paczki mozna teraz po prostu skasowac."
Write-Host ""
Write-Host "  Gotowe." -ForegroundColor Green
Pause-End
