// Voir arbre_lumiere.h pour l'idée générale.
#include "arbre_lumiere.h"

#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;
using lumiere::Morceau;
using lumiere::Vec3d;

namespace lumiere {

double Vec3d::length() const { return std::sqrt(x * x + y * y + z * z); }
Vec3d Vec3d::normalized() const {
	double l = length();
	return l > 0 ? Vec3d(x / l, y / l, z / l) : Vec3d(0, 0, 1);
}

// Numéro d'un coin (a le long de A→B, b le long de A→C, a + b ≤ 8) dans le morceau.
static inline int coin(int a, int b) { return b * 9 - b * (b - 1) / 2 + a; }

// Les 3 coins de chacun des 64 rayons, dans l'ordre du morceau type (morceau_type.gd).
struct TableRayons {
	int coins[NB_RAYONS][3];
	TableRayons() {
		int n = 0;
		for (int b = 0; b < COUPES; b++) {
			for (int j = 0; j < COUPES - b; j++) {
				coins[n][0] = coin(j, b);
				coins[n][1] = coin(j + 1, b);
				coins[n][2] = coin(j, b + 1);
				n++;
				if (j < COUPES - b - 1) {
					coins[n][0] = coin(j + 1, b);
					coins[n][1] = coin(j + 1, b + 1);
					coins[n][2] = coin(j, b + 1);
					n++;
				}
			}
		}
	}
};
static const TableRayons TABLE;

// Numéro du rayon qui contient le point (x, y) du morceau (unités : 1 = un petit triangle).
static int rayon_sous(double x, double y) {
	int b = std::clamp((int)std::floor(y), 0, COUPES - 1);
	int j = std::clamp((int)std::floor(x), 0, COUPES - 1 - b);
	double fu = x - j, fv = y - b;
	int base = 0;
	for (int r = 0; r < b; r++) {
		base += 2 * (COUPES - r) - 1;
	}
	if (fu + fv >= 1.0 && j < COUPES - b - 1) {
		return base + 2 * j + 1;
	}
	return base + 2 * j;
}

// Mélange de bits (splitmix64) : un nombre au hasard, mais toujours le même pour la même entrée.
static inline uint64_t melanger(uint64_t z) {
	z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
	z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
	return z ^ (z >> 31);
}

static inline double hasard_point(int64_t ix, int64_t iy, int64_t iz, uint64_t graine) {
	uint64_t h = melanger(graine ^ ((uint64_t)ix * 0x9E3779B97F4A7C15ULL));
	h = melanger(h ^ ((uint64_t)iy * 0xC2B2AE3D27D4EB4FULL));
	h = melanger(h ^ ((uint64_t)iz * 0x165667B19E3779F9ULL));
	return (double)(h >> 11) * (2.0 / 9007199254740992.0) - 1.0; // entre -1 et 1
}

// Bruit doux en 3D (valeurs au hasard aux nœuds d'une grille, raccordées en douceur).
static double bruit(double x, double y, double z, uint64_t graine) {
	double fx = std::floor(x), fy = std::floor(y), fz = std::floor(z);
	int64_t ix = (int64_t)fx, iy = (int64_t)fy, iz = (int64_t)fz;
	double u = x - fx, v = y - fy, w = z - fz;
	u = u * u * u * (u * (u * 6 - 15) + 10);
	v = v * v * v * (v * (v * 6 - 15) + 10);
	w = w * w * w * (w * (w * 6 - 15) + 10);
	double c000 = hasard_point(ix, iy, iz, graine), c100 = hasard_point(ix + 1, iy, iz, graine);
	double c010 = hasard_point(ix, iy + 1, iz, graine), c110 = hasard_point(ix + 1, iy + 1, iz, graine);
	double c001 = hasard_point(ix, iy, iz + 1, graine), c101 = hasard_point(ix + 1, iy, iz + 1, graine);
	double c011 = hasard_point(ix, iy + 1, iz + 1, graine), c111 = hasard_point(ix + 1, iy + 1, iz + 1, graine);
	double x00 = c000 + (c100 - c000) * u, x10 = c010 + (c110 - c010) * u;
	double x01 = c001 + (c101 - c001) * u, x11 = c011 + (c111 - c011) * u;
	double y0 = x00 + (x10 - x00) * v, y1 = x01 + (x11 - x01) * v;
	return y0 + (y1 - y0) * w;
}

// Les 12 coins et 20 faces de l'icosaèdre (faces tournées vers l'extérieur).
static const double PHI = 1.6180339887498949;
static const double ICO_COINS[12][3] = {
	{ -1, PHI, 0 }, { 1, PHI, 0 }, { -1, -PHI, 0 }, { 1, -PHI, 0 },
	{ 0, -1, PHI }, { 0, 1, PHI }, { 0, -1, -PHI }, { 0, 1, -PHI },
	{ PHI, 0, -1 }, { PHI, 0, 1 }, { -PHI, 0, -1 }, { -PHI, 0, 1 },
};
static const int ICO_FACES[20][3] = {
	{ 0, 11, 5 }, { 0, 5, 1 }, { 0, 1, 7 }, { 0, 7, 10 }, { 0, 10, 11 },
	{ 1, 5, 9 }, { 5, 11, 4 }, { 11, 10, 2 }, { 10, 7, 6 }, { 7, 1, 8 },
	{ 3, 9, 4 }, { 3, 4, 2 }, { 3, 2, 6 }, { 3, 6, 8 }, { 3, 8, 9 },
	{ 4, 9, 5 }, { 2, 4, 11 }, { 6, 2, 10 }, { 8, 6, 7 }, { 9, 8, 1 },
};

// Coins des 4 enfants, en coordonnées du parent sur une grille de 16 (A = (0,0), B = (16,0), C = (0,16)).
static const int ENFANTS[4][3][2] = {
	{ { 0, 0 }, { 8, 0 }, { 0, 8 } },   // 0 : A, milieu AB, milieu CA
	{ { 8, 0 }, { 16, 0 }, { 8, 8 } },  // 1 : milieu AB, B, milieu BC
	{ { 0, 8 }, { 8, 8 }, { 0, 16 } },  // 2 : milieu CA, milieu BC, C
	{ { 8, 8 }, { 0, 8 }, { 8, 0 } },   // 3 : le triangle du milieu (retourné)
};

// Pour un point de la grille qui n'est pas un coin à ce pas : les deux voisins dont il est le milieu.
static void voisins_milieu(int a, int b, int s, int &a1, int &b1, int &a2, int &b2) {
	bool ia = (a / s) % 2 == 1, ib = (b / s) % 2 == 1;
	if (ia && !ib) {
		a1 = a - s; b1 = b; a2 = a + s; b2 = b;
	} else if (!ia && ib) {
		a1 = a; b1 = b - s; a2 = a; b2 = b + s;
	} else {
		a1 = a - s; b1 = b + s; a2 = a + s; b2 = b - s;
	}
}

} // namespace lumiere

