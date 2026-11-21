"""Render a CC0 Poly Haven tree from 2 orthographic directions into a 2-cell RGBA atlas (crossed-quad impostor)."""
import bpy, os, math, sys
from mathutils import Vector
SRC = os.path.expanduser("~/maydon/raw/models/polyhaven-jacaranda_tree/jacaranda_tree_1k.gltf")
OUT = os.path.expanduser("~/maydon/game/assets/gen/tree_atlas.png")
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
for o in objs:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
size = mx - mn
center = (mn + mx) * 0.5
print("tree bounds", size)
sc = bpy.context.scene
try:
    sc.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError:
    sc.render.engine = "BLENDER_EEVEE"
sc.render.film_transparent = True
H = 1024
W = int(H * max(size.x, size.y) / size.z)
W = min(W, 1024)
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.view_settings.view_transform = "Standard"
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = size.z * 1.02
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sc.collection.objects.link(sun)
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(30))
if sc.world is None:
    sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
bg = sc.world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.6, 0.65, 0.7, 1)
bg.inputs[1].default_value = 0.8
parts = []
for i, ang in enumerate((0, 90)):
    r = math.radians(ang)
    d = 50.0
    cam.location = (center.x + d * math.sin(r), center.y - d * math.cos(r), center.z)
    cam.rotation_euler = (math.radians(90), 0, r)
    p = OUT.replace(".png", "_%d.png" % i)
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    parts.append(p)
os.system("magick %s +append %s" % (" ".join(parts), OUT))
for p in parts:
    os.remove(p)
print("tree aspect", W / H, "height", size.z)
