shader_type spatial;
// Distant crowd on stand terraces: seat rows with per-seat people of random
// colours that bob and jump when `excite` rises (goal, chance).
uniform vec2 size = vec2(100.0, 20.0);  // terrace length, depth along slope (m)
uniform float rows = 30.0;
uniform float seat_w = 0.55;
uniform float fill = 0.85;
uniform float excite = 0.0;
uniform vec3 seat_col : source_color = vec3(0.6, 0.06, 0.08);
uniform vec3 home_col : source_color = vec3(0.9, 0.1, 0.1);
uniform vec3 away_col : source_color = vec3(0.1, 0.2, 0.8);
uniform float night = 1.0;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 m = UV * size;
	vec2 cell = vec2(floor(m.x / seat_w), floor(UV.y * rows));
	vec2 f = vec2(fract(m.x / seat_w), fract(UV.y * rows));
	float r = h(cell);
	float occupied = step(r, fill);
	vec3 c = seat_col * 0.6;
	// row step shading
	c *= 0.75 + 0.25 * f.y;
	float t = TIME * (1.5 + r * 2.0) + r * 30.0;
	float bob = sin(t) * 0.04 + excite * max(0.0, sin(t * 2.3)) * 0.25;
	float body_top = 0.85 - bob;
	float person = occupied * step(0.15, f.x) * step(f.x, 0.85) * step(f.y, body_top);
	float headm = occupied * step(0.3, f.x) * step(f.x, 0.7) * step(body_top - 0.25, f.y) * step(f.y, body_top);
	vec3 shirt = mix(vec3(h(cell + 1.0), h(cell + 2.0), h(cell + 3.0)) * 0.8,
		mix(home_col, away_col, step(0.8, h(cell + 9.0))), step(0.45, h(cell + 4.0)));
	vec3 skin = mix(vec3(0.78, 0.6, 0.46), vec3(0.35, 0.24, 0.17), h(cell + 5.0));
	c = mix(c, shirt, person);
	c = mix(c, skin, headm);
	// phone flashes at night
	float flash = step(0.997, h(cell + floor(TIME * 2.0))) * night * occupied;
	ALBEDO = c;
	EMISSION = vec3(1.0) * flash * 2.0 + c * 0.05;
	ROUGHNESS = 0.9;
}
