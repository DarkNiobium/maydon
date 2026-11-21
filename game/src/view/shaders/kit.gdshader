shader_type spatial;
// Football kit recolouring. Vertex colour masks: R = shirt (0.5 = trim),
// G = shorts, B = socks, A = boots. UV2 = shirt front/back projection:
// x in -1..1 front, 1..3 back; y 0 waist → 1 collar. Number from a digit atlas.

uniform vec3 shirt_col : source_color = vec3(0.8, 0.1, 0.1);
uniform vec3 shirt2_col : source_color = vec3(1.0);
uniform vec3 trim_col : source_color = vec3(1.0);
uniform vec3 shorts_col : source_color = vec3(1.0);
uniform vec3 socks_col : source_color = vec3(0.8, 0.1, 0.1);
uniform vec3 boot_col : source_color = vec3(0.08);
uniform vec3 num_col : source_color = vec3(1.0);
uniform int pattern = 0;        // 0 plain, 1 stripes, 2 hoops, 3 sash
uniform sampler2D base_tex : source_color, filter_linear_mipmap;
uniform sampler2D fabric_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_fabric = false;
uniform sampler2D digits : source_color, filter_linear_mipmap;
instance uniform int number = 10;
instance uniform vec3 boot_tint : source_color = vec3(0.08);
instance uniform bool hide_socks = false;   // custom character with Socks_low

varying vec4 vcol;
varying vec2 uv2v;

void vertex() {
	vcol = COLOR;
	uv2v = UV2;
	if (hide_socks && COLOR.b > 0.5 && COLOR.a < 0.5) {
		VERTEX -= NORMAL * 0.012;
	}
}

float digit_mask(vec2 p, int d, out float outline) {
	// p in 0..1 inside one digit cell
	outline = 0.0;
	if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
		return 0.0;
	}
	vec2 uv = vec2((float(d) + p.x) / 10.0, 1.0 - p.y);
	vec4 s = texture(digits, uv);
	outline = s.g;
	return s.r;
}

void fragment() {
	vec3 base = texture(base_tex, UV).rgb;
	float shade = clamp(dot(base, vec3(0.333)) * 1.25, 0.35, 1.2);
	float m_shirt = step(0.75, vcol.r);
	float m_trim = step(0.25, vcol.r) * (1.0 - m_shirt);
	float m_shorts = step(0.5, vcol.g);
	float m_socks = step(0.5, vcol.b);
	float m_boots = step(0.5, vcol.a);
	vec3 c = vec3(0.5);
	vec3 sc = shirt_col;
	if (pattern == 1) {
		sc = mix(shirt_col, shirt2_col, step(0.5, fract(uv2v.x * 3.5)));
	} else if (pattern == 2) {
		sc = mix(shirt_col, shirt2_col, step(0.5, fract(uv2v.y * 4.0)));
	} else if (pattern == 3) {
		float sx = fract((uv2v.x + 1.0) * 0.5);
		sc = mix(shirt_col, shirt2_col, step(abs(sx - uv2v.y * 0.8 - 0.1), 0.12) * step(uv2v.x, 1.0));
	}
	c = mix(c, sc, m_shirt);
	c = mix(c, trim_col, m_trim);
	c = mix(c, shorts_col, m_shorts);
	c = mix(c, socks_col, m_socks);
	c = mix(c, boot_tint, m_boots);
	// shirt number: big on the back, small on the chest
	if (m_shirt > 0.5) {
		int n = clamp(number, 0, 99);
		int d0 = n / 10;
		int d1 = n % 10;
		bool back = uv2v.x > 1.0;
		vec2 q = back ? vec2(uv2v.x - 2.0, uv2v.y) : uv2v;
		float h = back ? 0.42 : 0.14;
		float w = h * 0.62 * 1.6;
		vec2 org = back ? vec2(0.0, 0.62) : vec2(0.38, 0.72);
		float ol0 = 0.0;
		float ol1 = 0.0;
		float m0 = 0.0;
		float m1 = 0.0;
		if (d0 > 0) {
			m0 = digit_mask(vec2((q.x - org.x + w) / w, (q.y - org.y + h * 0.5) / h), d0, ol0);
			m1 = digit_mask(vec2((q.x - org.x) / w, (q.y - org.y + h * 0.5) / h), d1, ol1);
		} else {
			m1 = digit_mask(vec2((q.x - org.x + w * 0.5) / w, (q.y - org.y + h * 0.5) / h), d1, ol1);
		}
		float ol = max(ol0, ol1);
		float fill = max(m0, m1);
		c = mix(c, c * 0.35, ol * (1.0 - fill));
		c = mix(c, num_col, fill);
	}
	// polyester jersey: soft fuzzy sheen at grazing angles, matte core; boots are glossy
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 cloth = c * shade;
	cloth += cloth * rim * 0.35 * (1.0 - m_boots);
	ALBEDO = cloth;
	ROUGHNESS = mix(0.78, 0.3, m_boots);
	SPECULAR = mix(0.28, 0.5, m_boots);
	CLEARCOAT = m_boots * 0.6;
	CLEARCOAT_ROUGHNESS = 0.2;
	if (has_fabric) {
		NORMAL_MAP = texture(fabric_nrm, UV * 3.5).rgb;
		NORMAL_MAP_DEPTH = 0.20 * (1.0 - m_boots);
	}
	SSS_STRENGTH = 0.0;
}
