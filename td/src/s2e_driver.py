"""RPLIDAR S2E dla TouchDesignera na Windowsie.

S2E to wersja ETHERNETOWA. Nie ma portu COM, nie ma przejsciowki USB i nie ma
czym krecic silnikiem - glowica kreci sie, odkad czujnik ma prad. Rozmowa idzie
po UDP na 192.168.11.2:8089, a protokol jest ten sam co po kablu szeregowym:
ramka zadania 0xA5 <komenda> [dlugosc] [dane] [suma XOR], a odpowiedz zaczyna
deskryptor 0xA5 0x5A.

Sterownik nie potrzebuje niczego spoza TouchDesignera: socket i zlib sa
w standardowym Pythonie, numpy jest w TD.

Czemu osobny watek: gotowanie sieci w TD potrafi stanac na kilkadziesiat
milisekund, a czujnik wypuszcza 333 datagramy na sekunde i nie czeka na nikogo.
Czytanie w onCook gubiloby obroty. Watek tylko odbiera i wpisuje do pierscienia,
a Script CHOP przepisuje ostatni stan.

Skan trzymany jest jako JEDEN trwaly pierscien BINS kubelkow ze znacznikiem
obrotu na kazdym kubelku, a nie jako bufor przepisywany co obrot. Dzieki temu
nie ma szwu na 0 stopni, a kubelek, ktory przestal zwracac odbicie, po prostu
sie starzeje i gasnie.

Uzycie z TouchDesignera (patrz s2e_scan.py):
    drv = mod('s2e_driver').acquire(ip='auto')
    dist = drv.snapshot()      # float32[BINS], milimetry, 0.0 = brak odbicia
"""

import builtins
import os
import socket
import struct
import threading
import time
import zlib

import numpy as np

DEFAULT_IP = "192.168.11.2"
DEFAULT_PORT = 8089

# Zmierzone na S2E firmware 1.02: 10,1 obrotu na sekunde, 32000 probek na
# sekunde, czyli 3170 probek na obrot - 0,11 stopnia miedzy probkami. 1024
# kubelki to 0,35 stopnia i srednio trzy probki na kubelek: gesto, a wciaz
# tanio w CHOP-ie i w teksturze.
BINS = 1024
MAX_GAP = 6           # tyle kubelkow dziury interpolujemy
STALE_REVS = 2        # kubelek bez odbicia przez tyle obrotow czyta sie jako pusty

# komendy
CMD_STOP = 0x25
CMD_SCAN = 0x20
CMD_RESET = 0x40
CMD_GET_INFO = 0x50
CMD_GET_HEALTH = 0x52
CMD_EXPRESS_SCAN = 0x82
CMD_GET_CONF = 0x84

# typy odpowiedzi ze skanem
ANS_STANDARD = 0x81
ANS_DENSE = 0x85
ANS_HQ = 0x83

# pola konfiguracji
CONF_SCAN_MODE_COUNT = 0x70
CONF_SCAN_MODE_US = 0x71
CONF_SCAN_MODE_MAXDIST = 0x74
CONF_SCAN_MODE_ANSTYPE = 0x75
CONF_SCAN_MODE_TYPICAL = 0x7C
CONF_SCAN_MODE_NAME = 0x7F
CONF_STATIC_IP = 0x1CCC0

# dlugosci ramek ze skanem
LEN_HQ = 1 + 8 + 96 * 8 + 4      # 781: sync, timestamp, 96 probek, crc32
LEN_DENSE = 2 + 2 + 40 * 2       # 84: suma, kat startowy, 40 odleglosci
LEN_STD = 5


def _req(cmd, payload=b""):
    """Ramka zadania. Suma XOR liczona po WSZYSTKICH bajtach, razem z 0xA5."""
    p = bytes([0xA5, cmd])
    if payload:
        p += bytes([len(payload)]) + payload
        cs = 0
        for b in p:
            cs ^= b
        p += bytes([cs])
    return p


