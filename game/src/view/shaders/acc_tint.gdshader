shader_type spatial;
// Accessories (headband, wristbands, gloves, armband): tint × grey texture.
uniform sampler2D acc_tex : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.95);

void fragment() {
	vec3 t = texture(acc_tex, UV).rgb;
	ALBEDO = tint * t * 1.15;
	ROUGHNESS = 0.75;
}
