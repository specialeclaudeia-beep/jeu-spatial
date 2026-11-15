// Ciel étoilé, toujours derrière tout le reste. Il n'éclaire rien (le vrai noir de l'espace).
shader_type sky;

float h(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

void sky() {
	vec3 g = EYEDIR * 350.0;
	vec3 c = floor(g);
	vec3 f = fract(g) - 0.5;
	float r = h(c);
	float etoile = 0.0;
	if (r > 0.993) {
		float eclat = (r - 0.993) / 0.007;
		etoile = smoothstep(0.32, 0.0, length(f)) * (0.25 + eclat * eclat * 1.5);
	}
	float teinte = h(c + vec3(7.0));
	vec3 couleur = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), teinte);
	COLOR = couleur * etoile;
}
