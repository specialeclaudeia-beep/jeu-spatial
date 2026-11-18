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

varying vec3 albedo_v;
varying vec3 direction_v;
varying float glisse;
varying vec3 pos_monde;
varying float profondeur;

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
	vec3 l = albedo * (soleil_couleur * soleil_eclairement * direct + lux_fond) / PI;
	vec3 vue = normalize(pos_monde - CAMERA_POSITION_WORLD);
	ALBEDO = oeil_vers_ecran(l + oeil_voile(vue, TIME), FRAGCOORD.xy, TIME);
	DEPTH = 1.0 - clamp(log2(max(profondeur, profondeur_pres) / profondeur_pres) / log2(profondeur_loin / profondeur_pres), 0.0, 1.0);
}
