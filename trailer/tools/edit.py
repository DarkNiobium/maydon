"""Assemble the MAYDON trailer.
usage: python3 edit.py <lang uz|ru> [--draft]   (draft = preview clips, 960x540)
"""
import os, sys, subprocess, json
import numpy as np

T = os.path.expanduser("~/maydon/trailer")
MUSIC = os.path.expanduser("~/maydon/game/assets/audio/music/zanelittle_electronic_outlaw.ogg")
FPS, SR = 30, 48000
B = 60 / 135 * 4
END = 50.9
T_END = 46.208

# (shot, start s, game-audio gain dB)
CUTS = [
    ("s01_aerial", 0.0, -5.0),
    ("s02_hero", 4.444, -5.0),
    ("s03_shoulder", 8.889, -3.0),
    ("s04_net", 14.208, -2.0),
    ("s05_celebrate", 15.986, -4.0),
    ("s06_stadium_run", 17.764, -6.0),
    ("s07_slide", 21.319, -5.0),
    ("s08_save", 23.097, -5.0),
    ("s09_volley", 24.875, -5.0),
    ("s10_screamer", 28.431, 0.0),
    ("s11_stadium_party", 31.986, -3.0),
    ("s12_locker", 33.764, None),
    ("s13_lobby", 37.319, None),
    ("s14a_tv", 40.875, -8.0),
    ("s14b_shoulder", 40.875 + B / 2, -8.0),
    ("s14c_arena3", 40.875 + B, -8.0),
    ("s14d_aerial_day", 40.875 + 1.5 * B, -8.0),
    ("s15_final", 44.431, -4.0),
]
# music edit: (src_start, src_end, dst_start)
MUSIC_EDL = [(0.0, 28.431, 0.0), (110.209, 128.0, 28.431), (168.42, 173.3, 46.208)]
FLASHES = [30.208, 46.208]


def fr(t):
    return int(round(t * FPS))


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr[-3000:])
        raise SystemExit("ffmpeg failed")
    return r


def decode(path, ss=0.0, dur=None):
    cmd = ["ffmpeg", "-v", "error", "-ss", str(ss), "-i", path]
    if dur:
        cmd += ["-t", str(dur)]
    cmd += ["-vn", "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).copy()


def fade(x, n_in, n_out):
    if n_in:
        x[:n_in] *= np.linspace(0, 1, n_in)[:, None]
    if n_out:
        x[-n_out:] *= np.linspace(1, 0, n_out)[:, None]
    return x


def build_audio(clip_dir, out_wav):
    n = int(END * SR)
    music = np.zeros((n, 2), np.float32)
    for s0, s1, d0 in MUSIC_EDL:
        seg = decode(MUSIC, s0, s1 - s0)
        seg = fade(seg, int(0.004 * SR), int(0.012 * SR))
        a = int(d0 * SR)
        b = min(n, a + len(seg))
        music[a:b] += seg[: b - a]
    # game audio per cut
    game = np.zeros((n, 2), np.float32)
    for i, (shot, t0, gain) in enumerate(CUTS):
        if gain is None:
            continue
        t1 = CUTS[i + 1][1] if i + 1 < len(CUTS) else T_END
        p = os.path.join(clip_dir, shot + ".mov")
        seg = decode(p, 0.0, t1 - t0 + 0.25)      # small tail, faded under the next cut
        seg = fade(seg, int(0.01 * SR), int(0.2 * SR)) * (10 ** (gain / 20))
        a = int(t0 * SR)
        b = min(n, a + len(seg))
        game[a:b] += seg[: b - a]
    # gentle sidechain-ish ducking of the game layer where the music is loud
    env = np.abs(music).mean(1)
    k = int(0.15 * SR)
    env = np.convolve(env, np.ones(k) / k, "same")
    duck = 1.0 / (1.0 + 2.2 * np.clip(env / 0.12, 0, 2))
    game *= duck[:, None]
    mix = music * 0.9 + game * 1.25
    # fade out the tail
    m = int(0.9 * SR)
    mix[-m:] *= np.linspace(1, 0, m)[:, None]
    raw = os.path.join(T, "build", "mix_raw.wav")
    write_wav(raw, mix)
    # loudness: -14 LUFS integrated, -1 dBTP
    run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", "loudnorm=I=-14:TP=-1.0:LRA=11", "-ar", str(SR), out_wav])


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    import wave
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    lang = sys.argv[1]
    draft = "--draft" in sys.argv
    clip_dir = os.path.join(T, "preview" if draft else "clips")
    W, H = (960, 540) if draft else (1920, 1080)
    os.makedirs(os.path.join(T, "build"), exist_ok=True)
    wav = os.path.join(T, "build", "mix.wav")
    build_audio(clip_dir, wav)
    ov = os.path.join(T, "build", "titles_" + lang)
    endbg = os.path.join(T, "build", "endbg.png")
    inputs, chains, labels = [], [], []
    for i, (shot, t0, _) in enumerate(CUTS):
        t1 = CUTS[i + 1][1] if i + 1 < len(CUTS) else T_END
        nfr = fr(t1) - fr(t0)
        inputs += ["-i", os.path.join(clip_dir, shot + ".mov")]
        chains.append(f"[{i}:v]scale={W}:{H}:flags=lanczos,setsar=1,fps={FPS},tpad=stop_mode=clone:stop_duration=1,"
                      f"trim=end_frame={nfr},setpts=PTS-STARTPTS[v{i}]")
        labels.append(f"[v{i}]")
    nc = len(CUTS)
    end_n = fr(END) - fr(T_END)
    inputs += ["-loop", "1", "-framerate", str(FPS), "-i", endbg]
    chains.append(f"[{nc}:v]scale={W}:{H},setsar=1,trim=end_frame={end_n},setpts=PTS-STARTPTS[vend]")
    labels.append("[vend]")
    chains.append(f"{''.join(labels)}concat=n={len(labels)}:v=1:a=0[cat]")
    # grade + vignette, flashes, fades
    chains.append(f"[cat]eq=contrast=1.05:saturation=1.10:gamma=0.98,vignette=angle=PI/5,"
                  f"fade=t=in:st=0:d=0.7,fade=t=out:st={END - 0.8:.2f}:d=0.8[graded]")
    inputs += ["-framerate", str(FPS), "-i", os.path.join(ov, "f_%05d.png")]
    chains.append(f"[{nc + 1}:v]scale={W}:{H},format=rgba[ttl]")
    chains.append("[graded][ttl]overlay=0:0:shortest=1,format=yuv420p[vout]")
    inputs += ["-i", wav]
    out = os.path.join(T, f"MAYDON_trailer_{lang}{'_draft' if draft else ''}.mp4")
    cmd = ["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", ";".join(chains),
           "-map", "[vout]", "-map", f"{nc + 2}:a", "-t", str(END),
           "-c:v", "libx264", "-preset", "medium" if draft else "slow", "-crf", "23" if draft else "16",
           "-profile:v", "high", "-movflags", "+faststart", "-c:a", "aac", "-b:a", "256k", out]
    run(cmd)
    print("wrote", out)


if __name__ == "__main__":
    main()
