// Le ciel du système de lumière : le vrai Soleil, l'étoile compagne, la Voie lactée et la lueur du fond
// du ciel, puis l'œil. Les étoiles du catalogue sont dessinées par-dessus (etoiles.gdshader).
// Étape 6 : à grande vitesse, chaque pixel cherche d'où vient vraiment sa lumière (aberration à
// l'envers) et la change de couleur et d'éclat (Doppler), comme le verrait un vrai œil.
shader_type sky;

#include "res://scripts/lumiere/oeil.gdshaderinc"
#include "res://scripts/lumiere/etoiles.gdshaderinc"
#include "res://scripts/lumiere/compagnon.gdshaderinc"
#include "res://scripts/lumiere/lentille.gdshaderinc"

const float ASSOMBRISSEMENT_BORD = 0.6;   // le bord du Soleil est plus sombre que son centre
const float T_FOND = 4500.0;              // couleur moyenne de la lumière de la Voie lactée (K)

// Un astre rond de rayon apparent a, direction dir, luminance au centre lum, vu dans la direction n.
// pix = taille d'un pixel (rad) au repos. Plus petit qu'un pixel, il devient un point lumineux qui
// garde exactement sa lumière (tache de 0,6 pixel, comme les étoiles).
float astre_rond(vec3 n, vec3 dir, float a, float lum, float pix) {
	float th = atan(length(cross(n, dir)), dot(n, dir));
	if (a > 0.75 * pix) {
		float couvre = clamp((a - th) / max(pix, 1e-9) + 0.5, 0.0, 1.0);
		float mu = sqrt(max(1.0 - (th * th) / (a * a), 0.0));
		return lum * (1.0 - ASSOMBRISSEMENT_BORD * (1.0 - mu)) * couvre;
	}
	float s = 0.6 * pix;
	float e = lum * (1.0 - ASSOMBRISSEMENT_BORD / 3.0) * PI * a * a;
	return e * exp(-th * th / (2.0 * s * s)) / (2.0 * PI * s * s);
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = vec3(0.0);   // le ciel ne sert pas aux reflets pour l'instant
	} else {
		vec3 d = normalize(EYEDIR);
		// D'où vient la lumière de ce pixel, au repos ? (aberration avec la vitesse opposée)
		vec4 ab = aberration(d, -oeil_vitesse);
		vec3 n = ab.xyz;
		float dop = 1.0 / ab.w;
		// Einstein B : près d'un trou noir, d'où vient VRAIMENT cette lumière ? (rayon suivi à l'envers)
		vec4 lo = lentille_origine(n);
		bool ombre_trou_noir = lo.w < 0.5;   // aucune lumière ne vient d'ici : l'ombre du trou noir
		n = ombre_trou_noir ? d : lo.xyz;
		float pix = oeil_pixel_angle * dop;
		float a = soleil_rayon_angle;
		vec3 l = doppler_surface(vec3(1.0), T_FOND, dop) * fond_galaxie(n);
		// Disque du Soleil à sa vraie taille, bord adouci sur un pixel.
		float disque = astre_rond(n, soleil_direction, a, soleil_luminance, pix);
		// La couronne du Soleil (gaz très chaud autour de lui), un millionième de son éclat :
		// formule de Baumbach. Invisible à côté du disque, elle apparaît quand un astre le cache.
		float th = atan(length(cross(n, soleil_direction)), dot(n, soleil_direction));
		float r = max(th / a, 1.0);
		float couronne = 1e-8 * (0.0532 / pow(r, 2.5) + 1.425 / pow(r, 7.0) + 2.565 / pow(r, 17.0));
		float couvre = clamp((a - th) / max(pix, 1e-9) + 0.5, 0.0, 1.0);
		l += doppler_surface(soleil_couleur, T_SOLEIL, dop) * (disque + soleil_luminance * couronne * (1.0 - couvre));
		// L'étoile compagne : un point orangé (plus petit qu'un pixel à 5 UA).
		if (compagnon_eclairement > 0.0) {
			l += doppler_surface(compagnon_couleur, compagnon_temperature, dop)
				* astre_rond(n, compagnon_direction, compagnon_rayon_angle, compagnon_luminance / (1.0 - ASSOMBRISSEMENT_BORD / 3.0), pix);
		}
		if (ombre_trou_noir) {
			l = vec3(0.0);
		}
		l += oeil_voile(d, TIME);
		COLOR = oeil_vers_ecran(l, FRAGCOORD.xy, TIME);
	}
}
