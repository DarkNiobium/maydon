shader_type spatial;
// Crowd on stand terraces: per-seat spectators drawn with anti-aliased SDF
// shapes (shoulders, torso, head, arms when cheering). Fades to an averaged
// colour at distance to avoid shimmering. `excite` makes them jump and wave.
uniform vec2 size = vec2(100.0, 20.0);
uniform float rows = 30.0;
uniform float seat_w = 0.55;
uniform float fill = 0.85;
uniform float excite = 0.0;
uniform vec3 seat_col : source_color = vec3(0.55, 0.06, 0.08);
uniform vec3 home_col : source_color = vec3(0.9, 0.1, 0.1);
uniform vec3 away_col : source_color = vec3(0.1, 0.2, 0.8);
uniform float night = 1.0;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float sd_box(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	vec2 m = UV * size;
	vec2 g = vec2(m.x / seat_w, (1.0 - UV.y) * rows);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float r = h(cell);
	float occupied = step(r, fill);
	vec2 fw = fwidth(g);
	float far = clamp(max(fw.x, fw.y) * 1.5 - 0.35, 0.0, 1.0);
	// concrete step + seat
	vec3 c = mix(vec3(0.13, 0.13, 0.14), seat_col * 0.7, step(0.35, f.y) * step(f.y, 0.75) * step(0.12, f.x) * step(f.x, 0.88));
	c *= 0.8 + 0.2 * f.y;
	// person (cell space: x 0..1, y 0..1 bottom->top; people stand taller than a row)
	float t = TIME * (1.4 + r * 2.0) + r * 40.0;
	float jump = excite * max(0.0, sin(t * 2.6)) * 0.22;
	float sway = sin(t * 0.7) * 0.04;
	vec2 p = vec2(f.x - 0.5 + sway, f.y - 0.15 - jump);
	float aa = max(fw.x, fw.y) * 1.2;
	float torso = sd_box(p - vec2(0.0, 0.42), vec2(0.27, 0.32), 0.12);
	float head = length(p - vec2(0.0, 0.92)) - 0.15;
	float arm_up = step(0.6, excite * (0.5 + 0.5 * sin(t * 1.3 + r * 9.0)));
	float arms = min(sd_box(p - vec2(-0.3, 0.95), vec2(0.05, 0.25), 0.05), sd_box(p - vec2(0.3, 0.95), vec2(0.05, 0.25), 0.05));
	arms = mix(1.0, arms, arm_up);
	float body = min(min(torso, head), arms);
	float pm = (1.0 - smoothstep(-aa, aa, body)) * occupied;
	float hm = (1.0 - smoothstep(-aa, aa, head)) * occupied;
	vec3 shirt = mix(vec3(h(cell + 1.0), h(cell + 2.0), h(cell + 3.0)) * 0.7 + 0.1,
		mix(home_col, away_col, step(0.82, h(cell + 9.0))), step(0.4, h(cell + 4.0)));
	vec3 skin = mix(vec3(0.76, 0.58, 0.44), vec3(0.36, 0.25, 0.18), h(cell + 5.0));
	vec3 hair = vec3(0.06, 0.05, 0.04);
	vec3 col = mix(c, shirt, pm);
	col = mix(col, mix(skin, hair, step(0.97, p.y - 0.0) * 0.0 + step(p.y, 0.9) * 0.0), hm);
	// far: average of the cell
	vec3 avg = mix(seat_col * 0.35, mix(shirt, skin, 0.25) * 0.8, fill * 0.75);
	col = mix(col, avg, far);
	float flash = step(0.996, h(cell + floor(TIME * 2.0))) * night * occupied;
	ALBEDO = col;
	EMISSION = vec3(1.0) * flash * 2.5;
	ROUGHNESS = 0.92;
}