using namespace lumiere;

// ---------------------------------------------------------------------------------------------
// Relief et couleur du sol
// ---------------------------------------------------------------------------------------------

double ArbreLumiere::longueur_onde(int n) const { return 400000.0 * (rayon / 600000.0) / std::ldexp(1.0, n); }
double ArbreLumiere::amplitude(int n) const { return 4000.0 * (rayon / 600000.0) * std::pow(2.0, -0.8 * n); }

// Hauteur (m) au-dessus du rayon de la planète. « octaves » = nombre de détails superposés,
// du plus grand (400 km) au plus fin. Plus un coin apparaît tard dans l'arbre, plus il en a :
// un coin garde donc toujours la même hauteur, quel que soit le morceau qui le calcule.
double ArbreLumiere::hauteur(const Vec3d &dir, int octaves) const {
	double h = 0;
	Vec3d p = dir * rayon;
	for (int n = 0; n < octaves; n++) {
		double l = 1.0 / longueur_onde(n);
		double v = bruit(p.x * l + n * 17.31, p.y * l - n * 9.77, p.z * l + n * 5.13, graine + (uint64_t)n * 101);
		if (n >= 2 && n < 8) {
			v = 1.0 - 2.0 * std::fabs(v); // crêtes : des chaînes de montagnes
		}
		h += amplitude(n) * v;
	}
	return h;
}

// Couleur du sol (albédo, lumière linéaire) : de grandes plaines sombres (comme les « mers » de la
// Lune) et des hauts plateaux clairs, avec des taches de plus en plus fines quand on s'approche.
void ArbreLumiere::couleur_sol(const Vec3d &dir, int octaves, float out[3]) const {
	Vec3d p = dir * rayon;
	double mer = 0;
	for (int n = 0; n < 3; n++) {
		double l = std::ldexp(1.0, n) / (900000.0 * rayon / 600000.0);
		mer += std::pow(0.5, n) * bruit(p.x * l + 3.7, p.y * l + 1.1, p.z * l - 8.2, graine ^ 0xC0FFEEULL);
	}
	double m = std::clamp((mer + 0.1) / 0.35, 0.0, 1.0);
	m = m * m * (3 - 2 * m);
	double detail = 0;
	for (int n = 2; n < octaves; n++) {
		double l = 1.0 / longueur_onde(n);
		detail += 0.25 * std::pow(2.0, -0.25 * (n - 2)) *
				bruit(p.x * l - n * 3.3, p.y * l + n * 7.9, p.z * l + n * 1.7, graine ^ (0xA1B2C3ULL + n));
	}
	double base = (0.17 + (0.075 - 0.17) * m) * std::exp(0.8 * detail);
	const double haut_[3] = { 1.0, 0.96, 0.90 };
	const double mer_[3] = { 0.92, 0.94, 1.0 };
	for (int i = 0; i < 3; i++) {
		out[i] = (float)std::clamp(base * (haut_[i] + (mer_[i] - haut_[i]) * m), 0.0, 0.6);
	}
}

// ---------------------------------------------------------------------------------------------
// Calcul d'un morceau
// ---------------------------------------------------------------------------------------------

void ArbreLumiere::calculer_racine(Morceau &m, int face) const {
	m.niveau = 0;
	m.adresse = (1ULL << 5) | (uint64_t)face;
	for (int i = 0; i < 3; i++) {
		const double *c = ICO_COINS[ICO_FACES[face][i]];
		m.coins[i] = Vec3d(c[0], c[1], c[2]).normalized();
		m.naissance_coins[i] = 0;
	}
	// Faces tournées vers l'extérieur : on vérifie et on retourne si besoin.
	Vec3d n = (m.coins[1] - m.coins[0]).cross(m.coins[2] - m.coins[0]);
	if (n.dot(m.coins[0] + m.coins[1] + m.coins[2]) < 0) {
		std::swap(m.coins[1], m.coins[2]);
	}
	finir_calcul(m, nullptr, 0);
}

