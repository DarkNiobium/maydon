#!/usr/bin/env python3
"""Write the AI key into the game as XOR-obfuscated bytes (NOT secure: extractable from the APK)."""
import os
SALT = b"MAYDON-7f3k9q-football"
k = open(os.path.expanduser("~/maydon/.secrets/gemini_key"), "rb").read().strip()
out = bytes(b ^ SALT[i % len(SALT)] for i, b in enumerate(k))
open(os.path.expanduser("~/maydon/game/assets/secret/k.bin"), "wb").write(out)
print("packed", len(out), "bytes")
