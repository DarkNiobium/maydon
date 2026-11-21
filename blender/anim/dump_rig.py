"""Dump the reference game_engine rig (rest data) to rig.json for the numpy pipeline."""
import bpy, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mlib as M
arm = bpy.data.objects['Human.rig']
rig = M.Rig.from_blender(arm)
out = dict(names=rig.names, parents=rig.parents, head=rig.head.tolist(), tail=rig.tail.tolist(), rest_q=rig.rest_q.tolist())
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rig.json'), 'w'))
print('RIG dumped', len(rig.names))
