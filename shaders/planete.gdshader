// Surface de la planète (provisoire) : continents, océans, glace aux pôles.
// La couleur est calculée à partir de la direction depuis le centre (NORMAL du maillage),
// donc la sphère lointaine et la « calotte » détaillée près du sol se raccordent parfaitement.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

varying vec3 dir;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float bruit(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(h3(i + vec3(0.0, 0.0, 0.0)), h3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(h3(i + vec3(0.0, 1.0, 0.0)), h3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(h3(i + vec3(0.0, 0.0, 1.0)), h3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(h3(i + vec3(0.0, 1.0, 1.0)), h3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 9; i++) {
		s += a * bruit(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	dir = normalize(NORMAL);
}

void fragment() {
	vec3 d = normalize(dir);
	float h = fbm(d * 2.5 + vec3(11.3, 2.7, -5.1)) - 0.5;
	float lat = abs(d.y);
	vec3 col;
	if (lat > 0.86 - h * 0.3) {
		col = vec3(0.85, 0.9, 0.95);                       // glace
	} else if (h < 0.0) {
		col = mix(vec3(0.03, 0.16, 0.36), vec3(0.01, 0.04, 0.15), clamp(-h * 5.0, 0.0, 1.0)); // océan
	} else if (h < 0.015) {
		col = vec3(0.72, 0.66, 0.46);                      // plage
	} else if (h > 0.2) {
		col = vec3(0.5, 0.45, 0.4);                        // roche
	} else {
		col = mix(vec3(0.22, 0.42, 0.15), vec3(0.1, 0.27, 0.1), clamp(fbm(d * 9.0 + vec3(3.0)), 0.0, 1.0));
	}
	ALBEDO = col;
}
