# s2e.ps1 - protokol RPLIDAR S2E w czystym PowerShellu, po UDP.
#
# Zadnych zaleznosci: dziala na swiezym Windowsie, zanim cokolwiek zainstalujesz,
# i bez TouchDesignera. Tego samego protokolu uzywa komponent w TD - tyle ze tam
# jest napisany w Pythonie.
#
# Ramka zadania:   0xA5 <komenda> [dlugosc] [dane...] [suma XOR wszystkich bajtow]
# Deskryptor odpowiedzi: 0xA5 0x5A <u32: 30 bitow dlugosci + 2 bity trybu> <typ>

$script:CMD_STOP        = 0x25
$script:CMD_SCAN        = 0x20
$script:CMD_GET_INFO    = 0x50
$script:CMD_GET_HEALTH  = 0x52
$script:CMD_EXPRESS     = 0x82
$script:CMD_GET_CONF    = 0x84

$script:ANS_STANDARD = 0x81
$script:ANS_HQ       = 0x83
$script:ANS_DENSE    = 0x85

$script:HQ_LEN = 781      # 1 sync + 8 znacznik czasu + 96*8 probek + 4 crc

function New-S2ERequest([byte]$Cmd, [byte[]]$Payload = $null) {
    $b = New-Object System.Collections.Generic.List[byte]
    $b.Add(0xA5); $b.Add($Cmd)
    if ($Payload -and $Payload.Length -gt 0) {
        $b.Add([byte]$Payload.Length)
        foreach ($x in $Payload) { $b.Add($x) }
        $cs = 0
        foreach ($x in $b) { $cs = $cs -bxor $x }
        $b.Add([byte]$cs)
    }
    return ,$b.ToArray()
}

function Connect-S2E([string]$Ip, [int]$Port = 8089, [int]$TimeoutMs = 1000) {
    $c = New-Object System.Net.Sockets.UdpClient
    $c.Client.ReceiveTimeout = $TimeoutMs
    $c.Client.ReceiveBufferSize = 4194304
    $c.Connect($Ip, $Port)
    return [pscustomobject]@{ Client = $c; Buf = (New-Object System.Collections.Generic.List[byte]) }
}

function Close-S2E($Link) {
    try { Send-S2E $Link $script:CMD_STOP } catch {}
    try { $Link.Client.Close() } catch {}
}

function Send-S2E($Link, [byte]$Cmd, [byte[]]$Payload = $null) {
    $r = New-S2ERequest $Cmd $Payload
    [void]$Link.Client.Send($r, $r.Length)
}

# Jeden datagram. Zwraca $null przy ciszy (a nie wyjatek).
function Receive-S2EDatagram($Link) {
    $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
    try { return ,[byte[]]$Link.Client.Receive([ref]$ep) } catch { return $null }
}

# Wyrzuca to, co jeszcze leci. OGRANICZONE CZASEM: przy dzialajacym skanie
# socket nigdy nie zamilknie i petla "czytaj do ciszy" wisialaby bez konca.
function Clear-S2E($Link, [double]$Seconds = 0.3) {
    $Link.Buf.Clear()
    $old = $Link.Client.Client.ReceiveTimeout
    $Link.Client.Client.ReceiveTimeout = 40
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
        if ($null -eq (Receive-S2EDatagram $Link)) { break }
    }
    $Link.Client.Client.ReceiveTimeout = $old
    $Link.Buf.Clear()
}

function Read-S2EInto($Link) {
    $d = Receive-S2EDatagram $Link
    if ($null -eq $d) { return 0 }
    $Link.Buf.AddRange([byte[]]$d)
    return $d.Length
}

# Deskryptor odpowiedzi -> @{ Len; Mode; Type } albo $null.
function Read-S2EDescriptor($Link, [double]$TimeoutSec = 2.0) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec) {
        for ($i = 0; $i -le $Link.Buf.Count - 7; $i++) {
            if ($Link.Buf[$i] -eq 0xA5 -and $Link.Buf[$i + 1] -eq 0x5A) {
                $head = $Link.Buf.GetRange($i, 7).ToArray()
                $Link.Buf.RemoveRange(0, $i + 7)
                $v = [BitConverter]::ToUInt32($head, 2)
                return @{ Len = [int]($v -band 0x3FFFFFFF); Mode = [int]($v -shr 30); Type = [int]$head[6] }
            }
        }
        if ((Read-S2EInto $Link) -eq 0) { }
    }
    return $null
}

