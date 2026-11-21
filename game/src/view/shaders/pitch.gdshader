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
uniform vec3 grass_a : source_color = vec3(0.19, 0.36, 0.10);
uniform vec3 grass_b : source_color = vec3(0.15, 0.30, 0.08);
uniform vec3 surround : source_color = vec3(0.13, 0.30, 0.10);
uniform vec3 line_col : source_color = vec3(0.86, 0.88, 0.85);
uniform sampler2D detail_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_detail = false;
uniform float detail_scale = 0.45;
uniform float wear = 0.5;
uniform bool cross_mow = false;

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

	// ---- grass ------------------------------------------------------------
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float ndv = clamp(V.y, 0.0, 1.0);
	float band = (p.x + hl) / (2.0 * hl / stripes);
	float stripe = mod(floor(band), 2.0);
	float sgn = stripe * 2.0 - 1.0;
	// blades lean along the mower's direction: looking with the lean shows the light blade
	// sides, looking against it shows the darker tips/soil -> stripes swap as the camera turns
	vec2 vh = normalize(V.xz + vec2(1e-4));
	float lean = sgn * vh.x;
	float graze = 1.0 - ndv;
	float mow = 1.0 + lean * (0.07 + 0.16 * graze);
	if (cross_mow) {
		float band2 = (p.y + hw) / (2.0 * hw / (stripes * 0.5));
		float sgn2 = mod(floor(band2), 2.0) * 2.0 - 1.0;
		mow *= 1.0 + sgn2 * vh.y * (0.025 + 0.06 * graze);
	}
	float n1 = vnoise(p * 0.07);
	float n2 = vnoise(p * 0.55 + 13.0);
	float n3 = vnoise(p * 2.3 + 71.0);
	vec3 g = mix(grass_a, grass_b, stripe);
	// patchy yellow/blue-green variation like real turfgrass
	g = mix(g, g * vec3(1.18, 1.08, 0.72), smoothstep(0.55, 0.95, n1) * 0.55);
	g = mix(g, g * vec3(0.85, 1.0, 1.05), smoothstep(0.6, 0.1, n1) * 0.35);
	g *= 0.9 + 0.14 * n2 + 0.05 * n3;
	g *= mow;
	if (turf) {
		// roll seams every 4 m + black rubber infill speckle
		g *= 0.95 + 0.05 * sin(p.y * 6.2832 * 0.25);
		g *= 1.0 - 0.25 * step(0.82, hash(floor(p * 40.0))) * (1.0 - smoothstep(6.0, 20.0, length(CAMERA_POSITION_WORLD - wpos)));
	}
	vec3 nrm_s = vec3(0.5, 0.5, 1.0);
	float fine = 1.0 - smoothstep(18.0, 60.0, dist);   // fine detail fades out -> no moire
	if (has_detail) {
		vec3 dt = texture(detail_tex, p * detail_scale).rgb;
		vec3 dtb = texture(detail_tex, p * detail_scale * 0.27 + vec2(0.37, 0.71)).rgb;
		dt = mix(dt, dtb, 0.35);
		float lum = dot(dt, vec3(0.299, 0.587, 0.114));
		vec3 dmod = mix(vec3(1.0), dt / max(lum, 0.05), turf ? 0.06 : 0.25) * (0.6 + lum * (turf ? 1.6 : 0.8));
		g *= mix(vec3(1.0), dmod, 0.35 + 0.65 * fine);
		vec3 dt2 = texture(macro_tex, p * 0.031).rgb;
		g *= 0.82 + 0.36 * dot(dt2, vec3(0.333));
		nrm_s = mix(vec3(0.5, 0.5, 1.0), texture(detail_nrm, p * detail_scale).rgb, fine);
	}
	// worn goalmouths, centre spot, linesman channels along the touchlines
	float wm = 0.0;
	if (!turf) {
		float w1 = exp(-pow(length(vec2(a.x - (hl - 4.5), p.y * 0.5)) / 4.2, 2.0));
		float w2 = exp(-pow(length(p) / 3.2, 2.0)) * 0.5;
		float w3 = exp(-pow((a.y - hw + 1.5) / 1.2, 2.0)) * 0.25 * step(a.x, hl * 0.5);
		float wn = 0.45 + 0.75 * n2 * (0.6 + 0.4 * n3);
		wm = clamp((w1 + w2 + w3) * wear * wn, 0.0, 1.0);
		wm = smoothstep(0.08, 0.9, wm);
		vec3 soil = vec3(0.30, 0.24, 0.15) * (0.75 + 0.35 * n3);
		vec3 dry = g * vec3(1.25, 1.1, 0.6);
		g = mix(g, dry, smoothstep(0.0, 0.4, wm) * 0.6);
		g = mix(g, soil, smoothstep(0.35, 1.0, wm) * 0.75);
	}
	// sheen of blade sides at grazing angles (sky reflected off the leaves)
	float fuzz = pow(graze, 4.0);
	g = mix(g, g * vec3(1.15, 1.2, 1.05) + vec3(0.02, 0.025, 0.015), fuzz * 0.5);
	float outside = 1.0 - step(a.x, hl + 0.6) * step(a.y, hw + 0.6);
	g = mix(g, surround * (0.85 + 0.25 * n1), outside * (turf ? 0.0 : 0.6));
	// painted lines: chalk over grass, blades still show through, slightly broken edges
	float paint = L * (0.82 + 0.18 * n3) * (1.0 - wm * 0.35);
	vec3 lc = line_col * (0.88 + 0.12 * dot(g, vec3(2.0)));
	ALBEDO = mix(g, lc, paint);
	ROUGHNESS = mix(0.86 - fuzz * 0.12, 0.78, paint);
	SPECULAR = mix(0.28, 0.4, paint);
	NORMAL_MAP = mix(nrm_s, vec3(0.5, 0.5, 1.0), paint * 0.6);
	NORMAL_MAP_DEPTH = 0.75;
}
