// Einstein C : la lumière qui traverse un trou de ver d'Ellis (voir trou_de_ver.h).
#include "trou_de_ver.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

namespace {
constexpr double PI_D = 3.14159265358979323846;
constexpr double PSI_MIN = -50.0;   // tout contre le bord de la gorge, la lumière a fait beaucoup de tours
constexpr double MU_MAX = 2000.0;   // grossissement le plus fort gardé

struct Branche {
	std::vector<double> theta;
	std::vector<double> psi;
};

// Image d'une étoile à l'angle psi dans une branche (ψ monotone en θ) : θ et grossissement μ.
void image(const Branche &b, double psi, double &th_out, double &mu_out) {
	th_out = 0.0;
	mu_out = 0.0;
	const int n = (int)b.psi.size();
	const bool monte = b.psi[n - 1] > b.psi[0];
	const double lo = monte ? b.psi[0] : b.psi[n - 1];
	const double hi = monte ? b.psi[n - 1] : b.psi[0];
	if (psi < lo || psi > hi) {
		return;
	}
	int a = 0;
	int c = n - 1;
	while (c - a > 1) {
		const int m = (a + c) / 2;
		if ((b.psi[m] < psi) == monte) {
			a = m;
		} else {
			c = m;
		}
	}
	const double dpsi = b.psi[c] - b.psi[a];
	if (dpsi == 0.0) {
		th_out = b.theta[a];
		return;
	}
	const double f = (psi - b.psi[a]) / dpsi;
	const double dth = b.theta[c] - b.theta[a];
	const double th = b.theta[a] + dth * f;
	const double s = std::sin(std::fabs(psi));
	th_out = th;
	if (s < 1e-6 && std::fabs(std::sin(th)) < 1e-5) {
		// tout près de l'axe (droit devant ou droit derrière) : sin θ / sin ψ → dθ/dψ
		const double g = dth / dpsi;
		mu_out = std::min(g * g, MU_MAX);
		return;
	}
	mu_out = s > 1e-12 ? std::min(std::fabs(std::sin(th) * dth / (s * dpsi)), MU_MAX) : MU_MAX;
}
} // namespace

double TrouDeVer::carlson_rf(double x, double y, double z) {
	// Duplication de Carlson (1995), précision relative ~1e-15.
	for (int i = 0; i < 60; i++) {
		const double sx = std::sqrt(x);
		const double sy = std::sqrt(y);
		const double sz = std::sqrt(z);
		const double l = sx * (sy + sz) + sy * sz;
		x = 0.25 * (x + l);
		y = 0.25 * (y + l);
		z = 0.25 * (z + l);
		const double m = (x + y + z) / 3.0;
		const double dx = 1.0 - x / m;
		const double dy = 1.0 - y / m;
		const double dz = 1.0 - z / m;
		if (std::max({ std::fabs(dx), std::fabs(dy), std::fabs(dz) }) < 1e-4) {
			const double e2 = dx * dy - dz * dz;
			const double e3 = dx * dy * dz;
			return (1.0 - e2 / 10.0 + e3 / 14.0 + e2 * e2 / 24.0 - 3.0 * e2 * e3 / 44.0) / std::sqrt(m);
		}
	}
	return 1.0 / std::sqrt((x + y + z) / 3.0);
}

double TrouDeVer::elliptique_f(double phi, double k) {
	const double s = std::sin(phi);
	const double c = std::cos(phi);
	return s * carlson_rf(c * c, std::max(1.0 - k * k * s * s, 0.0), 1.0);
}

double TrouDeVer::elliptique_k(double k) {
	return carlson_rf(0.0, std::max(1.0 - k * k, 1e-300), 1.0);
}

