"""Validate assets/chars/custom/base.glb without Blender (plain python3).

    python3 ~/maydon/blender/custom/check_glb.py [path.glb] [--json out.json]

Prints nodes, meshes (material, tris, vertex attributes, morph targets), skin, images; exits 1 on problems.
"""
import json, struct, sys, os

path = next((a for a in sys.argv[1:] if a.endswith(".glb")), os.path.expanduser("~/maydon/game/assets/chars/custom/base.glb"))
data = open(path, "rb").read()
magic, ver, length = struct.unpack("<III", data[:12])
assert magic == 0x46546C67, "not a GLB"
clen, ctype = struct.unpack("<II", data[12:20])
js = json.loads(data[20:20 + clen])
bin_off = 20 + clen + 8
binchunk = data[bin_off:]
problems = []


def acc_count(i):
    return js["accessors"][i]["count"]


def read_acc(i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    comp = {5126: ("f", 4), 5123: ("H", 2), 5121: ("B", 1), 5125: ("I", 4)}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", comp[1] * n)
    out = []
    for k in range(a["count"]):
        o = off + k * stride
        out.append(struct.unpack("<" + comp[0] * n, binchunk[o:o + comp[1] * n]))
    return out


nodes = js["nodes"]
skins = js.get("skins", [])
print("file", path, "%.1f MB" % (len(data) / 1e6))
print("skins", len(skins), "joints", [len(s["joints"]) for s in skins])
if len(skins) != 1 or len(skins[0]["joints"]) != 53:
    problems.append("expected one skin with 53 joints")
print("animations", len(js.get("animations", [])))
mats = [m.get("name") for m in js.get("materials", [])]
print("materials", mats)
report = {}
for ni, n in enumerate(nodes):
    if "mesh" not in n:
        continue
    me = js["meshes"][n["mesh"]]
    names = me.get("extras", {}).get("targetNames", [])
    for p in me["primitives"]:
        tris = acc_count(p["indices"]) // 3
        attrs = sorted(p["attributes"].keys())
        mat = mats[p["material"]] if "material" in p else None
        nt = len(p.get("targets", []))
        print("%-22s mat=%-5s tris=%5d verts=%5d morphs=%2d attrs=%s" % (n["name"], mat, tris, acc_count(p["attributes"]["POSITION"]), nt, ",".join(attrs)))
        report[n["name"]] = dict(material=mat, tris=tris, morphs=names, attrs=attrs)
        if "skin" not in n:
            problems.append(n["name"] + ": not skinned")
        if nt != len(names):
            problems.append(n["name"] + ": target names mismatch")
        if mat == "kit" and "COLOR_0" not in attrs:
            problems.append(n["name"] + ": kit material without COLOR_0")
        if mat in ("skin", "hair", "acc") and "COLOR_0" in attrs:
            problems.append(n["name"] + ": unexpected COLOR_0")
        if "JOINTS_1" in attrs:
            problems.append(n["name"] + ": more than 4 influences")
        if mat == "kit":
            cols = read_acc(p["attributes"]["COLOR_0"])
            uniq = sorted(set(tuple(round(c, 2) for c in col) for col in cols))
            print("    COLOR_0 values:", uniq[:8])
print("images", [(im.get("name"), im.get("mimeType")) for im in js.get("images", [])])
if "--json" in sys.argv:
    json.dump(report, open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=1)
if problems:
    print("PROBLEMS:")
    for p in problems:
        print("  -", p)
    sys.exit(1)
print("OK")
