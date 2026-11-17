// Astre d'essai du labo (étape 3) : une boule grise comme la Lune (albédo 12 %), éclairée par le
// vrai Soleil. Elle sert à juger l'œil (jour, nuit, éclipse) en attendant la planète en rayons (étape 4).
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://scripts/lumiere/oeil.gdshaderinc"

uniform float albedo = 0.12;

varying vec3 pos_monde;
varying vec3 pos_locale;
varying vec3 normale_monde;

// Petit bruit en 3D pour des taches claires et sombres (que le mouvement se voie).
float bruit3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = dot(i, vec3(1.0, 57.0, 113.0));
	vec4 a = fract(sin(vec4(n, n + 1.0, n + 57.0, n + 58.0)) * 43758.5453);
	vec4 b = fract(sin(vec4(n + 113.0, n + 114.0, n + 170.0, n + 171.0)) * 43758.5453);
	vec4 m = mix(a, b, f.z);
	vec2 m2 = mix(m.xy, m.zw, f.y);
	return mix(m2.x, m2.y, f.x);
}

void vertex() {
	pos_locale = VERTEX;
	pos_monde = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normale_monde = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(normale_monde);
	vec3 p = normalize(pos_locale);
	float taches = 0.55 * bruit3(p * 6.0) + 0.3 * bruit3(p * 17.0) + 0.15 * bruit3(p * 45.0);
	float a = albedo * (0.6 + 0.8 * taches);
	// Sol mat (loi de Lambert) : luminance = albédo × éclairement × cos(angle) / π.
	float l = a * soleil_eclairement * max(dot(n, soleil_direction), 0.0) / PI;
	vec3 vue = normalize(pos_monde - CAMERA_POSITION_WORLD);
	vec3 total = soleil_couleur * l + oeil_voile(vue, TIME);
	ALBEDO = oeil_vers_ecran(total, FRAGCOORD.xy, TIME);
}
