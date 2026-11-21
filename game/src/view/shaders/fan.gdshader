shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// One spectator per MultiMesh instance: a Y-axis billboard drawn either from a
// rendered sprite atlas or, as a fallback, from SDF shapes. Instance custom
// data: rgb = shirt colour, a = random seed. Cheers/jumps with `excite`.

uniform float excite = 0.0;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform bool use_atlas = false;
uniform vec2 atlas_grid = vec2(8.0, 2.0);   // columns = variants, rows = idle/cheer

varying vec4 cust;
varying float cheer;
varying float wy;
uniform float roof_h = 0.0;   // >0: stand is roofed from this height up (shade upper rows)

float h1(float x) {
	return fract(sin(x * 91.7) * 43758.5453);
}

void vertex() {
	cust = INSTANCE_CUSTOM;
	wy = MODEL_MATRIX[3].y;
	float seed = cust.a;
	float t = TIME * (1.3 + seed * 1.7) + seed * 60.0;
	cheer = step(0.55, excite * (0.6 + 0.4 * sin(t * 0.9)));
	float jump = excite * max(0.0, sin(t * 2.6)) * 0.22 * step(0.3, h1(seed + 3.0));
	VERTEX.y += jump + sin(t * 0.8) * 0.01;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float sd_box(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	float seed = cust.a;
	vec3 shirt = cust.rgb;
	vec3 skin = mix(vec3(0.78, 0.6, 0.46), vec3(0.34, 0.23, 0.16), h1(seed + 1.0));
	if (use_atlas) {
		float col = floor(h1(seed + 7.0) * atlas_grid.x);
		float row = cheer;
		vec2 uv = (vec2(col, row) + UV) / atlas_grid;
		vec4 s = texture(atlas, uv);
		// recolour the shirt (torso band, non-skin pixels) with the instance colour so the 8
		// rendered variants don't repeat visibly across a full stand
		vec3 base = s.rgb;
		float lum = dot(base, vec3(0.299, 0.587, 0.114));
		float skin_like = step(base.b * 1.08, base.g) * step(base.g * 1.05, base.r) * step(0.12, base.r - base.b);
		float torso = smoothstep(0.30, 0.36, UV.y) * (1.0 - smoothstep(0.58, 0.64, UV.y));
		if (cheer > 0.5) {
			torso = smoothstep(0.42, 0.47, UV.y) * (1.0 - smoothstep(0.66, 0.72, UV.y));
		}
		float rec = torso * (1.0 - skin_like) * step(0.25, h1(seed + 11.0));
		base = mix(base, shirt * (0.35 + lum * 1.3), rec);
		base *= 0.82 + 0.3 * h1(seed + 5.0);
		if (roof_h > 0.0) {
			base *= mix(1.0, 0.55, smoothstep(roof_h * 0.35, roof_h, wy));
		}
		// distant fans are a few pixels tall: pull them toward a local average so the stands read
		// as a crowd instead of high-frequency noise (no TAA on mobile)
		float far = smoothstep(30.0, 110.0, length(VERTEX));
		float l = dot(base, vec3(0.333));
		base = mix(base, mix(vec3(l), base, 0.55) * 0.9 + shirt * 0.06, far * 0.7);
		ALBEDO = base;
		ALPHA = s.a;
	} else {
		vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);
		float aa = fwidth(p.y) * 1.5;
		float torso = sd_box(p - vec2(0.0, 0.42), vec2(0.27, 0.2), 0.12);
		float legs = sd_box(p - vec2(0.0, 0.14), vec2(0.18, 0.14), 0.05);
		float head = length(p - vec2(0.0, 0.76)) - 0.11;
		float arms_down = min(sd_box(p - vec2(-0.3, 0.42), vec2(0.06, 0.18), 0.05), sd_box(p - vec2(0.3, 0.42), vec2(0.06, 0.18), 0.05));
		float arms_up = min(sd_box(p - vec2(-0.26, 0.78), vec2(0.06, 0.2), 0.05), sd_box(p - vec2(0.26, 0.78), vec2(0.06, 0.2), 0.05));
		float arms = mix(arms_down, arms_up, cheer);
		float body = min(min(torso, head), min(arms, legs));
		float a = 1.0 - smoothstep(-aa, aa, body);
		vec3 c = shirt;
		c = mix(c, vec3(0.12, 0.13, 0.16), 1.0 - smoothstep(-aa, aa, legs));
		c = mix(c, skin, 1.0 - smoothstep(-aa, aa, min(head, mix(1.0, arms, 0.0))));
		c = mix(c, skin, (1.0 - smoothstep(-aa, aa, arms)) * step(0.5, cheer) * step(0.85, p.y));
		c = mix(c, vec3(0.05, 0.04, 0.035), step(0.81, p.y) * (1.0 - smoothstep(-aa, aa, head)));
		// soft vertical shading
		c *= 0.75 + 0.35 * p.y;
		ALBEDO = c;
		ALPHA = a;
	}
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ROUGHNESS = 0.9;
}
