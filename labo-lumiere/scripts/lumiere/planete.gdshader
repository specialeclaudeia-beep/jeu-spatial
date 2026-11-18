// Dessin de la planète en rayons (étape 4, temps 4 « dessiner »).
// Chaque copie du morceau type (MultiMesh) est un triangle choisi par la partie C++ (ArbreLumiere).
// - La FORME vient de la texture des coins : pour chaque morceau (une ligne), 45 coins × 2 positions
//   (départ = forme du parent, visée = vrai relief), par rapport au centre du morceau. Juste après une
//   coupe, le morceau glisse en douceur de la forme du parent vers la sienne : pas de saut à l'écran.
// - La COULEUR vient de la texture des rayons : 3 texels par rayon (couleur de départ, couleur visée,
//   direction moyenne de la surface dont la longueur dit l'étalement).
// - La lumière directe du Soleil est calculée ici, à chaque pixel (décision Q43 = version B), en vraies
//   unités (cd/m²), puis passe par l'œil du pilote.
// Données par copie (INSTANCE_CUSTOM) : x = heure d'arrivée, y = profondeur des jupes, z = taille d'un rayon.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

#include "res://scripts/lumiere/oeil.gdshaderinc"

uniform sampler2D coins : filter_nearest;      // RGBA 32 bits flottants, 90 × places
uniform sampler2D rayons : filter_nearest;     // RGBA 8 bits, 768 × (places / 4)
uniform float maintenant = 0.0;                // horloge du labo (s), la même que la partie C++
uniform float duree_glissement = 0.5;          // s
uniform float lux_fond = 2.0e-4;               // lumière des étoiles et du fond du ciel (lux)
uniform vec3 centre_planete = vec3(0.0);       // centre de la planète dans le monde (repère de l'affichage)

varying flat int indice;
varying float glisse;
varying vec3 pos_monde;
varying flat mat3 rotation;

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
	rotation = mat3(MODEL_MATRIX);
	vec3 p = (MODEL_MATRIX * vec4(local, 1.0)).xyz;
	if (jupe) {
		// Le mur descend vers le centre de la planète.
		p -= normalize(p - centre_planete) * INSTANCE_CUSTOM.y;
	}
	pos_monde = p;
	indice = INSTANCE_ID * 64 + int(UV.x);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
}

void fragment() {
	ivec2 t = ivec2((indice % 256) * 3, indice / 256);
	vec3 c0 = texelFetch(rayons, t, 0).rgb;
	vec3 c1 = texelFetch(rayons, t + ivec2(1, 0), 0).rgb;
	vec3 albedo = mix(c0 * c0, c1 * c1, glisse);   // couleurs rangées par leur racine carrée
	vec3 dir = rotation * (texelFetch(rayons, t + ivec2(2, 0), 0).xyz * 2.0 - 1.0);
	float longueur = clamp(length(dir), 1e-4, 1.0);
	vec3 n = dir / longueur;
	// Direction moyenne non normalisée : plus elle est courte, plus la lumière est « étalée »
	// (la surface est rugueuse plus finement qu'un rayon : une partie regarde ailleurs).
	float etalement = 1.0 - longueur;
	float cs = dot(n, soleil_direction);
	float direct = max(cs, 0.0);
	direct = mix(direct, 0.5 * (cs + 1.0) * 0.6, etalement);
	// Sol mat : luminance = albédo × éclairement × cos / π.
	vec3 l = albedo * (soleil_couleur * soleil_eclairement * direct + lux_fond) / PI;
	vec3 vue = normalize(pos_monde - CAMERA_POSITION_WORLD);
	ALBEDO = oeil_vers_ecran(l + oeil_voile(vue, TIME), FRAGCOORD.xy, TIME);
}
