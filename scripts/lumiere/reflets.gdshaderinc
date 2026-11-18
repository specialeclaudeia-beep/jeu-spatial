// Les reflets (étape 9, scripts/lumiere/reflets.gd) : loi du miroir + loi de Fresnel.
// À inclure APRÈS oeil.gdshaderinc et compagnon.gdshaderinc. Deux cartes en longitude-latitude,
// prémultipliées (rgb = luminance × part couverte, a = part couverte), nombres à virgule :
//   reflets_ciel    : la planète (et la lune) vues de l'œil, tirées des rayons (repère d'affichage) ;
//   reflets_cockpit : l'intérieur du vaisseau vu de la tête, tiré des rayons lancés sur ses formes
//                     (repère du vaisseau ; reflets_base passe du vaisseau à l'affichage).
// Le Soleil et l'étoile compagne ne sont pas dans les cartes : leur disque est calculé exactement ici.

global uniform sampler2D reflets_ciel : filter_linear_mipmap, repeat_enable;
global uniform sampler2D reflets_cockpit : filter_linear_mipmap, repeat_enable;
global uniform mat3 reflets_base;            // repère du vaisseau → repère d'affichage
global uniform float reflets_rayon_sonde;    // m : boule autour de la tête où l'on « pose » la sonde
global uniform float reflets_actifs;         // 0 = pas de reflets (avant le premier calcul)

vec2 reflets_uv(vec3 d) {
	return vec2(atan(d.x, -d.z) / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
}

// L'intérieur du cockpit vu le long du rayon réfléchi r qui part du point p (tous deux dans le repère
// d'affichage, la tête est à l'origine). La sonde a été prise depuis la tête : on cherche où le rayon
// sort de la boule de rayon reflets_rayon_sonde, et on lit la sonde dans cette direction (correction de
// parallaxe). Rend rgb prémultiplié + part du rayon qui touche le cockpit.
vec4 reflets_cockpit_vu(vec3 p, vec3 r, float flou) {
	if (reflets_actifs <= 0.0) return vec4(0.0);
	mat3 inv = transpose(reflets_base);
	vec3 q = inv * p;
	vec3 rl = inv * r;
	float b = dot(q, rl);
	float c = dot(q, q) - reflets_rayon_sonde * reflets_rayon_sonde;
	float disc = b * b - c;
	vec3 d = rl;
	if (c < 0.0) {
		d = normalize(q + rl * (-b + sqrt(max(disc, 0.0))));
	} else if (b > 0.0) {
		return vec4(0.0);   // point loin de la tête et rayon qui part vers l'extérieur (vue de dehors)
	}
	return textureLod(reflets_cockpit, reflets_uv(d), flou * 4.0);
}

// La planète vue dans la direction r (affichage), rgb prémultiplié + part couverte.
vec4 reflets_ciel_vu(vec3 r, float flou) {
	if (reflets_actifs <= 0.0) return vec4(0.0);
	return textureLod(reflets_ciel, reflets_uv(r), flou * 5.0);
}

// Disque d'une étoile (direction s, rayon apparent a) vu dans la direction r, adouci sur un pixel
// (ou sur l'angle `flou` pour une surface rugueuse : la même lumière étalée sur une tache plus grande).
float reflets_disque(vec3 r, vec3 s, float a, float flou) {
	float th = atan(length(cross(r, s)), dot(r, s));
	float l = max(a + flou, oeil_pixel_angle);
	float tache = clamp((l - th) / max(oeil_pixel_angle, 1e-6) + 0.5, 0.0, 1.0);
	return tache * (a * a) / (l * l);   // même lumière totale sur une tache plus grande
}

// Luminance (cd/m²) de tout ce qu'on voit dans la direction r depuis le point p : cockpit, sinon la
// planète, sinon le Soleil et l'étoile compagne. vis_soleil = part du Soleil visible depuis le vaisseau.
// avec_etoiles = 0 : sans les disques (les objets ont déjà le reflet du Soleil dans light()).
vec3 reflets_luminance(vec3 p, vec3 r, float flou_angle, float vis_soleil, float vis_compagne, float avec_etoiles) {
	float flou = clamp(flou_angle / 1.2, 0.0, 1.0);
	vec4 ck = reflets_cockpit_vu(p, r, flou);
	vec4 cl = reflets_ciel_vu(r, flou);
	vec3 etoiles = avec_etoiles * soleil_couleur * soleil_luminance * 0.8 * reflets_disque(r, soleil_direction, soleil_rayon_angle, flou_angle) * vis_soleil;
	if (compagnon_eclairement > 0.0 && avec_etoiles > 0.0) {
		etoiles += compagnon_couleur * compagnon_luminance * vis_compagne
			* reflets_disque(r, compagnon_direction, compagnon_rayon_angle, flou_angle);
	}
	vec3 dehors = cl.rgb + (1.0 - clamp(cl.a, 0.0, 1.0)) * etoiles;
	return ck.rgb + (1.0 - clamp(ck.a, 0.0, 1.0)) * dehors;
}

// Rebond de la lumière dans le cockpit (étape 9, une partie de Q38) : lux reçus au point p de normale n
// venant des surfaces du cockpit (la sonde, très floue, vue dans la direction n : moyenne sur une
// demi-boule environ). Seulement près de la tête (la sonde a été prise de là) : nul au-delà de 4 m.
vec3 reflets_rebond_cockpit(vec3 p, vec3 n) {
	float pres = clamp((4.0 - length(p)) / 2.0, 0.0, 1.0);
	if (pres <= 0.0) return vec3(0.0);
	return PI * reflets_cockpit_vu(p, n, 0.75).rgb * pres;
}

// Part de la lumière renvoyée par une surface rugueuse, moyennée sur ses petites faces (approximation
// publiée par Karis, 2014, de l'intégrale de la loi de Fresnel sur une surface GGX). f0 = reflet de face.
vec3 reflets_part(vec3 f0, float rugosite, float nv) {
	vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
	vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
	vec4 r = rugosite * c0 + c1;
	float a004 = min(r.x * r.x, exp2(-9.28 * nv)) * r.x + r.y;
	vec2 ab = vec2(-1.04, 1.04) * a004 + r.zw;
	return f0 * ab.x + ab.y;
}

// Retrouve, approximativement, la luminance (cd/m²) d'une couleur d'écran déjà passée par l'œil
// (inverse de la vision de jour d'oeil_vers_ecran). Sert à la verrière : elle doit laisser passer 92 %
// de ce qu'il y a derrière elle, pas 100 %.
vec3 reflets_ecran_vers_luminance(vec3 e) {
	vec3 lin = mix(e / 12.92, pow((e + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), e));
	lin = clamp(lin, 0.0, 0.995);
	vec3 x = lin / (1.0 - lin);
	return x / max(oeil_gain, 1e-12) / max(oeil_filtre, vec3(1e-4));
}
