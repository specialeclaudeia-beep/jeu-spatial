// Les lampes du vaisseau (étape 8) : de vraies sources de lumière, en candelas, réglées par le processeur
// à chaque image (scripts/lumiere/objets.gd et le jeu). Deux lampes : A = le projecteur sous le nez
// (il éclaire le sol), B = la petite lampe du cockpit. Intensité 0 = éteinte.
// Loi de la lumière d'un point : éclairement = intensité × cos(angle avec la surface) / distance²,
// dans un cône de lumière dont le bord s'adoucit entre cos_bord.x (pleine lumière) et cos_bord.y (noir).
// Pas d'ombre pour ces lampes (à faire plus tard si besoin).

global uniform vec3 lampe_a_position;      // repère d'affichage (m)
global uniform vec3 lampe_a_direction;     // axe du cône, longueur 1
global uniform float lampe_a_intensite;    // candelas (0 = éteinte)
global uniform vec2 lampe_a_cos_bord;      // cos du demi-angle : pleine lumière, puis noir
global uniform vec3 lampe_a_couleur;       // couleur, luminance 1
global uniform vec3 lampe_b_position;
global uniform vec3 lampe_b_direction;
global uniform float lampe_b_intensite;
global uniform vec2 lampe_b_cos_bord;
global uniform vec3 lampe_b_couleur;

vec3 une_lampe(vec3 p, vec3 n, vec3 pos, vec3 axe, float i, vec2 bord, vec3 couleur) {
	vec3 v = pos - p;
	float d2 = max(dot(v, v), 1e-4);
	vec3 l = v * inversesqrt(d2);
	float cone = smoothstep(bord.y, bord.x, dot(-l, axe));
	return couleur * (i * cone * max(dot(n, l), 0.0) / d2);
}

// Éclairement (lux, en couleur) reçu au point p de normale n par les lampes du vaisseau.
vec3 lampes_eclairement(vec3 p, vec3 n) {
	vec3 e = vec3(0.0);
	if (lampe_a_intensite > 0.0) {
		e += une_lampe(p, n, lampe_a_position, lampe_a_direction, lampe_a_intensite, lampe_a_cos_bord, lampe_a_couleur);
	}
	if (lampe_b_intensite > 0.0) {
		e += une_lampe(p, n, lampe_b_position, lampe_b_direction, lampe_b_intensite, lampe_b_cos_bord, lampe_b_couleur);
	}
	return e;
}
