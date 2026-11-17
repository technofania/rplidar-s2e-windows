# test-lidar.ps1 - diagnostyka S2E bez TouchDesignera.
#
# Czysty PowerShell, zero zaleznosci: dziala na swiezym Windowsie, zanim
# cokolwiek zainstalujesz. Pokazuje po kolei, gdzie sie zatrzymuje - siec,
# ping, model, tryby, strumien danych.
#
# UDP nie jest na wylacznosc, wiec to NIE zablokuje TouchDesignera tak, jak
# robil to port COM przy A1/A2. Ale czujnik wysyla strumien temu, kto ostatni
# poprosil - uruchomione naraz TD i ta diagnostyka beda sobie dane wyrywac.
# Odznacz 'Active' na komponencie albo zamknij TD, zeby pomiar byl uczciwy.

param([string]$Ip = '', [double]$Seconds = 4.0)

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\s2e.ps1"

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'RPLIDAR S2E - diagnostyka'
Write-Host ""
Write-Host "  RPLIDAR S2E - diagnostyka" -ForegroundColor White

# --- 1. siec ---
Step "1/5 Siec tego komputera"
$locals = Get-LocalIPv4
if ($locals.Count -eq 0) {
    Warn "Komputer nie ma zadnego adresu IPv4 poza loopbackiem."
} else {
    foreach ($a in $locals) {
        Info ("{0,-28} {1}/{2}" -f $a.InterfaceAlias, $a.IPAddress, $a.PrefixLength)
    }
}
$same = Test-SameSubnet
if ($same) {
    Ok ("jest adres w podsieci czujnika: " + $same.IPAddress + " na " + $same.InterfaceAlias)
} else {
    Warn "Zaden adres tego komputera nie jest w podsieci czujnika ($($script:LidarIp))."
    Info "Bez tego nie da sie z nim rozmawiac. Uruchom INSTALUJ.bat - doda $($script:HostIp)."
}

# --- 2. ping ---
Step "2/5 Ping do czujnika"
$target = if ($Ip) { $Ip } else { $script:LidarIp }
if (Test-LidarPing $target) {
    Ok "$target odpowiada na ping"
    $n = Get-NetNeighbor -IPAddress $target -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($n) { Info ("MAC czujnika: " + $n.LinkLayerAddress) }
} else {
    Warn "$target nie odpowiada na ping."
    Info "Kabel LAN wpiety w komputer i w czujnik? Zasilacz czujnika podlaczony?"
    Info "Dioda na gniazdku LAN swieci? Glowica sie kreci (slychac szum)?"
}