void ArbreLumiere::calculer(Morceau &m, const Morceau *parent, int k) const {
	m.niveau = parent->niveau + 1;
	m.adresse = (parent->adresse << 2) | (uint64_t)k;
	// Les coins de l'enfant sont des points de la grille du parent (grille de 8, d'où / 2).
	// On refait la même opération que le parent pour obtenir exactement les mêmes nombres.
	Vec3d grille[NB_COINS];
	Vec3d A = parent->coins[0], B = parent->coins[1], C = parent->coins[2];
	Vec3d mAB = (A + B).normalized(), mCA = (C + A).normalized(), mBC = (B + C).normalized();
	for (int i = 0; i < 3; i++) {
		int a = ENFANTS[k][i][0], b = ENFANTS[k][i][1];
		Vec3d d;
		int nais;
		if (a == 0 && b == 0) { d = A; nais = parent->naissance_coins[0]; }
		else if (a == 16 && b == 0) { d = B; nais = parent->naissance_coins[1]; }
		else if (a == 0 && b == 16) { d = C; nais = parent->naissance_coins[2]; }
		else if (b == 0) { d = mAB; nais = m.niveau; }
		else if (a == 0) { d = mCA; nais = m.niveau; }
		else { d = mBC; nais = m.niveau; }
		m.coins[i] = d;
		m.naissance_coins[i] = nais;
	}
	(void)grille;
	finir_calcul(m, parent, k);
}

void ArbreLumiere::finir_calcul(Morceau &m, const Morceau *parent, int k) const {
	// 1. Les 45 coins : milieux successifs (pas de 4, puis 2, puis 1), ramenés sur la sphère.
	Vec3d dir[NB_COINS];
	int nais[NB_COINS];
	dir[coin(0, 0)] = m.coins[0];
	dir[coin(8, 0)] = m.coins[1];
	dir[coin(0, 8)] = m.coins[2];
	nais[coin(0, 0)] = m.naissance_coins[0];
	nais[coin(8, 0)] = m.naissance_coins[1];
	nais[coin(0, 8)] = m.naissance_coins[2];
	int niv_pas = m.niveau + 1;
	for (int s = 4; s >= 1; s /= 2, niv_pas++) {
		for (int b = 0; b <= 8; b += s) {
			for (int a = 0; a + b <= 8; a += s) {
				if (a % (2 * s) == 0 && b % (2 * s) == 0) {
					continue; // déjà fait au pas d'avant
				}
				int a1, b1, a2, b2;
				voisins_milieu(a, b, s, a1, b1, a2, b2);
				dir[coin(a, b)] = (dir[coin(a1, b1)] + dir[coin(a2, b2)]).normalized();
				nais[coin(a, b)] = niv_pas;
			}
		}
	}
	// 2. Le relief : chaque coin a les détails de son niveau de naissance (moins 2, pour qu'un
	// détail soit toujours plus grand que deux fois l'écart entre les coins).
	Vec3d pos[NB_COINS];
	Vec3d somme;
	for (int i = 0; i < NB_COINS; i++) {
		pos[i] = dir[i] * (rayon + hauteur(dir[i], std::max(0, nais[i] - 1)));
		somme = somme + pos[i];
	}
	m.centre = somme * (1.0 / NB_COINS);
	double r2 = 0;
	for (int i = 0; i < NB_COINS; i++) {
		Vec3d d = pos[i] - m.centre;
		r2 = std::max(r2, d.dot(d));
		m.cible[i][0] = (float)d.x;
		m.cible[i][1] = (float)d.y;
		m.cible[i][2] = (float)d.z;
	}
	int oct_fin = m.niveau + 2; // octaves des coins les plus fins
	double reste = amplitude(oct_fin) / (1.0 - std::pow(2.0, -0.8));
	m.rayon_englobant = std::sqrt(r2) + reste;
	m.cote = (m.coins[1] - m.coins[0]).length() * rayon;
	m.taille_rayon = (float)(m.cote / COUPES);
	m.jupe = (float)(5.0 * amplitude(m.niveau + 1) + 0.02 * m.cote);

	// 3. Départ du glissement : la forme et les couleurs du parent sous chaque point.
	Vec3d parent_pos[NB_COINS];
	if (parent) {
		for (int i = 0; i < NB_COINS; i++) {
			parent_pos[i] = parent->centre + Vec3d(parent->cible[i][0], parent->cible[i][1], parent->cible[i][2]);
		}
		const int(*C)[2] = ENFANTS[k];
		for (int b = 0; b <= 8; b++) {
			for (int a = 0; a + b <= 8; a++) {
				int P0 = C[0][0] * 8 + (C[1][0] - C[0][0]) * a + (C[2][0] - C[0][0]) * b; // grille de 16, × 8
				int P1 = C[0][1] * 8 + (C[1][1] - C[0][1]) * a + (C[2][1] - C[0][1]) * b;
				int x = P0 / 8, y = P1 / 8; // point sur la grille de 16 du parent
				Vec3d p;
				if (x % 2 == 0 && y % 2 == 0) {
					p = parent_pos[coin(x / 2, y / 2)];
				} else {
					int a1, b1, a2, b2;
					voisins_milieu(x, y, 1, a1, b1, a2, b2);
					p = (parent_pos[coin(a1 / 2, b1 / 2)] + parent_pos[coin(a2 / 2, b2 / 2)]) * 0.5;
				}
				Vec3d d = p - m.centre;
				int i = coin(a, b);
				m.depart[i][0] = (float)d.x;
				m.depart[i][1] = (float)d.y;
				m.depart[i][2] = (float)d.z;
			}
		}
	} else {
		std::memcpy(m.depart, m.cible, sizeof(m.cible));
	}

	// 4. Les rayons : couleur du sol, direction moyenne et son étalement.
	int oct_couleur = m.niveau + 3 - 1;      // les rayons sont au niveau du morceau + 3
	int oct_relief = m.niveau + 3 - 1;
	double etal = 0;
	for (int n = oct_relief; n < oct_relief + 8; n++) {
		double pente = 2.0 * amplitude(n) / longueur_onde(n);
		etal += pente * pente;
	}
	double longueur = std::clamp(1.0 / std::sqrt(1.0 + etal), 0.25, 1.0);
	for (int t = 0; t < NB_RAYONS; t++) {
		const int *c = TABLE.coins[t];
		Vec3d p0 = pos[c[0]], p1 = pos[c[1]], p2 = pos[c[2]];
		Vec3d mil = (p0 + p1 + p2) * (1.0 / 3.0);
		Vec3d n = (p1 - p0).cross(p2 - p0).normalized();
		if (n.dot(mil) < 0) {
			n = n * -1.0;
		}
		Vec3d d = mil - m.centre;
		m.centres[t][0] = (float)d.x;
		m.centres[t][1] = (float)d.y;
		m.centres[t][2] = (float)d.z;
		m.direction[t][0] = (float)(n.x * longueur);
		m.direction[t][1] = (float)(n.y * longueur);
		m.direction[t][2] = (float)(n.z * longueur);
		Vec3d dm = (dir[c[0]] + dir[c[1]] + dir[c[2]]).normalized();
		couleur_sol(dm, oct_couleur, m.albedo[t]);
	}
	if (parent) {
		const int(*C)[2] = ENFANTS[k];
		for (int t = 0; t < NB_RAYONS; t++) {
			// Centre du rayon en coordonnées du morceau (un petit triangle = 1), puis chez le parent.
			const int *c = TABLE.coins[t];
			double ca = 0, cb = 0;
			for (int i = 0; i < 3; i++) {
				int idx = c[i];
				int bb = 0;
				while (coin(0, bb + 1) <= idx && bb < 8) bb++;
				ca += idx - coin(0, bb);
				cb += bb;
			}
			ca /= 3.0;
			cb /= 3.0;
			double X = (C[0][0] * 8 + (C[1][0] - C[0][0]) * ca + (C[2][0] - C[0][0]) * cb) / 16.0;
			double Y = (C[0][1] * 8 + (C[1][1] - C[0][1]) * ca + (C[2][1] - C[0][1]) * cb) / 16.0;
			int tp = rayon_sous(X, Y);
			std::memcpy(m.albedo_depart[t], parent->albedo[tp], sizeof(float) * 3);
		}
	} else {
		std::memcpy(m.albedo_depart, m.albedo, sizeof(m.albedo));
	}
}

