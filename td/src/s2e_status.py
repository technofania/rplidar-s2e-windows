# Script DAT 'status': stan czujnika po polsku, zeby nie trzeba bylo czytac
# kodu ani Textportu, gdy cos nie dziala.
#
# To pierwsze miejsce, do ktorego zagladamy, gdy "nic nie widac".


def onCook(dat):
    comp = dat.parent()
    drvmod = mod(comp.op('s2e_driver'))
    drv = drvmod.peek()
    lines = []

    if not comp.par.Active.eval():
        lines.append('WYLACZONY - zaznacz parametr Active na komponencie.')
    elif drv is None:
        err = comp.fetch('error', '')
        lines.append('BRAK POLACZENIA' + (': ' + err if err else ''))
        lines.append('adresy tego komputera: ' +
                     (', '.join(drvmod._local_subnets()) or 'zadnego'))
        lines.append('sprawdzane adresy czujnika: ' +
                     ', '.join(drvmod.candidates()))
        lines.append('')
        lines.append('Po kolei:')
        lines.append(' 1. czujnik ma zasilacz i kabel LAN wpiety w komputer?')
        lines.append(' 2. karta sieciowa ma adres 192.168.11.5 (maska 255.255.255.0)?')
        lines.append('    Jesli nie - uruchom INSTALUJ.bat z folderu paczki.')
        lines.append(' 3. uruchom sprawdz-lidar.bat - pokaze, gdzie sie zatrzymuje')
        lines.append(' 4. Adres = auto albo wpisz recznie 192.168.11.2, potem Restart')
    else:
        head = 'DZIALA' if drv.mode != '-' else 'LACZY SIE'
        lines.append('%s  adres %s  tryb %s' % (head, drv.ip, drv.mode))
        lines.append('stan sterownika: %s' % drv.status)
        lines.append('obroty: %.0f rpm   obrotow: %d   probek: %d   bledow: %d'
                     % (drv.rpm, drv.rev, drv.samples, drv.errors))
        if drv.info:
            lines.append('czujnik: %s, firmware %s, hardware %s'
                         % (drv.info.get('name', '?'),
                            drv.info.get('firmware', '?'),
                            drv.info.get('hardware', '?')))
        if drv.health is not None:
            st = {0: 'OK', 1: 'OSTRZEZENIE', 2: 'BLAD'}.get(drv.health[0], '?')
            lines.append('zdrowie czujnika: %s (kod %d)' % (st, drv.health[1]))
        err = comp.fetch('error', '')
        if err:
            lines.append('ostatni blad: %s' % err)

    bg = comp.fetch('background', None)
    learning = comp.fetch('learn_until', 0.0) > 0.0
    lines.append('')
    if learning:
        lines.append('TLO: ucze sie... wyjdz z kadru!')
    elif bg is None:
        lines.append('TLO: nie nauczone - wszystko w zasiegu jest "obiektem".')
        lines.append('     Wyjdz z kadru i pulsnij "Naucz tlo".')
    else:
        lines.append('TLO: nauczone (%d kubelkow ze sciana)'
                     % int((bg > 0).sum()))

    dat.text = '\n'.join(lines)
    return
