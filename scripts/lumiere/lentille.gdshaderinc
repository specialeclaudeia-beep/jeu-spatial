// Einstein B : la lumière courbée par un trou noir (voir scripts/physique/lentille.gd).
// La table est calculée une fois par image (l'œil est le même pour tous les pixels) :
//   ligne 0 : pour un rayon vu sous l'angle θ du trou noir (θ = ombre + (π − ombre)·x²), l'angle ψ
//             d'où vient vraiment sa lumière (négatif : de l'autre côté, après un demi-tour) ;
//   ligne 1 : pour une étoile à l'angle ψ = π·s² du trou noir, ses deux images (θ1, μ1, θ2, μ2),
//             μ = grossissement (rapport des surfaces : l'éclat d'un point est multiplié par μ).
uniform vec4 lentille = vec4(0.0, 0.0, -1.0, 0.0);   // xyz = direction du trou noir, w = 1 si actif
uniform float lentille_ombre = 0.0;                  // rayon angulaire de l'ombre (rad)
// Nombres à virgule de 32 bits, lus sans filtre (la petite carte graphique du PC ne sait pas filtrer
// ce format) : on fait nous-mêmes le mélange entre deux cases voisines.
uniform sampler2D lentille_table : filter_nearest, repeat_disable;
const float LENTILLE_POINTS = 512.0;

vec4 lentille_lire(float x, int ligne) {
	float f = clamp(x, 0.0, 1.0) * (LENTILLE_POINTS - 1.0);
	int i = min(int(floor(f)), int(LENTILLE_POINTS) - 2);
	return mix(texelFetch(lentille_table, ivec2(i, ligne), 0), texelFetch(lentille_table, ivec2(i + 1, ligne), 0), f - float(i));
}

// Direction vue d → direction d'où vient sa lumière (w = 0 : dans l'ombre, rien ne vient d'ici).
vec4 lentille_origine(vec3 d) {
	if (lentille.w < 0.5) {
		return vec4(d, 1.0);
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
