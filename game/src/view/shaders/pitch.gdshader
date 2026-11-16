shader_type spatial;
render_mode cull_back;
// Football pitch: mowed natural grass or artificial turf with analytic,
// anti-aliased line markings (crisp at any distance, no big textures).

uniform float hl = 52.5;
uniform float hw = 34.0;
uniform float line_w = 0.12;
uniform float box_d = 16.5;
uniform float box_w = 40.32;
uniform float six_d = 5.5;
uniform float six_w = 18.32;
uniform float circle_r = 9.15;
uniform float pen_spot = 11.0;
uniform float arc_r = 9.15;
uniform float stripes = 18.0;
uniform bool turf = false;
uniform vec3 grass_a : source_color = vec3(0.16, 0.36, 0.11);
uniform vec3 grass_b : source_color = vec3(0.12, 0.30, 0.09);
uniform vec3 surround : source_color = vec3(0.13, 0.30, 0.10);
uniform vec3 line_col : source_color = vec3(0.92, 0.94, 0.92);
uniform sampler2D detail_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_detail = false;
uniform float detail_scale = 0.45;
uniform float wear = 0.5;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float lmask(float d, float w) {
	float fw = max(fwidth(d), 0.0005);
	return 1.0 - smoothstep(w * 0.5 - fw, w * 0.5 + fw, abs(d));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 a = abs(p);
	float L = 0.0;
	L = max(L, lmask(sd_box(p, vec2(hl, hw)), line_w));
	L = max(L, lmask(p.x, line_w) * step(a.y, hw));
	L = max(L, lmask(length(p) - circle_r, line_w));
	L = max(L, 1.0 - smoothstep(0.11, 0.14, length(p)));
	vec2 q = vec2(a.x - (hl - box_d * 0.5), p.y);
	L = max(L, lmask(sd_box(q, vec2(box_d * 0.5, box_w * 0.5)), line_w));
	vec2 q6 = vec2(a.x - (hl - six_d * 0.5), p.y);
	L = max(L, lmask(sd_box(q6, vec2(six_d * 0.5, six_w * 0.5)), line_w));
	vec2 ps = vec2(a.x - (hl - pen_spot), p.y);
	L = max(L, 1.0 - smoothstep(0.1, 0.13, length(ps)));
	L = max(L, lmask(length(ps) - arc_r, line_w) * step(a.x, hl - box_d));
	L = max(L, lmask(length(a - vec2(hl, hw)) - 1.0, line_w) * step(a.x, hl) * step(a.y, hw));
	float inside = step(a.x, hl + line_w) * step(a.y, hw + line_w);
	L *= inside;

	// grass
	float band = (p.x + hl) / (2.0 * hl / stripes);
	float stripe = mod(floor(band), 2.0);
	vec3 viewv = normalize(CAMERA_POSITION_WORLD - wpos);
	float sheen = 1.0 + (stripe * 2.0 - 1.0) * 0.06 * sign(viewv.x + 0.0001);
	vec3 g = mix(grass_a, grass_b, stripe) * sheen;
	float n1 = vnoise(p * 0.08);
	float n2 = vnoise(p * 0.6 + 13.0);
	g *= 0.86 + 0.22 * n1 + 0.06 * n2;
	if (turf) {
		g *= 0.95 + 0.05 * sin(p.y * 6.2832 * 2.0);
	}
	vec3 nrm = vec3(0.0, 0.0, 1.0);
	if (has_detail) {
		vec3 dt = texture(detail_tex, p * detail_scale).rgb;
		float lum = dot(dt, vec3(0.299, 0.587, 0.114));
		g *= mix(vec3(1.0), dt / max(lum, 0.05), 0.35) * (0.55 + lum * 0.9);
		vec3 dt2 = texture(macro_tex, p * 0.031).rgb;
		g *= 0.8 + 0.4 * dot(dt2, vec3(0.333));
		NORMAL_MAP = texture(detail_nrm, p * detail_scale).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}
	// worn goalmouths and centre
	if (!turf) {
		float w1 = exp(-pow(length(vec2(a.x - (hl - 4.0), p.y * 0.55)) / 4.0, 2.0));
		float w2 = exp(-pow(length(p) / 3.0, 2.0)) * 0.5;
		float wm = clamp((w1 + w2) * wear * (0.6 + 0.6 * n2), 0.0, 1.0);
		g = mix(g, vec3(0.30, 0.26, 0.15) * (0.8 + 0.3 * n2), wm * 0.55);
	}
	float outside = 1.0 - step(a.x, hl + 0.6) * step(a.y, hw + 0.6);
	g = mix(g, surround * (0.85 + 0.25 * n1), outside * (turf ? 0.0 : 0.6));
	ALBEDO = mix(g, line_col, L);
	ROUGHNESS = mix(0.82, 0.7, L);
	SPECULAR = 0.35;
}
