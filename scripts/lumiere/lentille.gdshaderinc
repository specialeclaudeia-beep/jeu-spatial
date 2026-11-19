// Einstein B : la lumière courbée par un trou noir (voir scripts/physique/lentille.gd).
// La table est calculée une fois par image (l'œil est le même pour tous les pixels) :
//   ligne 0 : pour un rayon vu sous l'angle θ du trou noir (θ = ombre + (π − ombre)·x²), l'angle ψ
//             d'où vient vraiment sa lumière (négatif : de l'autre côté, après un demi-tour) ;
//   ligne 1 : pour une étoile à l'angle ψ = π·s² du trou noir, ses deux images (θ1, μ1, θ2, μ2),
//             μ = grossissement (rapport des surfaces : l'éclat d'un point est multiplié par μ).
//
// Einstein C : le même mécanisme sert au TROU DE VER (lentille.w = 2, voir scripts/physique/trou_de_ver.gd
// et la partie C++ TrouDeVer). Table de 512 × 4 :
//   ligne 0 : rayon vu dans la gorge (θ < θ_c, θ = θ_c·(1 − (1 − x)²)) → ψ dans le ciel d'en face ;
//   ligne 1 : rayon vu hors de la gorge (θ = θ_c + (π − θ_c)·x²) → ψ dans notre ciel ;
//   ligne 2 : étoile de notre ciel à ψ = π·s² → ses images hors de la gorge ;
//   ligne 3 : étoile du ciel d'en face (après la symétrie des bouches) → ses images dans la gorge.
// Le ciel d'en face est relié au nôtre par la symétrie des deux bouches : direction m ↦ m − 2(m·k)k
// (k = axe des bouches) ; un vaisseau qui passe le long de l'axe ressort sans tourner.
uniform vec4 lentille = vec4(0.0, 0.0, -1.0, 0.0);   // xyz = direction du trou, w = 1 trou noir, 2 trou de ver
uniform float lentille_ombre = 0.0;                  // rayon angulaire de l'ombre (rad) ; trou de ver : de la gorge
uniform vec3 trou_axe = vec3(0.0, 1.0, 0.0);         // axe des deux bouches (repère du ciel)
uniform vec4 trou_soleil = vec4(0.0, 1.0, 0.0, 0.0); // étoile principale d'en face : direction (ciel d'en face), rayon apparent
uniform vec4 trou_soleil_lum = vec4(0.0);            // sa couleur (rgb, luminance 1) et sa luminance (cd/m²)
uniform float trou_soleil_t = 5772.0;                // sa température (K), pour le Doppler
// Nombres à virgule de 32 bits, lus sans filtre (la petite carte graphique du PC ne sait pas filtrer
// ce format) : on fait nous-mêmes le mélange entre deux cases voisines.
uniform sampler2D lentille_table : filter_nearest, repeat_disable;
const float LENTILLE_POINTS = 512.0;

vec4 lentille_lire(float x, int ligne) {
	float f = clamp(x, 0.0, 1.0) * (LENTILLE_POINTS - 1.0);
	int i = min(int(floor(f)), int(LENTILLE_POINTS) - 2);
	return mix(texelFetch(lentille_table, ivec2(i, ligne), 0), texelFetch(lentille_table, ivec2(i + 1, ligne), 0), f - float(i));
}

vec3 trou_symetrie(vec3 m) {
	return m - 2.0 * dot(m, trou_axe) * trou_axe;
}

// Trou de ver : direction vue d → direction d'origine ; w = 1 de notre ciel, 2 du ciel d'en face.
vec4 trou_origine(vec3 d) {
	vec3 L = lentille.xyz;
	float th = atan(length(cross(L, d)), dot(d, L));
	vec3 e = d - dot(d, L) * L;
	float le = length(e);
	e = le > 1e-7 ? e / le : normalize(cross(L, abs(L.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	float tc = lentille_ombre;
	if (th < tc) {
		float x = 1.0 - sqrt(clamp(1.0 - th / max(tc, 1e-9), 0.0, 1.0));
		float psi = lentille_lire(x, 0).r;
		return vec4(trou_symetrie(normalize(cos(psi) * L + sin(psi) * e)), 2.0);
	}
	float x = sqrt(clamp((th - tc) / max(PI - tc, 1e-6), 0.0, 1.0));
	float psi = lentille_lire(x, 1).r;
	return vec4(normalize(cos(psi) * L + sin(psi) * e), 1.0);
}

// Trou de ver : étoile (direction n, la même vue des deux bouches : elle est très loin) → son image de
// notre côté (secondaire = faux) ou son image dans la gorge, venue du ciel d'en face (secondaire = vrai).
vec4 trou_image(vec3 n, bool secondaire) {
	vec3 L = lentille.xyz;
	vec3 m = secondaire ? trou_symetrie(n) : n;
	float psi = atan(length(cross(L, m)), dot(m, L));
	vec3 e = m - dot(m, L) * L;
	float le = length(e);
	e = le > 1e-7 ? e / le : normalize(cross(L, abs(L.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec4 t = lentille_lire(sqrt(clamp(psi / PI, 0.0, 1.0)), secondaire ? 3 : 2);
	return vec4(normalize(cos(t.r) * L + sin(t.r) * e), t.g);
}

// Direction vue d → direction d'où vient sa lumière (w = 0 : dans l'ombre, rien ne vient d'ici ;
// w = 2 : elle vient du ciel d'en face, à travers un trou de ver).
vec4 lentille_origine(vec3 d) {
	if (lentille.w < 0.5) {
		return vec4(d, 1.0);
	}
	if (lentille.w > 1.5) {
		return trou_origine(d);
	}
	vec3 L = lentille.xyz;
	vec3 x = cross(L, d);
	float th = atan(length(x), dot(d, L));
	if (th < lentille_ombre) {
		return vec4(0.0);
	}
	vec3 e = d - dot(d, L) * L;
	float le = length(e);
	if (le < 1e-7) {
		return vec4(d, 1.0);
	}
	e /= le;
	float xs = sqrt(clamp((th - lentille_ombre) / max(PI - lentille_ombre, 1e-6), 0.0, 1.0));
	float psi = lentille_lire(xs, 0).r;
	return vec4(normalize(cos(psi) * L + sin(psi) * e), 1.0);
}

// Étoile dans la direction n → direction de son image (principale, ou secondaire = de l'autre côté du
// trou noir) et son grossissement (w ; 0 = pas d'image).
vec4 lentille_image(vec3 n, bool secondaire) {
	if (lentille.w < 0.5) {
		return vec4(n, secondaire ? 0.0 : 1.0);
	}
	if (lentille.w > 1.5) {
		return trou_image(n, secondaire);
	}
	vec3 L = lentille.xyz;
	float psi = atan(length(cross(L, n)), dot(n, L));
	vec3 e = n - dot(n, L) * L;
	float le = length(e);
	e = le > 1e-7 ? e / le : normalize(cross(L, abs(L.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	float s = sqrt(clamp(psi / PI, 0.0, 1.0));
	vec4 t = lentille_lire(s, 1);
	float th = secondaire ? t.b : t.r;
	float mu = secondaire ? t.a : t.g;
	return vec4(normalize(cos(th) * L + sin(th) * (secondaire ? -e : e)), mu);
}