Morceau *ArbreLumiere::assurer(uint64_t adresse) {
	auto it = cache.find(adresse);
	if (it != cache.end()) {
		return it->second.get();
	}
	int niv = niveau_de((int64_t)adresse);
	auto m = std::make_unique<Morceau>();
	if (niv <= 0) {
		calculer_racine(*m, (int)(adresse & 31));
	} else {
		Morceau *p = assurer(adresse >> 2);
		calculer(*m, p, (int)(adresse & 3));
	}
	m->derniere_image = image;
	Morceau *r = m.get();
	cache[adresse] = std::move(m);
	return r;
}

// ---------------------------------------------------------------------------------------------
// 1. Choisir
// ---------------------------------------------------------------------------------------------

bool ArbreLumiere::visible(const Morceau &m) const {
	Vec3d v = m.centre - cam;
	double r = m.rayon_englobant;
	// Hors du champ de vision ? (4 bords de l'écran)
	const Vec3d bords[4] = {
		devant * tan_h - droite, devant * tan_h + droite, devant * tan_v - haut, devant * tan_v + haut,
	};
	for (int i = 0; i < 4; i++) {
		Vec3d n = bords[i].normalized();
		if (n.dot(v) < -r) {
			return false;
		}
	}
	// Caché derrière l'horizon ?
	double r_cache = std::max(rayon - relief_max, rayon * 0.5);
	double dc = cam.length();
	if (dc > r_cache) {
		double dm = m.centre.length();
		double th_c = std::acos(r_cache / dc);
		double th_p = std::acos(std::min(1.0, r_cache / (dm + r)));
		double th_m = std::asin(std::min(1.0, r / std::max(dm, 1.0)));
		double cosang = std::clamp(m.centre.dot(cam) / (dm * dc), -1.0, 1.0);
		if (std::acos(cosang) > th_c + th_p + th_m) {
			return false;
		}
	}
	return true;
}