function Read-S2EPayload($Link, [int]$N, [double]$TimeoutSec = 2.0) {
    $t0 = Get-Date
    while ($Link.Buf.Count -lt $N -and ((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec) {
        [void](Read-S2EInto $Link)
    }
    if ($Link.Buf.Count -lt $N) { return $null }
    $out = [byte[]]$Link.Buf.GetRange(0, $N).ToArray()
    $Link.Buf.RemoveRange(0, $N)
    return ,$out
}

function Invoke-S2E($Link, [byte]$Cmd, [byte[]]$Payload = $null, [double]$TimeoutSec = 2.0) {
    $Link.Buf.Clear()
    Send-S2E $Link $Cmd $Payload
    $d = Read-S2EDescriptor $Link $TimeoutSec
    if ($null -eq $d) { return $null }
    $body = Read-S2EPayload $Link $d.Len $TimeoutSec
    if ($null -eq $body) { return $null }
    return @{ Type = $d.Type; Data = [byte[]]$body }
}

function Get-S2EConf($Link, [uint32]$Type, [byte[]]$Extra = $null) {
    $p = [BitConverter]::GetBytes([uint32]$Type)
    if ($Extra) { $p = $p + $Extra }
    $r = Invoke-S2E $Link $script:CMD_GET_CONF $p
    if ($null -eq $r -or $r.Data.Length -lt 4) { return $null }
    if ([BitConverter]::ToUInt32($r.Data, 0) -ne $Type) { return $null }
    if ($r.Data.Length -eq 4) { return ,([byte[]]@()) }
    return ,([byte[]]($r.Data[4..($r.Data.Length - 1)]))
}

function Get-S2EModelName([int]$Model) {
    switch ($Model) {
        0x71 { 'RPLIDAR S2E' }
        0x72 { 'RPLIDAR S2E' }
        0x61 { 'RPLIDAR S1' }
        0x41 { 'RPLIDAR S2' }
        default { ('model 0x{0:X2}' -f $Model) }
    }
}

# Model, firmware, numer seryjny. $null, gdy nic nie odpowiada.
function Get-S2EInfo($Link) {
    Send-S2E $Link $script:CMD_STOP
    Start-Sleep -Milliseconds 60
    Clear-S2E $Link 0.1
    $r = Invoke-S2E $Link $script:CMD_GET_INFO
    if ($null -eq $r -or $r.Data.Length -lt 20) { return $null }
    $fw = [BitConverter]::ToUInt16($r.Data, 1)
    return [pscustomobject]@{
        Model    = [int]$r.Data[0]
        Name     = Get-S2EModelName ([int]$r.Data[0])
        Firmware = ('{0}.{1:d2}' -f ($fw -shr 8), ($fw -band 0xFF))
        Hardware = [int]$r.Data[3]
        Serial   = ((($r.Data[4..19]) | ForEach-Object { '{0:X2}' -f $_ }) -join '')
    }
}

function Get-S2EHealth($Link) {
    $r = Invoke-S2E $Link $script:CMD_GET_HEALTH
    if ($null -eq $r -or $r.Data.Length -lt 3) { return $null }
    return [pscustomobject]@{
        Status = [int]$r.Data[0]
        Text   = @('OK', 'OSTRZEZENIE', 'BLAD')[[Math]::Min(2, [int]$r.Data[0])]
        Code   = [int][BitConverter]::ToUInt16($r.Data, 1)
    }
}

# Tryby skanu czujnika + numer zalecanego przez producenta.
function Get-S2EModes($Link) {
    $cnt = Get-S2EConf $Link 0x70
    $typ = Get-S2EConf $Link 0x7C
    if ($null -eq $cnt -or $null -eq $typ) { return $null }
    $count = [BitConverter]::ToUInt16($cnt, 0)
    $typical = [BitConverter]::ToUInt16($typ, 0)
    $modes = @()
    for ($m = 0; $m -lt [Math]::Min($count, 16); $m++) {
        $mid = [BitConverter]::GetBytes([uint16]$m)
        $nameB = Get-S2EConf $Link 0x7F $mid
        $usB   = Get-S2EConf $Link 0x71 $mid
        $maxB  = Get-S2EConf $Link 0x74 $mid
        $ansB  = Get-S2EConf $Link 0x75 $mid
        if ($null -eq $nameB -or $null -eq $usB) { continue }
        $name = ([Text.Encoding]::ASCII.GetString($nameB)) -replace "`0.*$", ''
        $modes += [pscustomobject]@{
            Id      = $m
            Name    = $name
            Us      = [BitConverter]::ToUInt32($usB, 0) / 256.0
            MaxM    = [BitConverter]::ToUInt32($maxB, 0) / 256.0
            Ans     = [int]$ansB[0]
            Typical = ($m -eq $typical)
        }
    }
    return $modes
}

function Get-S2EIpConf($Link) {
    $d = Get-S2EConf $Link 0x1CCC0 @(0, 0)
    if ($null -eq $d -or $d.Length -lt 12) { return $null }
    return [pscustomobject]@{
        Ip   = ($d[0..3]  -join '.')
        Mask = ($d[4..7]  -join '.')
        Gw   = ($d[8..11] -join '.')
    }
}

# Odbiera skan przez $Seconds sekund i zwraca statystyki.
# Parsujemy co $Stride-ta probke - do pokrycia kata i zakresu odleglosci to
# az nadto, a PowerShell nie udusi sie na 150 tysiacach iteracji.
function Measure-S2EScan($Link, [object]$Mode, [double]$Seconds = 4.0, [int]$Stride = 4) {
    Send-S2E $Link $script:CMD_STOP
    Start-Sleep -Milliseconds 120
    Clear-S2E $Link 0.2

    if ($Mode.Ans -eq $script:ANS_STANDARD) {
        Send-S2E $Link $script:CMD_SCAN
    } else {
        $p = @([byte]$Mode.Id, 0, 0, 0, 0)
        Send-S2E $Link $script:CMD_EXPRESS $p
    }
    $desc = Read-S2EDescriptor $Link 2.0
    if ($null -eq $desc) { return $null }
    if ($desc.Type -ne $Mode.Ans) {
        return [pscustomobject]@{ Error = ('czujnik odpowiedzial typem 0x{0:X2}, oczekiwano 0x{1:X2}' -f $desc.Type, $Mode.Ans) }
    }
    if ($desc.Type -ne $script:ANS_HQ) {
        return [pscustomobject]@{ Error = 'ta diagnostyka czyta tylko tryb HQ (Sensitivity)' }
    }

    # Rozgrzewka: pierwsze wywolania w PowerShellu sa kilka razy wolniejsze niz
    # kolejne, a mierzylibysmy wtedy szybkosc PowerShella, nie czujnika.
    $warm = [Diagnostics.Stopwatch]::StartNew()
    while ($warm.Elapsed.TotalSeconds -lt 0.7) { $null = Receive-S2EDatagram $Link }

    $frames = 0; $bad = 0; $pts = 0; $hits = 0
    $travel = 0.0
    $dmin = [double]::MaxValue; $dmax = 0.0
    $deg = New-Object 'bool[]' 360
    $prevAngle = -1.0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        $d = [byte[]](Receive-S2EDatagram $Link)
        if ($null -eq $d) { continue }
        if ($d.Length -ne $script:HQ_LEN -or $d[0] -ne 0xA5) { $bad++; continue }
        $frames++

        # Obroty liczymy jako SUME przebytego kata, a nie jako zliczone
        # przewiniecia przez zero. PowerShell nie nadaza za 390 datagramami na
        # sekunde i czesc gubi; przy zliczaniu przewiniec kazda zgubiona ramka
        # na granicy zera kasowalaby caly obrot i wynik wychodzil o polowe za
        # niski. Suma przyrostow jest na zgubione ramki odporna.
        $a0 = [BitConverter]::ToUInt16($d, 9) * 90.0 / 16384.0
        if ($prevAngle -ge 0) {
            $step = $a0 - $prevAngle
            if ($step -lt 0) { $step += 360.0 }
            $travel += $step
        }
        $prevAngle = $a0

        for ($k = 0; $k -lt 96; $k += $Stride) {
            $o = 9 + $k * 8
            $pts++
            $dist = [BitConverter]::ToUInt32($d, $o + 2) / 4.0
            if ($dist -gt 0) {
                $hits++
                if ($dist -lt $dmin) { $dmin = $dist }
                if ($dist -gt $dmax) { $dmax = $dist }
                $a = [int]([BitConverter]::ToUInt16($d, $o) * 90.0 / 16384.0)
                if ($a -ge 0 -and $a -lt 360) { $deg[$a] = $true }
            }
        }
    }
    $elapsed = $sw.Elapsed.TotalSeconds
    Send-S2E $Link $script:CMD_STOP

    $cov = 0
    foreach ($b in $deg) { if ($b) { $cov++ } }
    $revs = $travel / 360.0
    $rpm = 0.0
    if ($elapsed -gt 0) { $rpm = $revs * 60.0 / $elapsed }
    $lo = 0.0
    if ($hits -gt 0) { $lo = $dmin }
    return [pscustomobject]@{
        Error    = $null
        Seconds  = $elapsed
        Frames   = $frames
        Bad      = $bad
        Samples  = $frames * 96
        Parsed   = $pts
        Hits     = $hits
        Revs     = $revs
        Rpm      = $rpm
        Coverage = $cov
        DistMin  = $lo
        DistMax  = $dmax
    }
}
