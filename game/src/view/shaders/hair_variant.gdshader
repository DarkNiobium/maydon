shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// Variant hair: baked (tinted) card atlas + a soft rim so black hair reads as hair, not a cap.
uniform sampler2D hair_tex : source_color, filter_linear_mipmap;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.50;
uniform float roughness_hair : hint_range(0.0, 1.0) = 0.43;

void fragment() {
	vec4 t = texture(hair_tex, UV);
	vec3 c = t.rgb;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.8);
	ALBEDO = c * 1.10;
	ROUGHNESS = 0.56;
	SPECULAR = 0.15;
	EMISSION = c * rim * 0.012;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	BACKLIGHT = ALBEDO * 0.25;
}