void ArbreLumiere::visiter(Morceau *m) {
	m->derniere_image = image;
	if (!visible(*m)) {
		return;
	}
	double d = std::max((m->centre - cam).length() - m->rayon_englobant, 1e-3);
	double taille_px = m->cote / d * px_par_radian / COUPES; // taille d'un rayon à l'écran
	bool etait_coupe = interieurs_prec.count(m->adresse) > 0;
	double seuil = etait_coupe ? seuil_fusion : seuil_couper;
	if (taille_px > seuil && m->niveau < NIVEAU_MAX && budget_coupes >= 3) {
		Morceau *enfants[4];
		bool prets = true;
		for (int i = 0; i < 4; i++) {
			uint64_t a = (m->adresse << 2) | (uint64_t)i;
			auto it = cache.find(a);
			if (it == cache.end()) {
				prets = false;
				if (deja_demande.insert(a).second) {
					demandes.push_back({ taille_px, a });
				}
			} else {
				enfants[i] = it->second.get();
			}
		}
		if (prets) {
			budget_coupes -= 3;
			interieurs.insert(m->adresse);
			for (int i = 0; i < 4; i++) {
				visiter(enfants[i]);
			}
			return;
		}
	}
	affiches.push_back(m);
}

int ArbreLumiere::choisir(const PackedFloat64Array &p_camera, const PackedFloat32Array &p_axes, double p_tan_h,
		double p_tan_v, double p_hauteur_px, double p_temps) {
	image++;
	if (p_camera.size() >= 3) {
		cam = Vec3d(p_camera[0], p_camera[1], p_camera[2]);
	}
	if (p_axes.size() >= 9) {
		devant = Vec3d(p_axes[0], p_axes[1], p_axes[2]).normalized();
		droite = Vec3d(p_axes[3], p_axes[4], p_axes[5]).normalized();
		haut = Vec3d(p_axes[6], p_axes[7], p_axes[8]).normalized();
	}
	tan_h = p_tan_h;
	tan_v = p_tan_v;
	px_par_radian = p_hauteur_px / (2.0 * p_tan_v);
	budget_coupes = places - 24;
	affiches.clear();
	interieurs.clear();
	demandes.clear();
	deja_demande.clear();
	for (int f = 0; f < 20; f++) {
		visiter(assurer((1ULL << 5) | (uint64_t)f));
	}
	interieurs_prec.swap(interieurs);

	// Places dans les textures : on libère celles des morceaux partis, on donne une place aux nouveaux.
	std::unordered_set<uint64_t> nouveaux;
	nouveaux.reserve(affiches.size() * 2);
	for (Morceau *m : affiches) {
		nouveaux.insert(m->adresse);
	}
	for (auto it = place_de.begin(); it != place_de.end();) {
		if (!nouveaux.count(it->first)) {
			vider_place(it->second);
			it = place_de.erase(it);
		} else {
			++it;
		}
	}
	for (Morceau *m : affiches) {
		if (place_de.count(m->adresse)) {
			continue;
		}
		if (places_libres.empty()) {
			break; // ne devrait pas arriver (budget_coupes)
		}
		int p = places_libres.back();
		places_libres.pop_back();
		place_de[m->adresse] = p;
		occupant[p] = m->adresse;
		// Glissement seulement si le morceau vient de la coupe d'un parent qu'on voyait.
		bool coupe = m->niveau > 0 && affiches_prec.count(m->adresse >> 2) > 0;
		naissance[p] = (float)(coupe ? p_temps : p_temps - 1000.0);
		ecrire_place(p, *m);
		change = true;
	}
	affiches_prec.swap(nouveaux);
	std::sort(demandes.begin(), demandes.end(),
			[](const std::pair<double, uint64_t> &a, const std::pair<double, uint64_t> &b) { return a.first > b.first; });
	return (int)affiches.size();
}

// ---------------------------------------------------------------------------------------------
// 2. Éclairer
// ---------------------------------------------------------------------------------------------

void ArbreLumiere::tache_eclairer(void *p_travail, uint32_t p_i) {
	Travail *t = (Travail *)p_travail;
	t->arbre->calculer(*t->sortie[p_i], t->parents[p_i], t->enfants[p_i]);
}

int ArbreLumiere::eclairer(int p_max) {
	int n = std::min((int)demandes.size(), std::max(p_max, 0));
	if (n == 0) {
		return 0;
	}
	Travail t;
	t.arbre = this;
	std::vector<std::unique_ptr<Morceau>> neufs;
	for (int i = 0; i < n; i++) {
		uint64_t a = demandes[i].second;
		auto it = cache.find(a >> 2);
		if (it == cache.end()) {
			continue;
		}
		neufs.push_back(std::make_unique<Morceau>());
		t.sortie.push_back(neufs.back().get());
		t.parents.push_back(it->second.get());
		t.enfants.push_back((int)(a & 3));
	}
	int nb = (int)t.sortie.size();
	if (nb >= 4 && WorkerThreadPool::get_singleton()) {
		WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
		int64_t groupe = pool->add_native_group_task(&ArbreLumiere::tache_eclairer, &t, nb, -1, true, "Lumière : éclairer");
		pool->wait_for_group_task_completion(groupe);
	} else {
		for (int i = 0; i < nb; i++) {
			tache_eclairer(&t, i);
		}
	}
	for (auto &m : neufs) {
		m->derniere_image = image;
		uint64_t a = m->adresse;
		cache[a] = std::move(m);
	}
	oublier_anciens();
	return nb;
}

