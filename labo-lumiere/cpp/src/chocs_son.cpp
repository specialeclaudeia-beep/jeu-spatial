// Moteur audio, phase 3 : sons brefs fabriqués en direct (voir chocs_son.h).
#include "chocs_son.h"

#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <chrono>
#include <climits>
#include <cmath>

using namespace godot;

namespace {
constexpr double PI_D = 3.14159265358979323846;
constexpr double SIGMA2 = 1.0 / 3.0;      // carré moyen du bruit de départ (uniforme entre −1 et 1)
constexpr double SEUIL_FIN = 3e-5;        // −90 dB pleine échelle : en dessous, le choc est fini
constexpr double FONDU = 0.03;            // s : un choc qu'on interrompt s'éteint en 30 ms

inline uint32_t xorshift(uint32_t &x) {
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	return x;
}

inline double bruit(uint32_t &x) {
	return (double)(int32_t)xorshift(x) * (1.0 / 2147483648.0);
}

inline double normal(uint32_t &x) {
	const double u1 = (xorshift(x) + 1.0) * (1.0 / 4294967297.0);
	const double u2 = xorshift(x) * (1.0 / 4294967296.0);
	return std::sqrt(-2.0 * std::log(u1)) * std::cos(2.0 * PI_D * u2);
}

// Résonateur AR(2) de fréquence f et de perte eta ; renvoie a1, a2 et le gain qui donne une sortie de variance 1.
void resonateur(double f, double eta, double fs, double &a1, double &a2, double &g) {
	f = std::clamp(f, 20.0, 0.45 * fs);
	const double r = std::exp(-PI_D * f * eta / fs);
	a1 = 2.0 * r * std::cos(2.0 * PI_D * f / fs);
	a2 = r * r;
	const double k = (1.0 + a2) / ((1.0 - a2) * ((1.0 + a2) * (1.0 + a2) - a1 * a1));
	g = (k > 0.0 && std::isfinite(k)) ? 1.0 / std::sqrt(SIGMA2 * k) : 0.0;
}

void max_atomique(std::atomic<float> &a, float v) {
	float x = a.load(std::memory_order_relaxed);
	while (v > x && !a.compare_exchange_weak(x, v, std::memory_order_relaxed)) {
	}
}

void max_atomique_int(std::atomic<int> &a, int v) {
	int x = a.load(std::memory_order_relaxed);
	while (v > x && !a.compare_exchange_weak(x, v, std::memory_order_relaxed)) {
	}
}
} // namespace

// =====================================================================
// ChocsSon : le fil principal dépose les chocs
// =====================================================================
ChocsSon::ChocsSon() {}

bool ChocsSon::frapper(const PackedFloat32Array &p_modes, const PackedFloat32Array &p_options) {
	const uint32_t t = tete.load(std::memory_order_relaxed);
	const uint32_t q = queue.load(std::memory_order_acquire);
	if (t - q >= (uint32_t)FILE) {
		refuses.fetch_add(1, std::memory_order_relaxed);
		return false;
	}
	Choc &c = file[t % FILE];
	c.n = std::min((int)(p_modes.size() / 4), MODES);
	for (int i = 0; i < c.n; i++) {
		c.f[i] = p_modes[4 * i];
		c.tau[i] = p_modes[4 * i + 1];
		c.a[i] = p_modes[4 * i + 2];
		c.retard[i] = p_modes[4 * i + 3];
	}
	for (int k = 0; k < OPTIONS; k++) {
		c.o[k] = k < p_options.size() ? p_options[k] : 0.0f;
	}
	if (p_options.size() < 10) {
		c.o[8] = 1.0f;   // gains gauche et droit par défaut
		c.o[9] = 1.0f;
	}
	tete.store(t + 1, std::memory_order_release);
	return true;
}

void ChocsSon::couper() { coupures.fetch_add(1); }
void ChocsSon::set_taux(int p_taux) { taux.store(std::max(0, p_taux)); }
int ChocsSon::get_taux() const { return taux.load(); }
int ChocsSon::actifs() const { return n_actifs.load(); }
bool ChocsSon::est_silencieux() const { return n_actifs.load() == 0 && tete.load() == queue.load(); }

