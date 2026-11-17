# Parameter Execute DAT 'pars': reakcje na parametry komponentu.
#
# Zwykly Execute DAT nie dostaje onPulse ani onValueChange - dlatego to osobny
# operator. Jego parametr "OP" wskazuje na komponent s2e.


def onPulse(par):
    comp = par.owner
    drvmod = mod(comp.op('s2e_driver'))

    if par.name == 'Restart':
        try:
            drvmod.acquire(ip=comp.par.Ip.eval(), mode=comp.par.Mode.eval(),
                           restart=True)
            comp.store('error', '')
        except Exception as e:
            comp.store('error', str(e))

    elif par.name == 'Autodetect':
        drvmod.release()
        found = drvmod.autodetect()
        if found:
            comp.par.Ip = found
            comp.store('error', '')
        else:
            comp.store('error',
                       'szukanie: zaden z adresow %s nie odpowiedzial jak S2E'
                       % ', '.join(drvmod.candidates()))

    elif par.name == 'Learnbg':
        mod(comp.op('s2e_objects')).learn_start(comp)

    elif par.name == 'Clearbg':
        mod(comp.op('s2e_objects')).clear_background(comp)
    return


def onValueChange(par, prev):
    comp = par.owner
    drvmod = mod(comp.op('s2e_driver'))

    # Adresu i trybu skanu nie da sie przestawic w locie - jedno i drugie
    # wymaga nowego polaczenia. Zwalniamy, a 'scan' podniesie sterownik przy
    # nastepnym gotowaniu.
    if par.name in ('Ip', 'Mode'):
        drvmod.release()
    elif par.name == 'Active' and not par.eval():
        drvmod.release()
    return