void ArbreLumiere::oublier_anciens() {
	const size_t MAX = 12000, GARDER = 9000;
	if (cache.size() <= MAX) {
		return;
	}
	std::vector<std::pair<uint64_t, uint64_t>> vieux; // (dernière image, adresse)
	for (auto &e : cache) {
		if (e.second->niveau > 0 && e.second->derniere_image + 1 < image) {
			vieux.push_back({ e.second->derniere_image, e.first });
		}
	}
	std::sort(vieux.begin(), vieux.end());
	for (auto &v : vieux) {
		if (cache.size() <= GARDER) {
			break;
		}
		cache.erase(v.second);
	}
}

// ---------------------------------------------------------------------------------------------
// Envoi
// ---------------------------------------------------------------------------------------------

static inline uint8_t octet(double v) { return (uint8_t)std::clamp((int)std::lround(v * 255.0), 0, 255); }

void ArbreLumiere::ecrire_place(int p, const Morceau &m) {
	uint8_t *r = tampon_rayons.ptrw();
	const int largeur = RAYONS_PAR_LIGNE * TEXELS_PAR_RAYON;
	for (int t = 0; t < NB_RAYONS; t++) {
		int g = p * NB_RAYONS + t;
		int o = ((g / RAYONS_PAR_LIGNE) * largeur + (g % RAYONS_PAR_LIGNE) * TEXELS_PAR_RAYON) * 4;
		// Couleur codée par sa racine carrée : plus de nuances dans les sombres (8 bits seulement).
		for (int i = 0; i < 3; i++) {
			r[o + i] = octet(std::sqrt(m.albedo_depart[t][i]));
			r[o + 4 + i] = octet(std::sqrt(m.albedo[t][i]));
			r[o + 8 + i] = octet(m.direction[t][i] * 0.5 + 0.5);
		}
		r[o + 3] = 255;
		r[o + 7] = 255;
		r[o + 11] = 255;
	}
	float *c = (float *)tampon_coins.ptrw();
	for (int k = 0; k < NB_COINS; k++) {
		float *d = c + ((size_t)p * NB_COINS * TEXELS_PAR_COIN + k * 2) * 4;
		d[0] = m.depart[k][0]; d[1] = m.depart[k][1]; d[2] = m.depart[k][2]; d[3] = 0;
		d[4] = m.cible[k][0]; d[5] = m.cible[k][1]; d[6] = m.cible[k][2]; d[7] = 0;
	}
}

void ArbreLumiere::vider_place(int p) {
	occupant[p] = 0;
	places_libres.push_back(p);
}

bool ArbreLumiere::a_change() {
	bool c = change;
	change = false;
	return c;
}

PackedFloat32Array ArbreLumiere::tampon_instances(const Basis &R, const PackedFloat64Array &p_decalage) const {
	PackedFloat32Array out;
	out.resize(places * 16);
	float *o = out.ptrw();
	std::memset(o, 0, sizeof(float) * places * 16);
	Vec3d dec;
	if (p_decalage.size() >= 3) {
		dec = Vec3d(p_decalage[0], p_decalage[1], p_decalage[2]);
	}
	for (int p = 0; p < places; p++) {
		if (occupant[p] == 0) {
			continue;
		}
		auto it = cache.find(occupant[p]);
		if (it == cache.end()) {
			continue;
		}
		const Morceau &m = *it->second;
		float *d = o + p * 16;
		for (int r = 0; r < 3; r++) {
			Vector3 ligne = R.rows[r];
			double orig = ligne.x * m.centre.x + ligne.y * m.centre.y + ligne.z * m.centre.z;
			orig += r == 0 ? dec.x : (r == 1 ? dec.y : dec.z);
			d[r * 4 + 0] = ligne.x;
			d[r * 4 + 1] = ligne.y;
			d[r * 4 + 2] = ligne.z;
			d[r * 4 + 3] = (float)orig;
		}
		d[12] = naissance[p];
		d[13] = m.jupe;
		d[14] = m.taille_rayon;
		d[15] = (float)m.niveau;
	}
	return out;
}

// ---------------------------------------------------------------------------------------------
// Posemètre de l'œil
// ---------------------------------------------------------------------------------------------

