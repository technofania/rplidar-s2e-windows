# net-setup.ps1 - dodaje (albo usuwa) adres IP na karcie sieciowej.
#
# To jedyny krok calej paczki, ktory wymaga administratora: zmiana adresacji
# karty sieciowej jest operacja systemowa. Uruchamia go INSTALUJ.bat przez
# okno UAC - nic poza tym nie potrzebuje podwyzszonych uprawnien.
#
# Adres jest DODAWANY obok istniejacych, a nie zastepuje ich. Karta, ktora
# bierze adres z DHCP, dalej go bierze; internet po Wi-Fi dziala bez zmian.
# Dzieki temu cofniecie zmiany to usuniecie jednego adresu i tyle.

param(
    [Parameter(Mandatory = $true)][string]$Alias,
    [string]$Ip = '192.168.11.5',
    [int]$Prefix = 24,
    [switch]$Remove
)

$ErrorActionPreference = 'Continue'
$log = Join-Path $env:TEMP 'rplidar-s2e-net.log'

function Put($t) {
    Write-Host $t
    try { Add-Content -Path $log -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) -Encoding utf8 } catch {}
}

Put "--- net-setup: alias='$Alias' ip=$Ip/$Prefix remove=$Remove ---"

$existing = Get-NetIPAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -eq $Ip }

if ($Remove) {
    if ($existing) {
        try {
            Remove-NetIPAddress -InterfaceAlias $Alias -IPAddress $Ip -Confirm:$false -ErrorAction Stop
            Put "USUNIETO $Ip z karty '$Alias'"
        } catch {
            Put ("BLAD przy usuwaniu: " + $_.Exception.Message)
            exit 1
        }
    } else {
        Put "NIE BYLO $Ip na karcie '$Alias' - nic do usuniecia"
    }
    exit 0
}

if ($existing) {
    Put "JEST JUZ $Ip na karcie '$Alias'"
    exit 0
}

try {
    New-NetIPAddress -InterfaceAlias $Alias -IPAddress $Ip -PrefixLength $Prefix -ErrorAction Stop | Out-Null
    Put "DODANO $Ip/$Prefix na karte '$Alias'"
    exit 0
} catch {
    Put ("BLAD: " + $_.Exception.Message)
    exit 1
}