Dictionary ChocsSon::mesures() const {
	Dictionary d;
	const uint64_t n = echantillons.load();
	const double t = taux.load() > 0 ? taux.load() : AudioServer::get_singleton()->get_mix_rate();
	d["charge"] = n > 0 ? (double)ns_calcul.load() * 1e-9 / ((double)n / t) : 0.0;
	d["echantillons"] = (int64_t)n;
	d["crete"] = crete.load();
	d["non_finis"] = non_finis.load();
	d["joues"] = joues.load();
	d["voles"] = voles.load();
	d["refuses"] = refuses.load();
	d["actifs_max"] = actifs_max.load();
	return d;
}

void ChocsSon::remettre_mesures() {
	ns_calcul.store(0);
	echantillons.store(0);
	crete.store(0.0f);
	non_finis.store(0);
	joues.store(0);
	voles.store(0);
	refuses.store(0);
	actifs_max.store(0);
}

Ref<AudioStreamPlayback> ChocsSon::_instantiate_playback() const {
	Ref<LectureChocsSon> l;
	l.instantiate();
	l->flux = Ref<ChocsSon>(const_cast<ChocsSon *>(this));
	return l;
}

String ChocsSon::_get_stream_name() const { return "ChocsSon"; }
double ChocsSon::_get_length() const { return 0.0; }
bool ChocsSon::_is_monophonic() const { return true; }

void ChocsSon::_bind_methods() {
	ClassDB::bind_method(D_METHOD("frapper", "modes", "options"), &ChocsSon::frapper);
	ClassDB::bind_method(D_METHOD("couper"), &ChocsSon::couper);
	ClassDB::bind_method(D_METHOD("set_taux", "taux"), &ChocsSon::set_taux);
	ClassDB::bind_method(D_METHOD("get_taux"), &ChocsSon::get_taux);
	ClassDB::bind_method(D_METHOD("actifs"), &ChocsSon::actifs);
	ClassDB::bind_method(D_METHOD("est_silencieux"), &ChocsSon::est_silencieux);
	ClassDB::bind_method(D_METHOD("mesures"), &ChocsSon::mesures);
	ClassDB::bind_method(D_METHOD("remettre_mesures"), &ChocsSon::remettre_mesures);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "taux"), "set_taux", "get_taux");
	BIND_CONSTANT(CHOCS);
	BIND_CONSTANT(MODES);
}

// =====================================================================
// LectureChocsSon : le calcul, dans le fil audio
// =====================================================================
void LectureChocsSon::preparer() {
	const int t = flux->taux.load();
	taux = t > 0 ? (double)t : (double)AudioServer::get_singleton()->get_mix_rate();
	if (!(taux > 1000.0)) {
		taux = 48000.0;
	}
	for (int v = 0; v < ChocsSon::CHOCS; v++) {
		voix[v].actif = false;
	}
	coupures = flux->coupures.load();
}

