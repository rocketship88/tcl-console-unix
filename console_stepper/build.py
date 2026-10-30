#!/usr/bin/env python3
"""Build console_stepper.html: embed the TIP 561 sources into template.html.
   python3 build.py [out.html]
Sources (src/): tclIndex.txt, stub.tcl (consolecmd.tcl), impl.tcl (consolecmd.impl), tkout.tcl (Tk console.tcl excerpt)."""
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
blocks = [('tclIndex', 'tclIndex.txt'), ('stub', 'stub.tcl'), ('impl', 'impl.tcl'), ('tkout', 'tkout.tcl')]
out = ''
for bid, fn in blocks:
    t = open(os.path.join(here, 'src', fn), encoding='utf-8', newline='').read().replace('\r\n', '\n')
    if '</script' in t.lower():
        sys.exit(fn + ' contains "</script"; cannot embed it')
    out += '<script type="text/plain" id="src-%s">\n%s</script>\n' % (bid, t)
tpl = open(os.path.join(here, 'template.html'), encoding='utf-8').read()
assert tpl.count('/*@@SRC@@*/') == 1
dest = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, 'console_stepper.html')
open(dest, 'w', encoding='utf-8').write(tpl.replace('/*@@SRC@@*/', out))
print('wrote', dest, os.path.getsize(dest), 'bytes')
