# install.ps1 - instalator paczki RPLIDAR S2E (uruchamiany przez INSTALUJ.bat).
#
# Paczka nie instaluje Pythona, pakietow ani sterownikow - caly kod czujnika
# siedzi w komponencie TouchDesignera, a diagnostyka jest w PowerShellu.
# Instalator ma cztery zadania: ustawic adres na karcie sieciowej, znalezc
# czujnik, sprawdzic TouchDesignera i zrobic skroty.
#
# Tylko pierwszy z nich wymaga administratora (okno UAC) - i tylko wtedy, gdy
# komputer nie ma jeszcze adresu w podsieci czujnika.

param([switch]$NoShortcuts, [switch]$NoNetwork)

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\s2e.ps1"

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Set-Location $Root
try { Start-Transcript -Path (Join-Path $Root 'install.log') -Force | Out-Null } catch {}

$Host.UI.RawUI.WindowTitle = 'Instalator RPLIDAR S2E'
Write-Host ""
Write-Host "  RPLIDAR S2E dla TouchDesignera - instalacja" -ForegroundColor White
Write-Host "  Folder: $Root"

# --- 0. czy to na pewno rozpakowany folder ---
if ($Root -match '\\AppData\\Local\\Temp\\' -or $Root -match '\.zip\\') {
    Fail "Uruchamiasz instalator z wnetrza archiwum ZIP. Najpierw rozpakuj (prawy klik na ZIP > Wyodrebnij wszystko), potem uruchom INSTALUJ.bat z rozpakowanego folderu."
}
Get-ChildItem $Root -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

# --- 1. siec ---
Step "1/4 Adres karty sieciowej"
Info "S2E to czujnik ETHERNETOWY. Nie ma portu COM i nie ma przejsciowki USB."
Info "Fabrycznie siedzi pod $($script:LidarIp) i tego adresu nie zmienia - to"
Info "komputer musi dostac adres w tej samej podsieci, np. $($script:HostIp)."

$same = Test-SameSubnet
if ($same) {
    Ok ("jest juz adres w podsieci czujnika: " + $same.IPAddress + " na karcie '" + $same.InterfaceAlias + "'")
} elseif ($NoNetwork) {
    Warn "Pominieto konfiguracje sieci (parametr -NoNetwork)."
} else {
    $eth = Get-EthernetAdapters
    if ($eth.Count -eq 0) {
        Warn "Nie widze zadnej karty Ethernet z wpietym kablem."
        Info "Wepnij kabel od czujnika do gniazdka LAN w komputerze (albo do switcha,"
        Info "w ktorym siedzi i czujnik, i komputer) i uruchom INSTALUJ.bat ponownie."
        Info "Laptop bez gniazdka LAN potrzebuje przejsciowki USB-Ethernet."
    } else {
        $pick = $eth[0]
        if ($eth.Count -gt 1) {
            Write-Host ""
            Info "Kart Ethernet z wpietym kablem jest wiecej niz jedna:"
            for ($i = 0; $i -lt $eth.Count; $i++) {
                Info ("  [{0}] {1}  ({2})" -f ($i + 1), $eth[$i].Name, $eth[$i].InterfaceDescription)
            }
            $a = Read-Host "Ktora idzie do czujnika? [1-$($eth.Count)]"
            $n = 0
            if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $eth.Count) {
                $pick = $eth[$n - 1]
            } else {
                Info "Nierozpoznany wybor - biore pierwsza."
            }
        }
        Write-Host ""
        Info ("Dodam adres $($script:HostIp)/$($script:HostMask) na karte '" + $pick.Name + "'.")
        Info "Adres zostanie DODANY obok istniejacych - DHCP i internet dzialaja dalej."
        Info "Ten jeden krok wymaga administratora, wiec pojawi sie okno UAC."
        if (Ask-YesNo "Zrobic to teraz?") {
            $psargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                      ('"' + (Join-Path $PSScriptRoot 'net-setup.ps1') + '"'),
                      '-Alias', ('"' + $pick.Name + '"'),
                      '-Ip', $script:HostIp, '-Prefix', $script:HostMask)
            try {
                $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $psargs -Verb RunAs -Wait -PassThru
                Start-Sleep -Milliseconds 400
                $same = Test-SameSubnet
                if ($same) {
                    Ok ("ustawione: " + $same.IPAddress + " na '" + $same.InterfaceAlias + "'")
                } else {
                    Warn "Adres sie nie pojawil (kod wyjscia $($p.ExitCode))."
                    Info "Szczegoly: $env:TEMP\rplidar-s2e-net.log"
                }
            } catch {
                Warn ("Nie udalo sie: " + $_.Exception.Message)
                Info "Mozna ustawic recznie: Ustawienia > Siec > Ethernet > Edytuj IP,"
                Info "dodaj adres $($script:HostIp), maska 255.255.255.0, bramy nie wpisuj."
            }
        } else {
            Info "Pominieto. Bez adresu w podsieci czujnika nic nie zadziala."
        }
    }
}