def _crc32(data):
    """CRC32 Slamteca: zwykly CRC32, ale dane sa dopychane zerami do
    wielokrotnosci 4 bajtow, i to ZAWSZE o 1 do 4 bajtow, nigdy o 0."""
    pad = 4 - (len(data) & 3)
    return zlib.crc32(data + b"\x00" * pad) & 0xFFFFFFFF


def fill_gaps(d, max_gap=MAX_GAP):
    """Interpoluje krotkie dziury w pierscieniu odleglosci. Zwraca nowa tablice."""
    n = d.size
    idx = np.flatnonzero(d)
    if idx.size < 8:
        return d
    xi = np.concatenate([idx - n, idx, idx + n])
    yi = np.tile(d[idx], 3)
    pos = np.arange(n)
    interp = np.interp(pos, xi, yi)
    j = np.searchsorted(xi, pos, side="left")
    j = np.clip(j, 1, xi.size - 1)
    width = xi[j] - xi[j - 1]
    return np.where((d > 0) | (width <= max_gap + 1), interp, 0.0
                    ).astype(np.float32)


def model_name(model):
    return {0x71: "RPLIDAR S2E", 0x72: "RPLIDAR S2E",
            0x61: "RPLIDAR S1", 0x41: "RPLIDAR S2",
            }.get(model, "model 0x%02X" % model)


# ------------------------------------------------------------------ rozmowa