int LectureChocsSon::lancer(const ChocsSon::Choc &p_c) {
	const float prio = p_c.o[10];
	// une place libre ; sinon le choc le moins important, puis le plus ancien, s'éteint pour lui
	int libre = -1;
	int victime = -1;
	for (int v = 0; v < ChocsSon::CHOCS; v++) {
		const Voix &x = voix[v];
		if (!x.actif) {
			libre = v;
			break;
		}
		if (x.fondu >= 0.0) {
			continue;
		}
		if (x.priorite <= prio && (victime < 0 || x.priorite < voix[victime].priorite ||
										  (x.priorite == voix[victime].priorite && x.t > voix[victime].t))) {
			victime = v;
		}
	}
	if (libre < 0) {
		// plein : si un choc s'éteint déjà (pour un autre qui attend), on attend aussi ; sinon le moins
		// important (puis le plus ancien) s'éteint en 30 ms et le nouveau attend sa place
		for (int v = 0; v < ChocsSon::CHOCS; v++) {
			if (voix[v].fondu >= 0.0) {
				return 1;
			}
		}
		if (victime >= 0) {
			voix[victime].fondu = 1.0;
			flux->voles.fetch_add(1, std::memory_order_relaxed);
			return 1;
		}
		return 2;   // rien de moins important : perdu
	}
	Voix &x = voix[libre];
	x = Voix();
	x.actif = true;
	x.n = p_c.n;
	x.hasard = 0x9e3779b9u ^ (hasard = hasard * 1664525u + 1013904223u);
	if (!x.hasard) {
		x.hasard = 1;
	}
	double fin = 0.0;
	for (int i = 0; i < x.n; i++) {
		const double f = p_c.f[i];
		const double tau = std::max(1e-4, (double)p_c.tau[i]);
		const double a = p_c.a[i];
		const bool ok = std::isfinite(f) && f > 1.0 && f < 0.45 * taux && std::isfinite(a) && std::isfinite(tau);
		const double r = std::exp(-1.0 / (tau * taux));
		const double w = 2.0 * PI_D * f / taux;
		x.cr[i] = ok ? r * std::cos(w) : 0.0;
		x.ci[i] = ok ? r * std::sin(w) : 0.0;
		x.re[i] = ok ? a : 0.0;   // y = a e^(iωt) e^(−t/τ) ; on écoute la partie imaginaire (départ à 0)
		x.im[i] = 0.0;
		x.debut[i] = (int64_t)std::llround(std::max(0.0f, p_c.retard[i]) * taux);
		if (ok && std::fabs(a) > SEUIL_FIN) {
			fin = std::max(fin, std::max(0.0f, p_c.retard[i]) + tau * std::log(std::fabs(a) / SEUIL_FIN));
		}
	}
	x.montee = std::max(1.0, (double)p_c.o[0] * taux);
	fin = std::max(fin, (double)p_c.o[0]);
	// bouffée de bruit
	x.b_a = p_c.o[1];
	if (x.b_a > 0.0) {
		double g;
		resonateur(p_c.o[2], 0.7, taux, x.b_a1, x.b_a2, g);
		x.b_g = g;
		const double tm = std::max(1e-4, (double)p_c.o[3]);
		const double td = std::max(1e-3, (double)p_c.o[4]);
		x.b_km = std::exp(-1.0 / (tm * taux));
		x.b_kd = std::exp(-1.0 / (td * taux));
		fin = std::max(fin, td * std::log(std::max(x.b_a, SEUIL_FIN) / SEUIL_FIN) + 5.0 * tm);
	}
	// crissement
	x.c_a = p_c.o[5];
	if (x.c_a > 0.0) {
		x.c_f = p_c.o[6];
		x.c_n = std::max(0.01, (double)p_c.o[7]) * taux;
		double g;
		resonateur(1.6 * x.c_f, 0.6, taux, x.c_a1, x.c_a2, g);
		x.c_g = g;
		fin = std::max(fin, (double)p_c.o[7]);
	}
	x.fin = (int64_t)std::ceil(fin * taux) + 1;
	x.gauche = std::isfinite(p_c.o[8]) ? p_c.o[8] : 1.0f;
	x.droite = std::isfinite(p_c.o[9]) ? p_c.o[9] : 1.0f;
	x.priorite = p_c.o[10];
	flux->joues.fetch_add(1, std::memory_order_relaxed);
	return 0;
}

