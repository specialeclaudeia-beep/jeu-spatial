// Réglages communs aux objets proches dessinés avec le système de lumière (étape 8 : vaisseau, cockpit).
// Ils viennent du processeur à chaque image (le jeu, scripts/lumiere_jeu.gd).

// Profondeur logarithmique : LA MÊME que la planète (planete.gdshader), sinon le vaisseau passerait
// devant ou derrière le sol au hasard.
global uniform float affichage_pres;          // m : la distance la plus proche dessinée
global uniform float affichage_loin;          // m : la plus lointaine
// La planète vue d'ici : elle renvoie une partie de la lumière du Soleil (lumière de la planète,
// comme le « clair de Terre » sur la Lune).
global uniform vec3 planete_centre;           // repère d'affichage (m)
global uniform float planete_rayon;           // m
global uniform float planete_albedo;          // part moyenne de la lumière renvoyée par le sol
// Part du disque des étoiles encore visible depuis le vaisseau (cachée par la planète, une éclipse
// ou une montagne), calculée par le processeur une fois par image (le vaisseau est petit).
global uniform float objets_soleil_visible;
global uniform float objets_compagnon_visible;

float profondeur_log(float prof) {
	return 1.0 - clamp(log2(max(prof, affichage_pres) / affichage_pres) / log2(affichage_loin / affichage_pres), 0.0, 1.0);
}

// Lumière moyenne d'un cône de petites faces (même loi que planete.gdshader), ici pour une source
// étendue : la planète vue comme un disque de sinus de demi-angle sb dans la direction s.
float eclairage_cone(vec3 n, float sb, vec3 s) {
	float cs = dot(n, s);
	return cs > sb ? cs : (cs < -sb ? 0.0 : (cs + sb) * (cs + sb) / (4.0 * sb + 1e-6));
}

// Éclairement (lux) reçu au point p de normale n par la lumière que renvoie la planète.
// Boule mate éclairée par le Soleil, vue sous un angle de phase a : sa luminance moyenne vaut
// albédo × E / π × (2/3) × (sin a + (π − a) cos a) / π (loi de Lambert pour une sphère).
vec3 lumiere_planete(vec3 p, vec3 n) {
	if (planete_rayon <= 0.0) return vec3(0.0);
	vec3 v = planete_centre - p;
	float d = length(v);
	vec3 vers = v / d;
	float sb = min(planete_rayon / d, 1.0);
	float cos_phase = clamp(dot(-vers, soleil_direction), -1.0, 1.0);
	float a = acos(cos_phase);
	float phase = (2.0 / 3.0) * (sin(a) + (PI - a) * cos_phase) / PI;
	float luminance = planete_albedo * soleil_eclairement * objets_soleil_visible / PI * phase;
	// Un disque de luminance L et de sinus de demi-angle sb donne π L sb² face à lui.
	return soleil_couleur * (PI * luminance * sb * sb * eclairage_cone(n, sb, vers));
}
