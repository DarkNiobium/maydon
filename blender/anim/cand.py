"""Quick candidate previews: python3 cand.py name=rel:t0:t1 ..."""
import sys, process as P
for a in sys.argv[1:]:
    name, spec = a.split('=')
    rel, t0, t1 = spec.split(':')
    try:
        P.process_oneshot('cand_' + name, rel, (float(t0), float(t1)), align='start', inplace=False)
    except Exception as e:
        print('ERR', name, e)
