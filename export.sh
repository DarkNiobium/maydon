#!/bin/bash
# Build Android APK/AAB. Usage: export.sh [release|debug|emu|aab]
#  aab: Google Play bundle via Gradle (uses an isolated editor config with JDK 21; first run downloads Gradle)
#  release: arm64, Mobile (Vulkan) renderer, signed with release key → build/MAYDON.apk
#  emu:     x86_64+arm64 debug with GLES3 renderer (Android emulator can't present Vulkan) → build/MAYDON_emu.apk
cd ~/maydon/game
python3 ~/maydon/tools_py/pack_key.py >/dev/null 2>&1 || true
MODE=${1:-release}
KSDIR=~/.local/share/godot/keystores
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$KSDIR/maydon-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=maydon
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$(grep password $KSDIR/maydon-release.txt | cut -d= -f2)
mkdir -p build
if [ "$MODE" = "aab" ]; then
  CFG=$HOME/maydon/.godot_cfg
  mkdir -p $CFG/godot
  cp ~/.config/godot/editor_settings-4.7.tres $CFG/godot/
  sed -i "s|export/android/java_sdk_path = .*|export/android/java_sdk_path = \"$HOME/tools/jdk21/jdk-21.0.13+9\"|" $CFG/godot/editor_settings-4.7.tres
  XDG_CONFIG_HOME=$CFG timeout 1800 godot --headless --path . --install-android-build-template --export-release "Android AAB" build/MAYDON.aab 2>&1 | grep -E "ERROR|DONE" | tail -3
  ls -la build/MAYDON.aab
elif [ "$MODE" = "emu" ]; then
  cp project.godot /tmp/maydon_project.bak; cp export_presets.cfg /tmp/maydon_presets.bak
  sed -i '/renderer\/rendering_method.mobile=/d' project.godot
  sed -i 's/^renderer\/rendering_method="mobile"/renderer\/rendering_method="mobile"\nrenderer\/rendering_method.mobile="gl_compatibility"/' project.godot
  grep -q 'rendering_method.mobile="gl_compatibility"' project.godot || echo "WARN: renderer override not applied"
  sed -i 's/^architectures\/x86_64=false/architectures\/x86_64=true/' export_presets.cfg
  timeout 900 godot --headless --path . --export-debug "Android" build/MAYDON_emu.apk 2>&1 | grep -E "ERROR|DONE" | tail -3
  cp /tmp/maydon_project.bak project.godot; cp /tmp/maydon_presets.bak export_presets.cfg
  ls -la build/MAYDON_emu.apk
elif [ "$MODE" = "debug" ]; then
  timeout 900 godot --headless --path . --export-debug "Android" build/MAYDON_debug.apk 2>&1 | grep -E "ERROR|DONE" | tail -3
  ls -la build/MAYDON_debug.apk
else
  timeout 900 godot --headless --path . --export-release "Android" build/MAYDON.apk 2>&1 | grep -E "ERROR|DONE" | tail -3
  ls -la build/MAYDON.apk
fi