class _Link:
    """Jeden socket UDP do czujnika, z buforem strumienia.

    UDP nie jest na wylacznosc - w odroznieniu od portu COM dwa programy moga
    gadac z czujnikiem naraz. Czujnik odpowiada temu, kto ostatni poprosil,
    wiec uruchomiona diagnostyka i TouchDesigner beda sobie wyrywac strumien.
    To nie uszkodzi niczego, ale dane beda rwane.
    """

    def __init__(self, ip, port=DEFAULT_PORT, timeout=1.0):
        self.ip = ip
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(timeout)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
        self.sock.connect((ip, port))
        self.buf = bytearray()

    def close(self):
        try:
            self.sock.send(_req(CMD_STOP))
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass

    def send(self, data):
        self.sock.send(data)

    def recv(self, timeout=None):
        """Jeden datagram do bufora. Zwraca ile bajtow doszlo (0 = cisza)."""
        if timeout is not None:
            self.sock.settimeout(timeout)
        try:
            d = self.sock.recv(65535)
        except socket.timeout:
            return 0
        self.buf += d
        return len(d)

    def drain(self, seconds=0.3):
        """Wyrzuca to, co jeszcze leci. OGRANICZONE CZASEM - przy dzialajacym
        skanie socket nigdy nie zamilknie i petla "czytaj do timeoutu" wisi."""
        self.buf.clear()
        t0 = time.time()
        old = self.sock.gettimeout()
        self.sock.settimeout(0.03)
        try:
            while time.time() - t0 < seconds:
                self.sock.recv(65535)
        except Exception:
            pass
        self.sock.settimeout(old)
        self.buf.clear()

    def descriptor(self, timeout=2.0):
        """Deskryptor odpowiedzi: (dlugosc, tryb, typ). Rzuca przy ciszy."""
        t0 = time.time()
        while time.time() - t0 < timeout:
            i = bytes(self.buf).find(b"\xa5\x5a")
            if i >= 0 and len(self.buf) >= i + 7:
                del self.buf[:i]
                head = bytes(self.buf[:7])
                del self.buf[:7]
                v = struct.unpack("<I", head[2:6])[0]
                return v & 0x3FFFFFFF, v >> 30, head[6]
            self.recv(0.3)
        raise OSError("czujnik nie odpowiedzial (deskryptor)")

    def payload(self, n, timeout=2.0):
        t0 = time.time()
        while len(self.buf) < n and time.time() - t0 < timeout:
            self.recv(0.3)
        if len(self.buf) < n:
            raise OSError("czujnik odpowiedzial za krotko (%d z %d bajtow)"
                          % (len(self.buf), n))
        out = bytes(self.buf[:n])
        del self.buf[:n]
        return out

    def ask(self, cmd, data=b"", timeout=2.0):
        """Zadanie z odpowiedzia jednorazowa."""
        self.buf.clear()
        self.send(_req(cmd, data))
        ln, _mode, typ = self.descriptor(timeout)
        return typ, self.payload(ln, timeout)

    def conf(self, ctype, extra=b"", timeout=2.0):
        """GET_LIDAR_CONF. Odpowiedz zaczyna sie powtorzonym typem pola."""
        _typ, d = self.ask(CMD_GET_CONF, struct.pack("<I", ctype) + extra,
                           timeout)
        if len(d) < 4 or struct.unpack("<I", d[:4])[0] != ctype:
            raise OSError("czujnik odpowiedzial na inne pole konfiguracji")
        return d[4:]

    def device_info(self):
        _typ, d = self.ask(CMD_GET_INFO)
        if len(d) < 20:
            raise OSError("niepelna odpowiedz GET_INFO")
        fw = struct.unpack("<H", d[1:3])[0]
        return {"model": d[0], "name": model_name(d[0]),
                "firmware": "%d.%02d" % (fw >> 8, fw & 0xFF),
                "hardware": d[3], "serial": d[4:20].hex().upper()}

    def health(self):
        _typ, d = self.ask(CMD_GET_HEALTH)
        if len(d) < 3:
            return 2, 0
        return d[0], struct.unpack("<H", d[1:3])[0]

    def scan_modes(self):
        """Lista trybow czujnika + numer trybu zalecanego przez producenta."""
        count = struct.unpack("<H", self.conf(CONF_SCAN_MODE_COUNT)[:2])[0]
        typical = struct.unpack("<H", self.conf(CONF_SCAN_MODE_TYPICAL)[:2])[0]
        modes = []
        for m in range(min(count, 16)):
            mid = struct.pack("<H", m)
            name = self.conf(CONF_SCAN_MODE_NAME, mid).split(b"\x00")[0]
            modes.append({
                "id": m,
                "name": name.decode("ascii", "replace"),
                # us_per_sample przychodzi w formacie Q8 (stale punkt, 1/256)
                "us": struct.unpack("<I", self.conf(CONF_SCAN_MODE_US, mid)[:4])[0] / 256.0,
                "max_m": struct.unpack("<I", self.conf(CONF_SCAN_MODE_MAXDIST, mid)[:4])[0] / 256.0,
                "ans": self.conf(CONF_SCAN_MODE_ANSTYPE, mid)[0],
            })
        return modes, typical

    def ip_conf(self):
        d = self.conf(CONF_STATIC_IP, b"\x00\x00")
        if len(d) < 12:
            return {}
        fmt = lambda b: ".".join(str(x) for x in b)
        return {"ip": fmt(d[0:4]), "mask": fmt(d[4:8]), "gw": fmt(d[8:12])}


# ---------------------------------------------------------------- szukanie

def _local_subnets():
    """Adresy IPv4 tego komputera - zeby zgadnac, gdzie szukac czujnika."""
    out = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None,
                                       socket.AF_INET):
            a = info[4][0]
            if a and not a.startswith("127.") and a not in out:
                out.append(a)
    except Exception:
        pass
    return out


def saved_ip():
    """Adres zapamietany przez INSTALUJ.bat / sprawdz-lidar.bat, albo None."""
    try:
        p = os.path.join(os.environ.get("LOCALAPPDATA", ""), "RPLidarS2E",
                         "ip.txt")
        if os.path.isfile(p):
            with open(p, "r", encoding="utf-8", errors="ignore") as f:
                v = f.read().strip()
            return v or None
    except Exception:
        pass
    return None


def probe(ip, timeout=0.6):
    """Czy pod tym adresem odpowiada S2E? Slownik info albo None."""
    link = None
    try:
        link = _Link(ip, timeout=timeout)
        link.send(_req(CMD_STOP))
        time.sleep(0.05)
        link.drain(0.1)
        info = link.device_info()
        info["ip"] = ip
        return info
    except Exception:
        return None
    finally:
        if link:
            link.close()


