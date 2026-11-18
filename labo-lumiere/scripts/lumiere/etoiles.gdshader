// Les étoiles du catalogue de Yale (étape 6) : une copie d'un petit carré par étoile (MultiMesh).
// Chaque étoile est un point de vraie lumière (lux) : sa tache sur l'écran garde exactement cette
// lumière (tache de 0,6 pixel), puis l'œil la voit comme le reste (oeil.gdshaderinc). Rien n'est
// « masqué » à la main : quand une lumière forte est dans le champ (le Soleil, la planète de jour),
// l'œil s'y habitue et les étoiles disparaissent d'elles-mêmes, comme en vrai.
// Les étoiles brillantes ont aussi leur halo dans l'œil (même loi de la CIE que pour le Soleil).
// Données par copie : position = direction de l'étoile (longueur 1, repère fixe ; le nœud tourne avec
// le ciel), INSTANCE_CUSTOM.x = log10(lux), INSTANCE_CUSTOM.y = température / 10 000 K.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

#include "res://scripts/lumiere/oeil.gdshaderinc"
#include "res://scripts/lumiere/etoiles.gdshaderinc"
#include "res://scripts/lumiere/lentille.gdshaderinc"

uniform float halo = 1.0;              // 1 = halo dans l'œil (touche H du labo), 0 = sans
uniform float distance_dessin = 1.0e5; // m : entre le plan proche et le plan lointain de la caméra
uniform bool image_secondaire = false; // Einstein B : ce nœud dessine la 2e image (de l'autre côté du trou noir)
const float TACHE = 0.6;               // pixels : taille de la tache d'une étoile

varying vec3 lumiere_v;                // lux × couleur
varying vec2 px_v;                     // position dans le carré, en pixels
varying vec3 fond_v;                   // lumière derrière l'étoile (cd/m²)

void vertex() {
	vec3 n = normalize(MODEL_MATRIX[3].xyz);
	float t = INSTANCE_CUSTOM.y * 10000.0;
	float e = pow(10.0, INSTANCE_CUSTOM.x);
	// Einstein B : où le trou noir montre cette étoile, et combien plus (ou moins) brillante
	vec4 li = lentille_image(n, image_secondaire);
	vec3 n_source = n;   // le fond du ciel derrière l'image vient, lui aussi, de là
	n = li.xyz;
	e *= li.w;
	vec4 repos = corps_noir_lire(t);
	vec3 couleur = repos.rgb;
	vec4 ab = aberration(n, oeil_vitesse);
	if (abs(ab.w - 1.0) > 1e-6) {
		vec4 vu = corps_noir_lire(t * ab.w);
		e *= ab.w * ab.w * vu.a / max(repos.a, 1e-30);
		couleur = vu.rgb;
	}
	vec3 dir = ab.xyz;
	lumiere_v = couleur * e;
	// Une étoile trop faible pour cet œil (moins d'un demi-niveau de l'écran) n'est pas dessinée.
	float omega = oeil_pixel_angle * oeil_pixel_angle;
	float pic = e / (2.0 * PI * TACHE * TACHE * omega);
	float pix_deg = degrees(oeil_pixel_angle);
	// Taille du carré : la tache, plus le halo des étoiles brillantes (jusqu'où il dépasse 1e-5 cd/m²).
	float r_halo = halo > 0.5 ? pow(1.0e6 * e, 1.0 / 3.0) / pix_deg : 0.0;
	float rayon = clamp(r_halo, 2.5, 24.0);
	fond_v = vec3(fond_galaxie(n_source)) + oeil_voile(dir, TIME);
	vec4 vue = VIEW_MATRIX * vec4(dir * distance_dessin, 1.0);
	vec4 clip = PROJECTION_MATRIX * vue;
	px_v = VERTEX.xy * rayon;
	clip.xy += VERTEX.xy * rayon * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
	if (pic * oeil_gain < 2e-4 || vue.z > 0.0 || li.w <= 0.0) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);   // hors de l'écran
	}
}

void fragment() {
	float r2 = dot(px_v, px_v);
	float omega = oeil_pixel_angle * oeil_pixel_angle;
	vec3 l = lumiere_v * exp(-r2 / (2.0 * TACHE * TACHE)) / (2.0 * PI * TACHE * TACHE * omega);
	if (halo > 0.5) {
		// Lumière de l'étoile diffusée dans l'œil (CIE 146:2002), au-delà de 1,5 pixel.
		float th = max(sqrt(r2), 0.5) * degrees(oeil_pixel_angle);
		l += lumiere_v * (10.0 / (th * th * th) + 5.13 / (th * th)) * smoothstep(1.0, 2.0, sqrt(r2));
	}
	// Ce que l'étoile AJOUTE à ce que l'œil voit déjà derrière elle (le fond du ciel, le halo du Soleil).
	ALBEDO = max(oeil_vers_ecran(fond_v + l, FRAGCOORD.xy, TIME) - oeil_vers_ecran(fond_v, FRAGCOORD.xy, TIME), vec3(0.0));
	ALPHA = 1.0;
	// Tout au fond (profondeur inversée de Godot 4.7 : 0 = le plus loin) : la planète et la lune,
	// dessinées avant, cachent les étoiles qui sont derrière elles.
	DEPTH = 1.0e-7;
}
