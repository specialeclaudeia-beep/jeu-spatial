// Voir arbre_lumiere.h pour l'idée générale.
#include "arbre_lumiere.h"

#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <chrono>
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
		h += octave(p, n);
	}
	return h;
}

// Un détail du relief. Octaves 2 à 7 : des crêtes (chaînes de montagnes). Étape 7, octaves 17 à 25
// (des blocs de 1,5 m aux graviers de 1 cm) : des cailloux posés sur un sol bosselé. Au-delà : le
// grain du sable, jusqu'au millimètre. La valeur reste entre -1,5 et 1,5 fois l'amplitude.
double ArbreLumiere::octave(const Vec3d &p, int n) const {
	double l = 1.0 / longueur_onde(n);
	double x = p.x * l + n * 17.31, y = p.y * l - n * 9.77, z = p.z * l + n * 5.13;
	double v = bruit(x, y, z, graine + (uint64_t)n * 101);
	if (n >= 2 && n < 8) {
		v = 1.0 - 2.0 * std::fabs(v); // crêtes : des chaînes de montagnes
	} else if (n >= OCTAVE_CAILLOUX_MIN && n <= OCTAVE_CAILLOUX_MAX) {
		v = 0.55 * v + 1.2 * caillou(Vec3d(x, y, z), n, nullptr) - 0.2;
	}
	return amplitude(n) * v;
}

