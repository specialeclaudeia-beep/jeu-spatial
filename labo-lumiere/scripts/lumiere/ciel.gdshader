// Le ciel du système de lumière (étape 3) : le vrai Soleil, la lueur du fond du ciel, puis l'œil.
// Les étoiles viendront à l'étape 6.
shader_type sky;

#include "res://scripts/lumiere/oeil.gdshaderinc"

// Lueur du fond du ciel vu de l'espace (lumière zodiacale + étoiles trop faibles), cd/m².
const float FOND_CIEL = 2.0e-4;
const float ASSOMBRISSEMENT_BORD = 0.6;   // le bord du Soleil est plus sombre que son centre

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = vec3(0.0);   // le ciel ne sert pas aux reflets pour l'instant
	} else {
		vec3 d = normalize(EYEDIR);
		float th = atan(length(cross(d, soleil_direction)), dot(d, soleil_direction));
		float a = soleil_rayon_angle;
		// Disque du Soleil à sa vraie taille, bord adouci sur un pixel.
		float couvre = clamp((a - th) / max(oeil_pixel_angle, 1e-6) + 0.5, 0.0, 1.0);
		float mu = sqrt(max(1.0 - (th * th) / (a * a), 0.0));
		float bord = 1.0 - ASSOMBRISSEMENT_BORD * (1.0 - mu);
		vec3 l = vec3(FOND_CIEL) + soleil_couleur * soleil_luminance * bord * couvre;
		// La couronne du Soleil (gaz très chaud autour de lui), un millionième de son éclat :
		// formule de Baumbach. Invisible à côté du disque, elle apparaît quand un astre le cache.
		float r = max(th / a, 1.0);
		float couronne = 1e-8 * (0.0532 / pow(r, 2.5) + 1.425 / pow(r, 7.0) + 2.565 / pow(r, 17.0));
		l += soleil_couleur * soleil_luminance * couronne * (1.0 - couvre);
		l += oeil_voile(d, TIME);
		COLOR = oeil_vers_ecran(l, FRAGCOORD.xy, TIME);
	}
}
