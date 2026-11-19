// L'ATMOSPHÈRE de la planète dans le système de lumière (programme de départ : atmosphère).
// Les molécules de l'air (diffusion de Rayleigh, en 1/λ⁴ : le bleu est diffusé 5,7 fois plus que le
// rouge) et les fines poussières (diffusion de Mie, surtout vers l'avant : le halo blanc autour du
// Soleil) renvoient une partie de la lumière du Soleil vers l'œil : c'est le ciel. La même lumière
// manque ensuite au rayon direct : le Soleil rougit quand il traverse beaucoup d'air (coucher), et
// tout ce qu'on voit à travers l'air (sol lointain, lune, étoiles) est atténué et voilé de bleu.
// L'ozone absorbe un peu de jaune-orange : c'est lui qui garde le ciel bleu au crépuscule.
// Valeurs de l'air terrestre (Bruneton 2017, Hillaire 2020), en vraies unités : l'éclairement du Soleil
// (lux) × diffusion (1/m) × loi de phase (1/stéradian) × longueur (m) = luminance (cd/m²).
// Diffusion simple (une seule déviation) : le calcul est assez léger pour le PC.
// La même chose est calculée par le processeur (scripts/lumiere/atmosphere_lumiere.gd) pour l'œil
// (posemètre) et la lumière que reçoit le vaisseau.

global uniform vec3 atmo_centre;      // centre de la planète (repère d'affichage)
global uniform float atmo_rayon;      // m, rayon de la planète au niveau de la mer ; 0 = pas d'atmosphère
global uniform float atmo_soleil_part; // part du Soleil que la lune ne cache pas, vue du vaisseau (éclipse)

const vec3 ATMO_RAYLEIGH = vec3(5.802e-6, 13.558e-6, 33.1e-6);   // 1/m au niveau de la mer
const float ATMO_H_RAYLEIGH = 8000.0;                             // m
const float ATMO_MIE = 3.996e-6;                                  // diffusion, 1/m
const float ATMO_MIE_EXT = 4.40e-6;                               // diffusion + absorption
const float ATMO_H_MIE = 1200.0;
const float ATMO_G_MIE = 0.8;                                     // vers l'avant
const vec3 ATMO_OZONE = vec3(0.650e-6, 1.881e-6, 0.085e-6);       // absorption au cœur de la couche
const float ATMO_OZONE_CENTRE = 25000.0;
const float ATMO_OZONE_DEMI = 15000.0;
const float ATMO_HAUT = 100000.0;                                 // m : plus haut, l'air ne compte plus

// exp(y²)·erfc(y) pour y ≥ 0 (Abramowitz et Stegun jusqu'à 3, puis développement asymptotique).
float atmo_erfcx(float y) {
	if (y < 3.0) {
		float t = 1.0 / (1.0 + 0.3275911 * y);
		return t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
	}
	float u = 1.0 / (2.0 * y * y);
	return (1.0 - u + 3.0 * u * u - 15.0 * u * u * u) / (1.7724539 * y);
}

// Fonction de Chapman : quantité d'air traversée de la hauteur h (en hauteurs d'échelle) jusqu'à
// l'espace, sous le cosinus mu avec la verticale, rapportée à une colonne verticale depuis le niveau
// de la mer (x = rayon de la planète / hauteur d'échelle). Même formule que atmosphere_lumiere.gd.
float atmo_chapman(float x, float h, float mu) {
	float gx = x + h;
	if (mu >= 0.0) {
		return sqrt(1.5707963 * gx) * atmo_erfcx(sqrt(0.5 * gx) * mu) * exp(-h);
	}
	float x0 = sqrt(max(1.0 - mu * mu, 0.0)) * gx;
	return 2.0 * sqrt(1.5707963 * x0) * exp(x - x0) - sqrt(1.5707963 * gx) * atmo_erfcx(sqrt(0.5 * gx) * -mu) * exp(-h);
}