# --- 3. szukanie ---
Step "3/5 Szukam czujnika"
$found = (& "$PSScriptRoot\find-lidar.ps1" -Ip $Ip | Select-Object -Last 1)
if (-not $found) {
    Write-Host ""
    Warn "Czujnik nie odpowiedzial na pytanie o model."
    Info "Jesli ping dziala, a to nie - cos innego siedzi pod tym adresem,"
    Info "albo czujnik ma zmieniony port (fabrycznie $($script:LidarPort))."
    Pause-End
    exit 1
}
$link = Connect-S2E $found $script:LidarPort 1500
try {
    $info = Get-S2EInfo $link
    Ok ("$found -> " + $info.Name)
    Info ("firmware " + $info.Firmware + ", hardware " + $info.Hardware)
    Info ("numer seryjny " + $info.Serial)

    $health = Get-S2EHealth $link
    if ($health) {
        if ($health.Status -eq 0) { Ok ("zdrowie: " + $health.Text) }
        else { Warn ("zdrowie: " + $health.Text + ", kod " + $health.Code) }
    }
    $ipc = Get-S2EIpConf $link
    if ($ipc) { Info ("ustawienia czujnika: ip " + $ipc.Ip + "  maska " + $ipc.Mask + "  brama " + $ipc.Gw) }

    # --- 4. tryby ---
    Step "4/5 Tryby skanu"
    $modes = Get-S2EModes $link
    if (-not $modes) {
        Warn "Czujnik nie podal listy trybow."
        $mode = [pscustomobject]@{ Id = 3; Name = 'Sensitivity'; Us = 31.0; MaxM = 30.0; Ans = $script:ANS_HQ; Typical = $true }
        Info "Probuje trybem 3 (Sensitivity)."
    } else {
        foreach ($m in $modes) {
            $mark = if ($m.Typical) { '  <- zalecany przez czujnik' } else { '' }
            Info ("[{0}] {1,-14} {2,6:n2} us/probke   do {3,4:n0} m   format 0x{4:X2}{5}" -f
                  $m.Id, $m.Name, $m.Us, $m.MaxM, $m.Ans, $mark)
        }
        $mode = $modes | Where-Object { $_.Typical -and $_.Ans -eq $script:ANS_HQ } | Select-Object -First 1
        if (-not $mode) { $mode = $modes | Where-Object { $_.Ans -eq $script:ANS_HQ } | Select-Object -First 1 }
        if (-not $mode) {
            Warn "Czujnik nie ma trybu HQ - ta diagnostyka nie zmierzy strumienia."
            Info "Komponent w TouchDesignerze poradzi sobie i z innymi trybami."
            Close-S2E $link
            Pause-End
            exit 0
        }
    }

    # --- 5. dane ---
    Step ("5/5 Odbior danych ({0:n0} s, tryb {1})" -f $Seconds, $mode.Name)
    $r = Measure-S2EScan $link $mode $Seconds
    if ($null -eq $r) {
        Warn "Czujnik nie odpowiedzial na zadanie skanu."
        Info "Glowica stoi? Zasilacz slaby? Sprobuj odpiac i wpiac zasilanie."
    } elseif ($r.Error) {
        Warn $r.Error
    } else {
        $secs = [Math]::Max($r.Seconds, 0.001)
        $hitPct = 0.0
        if ($r.Parsed -gt 0) { $hitPct = 100.0 * $r.Hits / $r.Parsed }
        Ok ("ramek: {0} ({1:n0}/s), probek: {2} ({3:n0}/s)" -f $r.Frames, ($r.Frames / $secs), $r.Samples, ($r.Samples / $secs))
        Ok ("obrotow: {0:n1}, ~{1:n0} rpm" -f $r.Revs, $r.Rpm)
        Info "Pelny strumien to 333 ramki na sekunde, czyli ~32000 probek na sekunde."
        Info "Przy 10 obrotach na sekunde wychodzi ~3170 probek na obrot (0,11 stopnia)."
        Ok ("pokrycie kata: {0}% z 360 stopni" -f [int](100.0 * $r.Coverage / 360.0))
        Info ("z odbiciem: {0:n0}% sprawdzonych probek" -f $hitPct)
        if ($r.Hits -gt 0) {
            Info ("odleglosci: {0:n0} - {1:n0} mm" -f $r.DistMin, $r.DistMax)
        }
        if ($r.Bad -gt 0) { Warn ("odrzuconych datagramow: " + $r.Bad) }

        Write-Host ""
        $fps = $r.Frames / $secs
        if ($r.Frames -lt 100) {
            Warn "Bardzo malo danych. Sprawdz zasilanie czujnika i kabel LAN."
        } elseif ($fps -lt 250) {
            Warn ("Strumien jest rwany: {0:n0} ramek na sekunde zamiast ~333." -f $fps)
            Info "Najczesciej: TouchDesigner czyta czujnik rownoczesnie z ta diagnostyka."
            Info "Odznacz 'Active' na komponencie albo zamknij TD i uruchom test jeszcze raz."
        } elseif ($r.Coverage -lt 180) {
            Warn "Czujnik widzi mniej niz pol obrotu."
            Info "Normalne, gdy stoi w kacie albo tuz przy scianie. Jesli nie -"
            Info "cos zaslania glowice: tasma, wlasny kabel, obudowa."
        } else {
            Write-Host "  Czujnik dziala poprawnie." -ForegroundColor Green
        }
    }
} finally {
    Close-S2E $link
}

Write-Host ""
Info "Projekt TouchDesignera: td\RPLidarS2E.toe"
Info "Opis i rozwiazania problemow: README.md"
Pause-End