// Cailloux : au plus un par cellule d'une grille (taille = longueur d'onde de l'octave), placé et
// taillé au hasard (toujours le même pour la même cellule). On regarde les 8 cellules voisines.
// Forme : une bosse arrondie aux bords raides, plus haute pour les gros cailloux.
double ArbreLumiere::caillou(const Vec3d &q, int n, double *teinte) const {
	double bx = std::floor(q.x - 0.5), by = std::floor(q.y - 0.5), bz = std::floor(q.z - 0.5);
	double meilleur = 0.0;
	double t = 0.0;
	// Moins de gros blocs que de petits cailloux.
	double densite = 0.22 + 0.04 * (n - OCTAVE_CAILLOUX_MIN);
	uint64_t g = graine ^ (0x5EED0000ULL + (uint64_t)n * 7919ULL);
	for (int c = 0; c < 8; c++) {
		int64_t ix = (int64_t)bx + (c & 1), iy = (int64_t)by + ((c >> 1) & 1), iz = (int64_t)bz + ((c >> 2) & 1);
		uint64_t h = melanger(g ^ ((uint64_t)ix * 0x9E3779B97F4A7C15ULL));
		h = melanger(h ^ ((uint64_t)iy * 0xC2B2AE3D27D4EB4FULL));
		h = melanger(h ^ ((uint64_t)iz * 0x165667B19E3779F9ULL));
		if ((double)(h & 0xFFFF) / 65535.0 > densite) {
			continue;
		}
		double jx = ((double)((h >> 16) & 0xFF) / 255.0 - 0.5) * 0.6;
		double jy = ((double)((h >> 24) & 0xFF) / 255.0 - 0.5) * 0.6;
		double jz = ((double)((h >> 32) & 0xFF) / 255.0 - 0.5) * 0.6;
		double r = 0.18 + 0.22 * (double)((h >> 40) & 0xFF) / 255.0;
		double dx = q.x - (ix + 0.5 + jx), dy = q.y - (iy + 0.5 + jy), dz = q.z - (iz + 0.5 + jz);
		double d2 = (dx * dx + dy * dy + dz * dz) / (r * r);
		if (d2 >= 1.0) {
			continue;
		}
		double v = std::pow(1.0 - d2, 0.6) * (r / 0.4);
		if (v > meilleur) {
			meilleur = v;
			t = (double)((h >> 48) & 0xFF) / 127.5 - 1.0;
		}
	}
	if (teinte) {
		*teinte = t * std::min(1.0, meilleur * 4.0);
	}
	return meilleur;
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
	// Étape 7 : chaque caillou a sa propre teinte (plus clair ou plus sombre que le sol autour).
	double pierres = 0;
	for (int n = OCTAVE_CAILLOUX_MIN; n <= std::min(OCTAVE_CAILLOUX_MAX, octaves - 1); n++) {
		double l = 1.0 / longueur_onde(n);
		double t = 0;
		caillou(Vec3d(p.x * l + n * 17.31, p.y * l - n * 9.77, p.z * l + n * 5.13), n, &t);
		pierres += 0.35 * t;
	}
	double base = (0.17 + (0.075 - 0.17) * m) * std::exp(0.8 * detail + pierres);
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
	// Étape 7 : la lumière du coin (couleur, direction, horizon) est calculée en même temps que sa
	// hauteur (les mêmes détails du relief servent aux deux).
	Vec3d pos[NB_COINS];
	Vec3d somme;
	for (int i = 0; i < NB_COINS; i++) {
		double h = lumiere_coin(dir[i], nais[i], m.albedo[i], m.direction[i], m.horizon[i]);
		pos[i] = dir[i] * (rayon + h);
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
	double reste = 1.5 * amplitude(oct_fin) / (1.0 - std::pow(2.0, -0.8)); // 1,5 : les cailloux
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

	// 4. Les rayons : leur centre (pour le posemètre) ; leur lumière est rangée sur les coins.
	for (int t = 0; t < NB_RAYONS; t++) {
		const int *c = TABLE.coins[t];
		Vec3d d = (pos[c[0]] + pos[c[1]] + pos[c[2]]) * (1.0 / 3.0) - m.centre;
		m.centres[t][0] = (float)d.x;
		m.centres[t][1] = (float)d.y;
		m.centres[t][2] = (float)d.z;
	}
	if (parent) {
		// Départ du glissement des couleurs : comme pour les positions, la valeur du parent sous le coin.
		const int(*C)[2] = ENFANTS[k];
		for (int b = 0; b <= 8; b++) {
			for (int a = 0; a + b <= 8; a++) {
				int x = (C[0][0] * 8 + (C[1][0] - C[0][0]) * a + (C[2][0] - C[0][0]) * b) / 8;
				int y = (C[0][1] * 8 + (C[1][1] - C[0][1]) * a + (C[2][1] - C[0][1]) * b) / 8;
				int i = coin(a, b);
				if (x % 2 == 0 && y % 2 == 0) {
					std::memcpy(m.albedo_depart[i], parent->albedo[coin(x / 2, y / 2)], sizeof(float) * 3);
					std::memcpy(m.horizon_depart[i], parent->horizon[coin(x / 2, y / 2)], sizeof(float) * NB_AZIMUTS);
				} else {
					int a1, b1, a2, b2;
					voisins_milieu(x, y, 1, a1, b1, a2, b2);
					const float *u = parent->albedo[coin(a1 / 2, b1 / 2)];
					const float *v = parent->albedo[coin(a2 / 2, b2 / 2)];
					for (int q = 0; q < 3; q++) m.albedo_depart[i][q] = 0.5f * (u[q] + v[q]);
					const float *hu = parent->horizon[coin(a1 / 2, b1 / 2)];
					const float *hv = parent->horizon[coin(a2 / 2, b2 / 2)];
					for (int q = 0; q < NB_AZIMUTS; q++) m.horizon_depart[i][q] = 0.5f * (hu[q] + hv[q]);
				}
			}
		}
	} else {
		std::memcpy(m.albedo_depart, m.albedo, sizeof(m.albedo));
		std::memcpy(m.horizon_depart, m.horizon, sizeof(m.horizon));
	}
}

// Repère du lieu, le même dans planete.gdshader : t1 = « est » (perpendiculaire à l'axe Y de l'astre),
// t2 = « nord ». Il ne dépend que de la direction : deux morceaux voisins trouvent le même.
void ArbreLumiere::repere_lieu(const Vec3d &d, Vec3d &t1, Vec3d &t2) {
	Vec3d e = Vec3d(0, 1, 0).cross(d);
	if (e.length() < 1e-9) {
		e = Vec3d(1, 0, 0).cross(d); // tout près d'un pôle
	}
	t1 = e.normalized();
	t2 = d.cross(t1);
}

// Lumière d'un coin : couleur du sol, direction moyenne de la surface et son étalement, et (étape 7)
// hauteur de l'horizon dans 4 directions. Tout ne dépend que de la direction du coin et de son niveau
// de naissance : deux morceaux qui partagent ce coin trouvent exactement la même chose (pas de couture).
double ArbreLumiere::lumiere_coin(const Vec3d &d, int nais, float albedo[3], float direction[3],
		float horizon[NB_AZIMUTS]) const {
	int oct = std::max(0, nais - 1);
	couleur_sol(d, oct, albedo);
	// Pente du relief : différences de hauteur à l'écart des coins de ce niveau, de part et d'autre.
	// Chaque détail (octave) est gardé à part : sa pente sert ensuite pour l'horizon.
	double e = 1.0515 * rayon / std::ldexp(1.0, nais) * 0.5;
	Vec3d t1, t2;
	repere_lieu(d, t1, t2);
	double k = e / rayon;
	const Vec3d u_pts[4] = { (d + t1 * k).normalized(), (d - t1 * k).normalized(), (d + t2 * k).normalized(),
		(d - t2 * k).normalized() };
	double v0[40], g1[40], g2[40];
	double h0 = 0, hp[4] = { 0, 0, 0, 0 };
	Vec3d p0 = d * rayon;
	for (int n = 0; n < oct; n++) {
		v0[n] = octave(p0, n);
		double o[4];
		for (int j = 0; j < 4; j++) {
			o[j] = octave(u_pts[j] * rayon, n);
			hp[j] += o[j];
		}
		h0 += v0[n];
		g1[n] = (o[0] - o[1]) / (2.0 * e);
		g2[n] = (o[2] - o[3]) / (2.0 * e);
	}
	auto point = [&](int j) { return u_pts[j] * (rayon + hp[j]); };
	Vec3d gx = point(0) - point(1);
	Vec3d gy = point(2) - point(3);
	Vec3d n = gx.cross(gy).normalized();
	if (n.dot(d) < 0) {
		n = n * -1.0;
	}
	// Étalement : la pente des détails plus fins que ce coin (ils sont dans le rayon, pas dans le dessin).
	double etal = 0;
	for (int q = oct; q < oct + 8; q++) {
		double pente = 2.0 * amplitude(q) / longueur_onde(q);
		if (q >= OCTAVE_CAILLOUX_MIN && q <= OCTAVE_CAILLOUX_MAX) {
			pente *= 1.5; // les bords raides des cailloux
		}
		etal += pente * pente;
	}
	// Cône de petites faces dont l'angle moyen avec la direction moyenne vaut atan(pente) :
	// longueur de la moyenne = (1 + cos b) / 2.
	double cb = 1.0 / std::sqrt(1.0 + etal);
	double longueur = std::clamp((1.0 + cb) * 0.5, 0.5, 1.0);
	direction[0] = (float)(n.x * longueur);
	direction[1] = (float)(n.y * longueur);
	direction[2] = (float)(n.z * longueur);

	// Étape 7 : l'horizon. On marche vers l'est, le nord, l'ouest et le sud, à des distances qui doublent
	// (2, 4, 8, 16 fois l'écart des coins) puis quadruplent, jusqu'à 60 km (planète d'essai). À chaque pas,
	// les détails de la taille de la distance sont calculés pour de vrai ; les plus grands, qui ne font
	// qu'incliner le sol à cette échelle, suivent leur pente ; les plus petits ne cachent presque rien
	// de si loin. La courbure de la planète fait baisser le sol au loin (D² / 2R).
	double prefixe1[41], prefixe2[41];
	prefixe1[0] = prefixe2[0] = 0;
	for (int q = 0; q < oct; q++) {
		prefixe1[q + 1] = prefixe1[q] + g1[q];
		prefixe2[q + 1] = prefixe2[q] + g2[q];
	}
	const Vec3d axes[NB_AZIMUTS] = { t1, t2, t1 * -1.0, t2 * -1.0 };
	const double signe1[NB_AZIMUTS] = { 1, 0, -1, 0 }, signe2[NB_AZIMUTS] = { 0, 1, 0, -1 };
	double d_max = 60000.0 * rayon / 600000.0;
	double l0 = longueur_onde(0);
	for (int j = 0; j < NB_AZIMUTS; j++) {
		double meilleur = -1.5707963;
		double D = 2.0 * e;
		for (int pas = 0; pas < 40 && (D <= d_max || pas < 2); pas++) {
			int n_hi = std::min(oct - 1, (int)std::floor(std::log2(2.0 * l0 / D)));
			int n_lo = std::max(0, n_hi - 5);
			double dh = 0;
			if (oct > 0) {
				if (n_hi < 0) {
					n_lo = oct; // tout est plus grand que la distance : seulement la pente
				}
				dh = (prefixe1[n_lo] * signe1[j] + prefixe2[n_lo] * signe2[j]) * D;
				if (n_hi >= n_lo) {
					Vec3d q = (d + axes[j] * (D / rayon)).normalized() * rayon;
					for (int o = n_lo; o <= n_hi; o++) {
						dh += octave(q, o) - v0[o];
					}
				}
			}
			dh -= D * D / (2.0 * rayon);
			meilleur = std::max(meilleur, std::atan2(dh, D));
			D *= pas < 3 ? 2.0 : 4.0;
		}
		horizon[j] = (float)meilleur;
	}
	return h0;
}

// Part du disque d'une étoile (direction s, rayon apparent a) au-dessus de l'horizon h (4 azimuts) du
// lieu (verticale up, repère t1, t2). Même formule que planete.gdshader : l'horizon dans la direction de
// l'étoile est un mélange des 4 valeurs, et le bord de l'ombre est adouci sur le diamètre du disque
// (plus 0,6°, la finesse de la mesure de l'horizon).
double ArbreLumiere::part_sous_horizon(const Vec3d &up, const Vec3d &t1, const Vec3d &t2, const float h[NB_AZIMUTS],
		const Vec3d &s, double a) {
	double se = std::clamp(s.dot(up), -1.0, 1.0);
	double ce = s.dot(t1), cn = s.dot(t2);
	double l = std::sqrt(ce * ce + cn * cn);
	double hz = 0;
	if (l > 1e-9) {
		double c = ce / l, sn = cn / l;
		double pc = std::max(c, 0.0), pn = std::max(sn, 0.0), mc = std::max(-c, 0.0), mn = std::max(-sn, 0.0);
		hz = h[0] * pc * pc + h[1] * pn * pn + h[2] * mc * mc + h[3] * mn * mn;
	} else {
		hz = -1.5707963;
	}
	double el = std::asin(se);
	double demi = a + 0.005;
	return std::clamp((el - hz) / (2.0 * demi) + 0.5, 0.0, 1.0);
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

// Taille d'un rayon de ce morceau à l'écran, en pixels. Un sol vu de biais paraît plus petit
// (on compte la surface à l'écran : racine du cosinus, au moins 0,2).
double ArbreLumiere::taille_ecran(const Morceau &m) const {
	Vec3d v = m.centre - cam;
	double dist = v.length();
	double d = std::max(dist - m.rayon_englobant, 1e-5);
	double biais = 1.0;
	if (dist > m.rayon_englobant) {
		double c = std::fabs(m.centre.normalized().dot(v * (1.0 / dist)));
		biais = std::sqrt(std::max(c, 0.2));
	}
	return m.cote / d * px_par_radian / COUPES * biais;
}

// Regarde un morceau : invisible → rien ; assez fin → affiché ; trop gros → dans la file des coupes.
void ArbreLumiere::considerer(Morceau *m) {
	m->derniere_image = image;
	if (!visible(*m)) {
		return;
	}
	double t = taille_ecran(*m);
	bool etait_coupe = interieurs_prec.count(m->adresse) > 0;
	double seuil = etait_coupe ? seuil_fusion : seuil_couper;
	if (t > seuil && m->niveau < NIVEAU_MAX) {
		file.push_back({ t, m });
		std::push_heap(file.begin(), file.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
	} else {
		affiches.push_back(m);
	}
}

// Coupe les morceaux du plus gros à l'écran au plus petit, tant qu'il reste des places : le sol
// tout près de l'œil passe toujours en premier.
void ArbreLumiere::visiter(Morceau *) {
	auto plus_petit = [](const std::pair<double, Morceau *> &a, const std::pair<double, Morceau *> &b) { return a.first < b.first; };
	while (!file.empty()) {
		std::pop_heap(file.begin(), file.end(), plus_petit);
		auto [t, m] = file.back();
		file.pop_back();
		if (budget_coupes < 3) {
			affiches.push_back(m);
			continue;
		}
		Morceau *enfants[4];
		bool prets = true;
		for (int i = 0; i < 4; i++) {
			uint64_t a = (m->adresse << 2) | (uint64_t)i;
			auto it = cache.find(a);
			if (it == cache.end()) {
				prets = false;
				if (deja_demande.insert(a).second) {
					demandes.push_back({ t, a });
				}
			} else {
				enfants[i] = it->second.get();
			}
		}
		if (!prets) {
			affiches.push_back(m);
			continue;
		}
		budget_coupes -= 3;
		interieurs.insert(m->adresse);
		for (int i = 0; i < 4; i++) {
			considerer(enfants[i]);
		}
	}
}

int ArbreLumiere::choisir(const PackedFloat64Array &p_camera, const PackedFloat32Array &p_axes, double p_tan_h,
		double p_tan_v, double p_hauteur_px, double p_temps) {
	if (occupant.empty()) {
		configurer(rayon, 1, places);
	}
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
	file.clear();
	for (int f = 0; f < 20; f++) {
		considerer(assurer((1ULL << 5) | (uint64_t)f));
	}
	visiter(nullptr);
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

// Calcule les morceaux demandés, les plus gros à l'écran d'abord, par paquets de 8 répartis sur les
// fils de calcul, jusqu'à max_morceaux ou jusqu'à ce que le temps donné (ms) soit dépassé : une image
// ne doit jamais attendre longtemps (le reste sera fait aux images suivantes).
int ArbreLumiere::eclairer(int p_max, double p_budget_ms) {
	int n = std::min((int)demandes.size(), std::max(p_max, 0));
	auto debut = std::chrono::steady_clock::now();
	int fait = 0;
	const int PAQUET = 8;
	for (int depart = 0; depart < n; depart += PAQUET) {
		Travail t;
		t.arbre = this;
		std::vector<std::unique_ptr<Morceau>> neufs;
		for (int i = depart; i < std::min(n, depart + PAQUET); i++) {
			uint64_t a = demandes[i].second;
			auto it = cache.find(a >> 2);
			if (it == cache.end() || cache.count(a)) {
				continue;
			}
			neufs.push_back(std::make_unique<Morceau>());
			t.sortie.push_back(neufs.back().get());
			t.parents.push_back(it->second.get());
			t.enfants.push_back((int)(a & 3));
		}
		int nb = (int)t.sortie.size();
		if (nb >= 2 && WorkerThreadPool::get_singleton()) {
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
		fait += nb;
		double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - debut).count();
		if (ms > p_budget_ms) {
			break;
		}
	}
	oublier_anciens();
	return fait;
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
// Hauteur de l'horizon (rad) → 0..1 : x = h / 90°, code = 0,5 + 0,5 signe(x) √|x| (planete.gdshader décode).
static inline double code_horizon(double h) {
	double x = std::clamp(h / 1.5707963267948966, -1.0, 1.0);
	return 0.5 + 0.5 * (x < 0 ? -std::sqrt(-x) : std::sqrt(x));
}
static inline double decode_horizon(double c) {
	double x = 2.0 * c - 1.0;
	return (x < 0 ? -x * x : x * x) * 1.5707963267948966;
}

void ArbreLumiere::ecrire_place(int p, const Morceau &m) {
	uint8_t *r = tampon_rayons.ptrw();
	for (int k = 0; k < NB_COINS; k++) {
		int o = (p * NB_COINS * TEXELS_PAR_COIN_LUMIERE + k * TEXELS_PAR_COIN_LUMIERE) * 4;
		// Couleur codée par sa racine carrée : plus de nuances dans les sombres (8 bits seulement).
		for (int i = 0; i < 3; i++) {
			r[o + i] = octet(std::sqrt(m.albedo_depart[k][i]));
			r[o + 4 + i] = octet(std::sqrt(m.albedo[k][i]));
			r[o + 8 + i] = octet(m.direction[k][i] * 0.5 + 0.5);
		}
		r[o + 3] = 255;
		r[o + 7] = 255;
		r[o + 11] = 255;
		// Étape 7 : l'horizon (4 azimuts), codé par la racine de sa hauteur : plus de finesse près de 0
		// (là où le Soleil se couche derrière les cailloux).
		for (int q = 0; q < NB_AZIMUTS; q++) {
			r[o + 12 + q] = octet(code_horizon(m.horizon_depart[k][q]));
			r[o + 16 + q] = octet(code_horizon(m.horizon[k][q]));
		}
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
		double p_tan_h, double p_tan_v, const Vector3 &p_soleil, double p_eclairement, double p_fond,
		const PackedFloat64Array &p_occulteur, double p_soleil_angle) const {
	const int NX = 16, NY = 9;
	const bool avec_occulteur = p_occulteur.size() >= 4 && p_occulteur[3] > 0.0;
	Vec3d occ_c = avec_occulteur ? Vec3d(p_occulteur[0], p_occulteur[1], p_occulteur[2]) : Vec3d();
	double occ_r = avec_occulteur ? p_occulteur[3] : 0.0;
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
			const int *cc = TABLE.coins[t];
			Vec3d n;
			float al[3] = { 0, 0, 0 };
			for (int q = 0; q < 3; q++) {
				n = n + Vec3d(m->direction[cc[q]][0], m->direction[cc[q]][1], m->direction[cc[q]][2]) * (1.0 / 3.0);
				for (int w = 0; w < 3; w++) al[w] += m->albedo[cc[q]][w] / 3.0f;
			}
			double ln = n.length();
			double vers_oeil = -n.dot(v) / (ln * v.length());
			if (vers_oeil <= 0) continue; // face cachée
			int i = std::min(NX - 1, (int)((x + 1) * 0.5 * NX));
			int j = std::min(NY - 1, (int)((y + 1) * 0.5 * NY));
			double cs = n.dot(s) / ln;
			// Même loi que planete.gdshader : la lumière moyenne d'un cône de petites faces.
			double cb = std::clamp(2.0 * ln - 1.0, -1.0, 1.0);
			double sb = std::sqrt(std::max(1.0 - cb * cb, 0.0));
			double direct = cs > sb ? cs : (cs < -sb ? 0.0 : (cs + sb) * (cs + sb) / (4.0 * sb + 1e-6));
			double y_al = 0.2126 * al[0] + 0.7152 * al[1] + 0.0722 * al[2];
			if (direct > 0.0) {
				// Étape 6 : l'astre lui-même cache l'étoile quand elle est sous l'horizon (côté nuit, même
				// sur une pente tournée vers elle). Boule au niveau 0 (ou juste sous le point, s'il est plus bas).
				Vec3d p = c + v;
				double dp = p.length();
				double haut = p.dot(s) / dp;
				if (haut < 0.3) {
					direct *= part_soleil_visible(p, Vec3d(), std::min(rayon, dp * 0.9999), s, p_soleil_angle);
				}
			}
			if (direct > 0.0) {
				// Étape 7 : l'ombre du relief proche et des cailloux (horizon des 3 coins du rayon, tel que
				// la carte graphique le reçoit : codé sur 8 bits).
				float hz[NB_AZIMUTS] = { 0, 0, 0, 0 };
				for (int q = 0; q < 3; q++) {
					for (int w = 0; w < NB_AZIMUTS; w++) {
						hz[w] += (float)(decode_horizon(octet(code_horizon(m->horizon[cc[q]][w])) / 255.0) / 3.0);
					}
				}
				Vec3d up = (c + v).normalized(), e1, e2;
				repere_lieu(up, e1, e2);
				direct *= part_sous_horizon(up, e1, e2, hz, s, p_soleil_angle);
			}
			if (avec_occulteur && direct > 0.0) {
				direct *= part_soleil_visible(c + v, occ_c, occ_r, s, p_soleil_angle);
			}
			double l = y_al * p_eclairement * direct / 3.14159265358979323846;
			double ap = a_rayon * vers_oeil / (z * z);
			somme[j * NX + i] += l * ap;
			aire[j * NX + i] += ap;
		}
	}
	PackedFloat32Array out;
	out.resize(NX * NY);
	derniere_couverture.resize(NX * NY);
	for (int k = 0; k < NX * NY; k++) {
		double cov = std::min(1.0, aire[k] / aire_case);
		derniere_couverture.set(k, (float)cov);
		double moy = aire[k] > 0 ? somme[k] / aire[k] : 0.0;
		out[k] = (float)(moy * cov + p_fond * (1.0 - cov));
	}
	return out;
}

// ---------------------------------------------------------------------------------------------
// Divers
// ---------------------------------------------------------------------------------------------

// Le constructeur ne fait rien de lourd : l'éditeur de Godot crée parfois un exemplaire juste pour
// lire ses réglages, et le détruit tard (vu dans le cloud : plantage à la fermeture sinon).
ArbreLumiere::ArbreLumiere() {}
ArbreLumiere::~ArbreLumiere() {}

void ArbreLumiere::configurer(double p_rayon, int64_t p_graine, int p_places) {
	rayon = p_rayon;
	graine = melanger((uint64_t)p_graine);
	places = std::max(64, (p_places / 4) * 4);
	relief_max = 0;
	for (int n = 0; n < 40; n++) {
		relief_max += amplitude(n) * ((n >= OCTAVE_CAILLOUX_MIN && n <= OCTAVE_CAILLOUX_MAX) ? 1.5 : 1.0);
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

// Part d'un disque de rayon a cachée par un disque de rayon b dont le centre est à e (même formule
// que soleil.gd et planete.gdshader).
double ArbreLumiere::recouvrement(double a, double b, double e) {
	if (e >= a + b) return 0.0;
	if (e <= b - a) return 1.0;
	if (e <= a - b) return (b * b) / (a * a);
	double a2 = a * a, b2 = b * b;
	double u = std::clamp((e * e + a2 - b2) / (2.0 * e * a), -1.0, 1.0);
	double w = std::clamp((e * e + b2 - a2) / (2.0 * e * b), -1.0, 1.0);
	double aire = a2 * std::acos(u) + b2 * std::acos(w)
			- 0.5 * std::sqrt(std::max((-e + a + b) * (e + a - b) * (e - a + b) * (e + a + b), 0.0));
	return std::clamp(aire / (3.14159265358979323846 * a2), 0.0, 1.0);
}

double ArbreLumiere::part_soleil_visible(const Vec3d &p, const Vec3d &c, double r, const Vec3d &s, double a) {
	Vec3d v = c - p;
	double dc = v.length();
	if (dc <= r) return 0.0;
	double cs = std::clamp(v.dot(s) / dc, -1.0, 1.0);
	double e = std::acos(cs);
	double b = std::asin(std::min(r / dc, 1.0));
	if (e >= a + b) return 1.0;
	return 1.0 - recouvrement(a, b, e);
}

double ArbreLumiere::part_visible(const PackedFloat64Array &p, const PackedFloat64Array &o, const Vector3 &s,
		double a) const {
	if (p.size() < 3 || o.size() < 4) return 1.0;
	return part_soleil_visible(Vec3d(p[0], p[1], p[2]), Vec3d(o[0], o[1], o[2]), o[3],
			Vec3d(s.x, s.y, s.z).normalized(), a);
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
	r.resize(NB_COINS * 3);
	for (int t = 0; t < NB_COINS; t++)
		for (int i = 0; i < 3; i++) r[t * 3 + i] = m->albedo[t][i];
	return r;
}

PackedFloat32Array ArbreLumiere::directions_morceau(int64_t a) {
	Morceau *m = assurer((uint64_t)a);
	PackedFloat32Array r;
	r.resize(NB_COINS * 3);
	for (int t = 0; t < NB_COINS; t++)
		for (int i = 0; i < 3; i++) r[t * 3 + i] = m->direction[t][i];
	return r;
}

PackedFloat32Array ArbreLumiere::horizons_morceau(int64_t a) {
	Morceau *m = assurer((uint64_t)a);
	PackedFloat32Array r;
	r.resize(NB_COINS * NB_AZIMUTS);
	for (int t = 0; t < NB_COINS; t++)
		for (int i = 0; i < NB_AZIMUTS; i++) r[t * NB_AZIMUTS + i] = m->horizon[t][i];
	return r;
}

PackedFloat32Array ArbreLumiere::horizon_point(const PackedFloat64Array &p, int nais) const {
	float al[3], di[3], hz[NB_AZIMUTS];
	lumiere_coin(Vec3d(p[0], p[1], p[2]).normalized(), nais, al, di, hz);
	PackedFloat32Array r;
	for (int i = 0; i < NB_AZIMUTS; i++) r.push_back(hz[i]);
	return r;
}

double ArbreLumiere::part_horizon(const PackedFloat64Array &p, int nais, const Vector3 &s, double a) const {
	float al[3], di[3], hz[NB_AZIMUTS];
	Vec3d d = Vec3d(p[0], p[1], p[2]).normalized(), t1, t2;
	lumiere_coin(d, nais, al, di, hz);
	repere_lieu(d, t1, t2);
	return part_sous_horizon(d, t1, t2, hz, Vec3d(s.x, s.y, s.z).normalized(), a);
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
	ClassDB::bind_method(D_METHOD("eclairer", "max_morceaux", "budget_ms"), &ArbreLumiere::eclairer, DEFVAL(3.0));
	ClassDB::bind_method(D_METHOD("tampon_instances", "rotation", "decalage"), &ArbreLumiere::tampon_instances);
	ClassDB::bind_method(D_METHOD("donnees_rayons"), &ArbreLumiere::donnees_rayons);
	ClassDB::bind_method(D_METHOD("donnees_coins"), &ArbreLumiere::donnees_coins);
	ClassDB::bind_method(D_METHOD("a_change"), &ArbreLumiere::a_change);
	ClassDB::bind_method(D_METHOD("posemetre", "camera", "axes", "tan_h", "tan_v", "soleil", "eclairement", "fond",
			"occulteur", "soleil_angle"), &ArbreLumiere::posemetre, DEFVAL(PackedFloat64Array()), DEFVAL(0.004652));
	ClassDB::bind_method(D_METHOD("couverture"), &ArbreLumiere::couverture);
	ClassDB::bind_method(D_METHOD("part_visible", "point", "occulteur", "soleil", "soleil_angle"), &ArbreLumiere::part_visible);
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
	ClassDB::bind_method(D_METHOD("horizons_morceau", "adresse"), &ArbreLumiere::horizons_morceau);
	ClassDB::bind_method(D_METHOD("horizon_point", "direction", "naissance"), &ArbreLumiere::horizon_point);
	ClassDB::bind_method(D_METHOD("part_horizon", "direction", "naissance", "etoile", "rayon_angle"), &ArbreLumiere::part_horizon);
}