void LectureChocsSon::calculer(float *p_sortie, int p_n) {
	for (int i = 0; i < 2 * p_n; i++) {
		p_sortie[i] = 0.0f;
	}
	const uint32_t c = flux->coupures.load(std::memory_order_relaxed);
	if (c != coupures) {
		coupures = c;
		for (int v = 0; v < ChocsSon::CHOCS; v++) {
			if (voix[v].actif && voix[v].fondu < 0.0) {
				voix[v].fondu = 1.0;
			}
		}
	}
	// nouveaux chocs
	uint32_t q = flux->queue.load(std::memory_order_relaxed);
	const uint32_t t = flux->tete.load(std::memory_order_acquire);
	// d'abord ceux qui attendent une place (un choc en train de s'éteindre pour eux)
	int garde = 0;
	for (int k = 0; k < n_attente; k++) {
		const int r = lancer(attente[k]);
		if (r == 1 && garde < ATTENTE) {
			if (garde != k) {
				attente[garde] = attente[k];
			}
			garde++;
		} else if (r != 0) {
			flux->refuses.fetch_add(1, std::memory_order_relaxed);
		}
	}
	n_attente = garde;
	while (q != t) {
		const ChocsSon::Choc &ch = flux->file[q % ChocsSon::FILE];
		const int r = lancer(ch);
		if (r == 1 && n_attente < ATTENTE) {
			attente[n_attente++] = ch;
		} else if (r != 0) {
			flux->refuses.fetch_add(1, std::memory_order_relaxed);
		}
		q++;
	}
	flux->queue.store(q, std::memory_order_release);

	const double pas_fondu = 1.0 / (FONDU * taux);
	const double rho16 = std::exp(-16.0 / (0.01 * taux));   // tremblement du crissement : 10 ms (revu tous les 16)
	const double s_rho16 = std::sqrt(1.0 - rho16 * rho16);
	int actifs = 0;
	float pic = 0.0f;
	bool ok = true;
	for (int v = 0; v < ChocsSon::CHOCS; v++) {
		Voix &x = voix[v];
		if (!x.actif) {
			continue;
		}
		actifs++;
		if ((int)buf.size() < p_n) {
			buf.resize(p_n);
		}
		double *b = buf.data();
		for (int i = 0; i < p_n; i++) {
			b[i] = 0.0;
		}
		// 1. les modes : chacun à part (boucle simple, rapide) ; un mode éteint (sous −110 dB) n'est plus calculé
		for (int m = 0; m < x.n; m++) {
			const int64_t d = x.debut[m] - x.t;
			if (d >= p_n) {
				continue;
			}
			double re = x.re[m], im = x.im[m];
			const double cr = x.cr[m], ci = x.ci[m];
			for (int i = (int)std::max<int64_t>(0, d); i < p_n; i++) {
				b[i] += im;
				const double nr = re * cr - im * ci;
				im = re * ci + im * cr;
				re = nr;
			}
			x.re[m] = re;
			x.im[m] = im;
			if (d < 0 && std::fabs(re) + std::fabs(im) < 3e-6) {
				x.debut[m] = INT64_MAX / 2;   // éteint
			}
		}
		// 2. bouffée de bruit
		if (x.b_a > 0.0 && x.b_ed > 1e-7) {
			for (int i = 0; i < p_n; i++) {
				const double y = x.b_a1 * x.b_y1 - x.b_a2 * x.b_y2 + x.b_g * bruit(x.hasard);
				x.b_y2 = x.b_y1;
				x.b_y1 = y;
				x.b_em *= x.b_km;
				x.b_ed *= x.b_kd;
				b[i] += x.b_a * (1.0 - x.b_em) * x.b_ed * y;
			}
		}
		// 3. crissement : fréquence, tremblement et enveloppe revus tous les 16 échantillons ; le son pur est un
		// phaseur qui tourne (sinus, double et triple angle en découlent sans fonction trigonométrique)
		if (x.c_a > 0.0 && (double)x.t < x.c_n) {
			double cr = 1.0, ci = 0.0, env = 0.0, denv = 0.0;
			for (int i = 0; i < p_n; i++) {
				const int64_t tt = x.t + i;
				if ((double)tt >= x.c_n) {
					break;
				}
				if ((tt & 15) == 0 || i == 0) {
					x.c_tremble = rho16 * x.c_tremble + 0.03 * s_rho16 * normal(x.hasard);
					const double u = (double)tt / x.c_n;
					const double f = x.c_f * (1.0 + x.c_tremble) * (1.0 - 0.12 * u);
					const double w = 2.0 * PI_D * f / taux;
					cr = std::cos(w);
					ci = std::sin(w);
					const double u2 = std::min(1.0, (double)(tt + 16) / x.c_n);
					const double e1 = (1.0 - std::exp(-(double)tt / (0.004 * taux))) * std::pow(1.0 - u, 1.5);
					const double e2 = (1.0 - std::exp(-(double)(tt + 16) / (0.004 * taux))) * std::pow(1.0 - u2, 1.5);
					env = e1;
					denv = (e2 - e1) / 16.0;
					// le phaseur reste de longueur 1
					const double l = std::sqrt(x.c_pr * x.c_pr + x.c_pi * x.c_pi);
					if (l > 0.0) {
						x.c_pr /= l;
						x.c_pi /= l;
					} else {
						x.c_pr = 1.0;
						x.c_pi = 0.0;
					}
				}
				const double y = x.c_a1 * x.c_y1 - x.c_a2 * x.c_y2 + x.c_g * bruit(x.hasard);
				x.c_y2 = x.c_y1;
				x.c_y1 = y;
				const double sn = x.c_pi, cs = x.c_pr;
				b[i] += x.c_a * env * (sn + 0.35 * 2.0 * sn * cs + 0.15 * (3.0 * sn - 4.0 * sn * sn * sn) + 0.6 * y);
				const double nr = x.c_pr * cr - x.c_pi * ci;
				x.c_pi = x.c_pr * ci + x.c_pi * cr;
				x.c_pr = nr;
				env += denv;
			}
		}
		// 4. la force du choc monte pendant le contact (demi-cosinus) ; fondu ; gauche et droite
		for (int i = 0; i < p_n; i++) {
			double s = b[i];
			const double tt = (double)(x.t + i);
			if (tt < x.montee) {
				s *= 0.5 - 0.5 * std::cos(PI_D * tt / x.montee);
			}
			if (x.fondu >= 0.0) {
				s *= x.fondu;
				x.fondu = std::max(0.0, x.fondu - pas_fondu);
			}
			p_sortie[2 * i] += (float)(s * x.gauche);
			p_sortie[2 * i + 1] += (float)(s * x.droite);
		}
		x.t += p_n;
		if (x.t >= x.fin || x.fondu == 0.0) {
			x.actif = false;
		}
	}
	for (int i = 0; i < 2 * p_n; i++) {
		const float y = p_sortie[i];
		if (!(std::fabs(y) < 1e6f)) {
			ok = false;
		}
		pic = std::max(pic, std::fabs(y));
	}
	if (!ok) {
		for (int i = 0; i < 2 * p_n; i++) {
			p_sortie[i] = 0.0f;
		}
		for (int v = 0; v < ChocsSon::CHOCS; v++) {
			voix[v].actif = false;
		}
		flux->non_finis.fetch_add(1, std::memory_order_relaxed);
	} else {
		max_atomique(flux->crete, pic);
	}
	int restent = 0;
	for (int v = 0; v < ChocsSon::CHOCS; v++) {
		restent += voix[v].actif ? 1 : 0;
	}
	flux->n_actifs.store(restent, std::memory_order_relaxed);
	max_atomique_int(flux->actifs_max, actifs);
	temps += p_n / taux;
}

