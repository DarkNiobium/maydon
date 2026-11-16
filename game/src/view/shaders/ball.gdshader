shader_type spatial;
// Match ball: white panels with coloured pentagon-style patches and seams,
// computed from the surface direction (no texture needed).

uniform vec3 base_col : source_color = vec3(0.97, 0.97, 0.96);
uniform vec3 patch_col : source_color = vec3(0.05, 0.25, 0.75);
uniform vec3 patch2_col : source_color = vec3(0.95, 0.75, 0.1);

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

const vec3 ICO[12] = vec3[](
	vec3(0.0, 0.5257, 0.8507), vec3(0.0, 0.5257, -0.8507), vec3(0.0, -0.5257, 0.8507), vec3(0.0, -0.5257, -0.8507),
	vec3(0.5257, 0.8507, 0.0), vec3(-0.5257, 0.8507, 0.0), vec3(0.5257, -0.8507, 0.0), vec3(-0.5257, -0.8507, 0.0),
	vec3(0.8507, 0.0, 0.5257), vec3(-0.8507, 0.0, 0.5257), vec3(0.8507, 0.0, -0.5257), vec3(-0.8507, 0.0, -0.5257)
);

void fragment() {
	vec3 n = normalize(lpos);
	float best = -1.0;
	float second = -1.0;
	int bi = 0;
	for (int i = 0; i < 12; i++) {
		float d = dot(n, ICO[i]);
		if (d > best) {
			second = best;
			best = d;
			bi = i;
		} else if (d > second) {
			second = d;
		}
	}
	vec3 c = base_col;
	float patch_m = smoothstep(0.885, 0.9, best);
	vec3 pc = (bi % 3 == 0) ? patch2_col : patch_col;
	c = mix(c, pc, patch_m);
	// swoosh band between patches
	float band = smoothstep(0.02, 0.0, abs(best - second) - 0.012);
	c = mix(c, vec3(0.55), band * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.42;
	SPECULAR = 0.5;
	CLEARCOAT = 0.4;
}
