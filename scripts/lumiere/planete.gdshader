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
// - Étape 7 : 2 texels de plus par coin, la hauteur de l'HORIZON (départ et visée) vers l'est, le nord,
//   l'ouest et le sud. Elle ne dépend pas du Soleil : on compare ici la hauteur de l'étoile à celle de
//   l'horizon dans sa direction → ombres du relief proche et des cailloux, qui suivent le Soleil.
// - Einstein A2 : à très grande vitesse (oeil_vitesse, fraction de c), chaque coin est vu là où sa lumière
//   arrive vraiment dans l'œil qui bouge (aberration : tout se resserre vers l'avant), à la distance où
//   cette lumière est partie (× D), avec sa couleur et son éclat changés par l'effet Doppler (vers le
//   bleu et plus brillant devant, vers le rouge et plus sombre derrière : l'éclat vers l'avant).
//   L'éclairage (Soleil, ombres, éclipses) reste calculé là où la planète est vraiment : c'est la lumière
//   déjà renvoyée par le sol qui change en chemin vers l'œil. Vitesse nulle : rien ne change.
// Données par copie (INSTANCE_CUSTOM) : x = heure d'arrivée, y = profondeur des jupes, z = taille d'un rayon.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

#include "res://scripts/lumiere/oeil.gdshaderinc"
#include "res://scripts/lumiere/compagnon.gdshaderinc"
#include "res://scripts/lumiere/lampes.gdshaderinc"
#include "res://scripts/lumiere/etoiles.gdshaderinc"

uniform sampler2D coins : filter_nearest;      // RGBA 32 bits flottants, 90 × places
uniform sampler2D rayons : filter_nearest;     // RGBA 8 bits, 225 × places (5 texels par coin)
uniform float maintenant = 0.0;                // horloge du labo (s), la même que la partie C++
uniform float duree_glissement = 0.5;          // s
uniform float lux_fond = 2.0e-4;               // lumière des étoiles et du fond du ciel (lux)
uniform vec3 centre_planete = vec3(0.0);       // centre de la planète dans le monde (repère de l'affichage)
// Étape 5, éclipses : un astre (centre dans le repère de l'affichage, rayon en w) qui peut cacher
// le Soleil. w = 0 : aucun. Chaque coin reçoit la part du disque solaire qu'il voit encore :
// ombre (rien), pénombre (une partie), comme dans une vraie éclipse.
uniform vec4 occulteur = vec4(0.0);
// Étape 6 : rayon de l'astre lui-même (niveau 0). Il cache le Soleil et l'étoile compagne quand elles
// sont sous l'horizon : sans cela, une pente tournée vers elles s'éclairait en pleine nuit.
uniform float rayon_corps = 0.0;

varying vec3 albedo_v;
varying vec3 direction_v;
varying float glisse;
varying vec3 pos_monde;
varying float profondeur;
varying vec3 voile_v;
varying float soleil_visible;
varying float compagnon_visible;
varying vec4 horizon_v;          // hauteur de l'horizon (rad) vers l'est, le nord, l'ouest, le sud
varying vec3 soleil_lieu;        // Soleil dans le repère du lieu : (sinus de sa hauteur, vers l'est, vers le nord)
varying vec3 compagnon_lieu;
varying vec3 doppler_v;          // Einstein A2 : facteur Doppler sur la lumière renvoyée (rouge, vert, bleu)

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

// Part visible du disque d'une étoile (direction dir, rayon apparent a) depuis le point p, derrière
// une boule (centre c, rayon r).
float part_derriere(vec3 p, vec3 dir, float a, vec3 c, float r) {
	vec3 v = c - p;
	float dc = length(v);
	if (dc <= r) return 0.0;
	vec3 vn = v / dc;
	// Angle entre l'astre et le Soleil, calculé par atan2 : précis même pour de tout petits angles.
	float e = atan(length(cross(vn, dir)), dot(vn, dir));
	float b = asin(min(r / dc, 1.0));
	if (e >= a + b) return 1.0;
	return 1.0 - recouvrement(a, b, e);
}

// Part visible du disque d'une étoile depuis le point p : cachée par l'astre lui-même (sous l'horizon)
// et par l'occulteur (éclipse).
float part_etoile(vec3 p, vec3 dir, float a) {
	float part = 1.0;
	if (rayon_corps > 0.0) {
		vec3 q = p - centre_planete;
		float dq = length(q);
		if (dot(q, dir) < 0.3 * dq) {
			part = part_derriere(p, dir, a, centre_planete, min(rayon_corps, dq * 0.9999));
		}
	}
	if (occulteur.w > 0.0 && part > 0.0) {
		part *= part_derriere(p, dir, a, occulteur.xyz, occulteur.w);
	}
	return part;
}

// Étape 7 : hauteur codée de l'horizon → radians (même code que la partie C++).
vec4 decode_horizon(vec4 c) {
	vec4 x = c * 2.0 - 1.0;
	return sign(x) * x * x * (PI * 0.5);
}

// Étoile dans le repère du lieu (up = verticale, t1 = est, t2 = nord ; le même que la partie C++).
vec3 vers_lieu(vec3 s, vec3 up, vec3 t1, vec3 t2) {
	return vec3(dot(s, up), dot(s, t1), dot(s, t2));
}

