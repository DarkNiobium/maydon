"""Audio prep with ffmpeg (no synthesis — real CC0 recordings only).
  cut_audio.py loop <in> <out.ogg> <t0> <t1> [lufs=-26]   seamless loop (2 s crossfade end->start), loudness-normalised
  cut_audio.py shot <in> <out.ogg> <t0> <t1> [peak_db=-2] one-shot: 25 ms fades, high-pass, peak-normalised, mono"""
import subprocess, sys, json, os, tempfile

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(r.stderr[-2000:])
    return r

def loop(src, dst, t0, t1, lufs=-26.0):
    t0, t1, lufs = float(t0), float(t1), float(lufs)
    x = 2.0
    with tempfile.TemporaryDirectory() as td:
        body = os.path.join(td, 'body.wav')
        run(['ffmpeg', '-y', '-v', 'error', '-ss', str(t0), '-to', str(t1), '-i', src, '-ac', '2', '-ar', '32000',
             '-af', f'highpass=f=50,loudnorm=I={lufs}:TP=-3:LRA=11', body])
        d = t1 - t0
        # tail crossfades into the head: out = head(x..d-x) + crossfade(tail, head)
        run(['ffmpeg', '-y', '-v', 'error', '-i', body, '-i', body, '-filter_complex',
             f'[0]atrim=start={x}:end={d - x},asetpts=PTS-STARTPTS[mid];'
             f'[0]atrim=start={d - x}:end={d},asetpts=PTS-STARTPTS[tail];'
             f'[1]atrim=start=0:end={x},asetpts=PTS-STARTPTS[head];'
             f'[tail][head]acrossfade=d={x}:c1=tri:c2=tri[xf];[mid][xf]concat=n=2:v=0:a=1[o]',
             '-map', '[o]', '-c:a', 'libvorbis', '-q:a', '3', dst])
    print('loop', dst)

def shot(src, dst, t0, t1, peak=-2.0):
    t0, t1, peak = float(t0), float(t1), float(peak)
    d = t1 - t0
    r = run(['ffmpeg', '-hide_banner', '-ss', str(t0), '-to', str(t1), '-i', src, '-af', 'highpass=f=90,volumedetect',
             '-f', 'null', '-'])
    mx = 0.0
    for line in r.stderr.splitlines():
        if 'max_volume' in line:
            mx = float(line.split(':')[1].split()[0])
    gain = peak - mx
    run(['ffmpeg', '-y', '-v', 'error', '-ss', str(t0), '-to', str(t1), '-i', src, '-ac', '1', '-ar', '32000', '-af',
         f'highpass=f=90,volume={gain}dB,afade=t=in:d=0.025,afade=t=out:st={max(d - 0.06, 0)}:d=0.06',
         '-c:a', 'libvorbis', '-q:a', '4', dst])
    print('shot', dst, '%+.1f dB' % gain)

if __name__ == '__main__':
    a = sys.argv
    {'loop': lambda: loop(*a[2:]), 'shot': lambda: shot(*a[2:])}[a[1]]()
