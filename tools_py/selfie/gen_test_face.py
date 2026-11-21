#!/usr/bin/env python3
"""Generate a synthetic (fictional) selfie for testing the selfie->character pipeline."""
import json, base64, sys, urllib.request, os
KEY = open(os.path.expanduser("~/maydon/.secrets/gemini_key")).read().strip()
prompt = sys.argv[2] if len(sys.argv) > 2 else "Photorealistic smartphone selfie of a fictional 20-year-old Central Asian man with a short fade haircut and light stubble, neutral background, front facing, daylight."
body = {"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"responseModalities": ["IMAGE"]}}
req = urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent",
    data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "x-goog-api-key": KEY})
r = json.load(urllib.request.urlopen(req, timeout=120))
for p in r["candidates"][0]["content"]["parts"]:
    if "inlineData" in p:
        open(sys.argv[1], "wb").write(base64.b64decode(p["inlineData"]["data"]))
        print("saved", sys.argv[1])
        break
else:
    print(json.dumps(r)[:500])
