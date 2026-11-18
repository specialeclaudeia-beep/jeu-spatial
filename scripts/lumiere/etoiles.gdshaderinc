// Le ciel des étoiles (étape 6), commun au ciel (ciel.gdshader) et aux étoiles (etoiles.gdshader).
// Même lois que scripts/lumiere/etoiles.gd : lumière des corps noirs, Voie lactée, et ce que voit un œil
// qui va très vite (aberration et effet Doppler, relativité restreinte).
// À inclure APRÈS oeil.gdshaderinc.

global uniform vec3 oeil_vitesse;           // vitesse de l'œil, en fraction de la vitesse de la lumière
global uniform vec3 ciel_pole_galaxie;      // pôle nord de la galaxie (repère d'affichage)
global uniform vec3 ciel_centre_galaxie;    // centre de la galaxie (repère d'affichage)

// Table des corps noirs (etoiles.gd) : couleur (luminance 1) et efficacité relative (1 pour le Soleil),
// de 500 K à 2 millions de K.
uniform sampler2D corps_noir : filter_linear, repeat_disable;

const float CN_T_MIN = 500.0;
const float CN_T_MAX = 2.0e6;
const float CN_TAILLE = 256.0;
const float T_SOLEIL = 5772.0;

vec4 corps_noir_lire(float t) {
	float u = log(clamp(t, CN_T_MIN, CN_T_MAX) / CN_T_MIN) / log(CN_T_MAX / CN_T_MIN);
	return texture(corps_noir, vec2((u * (CN_TAILLE - 1.0) + 0.5) / CN_TAILLE, 0.5));
}

// Aberration : direction n vue au repos → direction vue par l'œil qui va à la vitesse b (fraction de c).
// Renvoie (direction vue, facteur Doppler D).
vec4 aberration(vec3 n, vec3 b) {
	float v = length(b);
	if (v < 1e-9) {
		return vec4(n, 1.0);
	}
	v = min(v, 0.999999);
	vec3 u = b / length(b);
	float g = 1.0 / sqrt(1.0 - v * v);
	float c = dot(n, u);
	vec3 vue = (n + u * (g * v + (g - 1.0) * c)) / (g * (1.0 + v * c));
	return vec4(normalize(vue), g * (1.0 + v * c));
}

// Lueur du fond du ciel (cd/m²) vers n (direction au repos) : la Voie lactée et le fond très faible.
float fond_galaxie(vec3 n) {
	float b = asin(clamp(dot(n, ciel_pole_galaxie), -1.0, 1.0));
	float vers_centre = acos(clamp(dot(n, ciel_centre_galaxie), -1.0, 1.0));
	float bande = exp(-pow(b / 0.14, 2.0)) * (0.35 + 0.65 * exp(-pow(vers_centre / 1.3, 2.0)));
	float bulbe = exp(-pow(vers_centre / 0.22, 2.0));
	return 7.0e-5 + 3.6e-4 * bande + 7.0e-4 * bulbe;
}

// Couleur et luminance d'une surface de température t vue avec le facteur Doppler d :
// un corps noir à t se voit comme un corps noir à d × t, d⁴ × (efficacité à d·t) / (efficacité à t)
// fois plus lumineux. couleur_repos = sa couleur sans vitesse (luminance 1).
vec3 doppler_surface(vec3 couleur_repos, float t, float d) {
	if (abs(d - 1.0) < 1e-6) {
		return couleur_repos;
	}
	vec4 a = corps_noir_lire(t);
	vec4 b = corps_noir_lire(t * d);
	return couleur_repos * (b.rgb / max(a.rgb, vec3(1e-6))) * (d * d * d * d * b.a / max(a.a, 1e-30));
}