// Part du disque d'une étoile au-dessus de l'horizon proche (même formule que la partie C++).
float part_horizon(vec4 h, vec3 l, float a) {
	float n = length(l.yz);
	float hz = -PI * 0.5;
	if (n > 1e-6) {
		vec2 c = l.yz / n;
		vec2 p = max(c, 0.0);
		vec2 m = max(-c, 0.0);
		hz = h.x * p.x * p.x + h.y * p.y * p.y + h.z * m.x * m.x + h.w * m.y * m.y;
	}
	float el = asin(clamp(l.x, -1.0, 1.0));
	return clamp((el - hz) / (2.0 * (a + 0.005)) + 0.5, 0.0, 1.0);
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
	vec3 c0 = texelFetch(rayons, ivec2(k * 5, place), 0).rgb;
	vec3 c1 = texelFetch(rayons, ivec2(k * 5 + 1, place), 0).rgb;
	albedo_v = mix(c0 * c0, c1 * c1, glisse);   // couleurs rangées par leur racine carrée
	direction_v = rotation * (texelFetch(rayons, ivec2(k * 5 + 2, place), 0).xyz * 2.0 - 1.0);
	// Étape 7 : horizon du coin et étoiles dans le repère du lieu (axe Y de l'astre = rotation[1]).
	vec4 h0 = decode_horizon(texelFetch(rayons, ivec2(k * 5 + 3, place), 0));
	vec4 h1 = decode_horizon(texelFetch(rayons, ivec2(k * 5 + 4, place), 0));
	horizon_v = mix(h0, h1, glisse);
	vec3 up = normalize(p - centre_planete);
	vec3 t1 = cross(rotation[1], up);
	t1 = length(t1) > 1e-6 ? normalize(t1) : normalize(cross(rotation[0], up));
	vec3 t2 = cross(up, t1);
	soleil_lieu = vers_lieu(soleil_direction, up, t1, t2);
	compagnon_lieu = vers_lieu(compagnon_direction, up, t1, t2);
	// L'ombre d'une éclipse varie lentement à l'échelle d'un rayon : calculée aux coins.
	soleil_visible = part_etoile(p, soleil_direction, soleil_rayon_angle);
	compagnon_visible = compagnon_eclairement > 0.0 ? part_etoile(p, compagnon_direction, compagnon_rayon_angle) : 0.0;
	// Einstein A2 : où l'œil qui va très vite voit ce coin, et le Doppler de sa lumière (reflet du Soleil,
	// corps noir à 5 772 K).
	vec3 vu = p;
	doppler_v = vec3(1.0);
	if (dot(oeil_vitesse, oeil_vitesse) > 0.0) {
		vec3 r = p - CAMERA_POSITION_WORLD;
		float dist = length(r);
		if (dist > 0.0) {
			vec4 ab = aberration(r / dist, oeil_vitesse);
			vu = CAMERA_POSITION_WORLD + ab.xyz * (dist * ab.w);
			doppler_v = doppler_surface(vec3(1.0), T_SOLEIL, ab.w);
		}
	}
	// Halo de l'œil calculé aux coins (il varie lentement à l'échelle d'un rayon de 8 pixels) :
	// beaucoup moins de calcul par pixel pour la petite carte graphique du PC.
	voile_v = oeil_voile(normalize(vu - CAMERA_POSITION_WORLD), TIME);
	vec4 vue = VIEW_MATRIX * vec4(vu, 1.0);
	profondeur = -vue.z;
	POSITION = PROJECTION_MATRIX * vue;
	// Étape 7 : la profondeur est écrite par le fragment (logarithmique) ; ici on met chaque point au
	// milieu de la boîte de vue, pour que la carte graphique ne coupe jamais le sol aux plans proche et
	// lointain de la caméra (l'œil peut être à 5 mm du sol et voir à 300 km). Seuls les points derrière
	// l'œil sont coupés (w < 0).
	POSITION.z = 0.0;
}

// Lumière moyenne d'un cône de petites faces (direction moyenne n, sinus du demi-angle sb) éclairé par
// une étoile dans la direction s.
float eclairage(vec3 n, float sb, vec3 s) {
	float cs = dot(n, s);
	return cs > sb ? cs : (cs < -sb ? 0.0 : (cs + sb) * (cs + sb) / (4.0 * sb + 1e-6));
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
	// Sol mat : luminance = albédo × éclairement × cos / π. Étape 6 : deux étoiles proches, leurs
	// lumières s'additionnent ; tout le reste du ciel (étoiles lointaines, Voie lactée) est regroupé
	// dans lux_fond.
	// Étape 7 : l'ombre du relief proche et des cailloux (horizon), à chaque pixel.
	vec3 e = soleil_couleur * soleil_eclairement * eclairage(n, sb, soleil_direction) * soleil_visible
		* part_horizon(horizon_v, soleil_lieu, soleil_rayon_angle);
	if (compagnon_eclairement > 0.0) {
		e += compagnon_couleur * compagnon_eclairement * eclairage(n, sb, compagnon_direction) * compagnon_visible
			* part_horizon(horizon_v, compagnon_lieu, compagnon_rayon_angle);
	}
	// Étape 8 : les lampes du vaisseau (projecteur) éclairent aussi le sol.
	e += lampes_eclairement(pos_monde, n);
	vec3 l = albedo * (e + lux_fond) / PI * doppler_v;
	ALBEDO = oeil_vers_ecran(l + voile_v, FRAGCOORD.xy, TIME);
	DEPTH = 1.0 - clamp(log2(max(profondeur, profondeur_pres) / profondeur_pres) / log2(profondeur_loin / profondeur_pres), 0.0, 1.0);
}
