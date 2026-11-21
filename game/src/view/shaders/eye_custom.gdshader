shader_type spatial;
// Custom-character eyes: real 512 px eyeball atlas with glossy sclera; the iris is tinted
// from the brown source to the look's eye colour, the pupil stays black.
uniform sampler2D eye_tex : source_color, filter_linear_mipmap;
uniform vec3 eye_col : source_color = vec3(0.20, 0.11, 0.06);

void fragment() {
	vec3 c = texture(eye_tex, UV).rgb;
	float lum = dot(c, vec3(0.30, 0.55, 0.15));
	float iris = smoothstep(0.62, 0.22, lum);
	vec3 tint = pow(lum, 0.72) * eye_col * 2.8;
	c = mix(c, tint, iris * 0.88);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = c;
	ROUGHNESS = 0.16;
	SPECULAR = 0.52;
	EMISSION = c * rim * 0.05;
}
