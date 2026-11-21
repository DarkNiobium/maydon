shader_type sky;
// Upper-hemisphere panorama (horizon on the bottom row, see tools_py/hdri_sky.py) + an analytic
// lower hemisphere: dark ground bounce instead of the mirrored haze of a "puresky" HDRI, which
// otherwise floods ambient light from below and makes everything look washed out.
uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float energy = 1.0;
uniform float rot = 0.0;                       // turns (0..1)
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 ground_col : source_color = vec3(0.10, 0.11, 0.09);
uniform vec3 glow_col : source_color = vec3(0.0); // city light pollution on the horizon
uniform float glow_h = 0.12;
uniform float haze = 0.0;                      // horizon haze strength
uniform vec3 haze_col : source_color = vec3(0.75, 0.8, 0.88);

vec3 pano_at(vec3 d) {
	float u = atan(d.x, -d.z) * 0.15915494 + 0.5 + rot;
	float el = asin(clamp(d.y, 0.0, 1.0));
	float v = 1.0 - el * 0.63661977;
	return textureLod(pano, vec2(u, clamp(v, 0.002, 0.998)), 0.0).rgb;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = max(d.y, 0.0);
	vec3 s = pano_at(vec3(d.x, max(d.y, 0.0), d.z)) * tint;
	s += glow_col * exp(-up / max(glow_h, 0.001));
	s = mix(s, haze_col, haze * exp(-up * 9.0));
	// below the horizon: fade into ground within a few degrees (the stadium/city hides it anyway)
	float g = smoothstep(0.0, 0.06, -d.y);
	vec3 col = mix(s, ground_col * (0.6 + 0.4 * (1.0 + d.y)), g);
	COLOR = col * energy;
}
