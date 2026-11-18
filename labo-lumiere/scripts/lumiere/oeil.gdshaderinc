// L'œil du pilote, commun à tous les programmes de dessin du système de lumière (étape 3).
// Chaque programme calcule d'abord une vraie luminance (candelas par m², comme un posemètre),
// puis appelle ces deux fonctions, dans cet ordre :
//   1. oeil_voile(direction)   : la lumière du Soleil diffusée DANS l'œil (halo, éblouissement) ;
//   2. oeil_vers_ecran(L, ...) : pupille + adaptation de la rétine + vision de nuit → couleur d'écran.
// Les réglages viennent du processeur à chaque image (scripts/lumiere/oeil.gd et soleil.gd), par des
// « réglages globaux » déclarés dans project.godot (section [shader_globals]).

global uniform vec3 soleil_direction;        // direction vers le Soleil, repère du monde, longueur 1
global uniform float soleil_eclairement;     // lux reçus du Soleil en plein jour (126 600 à 1 UA)
global uniform float soleil_luminance;       // luminance au centre du disque, cd/m²
global uniform float soleil_rayon_angle;     // rayon apparent du disque, en radians
global uniform float soleil_eclairement_oeil; // lux du Soleil qui entrent dans l'œil (part visible du
                                              // disque × angle avec le regard × halo oui/non)
global uniform vec3 soleil_couleur;          // couleur du Soleil, lumière linéaire de luminance 1
global uniform float oeil_gain;              // aire de la pupille / état d'adaptation de la rétine
global uniform float oeil_nuit;              // 0 = vision de jour (cônes) … 1 = vision de nuit (bâtonnets)
global uniform float oeil_pixel_angle;       // angle couvert par un pixel, en radians
global uniform vec3 oeil_droite;             // repère de la tête : vers la droite…
global uniform vec3 oeil_haut;               // … et vers le haut (le halo tourne avec la tête)
global uniform vec3 soleil_direction_vue;    // direction où l'œil VOIT le Soleil (= soleil_direction, sauf
                                              // à très grande vitesse : aberration, étape 6)

// Bruit fixe par pixel, entre 0 et 1.
float oeil_hasard(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Lumière du Soleil diffusée dans l'œil, vue dans la direction d (cd/m²).
// Fonction d'éblouissement de la CIE (publication 146, 2002), pour un œil de 25 ans aux yeux
// moyennement foncés : Léq / E = 10/θ³ + (5/θ² + 0,1·p/θ)·(1 + (âge/62,5)⁴) + 0,0025·p, θ en degrés.
// Le terme 10/θ³ (cils, cristallin) porte la « couronne » de fines raies ; un anneau irisé faible
// à environ 3,5° imite le halo du cristallin (Ritschel 2009).
vec3 oeil_voile(vec3 d, float temps) {
	float e = soleil_eclairement_oeil;
	if (e <= 0.0) {
		return vec3(0.0);
	}
	float c = dot(d, soleil_direction_vue);
	float th = degrees(atan(length(cross(d, soleil_direction_vue)), c));
	th = max(th, max(0.1, degrees(soleil_rayon_angle)));
	// Couronne : raies fines autour du Soleil, qui tournent avec la tête et frémissent un peu.
	vec3 ecart = d - soleil_direction_vue * c;
	float phi = atan(dot(ecart, oeil_haut), dot(ecart, oeil_droite));
	float raies = pow(abs(sin(phi * 23.0 + sin(phi * 7.0) * 2.0 + temps * 0.7)), 18.0)
		+ 0.6 * pow(abs(sin(phi * 41.0 - sin(phi * 3.0) * 3.0)), 24.0);
	float couronne = 10.0 / (th * th * th) * (0.55 + 2.2 * raies);
	float diffus = (5.0 / (th * th) + 0.05 / th) * 1.0256 + 0.00125;
	// Anneau irisé : le rouge un peu plus loin du Soleil que le bleu.
	vec3 rayons_anneau = vec3(3.9, 3.6, 3.25);
	vec3 anneau = 0.35 * (5.0 / (th * th)) * exp(-pow((vec3(th) - rayons_anneau) / 0.22, vec3(2.0)));
	return soleil_couleur * e * (couronne + diffus) + e * anneau;
}

// Luminance réelle (cd/m², lumière linéaire) → couleur d'écran, comme l'œil la voit.
// pixel = coordonnées du pixel (pour le tramage), temps = secondes (pour le grain de la nuit).
vec3 oeil_vers_ecran(vec3 l, vec2 pixel, float temps) {
	l = max(l, vec3(0.0));
	// Jour : réponse des cônes (loi de Naka-Rushton), un canal par couleur.
	vec3 x = l * oeil_gain;
	vec3 jour = x / (x + 1.0);
	vec3 ecran = jour;
	if (oeil_nuit > 0.0) {
		// Nuit : les bâtonnets voient mieux le bleu-vert, une seule « couleur », un peu bleutée,
		// avec le grain de la lumière faible (effet Purkinje).
		float gx = dot(l, vec3(0.4124, 0.3576, 0.1805));
		float gy = dot(l, vec3(0.2126, 0.7152, 0.0722));
		float gz = dot(l, vec3(0.0193, 0.1192, 0.9505));
		float scot = max(gy * (1.33 * (1.0 + (gy + gz) / max(gx, 1e-9)) - 1.68), 0.0) / 2.573;
		float xs = scot * oeil_gain;
		float r = xs / (xs + 1.0);
		r += (oeil_hasard(pixel + fract(temps * 7.31) * 113.0) - 0.5) * 0.08 * sqrt(r + 0.0004);
		vec3 nuit = max(r, 0.0) * vec3(0.80, 0.93, 1.28);
		ecran = mix(jour, nuit, oeil_nuit);
	}
	// L'écran attend des couleurs « sRGB » : le rendu Compatibilité ne fait pas cette conversion
	// lui-même pour nos programmes (vérifié à l'étape 3), on la fait donc ici.
	ecran = clamp(ecran, 0.0, 1.0);
	ecran = mix(ecran * 12.92, 1.055 * pow(ecran, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), ecran));
	// Tramage : ±½ niveau contre les bandes des couleurs 8 bits.
	return ecran + (oeil_hasard(pixel) - 0.5) / 255.0;
}
