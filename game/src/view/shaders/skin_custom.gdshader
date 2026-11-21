shader_type spatial;
// Customisable skin (assets/chars/custom): tone blends three aligned atlases
// (t 0..2: light → mid → dark), warmth tint, then hair-coloured masks in order
// scalp → beard → brows, iris tint and glossy eyes (all in the same atlas).
uniform sampler2D skin_light : source_color, filter_linear_mipmap;
uniform sampler2D skin_mid : source_color, filter_linear_mipmap;
uniform sampler2D skin_dark : source_color, filter_linear_mipmap;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform float tone : hint_range(0.0, 2.0) = 0.9;
uniform float warmth : hint_range(-1.0, 1.0) = 0.2;
uniform sampler2D scalp_mask : hint_default_black, filter_linear_mipmap;
uniform float scalp_on = 0.0;
uniform vec3 hair_col : source_color = vec3(0.08);
uniform sampler2D beard_mask : hint_default_black, filter_linear_mipmap;
uniform float beard_on = 0.0;
uniform vec3 beard_col : source_color = vec3(0.08);
uniform sampler2D brow_mask : hint_default_black, filter_linear_mipmap;
uniform vec3 brow_col : source_color = vec3(0.08);
uniform sampler2D iris_mask : hint_default_black, filter_linear_mipmap;
uniform vec3 eye_col : source_color = vec3(0.23, 0.14, 0.09);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec3 a = texture(skin_light, UV).rgb;
	vec3 b = texture(skin_mid, UV).rgb;
	vec3 c = texture(skin_dark, UV).rgb;
	vec3 base = mix(a, b, clamp(tone, 0.0, 1.0));
	base = mix(base, c, clamp(tone - 1.0, 0.0, 1.0));
	vec3 cool = vec3(1.02, 0.97, 0.99);
	vec3 warm = vec3(1.04, 1.0, 0.9);
	bool eyes = UV.x > 0.770 && UV.x < 0.885 && UV.y > 0.010 && UV.y < 0.125;
	bool teeth = UV.x > 0.892 && UV.x < 0.980 && UV.y > 0.010 && UV.y < 0.098;
	if (!eyes && !teeth) {
		base *= mix(cool, warm, warmth * 0.5 + 0.5);
	}
	// skin micro variation (keeps the large atlas from looking like a decal)
	float fine = vnoise(UV * vec2(760.0, 760.0));
	base *= 0.985 + 0.03 * fine;
	// scalp stubble: break the painted hairline with a low-frequency jitter and add strands
	float n1 = vnoise(UV * vec2(180.0, 110.0));
	float n2 = vnoise(UV * vec2(820.0, 420.0));
	float jitter = (n1 - 0.5) * 0.12;
	// expand the scalp mask a couple of millimetres so the hair shell never leaves a
	// bright ring of bare forehead between the cards and the painted hairline
	vec2 so = vec2(0.0028, 0.0028);
	float smm = texture(scalp_mask, UV).r;
	smm = max(smm, max(texture(scalp_mask, UV + vec2(so.x, 0.0)).r, texture(scalp_mask, UV - vec2(so.x, 0.0)).r));
	smm = max(smm, max(texture(scalp_mask, UV + vec2(0.0, so.y)).r, texture(scalp_mask, UV - vec2(0.0, so.y)).r));
	float sm = smoothstep(0.32 + jitter, 0.62 + jitter, smm) * scalp_on;
	float s1 = vnoise(UV * vec2(420.0, 90.0));
	float s2 = vnoise(UV * vec2(1400.0, 260.0));
	vec3 hc = hair_col * (0.35 + 1.25 * (0.65 * s1 + 0.35 * s2));
	base = mix(base, hc, clamp(sm, 0.0, 1.0));
	float bm = texture(beard_mask, UV).r * beard_on;
	float bn = 0.50 + 0.95 * (0.55 * n1 + 0.45 * n2);
	base = mix(base, beard_col * bn, clamp(bm * 0.90, 0.0, 1.0));
	float brm = texture(brow_mask, UV).r * (0.72 + 0.50 * vnoise(UV * vec2(1300.0, 70.0)));
	base = mix(base, brow_col, clamp(brm * 0.78, 0.0, 1.0));
	float rough = mix(0.62, 0.82, max(bm, sm));
	if (eyes) {
		float ir = texture(iris_mask, UV).r;
		float lum = dot(base, vec3(0.299, 0.587, 0.114));
		base = mix(base, lum * eye_col * 3.0, ir);
		rough = 0.12;
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = eyes ? 0.50 : 0.28;
	if (!eyes && !teeth) {
		// skin response: real SSS on Forward+ (desktop), cheap red-shifted translucency + soft
		// sheen on the mobile renderer (ears/fingers glow against floodlights, no plastic look)
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		SSS_STRENGTH = 0.32;
		BACKLIGHT = vec3(0.32, 0.09, 0.05) * dot(ALBEDO, vec3(0.6));
		ALBEDO = mix(ALBEDO, ALBEDO * vec3(1.08, 0.98, 0.95), rim * 0.5);

	}
	if (has_normal && !eyes) {
		NORMAL_MAP = texture(skin_normal, UV).rgb;
		NORMAL_MAP_DEPTH = 0.45;
	}
}
