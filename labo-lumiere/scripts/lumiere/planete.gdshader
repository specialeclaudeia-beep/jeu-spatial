// Dessin de la planète en rayons (étape 4, temps 4 « dessiner »).
// Chaque copie du morceau type (MultiMesh) est un triangle choisi par la partie C++ (ArbreLumiere).
// - La FORME vient de la texture des coins : pour chaque morceau (une ligne), 45 coins × 2 positions
//   (départ = forme du parent, visée = vrai relief), par rapport au centre du morceau. Juste après une
//   coupe, le morceau glisse en douceur de la forme du parent vers la sienne : pas de saut à l'écran.
// - La LUMIÈRE des rayons vient de la texture des rayons, rangée sur les coins partagés des rayons
//   (doc « couleurs stables ») : 3 texels par coin (couleur de départ, couleur visée, direction moyenne
//   de la surface dont la longueur dit l'étalement). La carte graphique passe en douceur d'un coin à
//   l'autre : pas de mosaïque, et deux morceaux voisins ont les mêmes valeurs sur leur bord commun.
// - La lumière directe du Soleil est calculée ici, à chaque pixel (décision Q43 = version B), en vraies
//   unités (cd/m²), puis passe par l'œil du pilote.
// Données par copie (INSTANCE_CUSTOM) : x = heure d'arrivée, y = profondeur des jupes, z = taille d'un rayon.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

#include "res://scripts/lumiere/oeil.gdshaderinc"

uniform sampler2D coins : filter_nearest;      // RGBA 32 bits flottants, 90 × places
uniform sampler2D rayons : filter_nearest;     // RGBA 8 bits, 135 × places
uniform float maintenant = 0.0;                // horloge du labo (s), la même que la partie C++
uniform float duree_glissement = 0.5;          // s
uniform float lux_fond = 2.0e-4;               // lumière des étoiles et du fond du ciel (lux)
uniform vec3 centre_planete = vec3(0.0);       // centre de la planète dans le monde (repère de l'affichage)
// Étape 5, éclipses : un astre (centre dans le repère de l'affichage, rayon en w) qui peut cacher
// le Soleil. w = 0 : aucun. Chaque coin reçoit la part du disque solaire qu'il voit encore :
// ombre (rien), pénombre (une partie), comme dans une vraie éclipse.
uniform vec4 occulteur = vec4(0.0);

varying vec3 albedo_v;
varying vec3 direction_v;
varying float glisse;
varying vec3 pos_monde;
varying float profondeur;
varying vec3 voile_v;
varying float soleil_visible;

// Part d'un disque de rayon a cachée par un disque de rayon b dont le centre est à e
// (même formule que soleil.gd et la partie C++).
float recouvrement(float a, float b, float e) {
	if (e >= a + b) return 0.0;
	if (e <= b - a) return 1.0;
	if (e <= a - b) return (b * b) / (a * a);
	float a2 = a * a;
	float b2 = b * b;
	float u = clamp((e * e + a2 - b2) / (2.0 * e * a), -1.0, 1.0);
	float w = clamp((e * e + b2 - a2) / (2.0 * e * b), -1.0, 1.0);
	float aire = a2 * acos(u) + b2 * acos(w)
		- 0.5 * sqrt(max((-e + a + b) * (e + a - b) * (e - a + b) * (e + a + b), 0.0));
	return clamp(aire / (PI * a2), 0.0, 1.0);
}

float part_soleil(vec3 p) {
	if (occulteur.w <= 0.0) return 1.0;
	vec3 v = occulteur.xyz - p;
	float dc = length(v);
	if (dc <= occulteur.w) return 0.0;
	vec3 vn = v / dc;
	// Angle entre l'astre et le Soleil, calculé par atan2 : précis même pour de tout petits angles.
	float e = atan(length(cross(vn, soleil_direction)), dot(vn, soleil_direction));
	float b = asin(min(occulteur.w / dc, 1.0));
	float a = soleil_rayon_angle;
	if (e >= a + b) return 1.0;
	return 1.0 - recouvrement(a, b, e);
}

