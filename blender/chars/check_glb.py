#!/usr/bin/env python3
"""Validate MAYDON footballer GLBs: structure, triangle counts, materials, vertex colours, UV2, textures.

    python3 check_glb.py ~/maydon/game/assets/chars/variants/*.glb
"""
import sys, json, struct, io
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    data = open(path, "rb").read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67
    off = 12
    js = None; binc = None
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def accessor(js, binc, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    dt = CT[a["componentType"]]
    n = NC[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride")
    cnt = a["count"]
    item = np.dtype(dt).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(binc, np.uint8, count=stride * cnt, offset=start).reshape(cnt, stride)[:, :item]
        arr = np.frombuffer(raw.tobytes(), dt).reshape(cnt, n)
    else:
        arr = np.frombuffer(binc, dt, count=cnt * n, offset=start).reshape(cnt, n)
    if a.get("normalized"):
        arr = arr.astype(np.float32) / np.iinfo(dt).max
    return arr


def image_size(js, binc, img):
    bv = js["bufferViews"][img["bufferView"]]
    b = binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", b[16:24]); return "png", w, h
    if b[:2] == b"\xff\xd8":
        i = 2
        while i < len(b):
            if b[i] != 0xFF:
                i += 1; continue
            m = b[i + 1]
            if m in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", b[i + 5:i + 9]); return "jpg", w, h
            seg = struct.unpack(">H", b[i + 2:i + 4])[0]
            i += 2 + seg
    return "?", 0, 0


def check(path, verbose=True):
    js, binc = load(path)
    out = {"file": path}
    nodes = js["nodes"]
    out["nodes"] = len(nodes)
    out["skins"] = len(js.get("skins", []))
    out["meshes"] = len(js.get("meshes", []))
    out["animations"] = len(js.get("animations", []))
    out["cameras"] = len(js.get("cameras", [])); out["lights"] = len(js.get("extensions", {}).get("KHR_lights_punctual", {}).get("lights", []))
    out["materials"] = [m["name"] for m in js.get("materials", [])]
    if js.get("skins"):
        sk = js["skins"][0]
        out["joints"] = [nodes[j]["name"] for j in sk["joints"]]
    tris = 0
    prim_info = []
    allpos = []
    for mesh in js["meshes"]:
        for p in mesh["primitives"]:
            idx = accessor(js, binc, p["indices"])
            t = len(idx) // 3
            tris += t
            mat = js["materials"][p["material"]]["name"]
            attrs = sorted(p["attributes"].keys())
            pos = accessor(js, binc, p["attributes"]["POSITION"])
            allpos.append(pos)
            info = dict(material=mat, tris=t, verts=len(pos), attrs=attrs)
            if "COLOR_0" in p["attributes"]:
                c = accessor(js, binc, p["attributes"]["COLOR_0"]).astype(np.float32)
                info["color_type"] = js["accessors"][p["attributes"]["COLOR_0"]]["type"]
                if c.shape[1] == 4:
                    vals = {}
                    for ch, nm in enumerate("RGBA"):
                        u, cnt = np.unique(np.round(c[:, ch], 2), return_counts=True)
                        vals[nm] = {float(k): int(v) for k, v in zip(u, cnt) if v > 0}
                    info["color_values"] = vals
            if "TEXCOORD_1" in p["attributes"]:
                uv2 = accessor(js, binc, p["attributes"]["TEXCOORD_1"]).astype(np.float32)
                info["uv2_range"] = [uv2.min(axis=0).round(3).tolist(), uv2.max(axis=0).round(3).tolist()]
                if "COLOR_0" in p["attributes"]:
                    c = accessor(js, binc, p["attributes"]["COLOR_0"]).astype(np.float32)
                    sh = c[:, 0] > 0.25
                    if sh.any():
                        u = uv2[sh]
                        front = u[:, 0] <= 1.0
                        info["uv2_shirt_front_x"] = [float(u[front, 0].min()), float(u[front, 0].max())] if front.any() else None
                        info["uv2_shirt_back_x"] = [float(u[~front, 0].min()), float(u[~front, 0].max())] if (~front).any() else None
                        info["uv2_shirt_y"] = [float(u[:, 1].min()), float(u[:, 1].max())]
            if "JOINTS_0" in p["attributes"]:
                w = accessor(js, binc, p["attributes"]["WEIGHTS_0"]).astype(np.float32)
                info["weight_sum_minmax"] = [float(w.sum(1).min()), float(w.sum(1).max())]
            prim_info.append(info)
    out["tris"] = tris
    out["primitives"] = prim_info
    P = np.concatenate(allpos)
    out["bbox_min"] = P.min(axis=0).round(3).tolist(); out["bbox_max"] = P.max(axis=0).round(3).tolist()
    out["images"] = [(img.get("name"),) + image_size(js, binc, img) for img in js.get("images", [])]
    return out


if __name__ == "__main__":
    for p in sys.argv[1:]:
        r = check(p)
        print(json.dumps({k: v for k, v in r.items() if k != "joints"}, indent=None, default=str))
        if "-j" in sys.argv:
            print("joints", r.get("joints"))