def candidates():
    """Adresy warte sprawdzenia, w sensownej kolejnosci, bez powtorzen."""
    out = []
    for ip in (saved_ip(), DEFAULT_IP):
        if ip and ip not in out:
            out.append(ip)
    # Czujnik fabrycznie siedzi pod x.y.z.2 swojej podsieci. Jesli ktos zmienil
    # adresacje, to najczesciej przeniosl caly odcinek, a nie samo .2.
    for me_ip in _local_subnets():
        parts = me_ip.split(".")
        if len(parts) != 4:
            continue
        guess = ".".join(parts[:3] + ["2"])
        if guess != me_ip and guess not in out:
            out.append(guess)
    return out


def autodetect(prefer=None):
    """Adres, pod ktorym odpowiada S2E, albo None."""
    order = []
    for ip in [prefer] + candidates():
        if ip and ip not in order:
            order.append(ip)
    for ip in order:
        if probe(ip):
            return ip
    return None


# ----------------------------------------------------------------- sterownik

class RPLidarS2E:
    def __init__(self, ip=DEFAULT_IP, port=DEFAULT_PORT, bins=BINS, mode=None):
        self.ip = ip
        self.port = port
        self.bins = bins
        self.want_mode = mode            # None = tryb zalecany przez czujnik
        self.link = None
        self._thread = None
        self._run = False
        self._lock = threading.Lock()
        self._dist = np.zeros(bins, np.float32)
        self._stamp = np.full(bins, -1e6, np.float32)
        self.rev = 0
        self.samples = 0
        self.errors = 0
        self.status = "idle"
        self.mode = "-"
        self.info = {}
        self.modes = []
        self.health = None
        self.last_rev_time = 0.0
        self.rpm = 0.0

    # ---------------- cykl zycia ----------------

    def start(self):
        """Otwiera polaczenie synchronicznie, zeby blad byl od razu widoczny,
        i rusza watkiem czytajacym."""
        if self.running:
            return self
        link = _Link(self.ip, self.port)
        try:
            link.send(_req(CMD_STOP))
            time.sleep(0.05)
            link.drain(0.15)
            self.info = link.device_info()
            self.health = link.health()
        except Exception:
            link.close()
            raise OSError(
                "czujnik pod %s nie odpowiada. Kabel w gniazdku LAN? Zasilacz "
                "podlaczony? Karta sieciowa ma adres w tej samej podsieci "
                "(np. 192.168.11.5)?" % self.ip)
        self.link = link
        self.status = "polaczony"
        self._run = True
        self._thread = threading.Thread(target=self._loop, daemon=True,
                                        name="s2e-" + self.ip)
        self._thread.start()
        return self

    def stop(self):
        """Zatrzymuje watek i DOPIERO POTEM zamyka socket.

        Kolejnosc ma znaczenie tak samo jak przy porcie COM: zamkniety socket
        pod dzialajacym watkiem zostawia watek w petli, ktora miele wyjatki.
        """
        self._run = False
        t = self._thread
        if t and t.is_alive():
            t.join(timeout=2.0)
        self._thread = None
        if self.link:
            self._close()
        self.status = "zatrzymany"

    @property
    def running(self):
        return bool(self._thread and self._thread.is_alive())

    def _close(self):
        link, self.link = self.link, None
        if link:
            link.close()

    # ---------------- dane ----------------

    def snapshot(self, fill=True):
        """Ostatni pelny obrot jako float32[bins] w mm; 0.0 = brak odbicia."""
        with self._lock:
            d = self._dist.copy()
            stamp = self._stamp.copy()
            rev = self.rev
        d[(rev - stamp) > STALE_REVS] = 0.0
        return fill_gaps(d) if fill else d

    def _commit(self, angles, dists):
        """Wrzuca probki jednej ramki do pierscienia."""
        if not len(angles):
            return
        a = np.asarray(angles, np.float32)
        d = np.asarray(dists, np.float32)
        keep = d > 0
        if not keep.any():
            return
        b = (a[keep] * (self.bins / 360.0)).astype(np.int32) % self.bins
        with self._lock:
            self._dist[b] = d[keep]
            self._stamp[b] = self.rev

    def _turned(self):
        now = time.time()
        if self.last_rev_time:
            dt = now - self.last_rev_time
            if dt > 0.001:
                self.rpm = self.rpm * 0.7 + (60.0 / dt) * 0.3
        self.last_rev_time = now
        self.rev += 1

    # ---------------- skan ----------------

    def _pick_mode(self):
        """Numer i opis trybu, ktorym bedziemy skanowac.

        Zalecany przez producenta (SCAN_MODE_TYPICAL) to na S2E "Sensitivity",
        ktory nadaje ramki HQ: 96 probek w jednym datagramie, z katem i
        odlegloscia wprost w kazdej probce. Jesli czujnik zaleci tryb, ktorego
        nie umiemy rozpakowac, spadamy na pierwszy, ktory umiemy.
        """
        self.modes, typical = self.link.scan_modes()
        known = (ANS_HQ, ANS_DENSE, ANS_STANDARD)
        by_id = {m["id"]: m for m in self.modes}

        want = self.want_mode
        if isinstance(want, str):
            want = want.strip().lower()
            if want in ("", "auto", "typical"):
                want = None
            else:
                hit = [m for m in self.modes if m["name"].lower() == want]
                want = hit[0]["id"] if hit else None

        for cand in (want, typical):
            if cand is not None and cand in by_id and by_id[cand]["ans"] in known:
                return by_id[cand]
        for m in self.modes:
            if m["ans"] in known:
                return m
        raise OSError("czujnik nie podaje trybu skanu, ktory umiemy czytac")

    def _begin(self, mode):
        """Startuje skan i sprawdza deskryptor. Zwraca (dlugosc ramki, typ)."""
        self.link.send(_req(CMD_STOP))
        time.sleep(0.1)
        self.link.drain(0.2)
        if mode["ans"] == ANS_STANDARD:
            self.link.send(_req(CMD_SCAN))
        else:
            # EXPRESS_SCAN: working_mode u8, working_flags u16, param u16
            self.link.send(_req(CMD_EXPRESS_SCAN,
                                struct.pack("<BHH", mode["id"], 0, 0)))
        ln, _m, typ = self.link.descriptor(2.0)
        if typ != mode["ans"]:
            raise OSError("czujnik odpowiedzial typem 0x%02X, a nie 0x%02X"
                          % (typ, mode["ans"]))
        return ln, typ

    def _loop(self):
        try:
            mode = self._pick_mode()
            ln, typ = self._begin(mode)
            self.mode = "%s (%.0f m)" % (mode["name"], mode["max_m"])
            self.status = "skanuje"
            if typ == ANS_HQ:
                self._loop_hq(ln)
            elif typ == ANS_DENSE:
                self._loop_dense(ln)
            else:
                self._loop_standard()
        except Exception as e:
            self.status = "blad: %s" % (e,)
        finally:
            # Watek zamyka polaczenie sam - patrz komentarz w stop().
            self._close()
            if not self.status.startswith("blad"):
                self.status = "zatrzymany"

    def _read(self, timeout=0.5):
        """Doklada jeden datagram do bufora. False = cisza."""
        return self.link.recv(timeout) > 0

    def _loop_hq(self, ln):
        """Tryb Sensitivity / HQ: jedna ramka 781 B na datagram.

        Ramka: 0xA5, znacznik czasu u64, 96 probek po 8 B
        (kat Q14 u16, odleglosc Q2 u32, jakosc u8, flagi u8), crc32.
        Bit 0 flag zapala sie na pierwszej probce nowego obrotu - w odroznieniu
        od kapsul express z A2, gdzie ten bit nie zapala sie nigdy.
        """
        n = 96
        buf = self.link.buf
        while self._run:
            if not self._read():
                continue
            while len(buf) >= ln:
                if buf[0] != 0xA5:
                    del buf[:1]
                    self.errors += 1
                    continue
                frame = bytes(buf[:ln])
                if _crc32(frame[:ln - 4]) != struct.unpack("<I", frame[ln - 4:])[0]:
                    del buf[:1]
                    self.errors += 1
                    continue
                del buf[:ln]

                raw = np.frombuffer(frame, np.uint8, n * 8, 9).reshape(n, 8)
                ang = raw[:, 0:2].copy().view(np.uint16).ravel() * (90.0 / 16384.0)
                dist = raw[:, 2:6].copy().view(np.uint32).ravel() * 0.25
                if (raw[:, 7] & 1).any():
                    self._turned()
                self.samples += n
                self._commit(ang, dist)

    def _loop_dense(self, ln):
        """Tryb DenseBoost: kapsula 84 B = suma, kat startowy, 40 odleglosci.

        Kapsula nie niesie katow probek - niesie tylko kat POCZATKOWY. Katy
        rozklada sie rowno miedzy katem startowym tej kapsuly a nastepnej,
        wiec kazda kapsula wyswietla sie dopiero, gdy przyjdzie nastepna.
        """
        cabins = 40
        prev = None
        last_q6 = 0
        buf = self.link.buf
        while self._run:
            if not self._read():
                continue
            while len(buf) >= ln:
                if (buf[0] >> 4) != 0xA or (buf[1] >> 4) != 0x5:
                    del buf[:1]
                    self.errors += 1
                    prev = None
                    continue
                pkt = bytes(buf[:ln])
                want = (pkt[0] & 0x0F) | ((pkt[1] & 0x0F) << 4)
                got = int(np.bitwise_xor.reduce(
                    np.frombuffer(pkt, np.uint8, ln - 2, 2)))
                if want != got:
                    del buf[:1]
                    self.errors += 1
                    prev = None
                    continue
                del buf[:ln]

                cur_q6 = struct.unpack("<H", pkt[2:4])[0] & 0x7FFF
                if cur_q6 < last_q6:
                    self._turned()
                last_q6 = cur_q6
                if prev is None:
                    prev = (cur_q6, pkt)
                    continue
                prev_q6, prev_pkt = prev
                prev = (cur_q6, pkt)

                diff_q8 = (cur_q6 << 2) - (prev_q6 << 2)
                if diff_q8 < 0:
                    diff_q8 += 360 << 8
                inc = (diff_q8 / 256.0) / cabins
                base = prev_q6 / 64.0
                ang = base + inc * np.arange(cabins, dtype=np.float32)
                dist = np.frombuffer(prev_pkt, np.uint16, cabins, 4
                                     ).astype(np.float32)
                self.samples += cabins
                self._commit(np.mod(ang, 360.0), dist)

    def _loop_standard(self):
        """Tryb Standard: 5 bajtow na probke, jeden datagram na probke.

        Na Ethernecie to marnotrawstwo (9000 datagramow na sekunde zamiast
        390) i czujnik gubi probki, ale dziala bez rozpakowywania kapsul,
        wiec zostaje jako awaryjny.
        """
        buf = self.link.buf
        while self._run:
            if not self._read():
                continue
            angles, dists = [], []
            i, n = 0, len(buf)
            while i + LEN_STD <= n:
                b0, b1 = buf[i], buf[i + 1]
                if ((b0 & 0x01) == ((b0 >> 1) & 0x01)) or not (b1 & 0x01):
                    i += 1
                    self.errors += 1
                    continue
                quality = b0 >> 2
                angles.append(((b1 >> 1) | (buf[i + 2] << 7)) / 64.0)
                dists.append((buf[i + 3] | (buf[i + 4] << 8)) / 4.0
                             if quality else 0.0)
                if b0 & 0x01:
                    self._turned()
                i += LEN_STD
                self.samples += 1
            del buf[:i]
            self._commit(angles, dists)


