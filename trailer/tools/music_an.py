import sys, subprocess, numpy as np
SR = 11025
def load(path):
    raw = subprocess.run(["ffmpeg","-v","quiet","-i",path,"-ac","1","-ar",str(SR),"-f","s16le","-"],capture_output=True).stdout
    return np.frombuffer(raw, np.int16).astype(np.float32)/32768
for path in sys.argv[1:]:
    x = load(path)
    hop = 256
    n = len(x)//hop
    fr = x[:n*hop].reshape(n, hop)
    rms = np.sqrt((fr**2).mean(1)+1e-12)
    # spectral flux onset envelope
    win = 1024
    frames = np.lib.stride_tricks.sliding_window_view(np.pad(x,(0,win)), win)[::hop][:n]
    spec = np.abs(np.fft.rfft(frames*np.hanning(win), axis=1))
    lo = spec[:, :int(150/(SR/win))].sum(1)  # bass/kick band
    flux = np.maximum(np.diff(np.log1p(spec), axis=0), 0).sum(1)
    flux = np.concatenate([[0], flux]); flux -= np.convolve(flux, np.ones(32)/32, 'same'); flux = np.maximum(flux, 0)
    fps = SR/hop
    # tempo via autocorrelation over 60-180 bpm
    ac = np.correlate(flux[:int(fps*90)], flux[:int(fps*90)], 'full')[int(fps*90)-1:]
    lags = np.arange(len(ac))/fps
    m = (lags > 60/180) & (lags < 60/60)
    best = lags[m][np.argmax(ac[m])]
    bpm = 60/best
    # beat phase: best offset
    period = best*fps
    scores = [flux[np.round(o + np.arange(0, (n-1-o)/period)*period).astype(int)].sum() for o in np.arange(0, period, 0.5)]
    off = np.arange(0, period, 0.5)[int(np.argmax(scores))]/fps
    dur = len(x)/SR
    print(f"== {path.split('/')[-1]} dur={dur:.1f}s bpm={bpm:.1f} first_beat={off:.3f}s bar={4*60/bpm:.3f}s")
    # loudness per 2 s window (dB) + bass energy
    seg = int(2*fps)
    line = []
    for i in range(0, n, seg):
        r = 20*np.log10(rms[i:i+seg].mean()+1e-9); b = 20*np.log10(lo[i:i+seg].mean()+1e-9)
        line.append(f"{i/fps:5.0f}s {r:6.1f}dB bass{b:6.1f}")
    for k in range(0, len(line), 4):
        print("   " + " | ".join(line[k:k+4]))
