shader_type spatial;
// Soviet-era panel apartment block: panel grid, balconies tone, lit windows at night.
uniform vec3 wall : source_color = vec3(0.62, 0.6, 0.55);
uniform vec2 size = vec2(30.0, 27.0);   // facade width / height (m)
uniform float floors = 9.0;
uniform float night = 1.0;
uniform float seed = 0.0;
uniform float win_w = 3.0;              // window module width (m)

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1)) + seed * 17.0) * 43758.5453);
}

void fragment() {
	vec2 m = UV * size;
	vec2 cell = vec2(floor(m.x / win_w), floor(m.y / (size.y / floors)));
	vec2 f = vec2(fract(m.x / win_w), fract(m.y / (size.y / floors)));
	float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.3, f.y) * step(f.y, 0.85);
	float r = h21(cell);
	vec3 c = wall * (0.9 + 0.1 * h21(cell + 3.1));
	// panel seams
	float seam = (1.0 - step(0.02, f.y)) + (1.0 - step(0.015, f.x));
	c *= 1.0 - seam * 0.25;
	vec3 glass = vec3(0.08, 0.1, 0.12);
	float lit = step(0.55, r) * night;
	vec3 warm = mix(vec3(1.0, 0.75, 0.45), vec3(0.75, 0.85, 1.0), step(0.85, h21(cell + 7.7)));
	c = mix(c, glass, win);
	ALBEDO = c * mix(0.72, 0.07, night);
	EMISSION = warm * lit * win * (0.6 + 0.8 * h21(cell + 1.3)) * 1.6;
	ROUGHNESS = mix(0.9, 0.2, win);
}