# --- 2. szukanie czujnika ---
Step "2/4 Szukam czujnika"
$ip = (& "$PSScriptRoot\find-lidar.ps1" | Select-Object -Last 1)
if ($ip) {
    $link = Connect-S2E $ip $script:LidarPort 1200
    try {
        $info = Get-S2EInfo $link
        if ($info) {
            Ok ("$ip -> " + $info.Name + ", firmware " + $info.Firmware)
            $h = Get-S2EHealth $link
            if ($h -and $h.Status -ne 0) { Warn ("zdrowie czujnika: " + $h.Text + ", kod " + $h.Code) }
            Save-Ip $ip
        }
    } finally { Close-S2E $link }
} else {
    Warn "Nie znalazlem czujnika."
    Info "Najczestsze przyczyny: zasilacz nie podlaczony (glowica musi sie krecic),"
    Info "kabel LAN nie wpiety, karta sieciowa bez adresu w podsieci czujnika."
    Info "Komponent w TouchDesignerze ma Adres = auto - znajdzie go sam, gdy sie pojawi."
}

# --- 3. TouchDesigner ---
Step "3/4 TouchDesigner"
$td = $null
foreach ($base in @("$env:ProgramFiles\Derivative", "${env:ProgramFiles(x86)}\Derivative")) {
    if (Test-Path $base) {
        $cand = Get-ChildItem $base -Directory -Filter 'TouchDesigner*' -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
        if ($cand) {
            $exe = Join-Path $cand.FullName 'bin\TouchDesigner.exe'
            if (Test-Path $exe) { $td = $exe; break }
        }
    }
}
if ($td) {
    Ok ("znaleziony: " + $td)
} else {
    Warn "Nie znalazlem TouchDesignera w Program Files."
    Info "Pobierz darmowa wersje Non-Commercial: https://derivative.ca/download"
    Info "Paczka wymaga wersji 2022.20000 lub nowszej (testowana na 2025.32460)."
}

# --- 4. skroty ---
Step "4/4 Skroty na pulpicie"
if ($NoShortcuts) {
    Info "Pominieto (parametr -NoShortcuts)."
} else {
    try {
        $desk = [Environment]::GetFolderPath('Desktop')
        $ws = New-Object -ComObject WScript.Shell
        $links = @(
            @{ Name = 'RPLIDAR S2E - projekt TouchDesigner'; Target = 'td\RPLidarS2E.toe'; Icon = 'shell32.dll,13' },
            @{ Name = 'RPLIDAR S2E - sprawdz czujnik';       Target = 'sprawdz-lidar.bat'; Icon = 'shell32.dll,23' },
            @{ Name = 'RPLIDAR S2E - folder';                Target = '';                  Icon = 'shell32.dll,3' }
        )
        foreach ($l in $links) {
            $target = if ($l.Target) { Join-Path $Root $l.Target } else { $Root }
            if ($l.Target -and -not (Test-Path $target)) { continue }
            $s = $ws.CreateShortcut((Join-Path $desk ($l.Name + '.lnk')))
            $s.TargetPath = $target
            $s.WorkingDirectory = $Root
            $s.IconLocation = "$env:SystemRoot\System32\$($l.Icon)"
            $s.Save()
        }
        Ok "Utworzono skroty na pulpicie"
    } catch {
        Warn ("Nie udalo sie utworzyc skrotow: " + $_.Exception.Message)
    }
}

Write-Host ""
Write-Host "  Gotowe." -ForegroundColor Green
if ($ip) {
    Write-Host "  Czujnik pod $ip. Otworz 'RPLIDAR S2E - projekt TouchDesigner' z pulpitu."
} else {
    Write-Host "  Podlacz czujnik i uruchom 'sprawdz-lidar.bat', potem otworz projekt z folderu td\."
}
Write-Host "  Szczegoly i rozwiazania problemow: README.md"
try { Stop-Transcript | Out-Null } catch {}
Pause-End