# ------------------------------------------------- rejestr na caly proces
#
# Sterownik NIE moze mieszkac tylko w pamieci operatora (op.store). Przeladowanie
# DAT-u, skasowanie komponentu albo wyczyszczenie pamieci operatora zostawialoby
# zywy watek, o ktorym nikt juz nie wie - a on dalej prosi czujnik o dane i
# wyrywa strumien temu, kto przyjdzie po nim. Rejestr siedzi w `builtins`, czyli
# przezywa kazde przeladowanie modulu i kazda zmiane w sieci.

_REG_KEY = "_rplidar_s2e_registry_v1"


def _registry():
    r = getattr(builtins, _REG_KEY, None)
    if r is None:
        r = {}
        setattr(builtins, _REG_KEY, r)
    return r


def peek(ip=None):
    """Dzialajacy sterownik (dla adresu albo jakikolwiek), bez uruchamiania."""
    reg = _registry()
    if ip:
        return reg.get(ip)
    for d in reg.values():
        if d.running:
            return d
    return None


def acquire(ip=None, mode=None, restart=False, exclusive=True):
    """Zwraca dzialajacy sterownik dla `ip`, uruchamiajac go w razie potrzeby.

    ip='' albo 'auto' - szukamy sami. Rzuca OSError z komunikatem po polsku.
    """
    reg = _registry()
    if not ip or str(ip).strip().lower() in ("auto", ""):
        have = peek()
        if have is not None and have.running and not restart:
            return have
        ip = autodetect()
        if not ip:
            raise OSError(
                "nie znalazlem S2E pod zadnym adresem (probowalem: %s). "
                "Sprawdz kabel LAN, zasilacz i adres karty sieciowej - "
                "uruchom sprawdz-lidar.bat z folderu paczki."
                % ", ".join(candidates()))

    if exclusive:
        for other in [p for p in list(reg) if p != ip]:
            release(other)

    drv = reg.get(ip)
    if drv is not None and (restart or not drv.running):
        try:
            drv.stop()
        except Exception:
            pass
        reg.pop(ip, None)
        drv = None
    if drv is None:
        drv = RPLidarS2E(ip=ip, mode=mode)
        reg[ip] = drv        # wpis PRZED start(), zeby nieudany start byl widoczny
        try:
            drv.start()
        except Exception:
            reg.pop(ip, None)
            raise
    return drv


