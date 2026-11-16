shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, blend_mix;
// Goal net / fence: procedural mesh cells with alpha. `size` = quad size in metres.

uniform vec3 col : source_color = vec3(0.95, 0.95, 0.95);
uniform vec2 size = vec2(1.0, 1.0);
uniform float cell = 0.12;
uniform float thick = 0.1;
uniform float opacity = 0.9;
uniform bool diamond = false;
uniform float rough = 0.6;
uniform float metal = 0.0;

void fragment() {
	vec2 p = UV * size / cell;
	if (diamond) {
		p = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	}
	vec2 f = abs(fract(p) - 0.5);
	float w = thick * 0.5;
	vec2 fw = max(fwidth(p), vec2(0.0001));
	vec2 m2 = smoothstep(vec2(0.5 - w) - fw, vec2(0.5 - w) + fw, f);
	float m = max(m2.x, m2.y);
	// fade the pattern into a soft haze far away to avoid moiré
	float far = clamp(max(fw.x, fw.y) * 2.0 - 0.3, 0.0, 1.0);
	m = mix(m, thick * 1.6, far);
	ALBEDO = col;
	ALPHA = clamp(m * opacity, 0.0, 1.0);
	ROUGHNESS = rough;
	METALLIC = metal;
}
