#!/usr/bin/env python3
"""MAYDON customizable footballer - full, resumable build.

    python3 ~/maydon/blender/custom/build.py            # run only the stages whose outputs are missing/stale
    python3 ~/maydon/blender/custom/build.py --force    # rebuild everything
    python3 ~/maydon/blender/custom/build.py --from=build   # force this stage and everything after it

Stages (Blender runs headless under `nice`; logs in work/logs/):
  deltas  stage_deltas.py  -> work/deltas.npz                    (morph deltas on the MPFB basemesh)
  tex     stage_tex.py     -> skin_*.jpg, masks, kit.png ...     (assets/chars/custom/)
  build   stage_build.py   -> base.glb, hair_*.png, acc.png
  check   check_glb.py     -> validation (plain python)
  preview preview.py       -> preview.png
  docs    make_docs.py     -> custom.json (README.md is hand-written)
A stage is skipped when all its outputs exist and are newer than its inputs (scripts + upstream outputs).
Every stage writes its outputs atomically, so an interrupted run can simply be restarted.
"""
import os, sys, subprocess, time, glob

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser("~/maydon/game/assets/chars/custom")
W = os.path.join(HERE, "work")
LOGS = os.path.join(W, "logs")
os.makedirs(LOGS, exist_ok=True)
BLENDER = os.environ.get("BLENDER", "blender")


def p(*a):
    return os.path.join(*a)


LIB = [p(HERE, f) for f in ("clib.py", "morphs.py", "catalog.py")] + [os.path.expanduser("~/maydon/blender/chars/mlib.py")]
STAGES = [
    ("deltas", ["blender", "stage_deltas.py"], LIB + [p(HERE, "stage_deltas.py")], [p(W, "deltas.npz")]),
    ("tex", ["blender", "stage_tex.py"], LIB + [p(HERE, "stage_tex.py")],
     [p(OUT, "skin_mid.jpg"), p(OUT, "beard_full.png"), p(OUT, "brows_thick.png"), p(OUT, "kit.png"), p(W, "tex_info.json")]),
    ("build", ["blender", "stage_build.py"], LIB + [p(HERE, f) for f in ("stage_build.py", "hairstyles.py", "ckit.py")] +
     [p(W, "deltas.npz"), p(OUT, "skin_mid.jpg"), p(OUT, "kit.png"), p(W, "tex_info.json")],
     [p(OUT, "base.glb"), p(W, "build_stats.json")]),
    ("check", ["python", "check_glb.py"], [p(HERE, "check_glb.py"), p(OUT, "base.glb")], [p(W, "check.ok")]),
    ("preview", ["blender", "preview.py"], [p(HERE, "preview.py"), p(HERE, "catalog.py"), p(OUT, "base.glb")], [p(OUT, "preview.png")]),
    ("docs", ["python", "make_docs.py"], [p(HERE, "make_docs.py"), p(HERE, "catalog.py"), p(HERE, "hairstyles.py"), p(HERE, "morphs.py"),
                                          p(W, "build_stats.json")], [p(OUT, "custom.json")]),
]


def stale(inputs, outputs):
    if not all(os.path.exists(o) for o in outputs):
        return True
    newest_in = max(os.path.getmtime(i) for i in inputs if os.path.exists(i))
    return min(os.path.getmtime(o) for o in outputs) < newest_in


def run_stage(name, cmd, outputs):
    log = p(LOGS, name + ".log")
    kind, script = cmd
    if kind == "blender":
        args = ["nice", BLENDER, "-b", "-noaudio", "--python", p(HERE, script)]
    else:
        args = [sys.executable, p(HERE, script)]
    t0 = time.time()
    print("[build] %-8s ..." % name, flush=True)
    with open(log, "w") as f:
        r = subprocess.run(args, stdout=f, stderr=subprocess.STDOUT, cwd=HERE)
    txt = open(log).read()
    ok = all(os.path.exists(o) for o in outputs) and "Traceback (most recent call last):\n  File \"" + HERE not in txt
    if kind == "python":
        ok = ok or (r.returncode == 0)
        if name == "check":
            ok = r.returncode == 0
            if ok:
                open(p(W, "check.ok"), "w").write(time.ctime())
    if not ok:
        print("[build] %s FAILED (see %s)" % (name, log))
        print("\n".join(txt.splitlines()[-25:]))
        sys.exit(1)
    print("[build] %-8s done in %.0fs" % (name, time.time() - t0), flush=True)


def main():
    argv = sys.argv[1:]
    force = "--force" in argv
    frm = next((a.split("=", 1)[1] for a in argv if a.startswith("--from=")), None)
    forcing = force
    for name, cmd, inputs, outputs in STAGES:
        if frm == name:
            forcing = True
        if forcing or stale(inputs, outputs):
            if forcing:
                for o in outputs:
                    if o.endswith(("deltas.npz", "check.ok")) and os.path.exists(o):
                        os.remove(o)
            if forcing:
                os.environ["MAYDON_FORCE"] = "1"      # stage scripts ignore their own caches
            run_stage(name, cmd, outputs)
        else:
            print("[build] %-8s up to date" % name)
    print("[build] all done ->", OUT)


if __name__ == "__main__":
    main()