PackedFloat32Array ArbreLumiere::posemetre(const PackedFloat64Array &p_camera, const PackedFloat32Array &p_axes,
		double p_tan_h, double p_tan_v, const Vector3 &p_soleil, double p_eclairement, double p_fond) const {
	const int NX = 16, NY = 9;
	std::vector<double> somme(NX * NY, 0.0), aire(NX * NY, 0.0);
	Vec3d c(p_camera[0], p_camera[1], p_camera[2]);
	Vec3d f = Vec3d(p_axes[0], p_axes[1], p_axes[2]).normalized();
	Vec3d dr = Vec3d(p_axes[3], p_axes[4], p_axes[5]).normalized();
	Vec3d hu = Vec3d(p_axes[6], p_axes[7], p_axes[8]).normalized();
	Vec3d s = Vec3d(p_soleil.x, p_soleil.y, p_soleil.z).normalized();
	double aire_case = (2.0 * p_tan_h / NX) * (2.0 * p_tan_v / NY);
	for (const Morceau *m : affiches) {
		double a_rayon = (double)m->taille_rayon * m->taille_rayon * 0.433;
		for (int t = 0; t < NB_RAYONS; t++) {
			Vec3d v = m->centre + Vec3d(m->centres[t][0], m->centres[t][1], m->centres[t][2]) - c;
			double z = v.dot(f);
			if (z <= 0) continue;
			double x = v.dot(dr) / (z * p_tan_h), y = -v.dot(hu) / (z * p_tan_v);
			if (x <= -1 || x >= 1 || y <= -1 || y >= 1) continue;
			Vec3d n(m->direction[t][0], m->direction[t][1], m->direction[t][2]);
			double ln = n.length();
			double vers_oeil = -n.dot(v) / (ln * v.length());
			if (vers_oeil <= 0) continue; // face cachée
			int i = std::min(NX - 1, (int)((x + 1) * 0.5 * NX));
			int j = std::min(NY - 1, (int)((y + 1) * 0.5 * NY));
			double cs = n.dot(s) / ln;
			double etal = 1.0 - ln;
			double direct = std::max(cs, 0.0);
			direct = direct + (0.5 * (cs + 1.0) * 0.6 - direct) * etal;
			const float *al = m->albedo[t];
			double y_al = 0.2126 * al[0] + 0.7152 * al[1] + 0.0722 * al[2];
			double l = y_al * p_eclairement * direct / Math_PI;
			double ap = a_rayon * vers_oeil / (z * z);
			somme[j * NX + i] += l * ap;
			aire[j * NX + i] += ap;
		}
	}
	PackedFloat32Array out;
	out.resize(NX * NY);
	for (int k = 0; k < NX * NY; k++) {
		double cov = std::min(1.0, aire[k] / aire_case);
		double moy = aire[k] > 0 ? somme[k] / aire[k] : 0.0;
		out[k] = (float)(moy * cov + p_fond * (1.0 - cov));
	}
	return out;
}

// ---------------------------------------------------------------------------------------------
// Divers
// ---------------------------------------------------------------------------------------------

ArbreLumiere::ArbreLumiere() { configurer(600000.0, 1, 1024); }
ArbreLumiere::~ArbreLumiere() {}

void ArbreLumiere::configurer(double p_rayon, int64_t p_graine, int p_places) {
	rayon = p_rayon;
	graine = melanger((uint64_t)p_graine);
	places = std::max(64, (p_places / 4) * 4);
	relief_max = 0;
	for (int n = 0; n < 40; n++) {
		relief_max += amplitude(n);
	}
	cache.clear();
	interieurs_prec.clear();
	affiches.clear();
	affiches_prec.clear();
	place_de.clear();
	occupant.assign(places, 0);
	naissance.assign(places, -1000.0f);
	places_libres.clear();
	for (int p = places - 1; p >= 0; p--) {
		places_libres.push_back(p);
	}
	tampon_rayons.resize((int64_t)largeur_rayons() * hauteur_rayons() * 4);
	tampon_rayons.fill(0);
	tampon_coins.resize((int64_t)largeur_coins() * places * 16);
	tampon_coins.fill(0);
	change = true;
	for (int f = 0; f < 20; f++) {
		assurer((1ULL << 5) | (uint64_t)f);
	}
}

void ArbreLumiere::regler_seuils(double p_couper, double p_fusion) {
	seuil_couper = std::max(p_couper, 0.5);
	seuil_fusion = std::clamp(p_fusion, 0.25, seuil_couper);
}

double ArbreLumiere::hauteur_sol(const PackedFloat64Array &p) const {
	return hauteur(Vec3d(p[0], p[1], p[2]).normalized(), 28);
}

int ArbreLumiere::niveau_de(int64_t a) {
	uint64_t u = (uint64_t)a;
	if (u < 32) return -1;
	int bits = 64 - __builtin_clzll(u);
	return (bits - 6) / 2;
}

int ArbreLumiere::niveau_max_affiche() const {
	int n = 0;
	for (const Morceau *m : affiches) n = std::max(n, m->niveau);
	return n;
}

PackedInt64Array ArbreLumiere::racines() const {
	PackedInt64Array r;
	for (int f = 0; f < 20; f++) r.push_back((int64_t)((1ULL << 5) | (uint64_t)f));
	return r;
}

PackedInt64Array ArbreLumiere::morceaux_affiches() const {
	PackedInt64Array r;
	for (const Morceau *m : affiches) r.push_back((int64_t)m->adresse);
	return r;
}

PackedFloat64Array ArbreLumiere::coins_morceau(int64_t a) {
	Morceau *m = assurer((uint64_t)a);
	PackedFloat64Array r;
	r.resize(NB_COINS * 3);
	for (int i = 0; i < NB_COINS; i++) {
		r[i * 3] = m->centre.x + m->cible[i][0];
		r[i * 3 + 1] = m->centre.y + m->cible[i][1];
		r[i * 3 + 2] = m->centre.z + m->cible[i][2];
	}
	return r;
}

