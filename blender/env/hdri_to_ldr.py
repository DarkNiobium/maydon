"""Convert HDR panoramas to tonemapped LDR JPGs for Godot PanoramaSkyMaterial (mobile-friendly)."""
import bpy, os, sys
args = sys.argv[sys.argv.index("--") + 1:]
src, dst, w, exposure = args[0], args[1], int(args[2]), float(args[3])
img = bpy.data.images.load(src)
img.scale(w, w // 2)
sc = bpy.context.scene
sc.view_settings.view_transform = "AgX"
sc.view_settings.exposure = exposure
sc.render.image_settings.file_format = "JPEG"
sc.render.image_settings.quality = 88
img.save_render(dst, scene=sc)
print("saved", dst)
