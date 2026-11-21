shader_type spatial;
// Shared skin pass for the generated variants: the GLB carries the albedo atlas, the game
// adds one shared pore/wrinkle normal map (saves a normal map per player) and the skin
// roughness/specular that the mobile renderer otherwise gets from stale glTF defaults.
uniform sampler2D base_tex : source_color, filter_linear_mipmap;
uniform sampler2D skin_nrm : hint_normal, filter_linear_mipmap;
uniform float normal_depth : hint_range(0.0, 1.0) = 0.45;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.6;
uniform float specular_base : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec3 c = texture(base_tex, UV).rgb;
	ALBEDO = c;
	ROUGHNESS = roughness_base;
	SPECULAR = specular_base;
	NORMAL_MAP = texture(skin_nrm, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	// skin response: real SSS on Forward+ (desktop), cheap red-shifted translucency + soft
	// sheen on the mobile renderer (ears/fingers glow against floodlights, no plastic look)
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	SSS_STRENGTH = 0.32;
	BACKLIGHT = vec3(0.32, 0.09, 0.05) * dot(ALBEDO, vec3(0.6));
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(1.08, 0.98, 0.95), rim * 0.5);

}