// Profondeur « logarithmique » : de 5 cm à des milliers de km sans que les montagnes lointaines se
// mélangent (la profondeur normale n'a pas assez de précision si loin).
uniform float profondeur_pres = 0.05;
uniform float profondeur_loin = 1.0e7;

void vertex() {
	int k = int(UV.y);
	bool jupe = k >= 64;
	if (jupe) {
		k -= 64;
	}
	int place = INSTANCE_ID;
	vec3 depart = texelFetch(coins, ivec2(k * 2, place), 0).xyz;
	vec3 cible = texelFetch(coins, ivec2(k * 2 + 1, place), 0).xyz;
	glisse = smoothstep(0.0, 1.0, clamp((maintenant - INSTANCE_CUSTOM.x) / duree_glissement, 0.0, 1.0));
	vec3 local = mix(depart, cible, glisse);
	mat3 rotation = mat3(MODEL_MATRIX);
	vec3 p = (MODEL_MATRIX * vec4(local, 1.0)).xyz;
	if (jupe) {
		// Le mur descend vers le centre de la planète.
		p -= normalize(p - centre_planete) * INSTANCE_CUSTOM.y;
	}
	pos_monde = p;
	vec3 c0 = texelFetch(rayons, ivec2(k * 3, place), 0).rgb;
	vec3 c1 = texelFetch(rayons, ivec2(k * 3 + 1, place), 0).rgb;
	albedo_v = mix(c0 * c0, c1 * c1, glisse);   // couleurs rangées par leur racine carrée
	direction_v = rotation * (texelFetch(rayons, ivec2(k * 3 + 2, place), 0).xyz * 2.0 - 1.0);
	// Halo de l'œil calculé aux coins (il varie lentement à l'échelle d'un rayon de 8 pixels) :
	// beaucoup moins de calcul par pixel pour la petite carte graphique du PC.
	voile_v = oeil_voile(normalize(p - CAMERA_POSITION_WORLD), TIME);
	// L'ombre d'une éclipse varie lentement à l'échelle d'un rayon : calculée aux coins.
	soleil_visible = part_soleil(p);
	vec4 vue = VIEW_MATRIX * vec4(p, 1.0);
	profondeur = -vue.z;
	POSITION = PROJECTION_MATRIX * vue;
}

void fragment() {
	vec3 albedo = albedo_v;
	vec3 dir = direction_v;
	float longueur = clamp(length(dir), 1e-4, 1.0);
	vec3 n = dir / longueur;
	// Direction moyenne non normalisée : plus elle est courte, plus la surface est rugueuse plus
	// finement qu'un rayon (ses petites faces regardent dans un cône autour de la direction moyenne).
	// Un cône de demi-angle b donne une moyenne de longueur (1 + cos b) / 2. Une petite face reçoit
	// cos(angle avec le Soleil) si elle le voit, 0 sinon : en moyenne sur le cône, la lumière déborde
	// un peu au-delà de la ligne jour/nuit, mais jamais jusqu'au côté nuit.
	float sb = sqrt(max(1.0 - pow(2.0 * longueur - 1.0, 2.0), 0.0));   // sinus de b
	float cs = dot(n, soleil_direction);
	float direct = cs > sb ? cs : (cs < -sb ? 0.0 : (cs + sb) * (cs + sb) / (4.0 * sb + 1e-6));
	// Sol mat : luminance = albédo × éclairement × cos / π.
	vec3 l = albedo * (soleil_couleur * soleil_eclairement * direct * soleil_visible + lux_fond) / PI;
	ALBEDO = oeil_vers_ecran(l + voile_v, FRAGCOORD.xy, TIME);
	DEPTH = 1.0 - clamp(log2(max(profondeur, profondeur_pres) / profondeur_pres) / log2(profondeur_loin / profondeur_pres), 0.0, 1.0);
}