void LectureChocsSon::_start(double p_from_pos) {
	preparer();
	joue = true;
}

void LectureChocsSon::_stop() {
	joue = false;
	for (int v = 0; v < ChocsSon::CHOCS; v++) {
		voix[v].actif = false;
	}
	if (flux.is_valid()) {
		flux->n_actifs.store(0);
	}
}

bool LectureChocsSon::_is_playing() const { return joue; }
int32_t LectureChocsSon::_get_loop_count() const { return 0; }
double LectureChocsSon::_get_playback_position() const { return temps; }
void LectureChocsSon::_seek(double p_position) {}

int32_t LectureChocsSon::_mix(AudioFrame *p_buffer, float p_rate_scale, int32_t p_frames) {
	if (flux.is_null() || p_frames <= 0) {
		return 0;
	}
	if (!joue) {
		for (int i = 0; i < p_frames; i++) {
			p_buffer[i].left = 0.0f;
			p_buffer[i].right = 0.0f;
		}
		return p_frames;
	}
	const auto t0 = std::chrono::steady_clock::now();
	static_assert(sizeof(AudioFrame) == 2 * sizeof(float), "AudioFrame = 2 nombres");
	calculer(reinterpret_cast<float *>(p_buffer), p_frames);
	const auto ns = (uint64_t)std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0).count();
	flux->ns_calcul.fetch_add(ns, std::memory_order_relaxed);
	flux->echantillons.fetch_add((uint64_t)p_frames, std::memory_order_relaxed);
	return p_frames;
}