// Ozone au-dessus de l'altitude z (m), en mètres « au cœur de la couche ».
float atmo_ozone_dessus(float z) {
	float a = ATMO_OZONE_CENTRE - ATMO_OZONE_DEMI;
	float b = ATMO_OZONE_CENTRE + ATMO_OZONE_DEMI;
	if (z >= b) return 0.0;
	float total = ATMO_OZONE_DEMI;   // aire du triangle
	if (z <= a) return total;
	if (z >= ATMO_OZONE_CENTRE) {
		float u = (b - z) / ATMO_OZONE_DEMI;
		return 0.5 * ATMO_OZONE_DEMI * u * u;
	}
	float u = (z - a) / ATMO_OZONE_DEMI;
	return total - 0.5 * ATMO_OZONE_DEMI * u * u;
}

// Épaisseur optique (sans unité, par couleur) de p (distance r au centre) jusqu'à l'espace dans la
// direction de cosinus mu avec la verticale. Derrière la planète, elle devient très grande (nuit).
vec3 atmo_epaisseur(float r, float mu) {
	float z = max(r - atmo_rayon, 0.0);
	float ch_r = atmo_chapman(atmo_rayon / ATMO_H_RAYLEIGH, z / ATMO_H_RAYLEIGH, mu);
	float ch_m = atmo_chapman(atmo_rayon / ATMO_H_MIE, z / ATMO_H_MIE, mu);
	// ozone : sa colonne verticale × l'allongement du chemin de l'air (celui de Rayleigh)
	float masse_air = ch_r / max(exp(-z / ATMO_H_RAYLEIGH), 1e-30);
	return ATMO_RAYLEIGH * (ATMO_H_RAYLEIGH * ch_r) + vec3(ATMO_MIE_EXT * ATMO_H_MIE * ch_m)
		+ ATMO_OZONE * (atmo_ozone_dessus(z) * min(masse_air, 40.0));
}

// Part de la lumière du Soleil (direction s) qui arrive jusqu'au point p (repère d'affichage).
vec3 atmo_transmission_soleil(vec3 p, vec3 s) {
	if (atmo_rayon <= 0.0) return vec3(1.0);
	vec3 q = p - atmo_centre;
	float r = length(q);
	if (r > atmo_rayon + ATMO_HAUT) return vec3(1.0);
	return exp(-atmo_epaisseur(r, dot(q, s) / r));
}

float atmo_phase_rayleigh(float c) {
	return 3.0 / (16.0 * PI) * (1.0 + c * c);
}

float atmo_phase_mie(float c) {
	// Cornette-Shanks (forme normalisée de Henyey-Greenstein)
	float g = ATMO_G_MIE;
	float g2 = g * g;
	return 3.0 / (8.0 * PI) * (1.0 - g2) * (1.0 + c * c) / ((2.0 + g2) * pow(max(1.0 + g2 - 2.0 * g * c, 1e-6), 1.5));
}

// Un morceau du chemin, de ta à tb, en m pas plus fins du côté où l'air est le plus épais
// (vers_b = vrai : pas fins vers tb). Ajoute la lumière diffusée à somme et l'épaisseur traversée à tau.
void atmo_morceau(vec3 q, vec3 d, vec3 s, float ta, float tb, int m, bool vers_b, float ph_r, float ph_m,
		inout vec3 tau, inout vec3 somme) {
	float l = tb - ta;
	for (int i = 0; i < m; i++) {
		float k0 = float(i) / float(m);
		float k1 = float(i + 1) / float(m);
		float u0 = vers_b ? 1.0 - (1.0 - k0) * (1.0 - k0) : k0 * k0;
		float u1 = vers_b ? 1.0 - (1.0 - k1) * (1.0 - k1) : k1 * k1;
		float pas = l * (u1 - u0);
		vec3 p = q + d * (ta + l * 0.5 * (u0 + u1));
		float r = length(p);
		float z = max(r - atmo_rayon, 0.0);
		float dr = exp(-z / ATMO_H_RAYLEIGH);
		float dm = exp(-z / ATMO_H_MIE);
		float dz = max(1.0 - abs(z - ATMO_OZONE_CENTRE) / ATMO_OZONE_DEMI, 0.0);
		vec3 ext = ATMO_RAYLEIGH * dr + vec3(ATMO_MIE_EXT * dm) + ATMO_OZONE * dz;
		// transmission jusqu'au milieu du morceau, puis on ajoute tout le morceau
		vec3 tau_milieu = tau + ext * (0.5 * pas);
		tau += ext * pas;
		vec3 vers_soleil = exp(-atmo_epaisseur(r, dot(p, s) / r));
		somme += exp(-tau_milieu) * vers_soleil * (ATMO_RAYLEIGH * (dr * ph_r) + vec3(ATMO_MIE * dm * ph_m)) * pas;
	}
}

