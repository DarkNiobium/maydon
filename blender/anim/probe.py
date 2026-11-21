import bpy, addon_utils, sys
print("ADDONS", [m for m in bpy.context.preferences.addons.keys() if 'mpfb' in m])
try:
    from bl_ext.user_default.mpfb.services.humanservice import HumanService
    print("IMPORT OK")
except Exception as e:
    print("IMPORT FAIL", e)