double TrouDeVer::angle_parcouru(double theta, double l_o, double a, bool &traverse) {
	const double r_o = std::sqrt(a * a + l_o * l_o);
	const double b = r_o * std::sin(theta);
	traverse = false;
	if (b < 1e-15 * r_o) {
		// rayon droit : vers le trou il traverse (b = 0 < a), à l'opposé il s'en va
		traverse = theta < 0.5 * PI_D;
		return 0.0;
	}
	if (theta < 0.5 * PI_D && b < a) {
		// à travers la gorge : ∫ de −∞ à l_o = (b/a)·[2K(b/a) − F(asin(a/r_o), b/a)]
		traverse = true;
		const double k = b / a;
		return k * (2.0 * elliptique_k(k) - elliptique_f(std::asin(std::min(a / r_o, 1.0)), k));
	}
	if (b < a) {
		// s'éloigne sans point de retour : ∫ de l_o à +∞ = (b/a)·F(asin(a/r_o), b/a)
		const double k = b / a;
		return k * elliptique_f(std::asin(std::min(a / r_o, 1.0)), k);
	}
	// b > a : point de retour en r = b. ∫ de l_o à +∞ = F(asin(b/r_o), a/b) ; aller-retour = 2K(a/b).
	const double k = a / b;
	const double loin = elliptique_f(std::asin(std::min(b / r_o, 1.0)), k);
	if (theta >= 0.5 * PI_D) {
		return loin;
	}
	return 2.0 * elliptique_k(k) - loin;
}

Vector2 TrouDeVer::angle_origine(double theta, double l_o, double a) const {
	bool traverse = false;
	const double phi = angle_parcouru(theta, l_o, a, traverse);
	return Vector2((real_t)std::max(PI_D - phi, PSI_MIN), traverse ? -1.0f : 1.0f);
}

double TrouDeVer::angle_gorge(double l_o, double a) const {
	return std::asin(std::min(a / std::sqrt(a * a + l_o * l_o), 1.0));
}

double TrouDeVer::deviation(double b, double a) const {
	if (b <= a) {
		return NAN;
	}
	return 2.0 * elliptique_k(a / b) - PI_D;
}

PackedFloat32Array TrouDeVer::table(double l_o, double a) const {
	const int n = POINTS;
	const double tc = angle_gorge(l_o, a);
	Branche dedans;
	Branche dehors;
	dedans.theta.resize(n);
	dedans.psi.resize(n);
	dehors.theta.resize(n);
	dehors.psi.resize(n);
	bool t = false;
	for (int k = 0; k < n; k++) {
		const double x = (double)k / (n - 1);
		// dans la gorge : serré près du bord (x = 1), où tout change vite
		const double th0 = tc * (1.0 - (1.0 - x) * (1.0 - x)) * (1.0 - 1e-12);
		dedans.theta[k] = th0;
		dedans.psi[k] = std::max(PI_D - angle_parcouru(th0, l_o, a, t), PSI_MIN);
		// dehors : serré près du bord (x = 0)
		const double xs = k == 0 ? 0.5 / n : x;
		const double th1 = tc + (PI_D - tc) * xs * xs;
		dehors.theta[k] = th1;
		dehors.psi[k] = std::max(PI_D - angle_parcouru(th1, l_o, a, t), PSI_MIN);
	}
	PackedFloat32Array out;
	out.resize(n * 4 * 4);
	float *p = out.ptrw();
	for (int k = 0; k < n; k++) {
		p[(0 * n + k) * 4 + 0] = (float)dedans.psi[k];
		p[(1 * n + k) * 4 + 0] = (float)dehors.psi[k];
		const double s = (double)k / (n - 1);
		const double psi_s = std::max(PI_D * s * s, 1e-6);
		double th1, mu1, th2, mu2;
		image(dehors, psi_s, th1, mu1);
		image(dehors, -psi_s, th2, mu2);
		float *q = p + (2 * n + k) * 4;
		q[0] = (float)th1;
		q[1] = (float)mu1;
		q[2] = (float)th2;
		q[3] = (float)mu2;
		image(dedans, psi_s, th1, mu1);
		image(dedans, -psi_s, th2, mu2);
		q = p + (3 * n + k) * 4;
		q[0] = (float)th1;
		q[1] = (float)mu1;
		q[2] = (float)th2;
		q[3] = (float)mu2;
	}
	return out;
}

void TrouDeVer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("angle_origine", "theta", "l_o", "a"), &TrouDeVer::angle_origine);
	ClassDB::bind_method(D_METHOD("angle_gorge", "l_o", "a"), &TrouDeVer::angle_gorge);
	ClassDB::bind_method(D_METHOD("deviation", "b", "a"), &TrouDeVer::deviation);
	ClassDB::bind_method(D_METHOD("table", "l_o", "a"), &TrouDeVer::table);
}
