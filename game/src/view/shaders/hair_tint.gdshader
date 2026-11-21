shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// Greyscale hair cards tinted to any colour, alpha-tested (mobile friendly).
// A soft rim keeps short black hair from reading as a plastic helmet.
uniform sampler2D hair_tex : source_color, filter_linear_mipmap;
uniform vec3 hair_col : source_color = vec3(0.1, 0.08, 0.06);

void fragment() {
	vec4 t = texture(hair_tex, UV);
	float l = dot(t.rgb, vec3(0.333));
	vec3 c = hair_col * pow(l, 1.35) * 2.2;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.8);
	ALBEDO = c;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.52;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	BACKLIGHT = ALBEDO * 0.25;
	ROUGHNESS = 0.58;
	SPECULAR = 0.12;
	EMISSION = c * rim * 0.012;
}