// Chemin de la lumière de o vers o + d·t, t de 0 à t_max (d de longueur 1), s = vers le Soleil,
// n = nombre de points de calcul. Renvoie la lumière que l'air ajoute (luminance par lux du Soleil,
// rgb) ; transmission = part de la lumière du bout du chemin qui arrive à o.
// Les points sont serrés là où l'air est le plus épais (le point le plus bas du chemin) : une coquille
// d'air de 8 km d'épaisseur vue de loin reste bien calculée avec peu de points.
vec3 atmo_chemin(vec3 o, vec3 d, float t_max, vec3 s, int n, out vec3 transmission) {
	transmission = vec3(1.0);
	if (atmo_rayon <= 0.0) return vec3(0.0);
	vec3 q = o - atmo_centre;
	float rh = atmo_rayon + ATMO_HAUT;
	// entrée et sortie de la coquille d'air (sphère du haut de l'atmosphère)
	float b = dot(q, d);
	float c = dot(q, q) - rh * rh;
	float delta = b * b - c;
	if (delta <= 0.0) return vec3(0.0);
	float sq = sqrt(delta);
	float t0 = max(-b - sq, 0.0);
	float t1 = min(-b + sq, t_max);
	// le sol coupe le chemin (rayon qui file vers la planète)
	float cs = dot(q, q) - atmo_rayon * atmo_rayon;
	float ds = b * b - cs;
	if (ds > 0.0 && cs > 0.0) {
		float ts = -b - sqrt(ds);
		if (ts > 0.0) t1 = min(t1, ts);
	}
	if (t1 <= t0) return vec3(0.0);
	float mu_s = dot(d, s);
	float ph_r = atmo_phase_rayleigh(mu_s);
	float ph_m = atmo_phase_mie(mu_s);
	vec3 tau = vec3(0.0);
	vec3 somme = vec3(0.0);
	float tp = clamp(-b, t0, t1);   // point le plus bas du chemin
	float part = (tp - t0) / (t1 - t0);
	int na = part < 0.02 ? 0 : (part > 0.98 ? n : n / 2);
	if (na > 0) atmo_morceau(q, d, s, t0, tp, na, true, ph_r, ph_m, tau, somme);
	if (n - na > 0) atmo_morceau(q, d, s, tp, t1, n - na, false, ph_r, ph_m, tau, somme);
	transmission = exp(-tau);
	return somme;
}

// Éclairement du ciel sur une surface tournée vers le haut au point p (en part de l'éclairement du
// Soleil hors de l'atmosphère, rgb). Simplification : l'air au-dessus de p a diffusé la part
// (1 − transmission) de la lumière du Soleil ; à peu près autant descend vers le sol (diffusions
// multiples et sol compris). Plus un peu de lumière de crépuscule quand le Soleil vient de se coucher.
vec3 atmo_eclairement_ciel(vec3 p, vec3 s) {
	if (atmo_rayon <= 0.0) return vec3(0.0);
	vec3 q = p - atmo_centre;
	float r = length(q);
	if (r > atmo_rayon + ATMO_HAUT) return vec3(0.0);
	float mu = dot(q, s) / r;
	vec3 t_s = exp(-atmo_epaisseur(r, mu));
	// part de l'air au-dessus de p (il n'y a plus de ciel en haut de l'atmosphère)
	float air = exp(-max(r - atmo_rayon, 0.0) / ATMO_H_RAYLEIGH);
	return ((1.0 - t_s) * max(mu, 0.0) + vec3(0.6, 0.75, 1.0) * (0.003 * smoothstep(-0.2, 0.0, mu))) * air;
}