def release(ip=None):
    """Zatrzymuje i zapomina sterownik (albo wszystkie, gdy ip=None)."""
    reg = _registry()
    for p in ([ip] if ip else list(reg)):
        drv = reg.pop(p, None)
        if drv is not None:
            try:
                drv.stop()
            except Exception:
                pass


def reap(ip=None):
    """Zatrzymuje sterowniki, o ktorych nikt juz nie wie. Zwraca ile ubil.

    Potrzebne, bo wczytanie innego projektu (File > Open) kasuje komponent
    razem z rejestrem, ale NIE zatrzymuje watka czytajacego - a ten dalej
    trzyma strumien czujnika i nowy projekt dostaje dane poszarpane na pol.
    """
    import gc
    killed = 0
    reg = _registry()
    known = set(id(d) for d in reg.values())
    for o in gc.get_objects():
        if type(o).__name__ != "RPLidarS2E" or id(o) in known:
            continue
        if ip and getattr(o, "ip", None) != ip:
            continue
        if not getattr(o, "link", None) and not getattr(o, "_run", False):
            continue
        try:
            o._run = False
            t = getattr(o, "_thread", None)
            if t is not None and t.is_alive():
                t.join(timeout=1.0)
            link = getattr(o, "link", None)
            if link:
                link.close()
                o.link = None
            killed += 1
        except Exception:
            pass
    return killed


def registry_state():
    """Co siedzi w rejestrze - do DAT-u ze statusem."""
    return {p: (d.status, d.running) for p, d in _registry().items()}
