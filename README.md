# RPLIDAR S2E w TouchDesignerze na Windows – zestaw dla studentów

Lidar 2D **Slamtec RPLIDAR S2E** podłączony kablem **Ethernet**, czytany
**bezpośrednio w TouchDesignerze** – bez Pythona, bez ROS, bez SDK, bez
instalowania czegokolwiek w systemie. Skan na żywo, nauka tła pustego
pomieszczenia, wykrywanie i śledzenie ludzi, wyjście OSC i gotowy projekt
do przerabiania.

| Co widzi czujnik | Demo reagujące na ludzi |
|---|---|
| ![widok z góry](docs/widok.png) | ![demo](docs/demo.png) |

*Po lewej: biały – skan na żywo, niebieski – nauczone tło, czerwony – to, czego
w pustym pokoju nie było, zielone kółka – śledzone obiekty.*

> **S2E to wersja ethernetowa.** Nie ma portu COM, nie ma przejściówki USB
> i nie ma czym kręcić silnikiem – głowica kręci się, odkąd czujnik ma prąd.
> Jeśli masz A1, A2 albo A3 na USB, to jest osobna paczka:
> [rplidar-windows](https://github.com/technofania/rplidar-windows).

---

## Czego potrzebujesz

- Windows 10 lub 11 (64-bit)
- RPLIDAR **S2E** z zasilaczem z zestawu
- kabel Ethernet (zwykły patchcord) i **gniazdko LAN w komputerze** –
  laptop bez gniazdka potrzebuje przejściówki USB-Ethernet
- [TouchDesigner](https://derivative.ca/download) **2022.20000 lub nowszy**
  (darmowa wersja Non-Commercial w zupełności wystarczy; testowane na 2025.32460)
- **jednorazowo prawa administratora** – tylko po to, żeby dodać komputerowi
  adres IP w podsieci czujnika. Nic poza tym nie wymaga UAC.

> Czujnik **musi mieć własny zasilacz**. Ethernet nie zasila go po kablu
> (to nie jest PoE), a głowica bez prądu nie kręci się wcale.

## Dlaczego w ogóle trzeba cokolwiek ustawiać

S2E ma adres **192.168.11.2** wpisany na stałe i sam o nic nie prosi – nie
pyta o DHCP, nie rozgłasza się w sieci. Żeby komputer mógł do niego mówić,
musi mieć własny adres w tej samej podsieci, czyli **192.168.11.x**.

Instalator **dodaje** adres `192.168.11.5` obok istniejących, zamiast je
zastępować. Dzięki temu Wi-Fi, internet i DHCP działają dalej bez zmian,
a cofnięcie zmiany to usunięcie jednego adresu.

## Instalacja (3 minuty)

1. **Pobierz paczkę:** zielony przycisk **Code → Download ZIP** na tej stronie.
2. **Rozpakuj** ZIP: prawy klik → *Wyodrębnij wszystko…* → np. do `Dokumenty`.
   Nie uruchamiaj niczego z wnętrza ZIP-a.
3. **Podłącz czujnik**: zasilacz do gniazdka, kabel Ethernet do komputera.
   Głowica powinna zacząć się kręcić (słychać szum), a dioda na gnieździe LAN
   zamrugać.
4. Kliknij dwa razy **`INSTALUJ.bat`**.
   - Jeśli pojawi się *„System Windows ochronił ten komputer"*: **Więcej informacji → Uruchom mimo to**.
   - Przy kroku 1/4 wyskoczy **okno UAC** – to ten jedyny moment, w którym
     potrzebne są prawa administratora.
5. Instalator ustawi adres karty, znajdzie czujnik, sprawdzi TouchDesignera
   i zrobi skróty na pulpicie.
6. Otwórz **`td\RPLidarS2E.toe`** (albo skrót *„RPLIDAR S2E – projekt TouchDesigner"*).

To wszystko. Żadnego `pip`, żadnego `venv`, żadnego SDK Slamteca.

### Jeśli wolisz ustawić adres ręcznie

Ustawienia → Sieć i internet → Ethernet → **Edytuj** przy „Przypisanie IP" →
Ręcznie → IPv4 włączone → adres `192.168.11.5`, maska `255.255.255.0`,
bramy i DNS **nie wpisuj**. Potem uruchom `sprawdz-lidar.bat`.

## Pierwsze uruchomienie

Po otwarciu projektu kliknij na komponent **`s2e`** i spójrz na DAT **`status`**
w środku – to jedyne miejsce, do którego warto zaglądać, gdy coś nie działa.
Powinno być:

```
DZIALA  adres 192.168.11.2  tryb Sensitivity (30 m)
stan sterownika: skanuje
obroty: 606 rpm   obrotow: 118   probek: 374112   bledow: 0
czujnik: RPLIDAR S2E, firmware 1.02, hardware 18
zdrowie czujnika: OK (kod 0)

TLO: nie nauczone - wszystko w zasiegu jest "obiektem".
```

Teraz **wyjdź z zasięgu czujnika** i pulsnij **„Naucz tło"** (strona *Tlo i obiekty*).
Przez 3 sekundy komponent zapamiętuje, jak wygląda puste pomieszczenie. Od tej chwili
„obiektem" jest tylko to, czego w nim nie było – czyli ludzie.

Tło zapisuje się razem z projektem (siedzi w DAT-cie `bg_data`), ale **po przestawieniu
czujnika albo przemeblowaniu trzeba nauczyć je od nowa** – zapisane tło nie wie
o przeprowadzce.

## Komponent `s2e`

Przeciągnij **`td\rplidar_s2e.tox`** do własnego projektu i masz wszystko poniżej.
Komponent jest samowystarczalny – cały kod siedzi w DAT-ach w środku.

### Co z niego wychodzi

| Operator | Co daje |
|---|---|
| `scan` | CHOP, kanał `dist`: **1024 kubełki** odległości w mm, kubełek `k` = kąt `k · 360/1024`, `0` = brak odbicia |
| `objects` | CHOP, próbka na slot: `active id x y dist angle width age speed`. `x`,`y` w **metrach**, `x` w prawo, `y` do przodu czujnika |
| `info` | CHOP: `ok rpm revs samples errors objects points background learning` |
| `view` | TOP 720×720: widok z góry |
| `cloud` | TOP 1024×1 RGBA32F: `R`=x[m] `G`=y[m] `B`=odległość[m] `A`=1 odbicie / 2 obiekt – gotowe pod instancing i GLSL |
| `objdata` | TOP *Slots*×1 RGBA32F: `R`=x[m] `G`=y[m] `B`=szerokość[m] `A`=1 gdy slot zajęty |
| `status` | DAT: stan czujnika po polsku |
| `oscout` | wysyła `objects` po OSC, gdy zaznaczysz *Wysyłaj OSC* |

### Parametry

**Lidar**

| Parametr | Co robi |
|---|---|
| **Active** | wyłączenie zamyka połączenie – przydatne, gdy chcesz uruchomić `sprawdz-lidar.bat` |
| **Adres czujnika** | `auto` = szukaj sam (zalecane). Można wpisać `192.168.11.2` na sztywno |
| **Znajdź czujnik** | przeszukuje sensowne adresy i wpisuje znaleziony |
| **Tryb skanu** | `auto` bierze tryb zalecany przez czujnik (na S2E: *Sensitivity*). Patrz niżej |
| **Restart sterownika** | zamyka i otwiera połączenie od nowa |

**Tlo i obiekty**

| Parametr | Co robi |
|---|---|
| **Naucz tło** | 3 s nauki **pustego** pomieszczenia |
| **Wyczyść tło** | po tym wszystko w zasięgu jest znowu „obiektem" |
| **Używaj tła** | wyłączone = wykrywaj wszystko w zasięgu (dobre do pierwszego sprawdzenia, bezużyteczne w instalacji) |
| **Margines tła** | o ile mm bliżej niż tło musi coś być, żeby liczyło się jako nowe. Za mało → ściany migoczą; za dużo → człowiek przy ścianie znika |
| **Zasięg min / max** | odcina odbicia od obudowy i te z drugiego końca sali |
| **Min. / max. szerokość obiektu** | w kubełkach. Min 6 odsiewa pojedyncze zgubione próbki, max 160 odsiewa „całą ścianę" |
| **Dopuszczalna dziura** | ile pustych kubełków wolno przeskoczyć, sklejając jeden obiekt |
| **Głębokość przedniej powierzchni** | liczy się tylko to, co jest najbliżej – inaczej środek obiektu wędrowałby po całym ramieniu |

**Sledzenie** – `Slots` (ile obiektów naraz), `Max. przeskok` (ile metrów obiekt może
przeskoczyć i wciąż być sobą), `Zwolnienie numeru po` (jak długo trzymać numer, gdy
obiekt zniknął), `Wygładzanie`.

**Widok** – zasięg widoku z góry, czy rysować tło i kółka obiektów.

**OSC** – adres i port odbiorcy. Adresy wiadomości to nazwy kanałów `objects`.

### Tryby skanu

Czujnik sam podaje listę swoich trybów – `sprawdz-lidar.bat` ją wypisuje.
Na egzemplarzu z firmware 1.02 jest ich cztery:

| Tryb | Zasięg | Format ramki | Czyta go komponent? |
|---|---|---|---|
| Standard | 16 m | 5 bajtów na próbkę | tak, ale to awaryjny – jeden datagram na próbkę to marnotrawstwo na Ethernecie |
| DenseBoost | 30 m | kapsuła 84 B, 40 próbek | tak |
| UltraDense | 30 m | kapsuła 165 B | **nie** |
| **Sensitivity** | **30 m** | **ramka HQ 781 B, 96 próbek** | **tak – domyślny, zalecany przez czujnik** |

Zostaw **auto**. Sensitivity daje 30 metrów zasięgu, 32 000 próbek na sekundę
i kąt oraz odległość wprost w każdej próbce – nie ma powodu wybierać czegoś innego.

## Pomysły na instalacje

- **Ludzie jako wejście:** naucz tło → `objects` → `x`, `y` sterują dźwiękiem,
  światłem, obrazem. `info/objects` = „ilu ludzi w kadrze".
- **Ściana dotykowa:** powieś lidar **płasko na ścianie**, kilka cm przed płaszczyzną
  projekcji. Dłoń dotykająca ściany wchodzi w płaszczyznę skanu i jest wykrywana jako
  obiekt. Trzeba dorobić kalibrację lidar↔projektor.
- **Bramka / licznik przejść:** wąski wycinek kąta + `age` i `speed` z `objects`.
- **Duża przestrzeń:** 30 metrów zasięgu to zupełnie inna skala niż 6 metrów A2 –
  jeden S2E obsłuży całą salę gimnastyczną.
- **Własny wygląd:** `cloud` jako źródło instancji (1024 punkty), `objdata` w swoim
  GLSL-u – tak zrobione jest demo w `RPLidarS2E.toe` (plik `td/src/demo.frag`, 40 linii).

## Diagnostyka bez TouchDesignera

**`sprawdz-lidar.bat`** – czysty PowerShell, działa na świeżym Windowsie, zanim
cokolwiek zainstalujesz. Pokazuje po kolei, gdzie się zatrzymuje:

```
=== 1/5 Siec tego komputera ===
  [OK] jest adres w podsieci czujnika: 192.168.11.5 na Ethernet

=== 2/5 Ping do czujnika ===
  [OK] 192.168.11.2 odpowiada na ping
       MAC czujnika: 52-50-78-7A-51-48

=== 3/5 Szukam czujnika ===
  [OK] 192.168.11.2 -> RPLIDAR S2E
       firmware 1.02, hardware 18
  [OK] zdrowie: OK
       ustawienia czujnika: ip 192.168.11.2  maska 255.255.255.0  brama 192.168.11.1

=== 4/5 Tryby skanu ===
       [0] Standard        62.00 us/probke   do   16 m   format 0x81
       [1] DenseBoost      31.00 us/probke   do   30 m   format 0x85
       [2] UltraDense      31.00 us/probke   do   30 m   format 0x86
       [3] Sensitivity     31.00 us/probke   do   30 m   format 0x83  <- zalecany przez czujnik

=== 5/5 Odbior danych (4 s, tryb Sensitivity) ===
  [OK] ramek: 1335 (334/s), probek: 128160 (32,017/s)
  [OK] obrotow: 40.3, ~605 rpm
  [OK] pokrycie kata: 96% z 360 stopni
       odleglosci: 107 - 7,248 mm
```

Odznacz **Active** na komponencie (albo zamknij TD), zanim to uruchomisz.
UDP **nie jest na wyłączność** – w odróżnieniu od portu COM nic się nie
zablokuje – ale czujnik wysyła strumień temu, kto ostatni poprosił, więc
TouchDesigner i diagnostyka naraz będą sobie dane wyrywać.

## Typowe problemy

| Objaw | Co zrobić |
|---|---|
| `status` mówi „BRAK POLACZENIA", głowica się kręci | Komputer nie ma adresu w podsieci czujnika. Uruchom `INSTALUJ.bat` albo ustaw `192.168.11.5` ręcznie. |
| Ping do `192.168.11.2` nie przechodzi | Kabel Ethernet nie wpięty albo wpięty w inne gniazdo niż to, które dostało adres. Sprawdź diody na gnieździe LAN. |
| Głowica nie kręci się wcale | Brak zasilania. Ethernet **nie zasila** czujnika – zasilacz z zestawu musi być w gniazdku. |
| Instalator mówi „nie widzę karty Ethernet z wpiętym kablem" | Laptop bez gniazdka LAN – potrzebna przejściówka USB-Ethernet. Albo kabel wpięty do switcha, który nie jest podłączony do komputera. |
| Adres się ustawił, ale po restarcie znikł | Adres dodany przez `New-NetIPAddress` jest trwały. Jeśli znika, ktoś/coś przestawia kartę na DHCP – sprawdź oprogramowanie producenta laptopa. |
| Strumień jest rwany, `bledow` rośnie | Dwa programy naraz czytają czujnik (drugi TouchDesigner, otwarta diagnostyka). Czujnik wysyła dane ostatniemu, kto poprosił. |
| Czujnik jest w sieci razem z innymi urządzeniami i gubi dane | 32 000 próbek na sekundę to ~20 Mbit/s **ciągłego** UDP. Przez przeciążony switch albo Wi-Fi to nie przejdzie. Najlepiej kabel prosto do komputera. |
| Dane w TD zamarzły, obraz płynie dalej | Script CHOP/TOP **bez wejścia nigdy nie jest oznaczany jako brudny**. Komponent gotuje je na piechotę w Execute DAT `exec` – jeśli przepisujesz kod do siebie, nie zgub tego. |
| TouchDesigner zapisał projekt „with errors" | Pamięć operatora jest marynowana do `.toe`, a socket, wątek i Tracker się nie marynują. Komponent czyści to w `onProjectPreSave` – jeśli przepisujesz kod, przepisz też to. |
| Wszystko jest „obiektem", cały pokój świeci na czerwono | Tło nie jest nauczone. Wyjdź z kadru i pulsnij **Naucz tło**. |
| Po nauce tła nic nie jest wykrywane | Tło nauczone z Tobą w kadrze – stoisz teraz tam, gdzie „zawsze była ściana". Naucz jeszcze raz, przy pustym pomieszczeniu. |
| Obiekty pojawiają się tam, gdzie nikogo nie ma | Kierunki, w których podczas nauki nie było żadnego odbicia, traktowane są jako otwarta przestrzeń – tam **każde** odbicie jest nowe. Zmniejsz **Zasięg max** albo zwiększ **Margines tła**. |
| Lidar widzi tylko wycinek z 360° | Normalne, gdy stoi w kącie albo przy ścianie. Jeśli nie – coś zasłania głowicę: taśma, własny kabel, obudowa. Sprawdź pokrycie w `sprawdz-lidar.bat`. |
| Czarne, szklane albo lustrzane powierzchnie nie są widziane | Tak działa lidar – czarny materiał nie odbija, szkło przepuszcza, lustro odbija w bok. Nie da się tego wyregulować, trzeba to obejść ustawieniem czujnika. |
| TD nie otwiera `.toe` | Za stara wersja. Zaktualizuj albo przeciągnij `td\rplidar_s2e.tox` do pustego projektu. |

## Dla zaawansowanych

### Ile właściwie widzi S2E

Zmierzone na firmware 1.02, tryb Sensitivity:

| | |
|---|---|
| obroty głowicy | 10,1 na sekundę (606 rpm), **nie da się zmienić** |
| próbek na sekundę | 32 000 |
| próbek na obrót | ~3170, czyli **0,11°** między próbkami |
| datagramów na sekundę | 333 (po 781 bajtów) |
| zasięg | 0,1 – 30 m |

Dla porównania: A2 przy fabrycznych obrotach daje 1,2°, a po zwolnieniu silnika
0,67°. S2E jest od tego sześć razy gęstszy i nie trzeba nic kombinować z PWM –
**komenda sterowania obrotami (`0xA8`) na tym egzemplarzu nic nie robi**,
głowica zawsze kręci się 10 razy na sekundę.

Kubełków jest **1024** (0,35°), czyli średnio **trzy próbki na kubełek**.
Można by zrobić 2048, ale wtedy część kubełków byłaby pusta i trzeba by więcej
interpolować, a `scan` i `cloud` urosłyby bez zysku.

### Jak to jest zrobione

- **Bez SDK i bez pyserial.** Protokół S2E to zwykły protokół RPLIDAR-a opakowany
  w datagramy UDP – ta sama ramka `0xA5 <komenda> …`, ten sam deskryptor
  odpowiedzi `0xA5 0x5A`. Wystarczy `socket` ze standardowego Pythona.
- **Osobny wątek.** Zatkane gotowanie sieci nie może gubić danych skanu, więc
  czytanie socketu chodzi w tle, a `scan` tylko przepisuje ostatni stan.
- **Jeden trwały pierścień 1024 kubełków** ze znacznikiem obrotu na każdym, zamiast
  podwójnego bufora przepisywanego co obrót. Dzięki temu nie ma szwu na 0°, a kubełek,
  który przestał zwracać odbicie, po prostu się starzeje i gaśnie.
- **Rejestr sterownika w `builtins`.** Przeładowanie DAT-u albo skasowanie komponentu
  zostawiało wcześniej żywy wątek, który dalej wyrywał czujnikowi strumień.
  Teraz sterownik da się odnaleźć i zamknąć zawsze.
- **Wątek zamyka socket sam.** Zamknięcie socketu pod działającym wątkiem zostawia
  go w pętli mielącej wyjątki.

### Protokół – co warto wiedzieć

Sprawdzone na S2E, firmware 1.02, hardware 18:

- **Kanał UDP jest przezroczysty.** Slamtec w swoim SDK (`sl_udp_channel.cpp`)
  traktuje go dokładnie jak port szeregowy: te same komendy, te same odpowiedzi.
  W praktyce **każdy datagram to dokładnie jedna ramka**, więc nie trzeba nawet
  sklejać strumienia.
- **Tryb Sensitivity nadaje ramki HQ, nie kapsuły express.** Ramka ma 781 bajtów:
  `0xA5`, znacznik czasu (u64), 96 próbek po 8 bajtów (kąt Q14 u16, odległość Q2
  u32, jakość u8, flagi u8), CRC32.
- **Kąt i odległość są w każdej próbce wprost** – nie trzeba, jak przy kapsułach
  express z A2, rozkładać kątów między kapsułami. Kąt = `angle_q14 · 90 / 2^14`
  stopni, odległość = `dist_q2 / 4` milimetrów.
- **Bit 0 flag to bit synchronizacji** i on **naprawdę się zapala**, raz na obrót –
  w odróżnieniu od kapsuł express z A2, gdzie nie zapalał się nigdy.
- **CRC32 Slamteca to zwykły CRC32** (wielomian `0x04C11DB7`, odwrócony, init
  i final XOR `0xFFFFFFFF`), ale **dane są dopychane zerami do wielokrotności
  4 bajtów, i to zawsze o 1 do 4 bajtów, nigdy o 0**. W Pythonie:
  `zlib.crc32(data + b'\0' * (4 - len(data) % 4))`.
- Komendy z payloadem mają sumę **XOR po wszystkich bajtach żądania**, razem
  z `0xA5` i bajtem długości.
- `GET_LIDAR_CONF` (`0x84`) z polem `0x1CCC0` zwraca adres IP, maskę i bramę
  zapisane w czujniku – stąd diagnostyka wie, pod czym czujnik ma siedzieć.

### Test z linii poleceń

```powershell
# siec, ping, model, tryby, 4 s odbioru
powershell -ExecutionPolicy Bypass -File scripts\test-lidar.ps1

# samo znalezienie czujnika (zapisuje adres dla TouchDesignera)
powershell -ExecutionPolicy Bypass -File scripts\find-lidar.ps1

# konkretny adres, dłuższy pomiar
powershell -ExecutionPolicy Bypass -File scripts\test-lidar.ps1 -Ip 192.168.11.2 -Seconds 10
```

### Własny kod w TouchDesignerze

```python
drv = mod('/project1/s2e/s2e_driver').acquire(ip='auto')
dist = drv.snapshot()          # numpy float32[1024], mm, 0.0 = brak odbicia
print(drv.rpm, drv.mode, drv.info)

logic = mod('/project1/s2e/s2e_logic')
mask = logic.foreground(dist, bg)          # bg z op('/project1/s2e').fetch('background')
for b in logic.blobs(mask, dist):
    print(b['x'], b['y'], b['dist'], b['width'])
```

Sterownik nie korzysta z niczego z TouchDesignera, więc da się go uruchomić
także w zwykłym Pythonie (potrzebne tylko `numpy`):

```python
import sys; sys.path.insert(0, r'...\td\src')
import s2e_driver as D
drv = D.acquire(ip=D.autodetect())
```

### Przebudowa komponentu ze źródeł

Pliki w `td\src\` są **źródłem prawdy**, a `.tox` to ich spakowana kopia. Po zmianie
pliku trzeba go wczytać z powrotem – inaczej TouchDesigner dalej pracuje na starej
wersji i nic tego nie zgłosi:

W **Textporcie** TouchDesignera (Alt+T):

```python
SRC = r'C:\...\rplidar-s2e-windows\td\src'
exec(open(SRC + r'\build_s2e.py', encoding='utf-8').read())
op('/project1/s2e').save(r'C:\...\rplidar-s2e-windows\td\rplidar_s2e.tox')
```

Skrypt musi dostać **jedną** przestrzeń nazw. Jeśli wywołasz go z osobnym
słownikiem lokalnym (`exec(kod, globalne, lokalne)`), funkcje w środku nie
zobaczą `import os` z góry pliku i dostaniesz
`NameError: name 'os' is not defined`.

## Pliki w paczce

| Plik | Do czego |
|---|---|
| `INSTALUJ.bat` | instalacja (UAC tylko przy ustawianiu adresu karty) |
| `sprawdz-lidar.bat` | diagnostyka czujnika bez TouchDesignera |
| `znajdz-lidar.bat` | sama autodetekcja adresu |
| `odinstaluj.bat` | usuwa skróty, zapamiętany adres i dodany adres IP |
| `scripts\s2e.ps1` | protokół S2E po UDP w czystym PowerShellu |
| `scripts\net-setup.ps1` | jedyny krok wymagający administratora |
| `scripts\find-lidar.ps1`, `test-lidar.ps1` | autodetekcja i diagnostyka |
| `td\RPLidarS2E.toe` | gotowy projekt z komponentem i demem |
| `td\rplidar_s2e.tox` | sam komponent – przeciągnij do swojego projektu |
| `td\src\` | źródła wszystkich DAT-ów + `build_s2e.py`, który składa komponent |

## Licencja

MIT – patrz [LICENSE](LICENSE). Opis protokołu na podstawie publicznej dokumentacji
Slamteca i `rplidar_sdk` (BSD-2), patrz [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
