"""Inspect anims.glb: animations, channels per animation, sampled durations, skin joints."""
import json, struct, sys, os
path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/maydon/game/assets/chars/anims.glb')
with open(path, 'rb') as f:
    data = f.read()
magic, ver, length = struct.unpack('<III', data[:12])
clen, ctype = struct.unpack('<II', data[12:20])
g = json.loads(data[20:20 + clen])
nodes = g['nodes']
print('nodes', len(nodes), 'meshes', len(g.get('meshes', [])), 'skins', len(g.get('skins', [])))
sk = g['skins'][0]
print('skin joints', len(sk['joints']), [nodes[j]['name'] for j in sk['joints']][:60])
acc = g['accessors']
for a in g['animations']:
    tgt = {}
    tmax = 0
    for ch in a['channels']:
        n = nodes[ch['target']['node']]['name']
        tgt.setdefault(n, set()).add(ch['target']['path'])
        s = a['samplers'][ch['sampler']]
        tmax = max(tmax, acc[s['input']]['max'][0])
        cnt = acc[s['input']]['count']
    rot = sum(1 for v in tgt.values() if 'rotation' in v)
    print('%-14s channels %3d  bones_with_rot %2d  keys %3d  len %.3fs  pelvis %s' % (a['name'], len(a['channels']), rot, cnt, tmax, sorted(tgt.get('pelvis', []))))