PackedFloat64Array ArbreLumiere::coins_depart_morceau(int64_t a) {
	Morceau *m = assurer((uint64_t)a);
	PackedFloat64Array r;
	r.resize(NB_COINS * 3);
	for (int i = 0; i < NB_COINS; i++) {
		r[i * 3] = m->centre.x + m->depart[i][0];
		r[i * 3 + 1] = m->centre.y + m->depart[i][1];
		r[i * 3 + 2] = m->centre.z + m->depart[i][2];
	}
	return r;
}

PackedFloat32Array ArbreLumiere::couleurs_morceau(int64_t a) {
	Morceau *m = assurer((uint64_t)a);
	PackedFloat32Array r;
	r.resize(NB_RAYONS * 3);
	for (int t = 0; t < NB_RAYONS; t++)
		for (int i = 0; i < 3; i++) r[t * 3 + i] = m->albedo[t][i];
	return r;
}

PackedFloat32Array ArbreLumiere::directions_morceau(int64_t a) {
	Morceau *m = assurer((uint64_t)a);
	PackedFloat32Array r;
	r.resize(NB_RAYONS * 3);
	for (int t = 0; t < NB_RAYONS; t++)
		for (int i = 0; i < 3; i++) r[t * 3 + i] = m->direction[t][i];
	return r;
}

PackedFloat64Array ArbreLumiere::centre_morceau(int64_t a) {
	Morceau *m = assurer((uint64_t)a);
	PackedFloat64Array r;
	r.push_back(m->centre.x);
	r.push_back(m->centre.y);
	r.push_back(m->centre.z);
	r.push_back(m->rayon_englobant);
	r.push_back(m->cote);
	return r;
}

void ArbreLumiere::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurer", "rayon", "graine", "places"), &ArbreLumiere::configurer);
	ClassDB::bind_method(D_METHOD("regler_seuils", "couper_px", "fusionner_px"), &ArbreLumiere::regler_seuils);
	ClassDB::bind_method(D_METHOD("get_rayon"), &ArbreLumiere::get_rayon);
	ClassDB::bind_method(D_METHOD("get_relief_max"), &ArbreLumiere::get_relief_max);
	ClassDB::bind_method(D_METHOD("choisir", "camera", "axes", "tan_h", "tan_v", "hauteur_px", "temps"), &ArbreLumiere::choisir);
	ClassDB::bind_method(D_METHOD("eclairer", "max_morceaux"), &ArbreLumiere::eclairer);
	ClassDB::bind_method(D_METHOD("tampon_instances", "rotation", "decalage"), &ArbreLumiere::tampon_instances);
	ClassDB::bind_method(D_METHOD("donnees_rayons"), &ArbreLumiere::donnees_rayons);
	ClassDB::bind_method(D_METHOD("donnees_coins"), &ArbreLumiere::donnees_coins);
	ClassDB::bind_method(D_METHOD("a_change"), &ArbreLumiere::a_change);
	ClassDB::bind_method(D_METHOD("posemetre", "camera", "axes", "tan_h", "tan_v", "soleil", "eclairement", "fond"), &ArbreLumiere::posemetre);
	ClassDB::bind_method(D_METHOD("hauteur_sol", "direction"), &ArbreLumiere::hauteur_sol);
	ClassDB::bind_method(D_METHOD("nb_morceaux"), &ArbreLumiere::nb_morceaux);
	ClassDB::bind_method(D_METHOD("nb_rayons"), &ArbreLumiere::nb_rayons);
	ClassDB::bind_method(D_METHOD("nb_en_cache"), &ArbreLumiere::nb_en_cache);
	ClassDB::bind_method(D_METHOD("nb_demandes"), &ArbreLumiere::nb_demandes);
	ClassDB::bind_method(D_METHOD("get_places"), &ArbreLumiere::get_places);
	ClassDB::bind_method(D_METHOD("largeur_rayons"), &ArbreLumiere::largeur_rayons);
	ClassDB::bind_method(D_METHOD("hauteur_rayons"), &ArbreLumiere::hauteur_rayons);
	ClassDB::bind_method(D_METHOD("largeur_coins"), &ArbreLumiere::largeur_coins);
	ClassDB::bind_method(D_METHOD("niveau_max_affiche"), &ArbreLumiere::niveau_max_affiche);
	ClassDB::bind_method(D_METHOD("racines"), &ArbreLumiere::racines);
	ClassDB::bind_method(D_METHOD("morceaux_affiches"), &ArbreLumiere::morceaux_affiches);
	ClassDB::bind_static_method("ArbreLumiere", D_METHOD("adresse_enfant", "adresse", "i"), &ArbreLumiere::adresse_enfant);
	ClassDB::bind_static_method("ArbreLumiere", D_METHOD("niveau_de", "adresse"), &ArbreLumiere::niveau_de);
	ClassDB::bind_method(D_METHOD("coins_morceau", "adresse"), &ArbreLumiere::coins_morceau);
	ClassDB::bind_method(D_METHOD("coins_depart_morceau", "adresse"), &ArbreLumiere::coins_depart_morceau);
	ClassDB::bind_method(D_METHOD("couleurs_morceau", "adresse"), &ArbreLumiere::couleurs_morceau);
	ClassDB::bind_method(D_METHOD("directions_morceau", "adresse"), &ArbreLumiere::directions_morceau);
	ClassDB::bind_method(D_METHOD("centre_morceau", "adresse"), &ArbreLumiere::centre_morceau);
}
