# review.py out.jpg shot1 shot2 ... : 6 frames per shot from preview/<shot>.mov, one row each
import sys, subprocess, os
from PIL import Image, ImageDraw
out, shots = sys.argv[1], sys.argv[2:]
W, H, N = 320, 180, 6
sheet = Image.new("RGB", (W * N, H * len(shots)), "black")
d = ImageDraw.Draw(sheet)
for r, s in enumerate(shots):
    mov = os.path.expanduser(f"~/maydon/trailer/preview/{s}.mov")
    dur = float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",mov],capture_output=True,text=True).stdout)
    for i in range(N):
        t = dur * (i + 0.5) / N
        png = f"/tmp/claude-1000/rv_{i}.png"
        subprocess.run(["ffmpeg","-v","error","-y","-ss",str(t),"-i",mov,"-frames:v","1","-s",f"{W}x{H}",png])
        sheet.paste(Image.open(png).convert("RGB"), (i * W, r * H))
    d.text((4, r * H + 2), s, fill="yellow")
sheet.save(out, quality=85)
