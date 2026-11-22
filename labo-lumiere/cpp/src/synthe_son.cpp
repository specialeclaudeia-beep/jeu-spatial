// Moteur audio, phase 2 : sons continus fabriqués en direct (voir synthe_son.h).
#include "synthe_son.h"

#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <complex>
#include <map>
#include <mutex>

using namespace godot;

namespace {
constexpr double PI_D = 3.14159265358979323846;
constexpr double SIGMA2 = 1.0 / 3.0;   // carré moyen du bruit de départ (uniforme entre −1 et 1)
constexpr double INV_2_31 = 1.0 / 2147483648.0;
constexpr int PASSE_TOUT_48K[4] = { 113, 173, 233, 293 };   // retards (échantillons à 48 kHz)

// Fréquence centrale de la bande j (tiers d'octave) : 31,25 Hz × 2^((j − 1) / 3), de 24,8 Hz à 20,2 kHz.
double centre(int j) {
	return 31.25 * std::pow(2.0, (j - 1) / 3.0);
}

inline uint32_t xorshift(uint32_t &x) {
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	return x;
}

inline double bruit(uint32_t &x) {
	return (double)(int32_t)xorshift(x) * INV_2_31;
}

uint32_t melanger(uint32_t a) {
	// mélangeur de bits (splitmix32) : des graines voisines donnent des suites sans rapport
	a += 0x9e3779b9u;
	a = (a ^ (a >> 16)) * 0x85ebca6bu;
	a = (a ^ (a >> 13)) * 0xc2b2ae35u;
	a ^= a >> 16;
	return a ? a : 0x1234567u;
}

inline bool fini(double x) {
	return std::isfinite(x);
}

// Filtre d'une bande : Butterworth passe-bande d'ordre 4 (2 sections de 2 pôles), bords à ±1/6 d'octave,
// gain 1 au centre. Numérateur de chaque section : (1 − z⁻²) (zéros à 0 Hz et à la moitié du taux).
struct CoefsBande {
	bool active = false;
	double b0 = 0.0;
	double a1[2] = { 0, 0 }, a2[2] = { 0, 0 };
	double echelle = 0.0;   // 1 / (σ² Σh²) : énergie voulue → carré du gain
};

struct TableBandes {
	CoefsBande b[SyntheSon::BANDES];
};

CoefsBande concevoir_bande(double fc, double fs) {
	CoefsBande c;
	const double f1 = fc * std::pow(2.0, -1.0 / 6.0);
	const double f2 = fc * std::pow(2.0, 1.0 / 6.0);
	if (f2 >= 0.49 * fs) {
		return c;   // bande au-delà de ce que le taux d'échantillonnage peut rendre
	}
	// passage du filtre analogique au numérique (transformation bilinéaire, fréquences « pré-déformées »)
	const double w1 = std::tan(PI_D * f1 / fs);
	const double w2 = std::tan(PI_D * f2 / fs);
	const double bw = w2 - w1;
	const double w0c = w1 * w2;
	const std::complex<double> p(-std::sqrt(0.5), std::sqrt(0.5));   // pôle du Butterworth d'ordre 2
	const std::complex<double> pb = p * bw;
	const std::complex<double> racine = std::sqrt(pb * pb - 4.0 * w0c);
	const std::complex<double> s[2] = { (pb + racine) * 0.5, (pb - racine) * 0.5 };
	for (int k = 0; k < 2; k++) {
		const std::complex<double> z = (1.0 + s[k]) / (1.0 - s[k]);
		c.a1[k] = 2.0 * z.real();
		c.a2[k] = std::norm(z);
	}
	// gain 1 au centre
	const double w0 = 2.0 * std::atan(std::sqrt(w0c));
	const std::complex<double> zi = std::polar(1.0, -w0);   // z⁻¹
	std::complex<double> h = 1.0;
	for (int k = 0; k < 2; k++) {
		h *= (1.0 - zi * zi) / (1.0 - c.a1[k] * zi + c.a2[k] * zi * zi);
	}
	c.b0 = 1.0 / std::abs(h);
	// Σh² : énergie de la réponse à une impulsion (le bruit qui passe garde σ² Σh²)
	double s1a = 0, s2a = 0, s1b = 0, s2b = 0, somme = 0, recent = 0;
	const int n_max = (int)(fs * 8.0);
	for (int n = 0; n < n_max; n++) {
		const double x = n == 0 ? 1.0 : 0.0;
		const double y1 = c.b0 * x + s1a;
		s1a = c.a1[0] * y1 + s2a;
		s2a = -c.b0 * x - c.a2[0] * y1;
		const double y2 = y1 + s1b;
		s1b = c.a1[1] * y2 + s2b;
		s2b = -y1 - c.a2[1] * y2;
		somme += y2 * y2;
		recent += y2 * y2;
		if ((n & 1023) == 1023) {
			if (n > 4096 && recent < 1e-15 * somme) {
				break;
			}
			recent = 0.0;
		}
	}
	c.echelle = somme > 0.0 ? 1.0 / (SIGMA2 * somme) : 0.0;
	c.active = somme > 0.0;
	return c;
}

// Les filtres ne dépendent que du taux : calculés une fois (quelques ms), partagés par toutes les couches.
const TableBandes &table_bandes(double fs) {
	static std::mutex verrou;
	static std::map<int, TableBandes> tables;
	std::lock_guard<std::mutex> garde(verrou);
	const int cle = (int)std::lround(fs);
	auto it = tables.find(cle);
	if (it == tables.end()) {
		TableBandes t;
		for (int j = 0; j < SyntheSon::BANDES; j++) {
			t.b[j] = concevoir_bande(centre(j), fs);
		}
		it = tables.emplace(cle, t).first;
	}
	return it->second;
}

void max_atomique(std::atomic<float> &a, float v) {
	float ancien = a.load(std::memory_order_relaxed);
	while (v > ancien && !a.compare_exchange_weak(ancien, v, std::memory_order_relaxed)) {
	}
}
} // namespace

// =====================================================================
// SyntheSon : la couche (ses cibles, partagées avec le fil audio)
// =====================================================================
SyntheSon::SyntheSon() {
	for (int j = 0; j < BANDES; j++) {
		cible_bandes[j].store(0.0f);
		cible_gauche[j].store(0.5f);
	}
	for (int i = 0; i < MODES; i++) {
		cible_modes[i].store(0.0f);
		modes_f[i].store(0.0f);
		modes_perte[i].store(0.0f);
	}
	for (int i = 0; i < RAIES; i++) {
		raies_f[i].store(0.0f);
		raies_e[i].store(0.0f);
	}
}

void SyntheSon::regler_bandes(const PackedFloat32Array &p_energies) {
	const int n = std::min((int)p_energies.size(), BANDES);
	for (int j = 0; j < n; j++) {
		const float e = p_energies[j];
		cible_bandes[j].store(fini(e) && e > 0.0f ? e : 0.0f, std::memory_order_relaxed);
	}
	for (int j = n; j < BANDES; j++) {
		cible_bandes[j].store(0.0f, std::memory_order_relaxed);
	}
}

void SyntheSon::regler_gauche(const PackedFloat32Array &p_parts) {
	const int n = std::min((int)p_parts.size(), BANDES);
	for (int j = 0; j < BANDES; j++) {
		float w = j < n ? p_parts[j] : 0.5f;
		w = fini(w) ? std::min(1.0f, std::max(0.0f, w)) : 0.5f;
		if (std::fabs(w - 0.5f) < 0.005f) {
			w = 0.5f;   // moins de 0,1 dB d'écart : au milieu (un seul calcul pour les deux oreilles)
		}
		cible_gauche[j].store(w, std::memory_order_relaxed);
	}
}

void SyntheSon::regler_modes(const PackedFloat32Array &p_frequences, const PackedFloat32Array &p_pertes) {
	const int n = std::min({ (int)p_frequences.size(), (int)p_pertes.size(), MODES });
	for (int i = 0; i < n; i++) {
		modes_f[i].store(p_frequences[i], std::memory_order_relaxed);
		modes_perte[i].store(p_pertes[i], std::memory_order_relaxed);
	}
	nombre_modes.store(n, std::memory_order_relaxed);
	version_modes.fetch_add(1, std::memory_order_release);
}

void SyntheSon::regler_energie_modes(const PackedFloat32Array &p_energies) {
	const int n = std::min((int)p_energies.size(), MODES);
	for (int i = 0; i < n; i++) {
		const float e = p_energies[i];
		cible_modes[i].store(fini(e) && e > 0.0f ? e : 0.0f, std::memory_order_relaxed);
	}
	for (int i = n; i < MODES; i++) {
		cible_modes[i].store(0.0f, std::memory_order_relaxed);
	}
}

void SyntheSon::regler_raie(int p_i, double p_frequence, double p_energie) {
	if (p_i < 0 || p_i >= RAIES) {
		return;
	}
	raies_f[p_i].store(fini(p_frequence) && p_frequence > 0.0 ? (float)p_frequence : 0.0f, std::memory_order_relaxed);
	raies_e[p_i].store(fini(p_energie) && p_energie > 0.0 ? (float)p_energie : 0.0f, std::memory_order_relaxed);
}

void SyntheSon::couper() {
	for (int j = 0; j < BANDES; j++) {
		cible_bandes[j].store(0.0f, std::memory_order_relaxed);
	}
	for (int i = 0; i < MODES; i++) {
		cible_modes[i].store(0.0f, std::memory_order_relaxed);
	}
	for (int i = 0; i < RAIES; i++) {
		raies_e[i].store(0.0f, std::memory_order_relaxed);
	}
}

void SyntheSon::set_lissage(double p_s) { lissage.store((float)std::max(0.0, p_s)); }
double SyntheSon::get_lissage() const { return lissage.load(); }
void SyntheSon::set_instabilite(double p_relative) { instabilite.store((float)std::clamp(p_relative, 0.0, 0.2)); }
double SyntheSon::get_instabilite() const { return instabilite.load(); }
void SyntheSon::set_instabilite_temps(double p_s) { instabilite_temps.store((float)std::max(0.001, p_s)); }
double SyntheSon::get_instabilite_temps() const { return instabilite_temps.load(); }
void SyntheSon::set_taux(int p_taux) { taux.store(std::max(0, p_taux)); }
int SyntheSon::get_taux() const { return taux.load(); }
void SyntheSon::set_graine(int p_graine) { graine.store(p_graine); }
int SyntheSon::get_graine() const { return graine.load(); }

PackedFloat32Array SyntheSon::centres() {
	PackedFloat32Array c;
	c.resize(BANDES);
	for (int j = 0; j < BANDES; j++) {
		c[j] = (float)centre(j);
	}
	return c;
}

double SyntheSon::energie_cible() const {
	double e = 0.0;
	for (int j = 0; j < BANDES; j++) {
		e += cible_bandes[j].load(std::memory_order_relaxed);
	}
	const int n = nombre_modes.load(std::memory_order_relaxed);
	for (int i = 0; i < n; i++) {
		e += cible_modes[i].load(std::memory_order_relaxed);
	}
	for (int i = 0; i < RAIES; i++) {
		e += raies_e[i].load(std::memory_order_relaxed);
	}
	return e;
}

double SyntheSon::energie_en_cours() const { return en_cours.load(); }
bool SyntheSon::est_silencieux() const { return silencieux.load(); }

Dictionary SyntheSon::mesures() const {
	Dictionary d;
	const uint64_t n = echantillons.load();
	const uint64_t ns = ns_calcul.load();
	const double t = taux.load() > 0 ? taux.load() : AudioServer::get_singleton()->get_mix_rate();
	// part d'un cœur du processeur : temps de calcul / durée du son calculé
	d["charge"] = n > 0 ? (double)ns * 1e-9 / ((double)n / t) : 0.0;
	d["us_par_seconde"] = n > 0 ? (double)ns * 1e-3 / ((double)n / t) : 0.0;
	d["us_max_appel"] = us_max_appel.load();
	d["appels"] = (int64_t)appels.load();
	d["echantillons"] = (int64_t)n;
	d["crete"] = crete.load();
	d["non_finis"] = non_finis.load();
	return d;
}

void SyntheSon::remettre_mesures() {
	ns_calcul.store(0);
	echantillons.store(0);
	appels.store(0);
	us_max_appel.store(0.0f);
	crete.store(0.0f);
	non_finis.store(0);
}

Ref<AudioStreamPlayback> SyntheSon::_instantiate_playback() const {
	Ref<LectureSyntheSon> l;
	l.instantiate();
	l->flux = Ref<SyntheSon>(const_cast<SyntheSon *>(this));
	l->hasard_raies = melanger((uint32_t)graine.load() * 7919u + (uint32_t)lectures.fetch_add(1) * 104729u);
	return l;
}

String SyntheSon::_get_stream_name() const { return "SyntheSon"; }
double SyntheSon::_get_length() const { return 0.0; }
bool SyntheSon::_is_monophonic() const { return true; }

void SyntheSon::_bind_methods() {
	ClassDB::bind_method(D_METHOD("regler_bandes", "energies"), &SyntheSon::regler_bandes);
	ClassDB::bind_method(D_METHOD("regler_gauche", "parts"), &SyntheSon::regler_gauche);
	ClassDB::bind_method(D_METHOD("regler_modes", "frequences", "pertes"), &SyntheSon::regler_modes);
	ClassDB::bind_method(D_METHOD("regler_energie_modes", "energies"), &SyntheSon::regler_energie_modes);
	ClassDB::bind_method(D_METHOD("regler_raie", "i", "frequence", "energie"), &SyntheSon::regler_raie);
	ClassDB::bind_method(D_METHOD("couper"), &SyntheSon::couper);
	ClassDB::bind_method(D_METHOD("set_lissage", "s"), &SyntheSon::set_lissage);
	ClassDB::bind_method(D_METHOD("get_lissage"), &SyntheSon::get_lissage);
	ClassDB::bind_method(D_METHOD("set_instabilite", "relative"), &SyntheSon::set_instabilite);
	ClassDB::bind_method(D_METHOD("get_instabilite"), &SyntheSon::get_instabilite);
	ClassDB::bind_method(D_METHOD("set_instabilite_temps", "s"), &SyntheSon::set_instabilite_temps);
	ClassDB::bind_method(D_METHOD("get_instabilite_temps"), &SyntheSon::get_instabilite_temps);
	ClassDB::bind_method(D_METHOD("set_taux", "taux"), &SyntheSon::set_taux);
	ClassDB::bind_method(D_METHOD("get_taux"), &SyntheSon::get_taux);
	ClassDB::bind_method(D_METHOD("set_graine", "graine"), &SyntheSon::set_graine);
	ClassDB::bind_method(D_METHOD("get_graine"), &SyntheSon::get_graine);
	ClassDB::bind_static_method("SyntheSon", D_METHOD("centres"), &SyntheSon::centres);
	ClassDB::bind_method(D_METHOD("energie_cible"), &SyntheSon::energie_cible);
	ClassDB::bind_method(D_METHOD("energie_en_cours"), &SyntheSon::energie_en_cours);
	ClassDB::bind_method(D_METHOD("est_silencieux"), &SyntheSon::est_silencieux);
	ClassDB::bind_method(D_METHOD("mesures"), &SyntheSon::mesures);
	ClassDB::bind_method(D_METHOD("remettre_mesures"), &SyntheSon::remettre_mesures);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lissage"), "set_lissage", "get_lissage");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "instabilite"), "set_instabilite", "get_instabilite");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "instabilite_temps"), "set_instabilite_temps", "get_instabilite_temps");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "taux"), "set_taux", "get_taux");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "graine"), "set_graine", "get_graine");
	BIND_CONSTANT(BANDES);
	BIND_CONSTANT(MODES);
	BIND_CONSTANT(RAIES);
	BIND_CONSTANT(BLOC);
}

// =====================================================================
// LectureSyntheSon : le calcul, dans le fil audio
// =====================================================================
LectureSyntheSon::LectureSyntheSon() {
	for (int j = 0; j < SyntheSon::BANDES; j++) {
		pas_g[j] = 0.0;
	}
	for (int i = 0; i < SyntheSon::MODES; i++) {
		pas_b[i] = 0.0;
	}
	for (int i = 0; i < SyntheSon::RAIES; i++) {
		pas_a[i] = 0.0;
		rot_re[i] = 1.0;
		rot_im[i] = 0.0;
	}
}

void LectureSyntheSon::preparer() {
	if (flux.is_null()) {
		return;
	}
	const int t = flux->taux.load();
	taux = t > 0 ? (double)t : (double)AudioServer::get_singleton()->get_mix_rate();
	if (!(taux > 1000.0)) {
		taux = 48000.0;
	}
	const TableBandes &tb = table_bandes(taux);
	const uint32_t g = (uint32_t)flux->graine.load();
	for (int j = 0; j < SyntheSon::BANDES; j++) {
		Bande &b = bandes[j];
		const CoefsBande &c = tb.b[j];
		b.active = c.active;
		b.b0 = c.b0;
		for (int k = 0; k < 2; k++) {
			b.a1[k] = c.a1[k];
			b.a2[k] = c.a2[k];
			b.s1[k] = 0.0;
			b.s2[k] = 0.0;
		}
		b.echelle = c.echelle;
		b.hasard = melanger(hasard_raies ^ (g * 31u + (uint32_t)j * 2654435761u));
		b.e = 0.0;
		b.g = 0.0;
		b.gc = 0.0;
		b.w = 0.5;
		b.pl = b.pr = b.plc = b.prc = 1.0;
		pas_g[j] = 0.0;
		pas_pl[j] = pas_pr[j] = 0.0;
	}
	au_milieu = true;
	for (int i = 0; i < SyntheSon::MODES; i++) {
		modes[i] = Mode();
		modes[i].hasard = melanger(hasard_raies ^ (g * 131u + (uint32_t)i * 40503u + 977u));
		pas_b[i] = 0.0;
	}
	for (int i = 0; i < SyntheSon::RAIES; i++) {
		raies[i] = Raie();
		pas_a[i] = 0.0;
	}
	for (int k = 0; k < 4; k++) {
		const int d = std::max(1, (int)std::lround(PASSE_TOUT_48K[k] * taux / 48000.0));
		passe_tout[k].ligne.assign(d, 0.0f);
		passe_tout[k].pos = 0;
	}
	mono.assign(SyntheSon::BLOC, 0.0f);
	droite.assign(SyntheSon::BLOC, 0.0f);
	version_modes = 0xffffffffu;
	dans_bloc = 0;
	temps = 0.0;
	pret = true;
}

void LectureSyntheSon::preparer_modes() {
	const int n = flux->nombre_modes.load(std::memory_order_relaxed);
	for (int i = 0; i < SyntheSon::MODES; i++) {
		Mode &m = modes[i];
		const double f = i < n ? flux->modes_f[i].load(std::memory_order_relaxed) : 0.0;
		const double eta = i < n ? flux->modes_perte[i].load(std::memory_order_relaxed) : 0.0;
		const bool ok = f > 1.0 && f < 0.45 * taux && eta > 1e-5 && eta < 2.0;
		if (!ok) {
			m.actif = false;
			m.a1 = m.a2 = m.k = 0.0;
			continue;
		}
		// résonateur : y = a1 y1 − a2 y2 + b x, amortissement e^(−t/τ) avec τ = 1 / (π f η)
		const double r = std::exp(-PI_D * f * eta / taux);
		const double w = 2.0 * PI_D * f / taux;
		m.a1 = 2.0 * r * std::cos(w);
		m.a2 = r * r;
		m.bande = std::min(SyntheSon::BANDES - 1, std::max(0, (int)std::lround(1.0 + 3.0 * std::log2(f / 31.25))));
		// carré moyen de y pour un bruit blanc de carré moyen 1 (processus AR(2))
		m.k = (1.0 + m.a2) / ((1.0 - m.a2) * ((1.0 + m.a2) * (1.0 + m.a2) - m.a1 * m.a1));
		m.actif = fini(m.k) && m.k > 0.0;
	}
}

void LectureSyntheSon::debut_bloc() {
	const double dt = SyntheSon::BLOC / taux;
	const double tau = flux->lissage.load(std::memory_order_relaxed);
	k_lissage = tau > 1e-4 ? 1.0 - std::exp(-dt / tau) : 1.0;
	const uint32_t v = flux->version_modes.load(std::memory_order_acquire);
	if (v != version_modes) {
		version_modes = v;
		preparer_modes();
	}
	double en_cours = 0.0;
	bool silence = true;
	// côté : glisse un peu plus lentement que le volume (30 ms au moins), pour qu'un son qui change de côté
	// ne « saute » jamais d'une oreille à l'autre
	const double k_cote = 1.0 - std::exp(-dt / std::max(0.03, (double)tau));
	au_milieu = true;
	for (int j = 0; j < SyntheSon::BANDES; j++) {
		Bande &b = bandes[j];
		b.pl = b.plc;
		b.pr = b.prc;
		const double w_cible = flux->cible_gauche[j].load(std::memory_order_relaxed);
		b.w += (w_cible - b.w) * k_cote;
		if (std::fabs(b.w - w_cible) < 1e-3) {
			b.w = w_cible;   // arrivé (à 0,01 dB près) : plus de rampe, boucle plus légère
		}
		b.plc = b.w == 0.5 ? 1.0 : std::sqrt(2.0 * b.w);
		b.prc = b.w == 0.5 ? 1.0 : std::sqrt(2.0 * (1.0 - b.w));
		pas_pl[j] = (b.plc - b.pl) / SyntheSon::BLOC;
		pas_pr[j] = (b.prc - b.pr) / SyntheSon::BLOC;
		au_milieu = au_milieu && b.pl == 1.0 && b.plc == 1.0 && b.pr == 1.0 && b.prc == 1.0;
	}
	for (int j = 0; j < SyntheSon::BANDES; j++) {
		Bande &b = bandes[j];
		b.g = b.gc;   // fin exacte de la rampe du bloc précédent (pas d'erreur qui s'accumule)
		if (!b.active) {
			pas_g[j] = 0.0;
			continue;
		}
		const double cible = flux->cible_bandes[j].load(std::memory_order_relaxed);
		b.e += (cible - b.e) * k_lissage;
		if (cible == 0.0 && b.e < 1e-16) {
			b.e = 0.0;
		}
		b.gc = std::sqrt(b.e * b.echelle);
		pas_g[j] = (b.gc - b.g) / SyntheSon::BLOC;
		en_cours += b.e;
		const double reste = std::fabs(b.s1[0]) + std::fabs(b.s2[0]) + std::fabs(b.s1[1]) + std::fabs(b.s2[1]);
		if (b.g == 0.0 && b.gc == 0.0 && reste < 1e-9) {
			b.s1[0] = b.s2[0] = b.s1[1] = b.s2[1] = 0.0;   // filtre éteint (sous −180 dB)
		}
		silence = silence && b.g == 0.0 && b.gc == 0.0 && b.s1[0] == 0.0 && b.s2[0] == 0.0 && b.s1[1] == 0.0 &&
				b.s2[1] == 0.0;
	}
	for (int i = 0; i < SyntheSon::MODES; i++) {
		Mode &m = modes[i];
		m.b = m.bc;
		if (!m.actif) {
			m.e = m.b = m.bc = m.y1 = m.y2 = 0.0;
			pas_b[i] = 0.0;
			continue;
		}
		const double cible = flux->cible_modes[i].load(std::memory_order_relaxed);
		m.e += (cible - m.e) * k_lissage;
		if (cible == 0.0 && m.e < 1e-16) {
			m.e = 0.0;
		}
		m.bc = std::sqrt(m.e / (SIGMA2 * m.k));
		pas_b[i] = (m.bc - m.b) / SyntheSon::BLOC;
		en_cours += m.e;
		if (m.bc == 0.0 && m.b == 0.0 && std::fabs(m.y1) + std::fabs(m.y2) < 1e-7) {
			m.y1 = m.y2 = 0.0;   // résonance éteinte (sous −140 dB)
		}
		silence = silence && m.bc == 0.0 && m.b == 0.0 && m.y1 == 0.0 && m.y2 == 0.0;
	}
	const double sigma = flux->instabilite.load(std::memory_order_relaxed);
	const double tau_t = flux->instabilite_temps.load(std::memory_order_relaxed);
	const double rho = std::exp(-dt / std::max(1e-3, tau_t));
	for (int i = 0; i < SyntheSon::RAIES; i++) {
		Raie &r = raies[i];
		const double f_cible = flux->raies_f[i].load(std::memory_order_relaxed);
		double e_cible = flux->raies_e[i].load(std::memory_order_relaxed);
		if (!(f_cible > 1.0 && f_cible < 0.45 * taux)) {
			e_cible = 0.0;
		}
		if (e_cible > 0.0) {
			r.f = r.f > 0.0 ? r.f + (f_cible - r.f) * k_lissage : f_cible;
		}
		r.e += (e_cible - r.e) * k_lissage;
		if (e_cible == 0.0 && r.e < 1e-16) {
			r.e = 0.0;
		}
		// tremblement de la fréquence : bruit lent (Ornstein-Uhlenbeck), écart type « instabilite »
		const double u1 = (xorshift(hasard_raies) + 1.0) * (1.0 / 4294967297.0);
		const double u2 = xorshift(hasard_raies) * (1.0 / 4294967296.0);
		const double normal = std::sqrt(-2.0 * std::log(u1)) * std::cos(2.0 * PI_D * u2);
		r.tremble = rho * r.tremble + sigma * std::sqrt(1.0 - rho * rho) * normal;
		r.a = r.ac;
		r.ac = std::sqrt(2.0 * r.e);
		pas_a[i] = (r.ac - r.a) / SyntheSon::BLOC;
		const double f = std::max(0.0, r.f * (1.0 + r.tremble));
		const double d = 2.0 * PI_D * f / taux;
		rot_re[i] = std::cos(d);
		rot_im[i] = std::sin(d);
		const double norme = std::sqrt(r.re * r.re + r.im * r.im);
		if (norme > 0.0) {
			r.re /= norme;
			r.im /= norme;
		} else {
			r.re = 1.0;
			r.im = 0.0;
		}
		en_cours += r.e;
		silence = silence && r.ac == 0.0 && r.a == 0.0;
	}
	flux->en_cours.store((float)en_cours, std::memory_order_relaxed);
	flux->silencieux.store(silence, std::memory_order_relaxed);
}

void LectureSyntheSon::remettre_a_zero() {
	for (int j = 0; j < SyntheSon::BANDES; j++) {
		Bande &b = bandes[j];
		b.s1[0] = b.s1[1] = b.s2[0] = b.s2[1] = 0.0;
		b.e = b.g = b.gc = 0.0;
		pas_g[j] = 0.0;
	}
	for (int i = 0; i < SyntheSon::MODES; i++) {
		modes[i].y1 = modes[i].y2 = modes[i].e = modes[i].b = modes[i].bc = 0.0;
		pas_b[i] = 0.0;
	}
	for (int i = 0; i < SyntheSon::RAIES; i++) {
		raies[i].e = raies[i].a = raies[i].ac = 0.0;
		pas_a[i] = 0.0;
	}
	for (int k = 0; k < 4; k++) {
		std::fill(passe_tout[k].ligne.begin(), passe_tout[k].ligne.end(), 0.0f);
	}
}

#if defined(__GNUC__) && !defined(__clang__)
__attribute__((optimize("O3")))
#endif
void LectureSyntheSon::calculer(float *p_sortie, int p_n) {
	// p_sortie : 2 × p_n valeurs (gauche, droite)
	int fait = 0;
	while (fait < p_n) {
		if (dans_bloc == 0) {
			debut_bloc();
		}
		const int k = std::min(p_n - fait, SyntheSon::BLOC - dans_bloc);
		float *m = mono.data();
		float *md_ = droite.data();
		std::fill(m, m + k, 0.0f);
		// côtés au début de ce morceau (un bloc de 256 peut être coupé en plusieurs appels : chaque morceau repart
		// d'où le précédent s'est arrêté, sinon le côté « reculerait » d'un coup)
		double pl0[SyntheSon::BANDES], pr0[SyntheSon::BANDES];
		if (!au_milieu) {
			std::fill(md_, md_ + k, 0.0f);
			for (int j = 0; j < SyntheSon::BANDES; j++) {
				pl0[j] = bandes[j].pl;
				pr0[j] = bandes[j].pr;
			}
		}
		// 1. bruit filtré : les bandes actives, rangées côte à côte (le processeur les mène de front)
		int idx[SyntheSon::BANDES];
		int na = 0;
		for (int j = 0; j < SyntheSon::BANDES; j++) {
			const Bande &b = bandes[j];
			if (b.active && (b.g != 0.0 || pas_g[j] != 0.0 || b.s1[0] != 0.0 || b.s2[0] != 0.0 || b.s1[1] != 0.0 ||
										b.s2[1] != 0.0)) {
				idx[na++] = j;   // (un filtre qui sonne encore après la coupure va jusqu'au bout)
			}
		}
		if (na > 0) {
			double b0[SyntheSon::BANDES], a1a[SyntheSon::BANDES], a2a[SyntheSon::BANDES], a1b[SyntheSon::BANDES],
					a2b[SyntheSon::BANDES], s1a[SyntheSon::BANDES], s2a[SyntheSon::BANDES], s1b[SyntheSon::BANDES],
					s2b[SyntheSon::BANDES], g[SyntheSon::BANDES], dg[SyntheSon::BANDES], pl[SyntheSon::BANDES],
					pr[SyntheSon::BANDES], dpl[SyntheSon::BANDES], dpr[SyntheSon::BANDES];
			uint32_t h[SyntheSon::BANDES];
			for (int q = 0; q < na; q++) {
				const Bande &b = bandes[idx[q]];
				b0[q] = b.b0;
				a1a[q] = b.a1[0];
				a2a[q] = b.a2[0];
				a1b[q] = b.a1[1];
				a2b[q] = b.a2[1];
				s1a[q] = b.s1[0];
				s2a[q] = b.s2[0];
				s1b[q] = b.s1[1];
				s2b[q] = b.s2[1];
				g[q] = b.g;
				dg[q] = pas_g[idx[q]];
				h[q] = b.hasard;
				pl[q] = b.pl;
				pr[q] = b.pr;
				dpl[q] = pas_pl[idx[q]];
				dpr[q] = pas_pr[idx[q]];
			}
			bool rampe = false;
			for (int q = 0; q < na; q++) {
				rampe = rampe || dpl[q] != 0.0 || dpr[q] != 0.0;
			}
			if (!au_milieu && rampe) {
				// chaque bande a son côté : deux sommes (gauche, droite) ; un côté qui change glisse
				// échantillon par échantillon (une marche, même minuscule, sur un grave très fort s'entendrait)
				for (int i = 0; i < k; i++) {
					double sg = 0.0, sd = 0.0;
					for (int q = 0; q < na; q++) {
						const double x = g[q] * bruit(h[q]);
						const double y1 = b0[q] * x + s1a[q];
						s1a[q] = a1a[q] * y1 + s2a[q];
						s2a[q] = -b0[q] * x - a2a[q] * y1;
						const double y2 = y1 + s1b[q];
						s1b[q] = a1b[q] * y2 + s2b[q];
						s2b[q] = -y1 - a2b[q] * y2;
						sg += y2 * pl[q];
						sd += y2 * pr[q];
						g[q] += dg[q];
						pl[q] += dpl[q];
						pr[q] += dpr[q];
					}
					m[i] += (float)sg;
					md_[i] += (float)sd;
				}
			} else if (!au_milieu) {
				// côtés arrivés (le cas le plus courant) : pas de rampe, boucle plus légère
				for (int i = 0; i < k; i++) {
					double sg = 0.0, sd = 0.0;
					for (int q = 0; q < na; q++) {
						const double x = g[q] * bruit(h[q]);
						const double y1 = b0[q] * x + s1a[q];
						s1a[q] = a1a[q] * y1 + s2a[q];
						s2a[q] = -b0[q] * x - a2a[q] * y1;
						const double y2 = y1 + s1b[q];
						s1b[q] = a1b[q] * y2 + s2b[q];
						s2b[q] = -y1 - a2b[q] * y2;
						sg += y2 * pl[q];
						sd += y2 * pr[q];
						g[q] += dg[q];
					}
					m[i] += (float)sg;
					md_[i] += (float)sd;
				}
			} else
			for (int i = 0; i < k; i++) {
				double somme = 0.0;
				for (int q = 0; q < na; q++) {
					// le volume agit AVANT le filtre : un tiers d'octave ne peut pas changer plus vite que sa
					// largeur ne le permet (25 Hz : ~50 ms ; 8 kHz : < 1 ms). Après le filtre, une montée
					// de 5 ms serait un petit « clic » dans les graves.
					const double x = g[q] * bruit(h[q]);
					const double y1 = b0[q] * x + s1a[q];
					s1a[q] = a1a[q] * y1 + s2a[q];
					s2a[q] = -b0[q] * x - a2a[q] * y1;
					const double y2 = y1 + s1b[q];
					s1b[q] = a1b[q] * y2 + s2b[q];
					s2b[q] = -y1 - a2b[q] * y2;
					somme += y2;
					g[q] += dg[q];
				}
				m[i] += (float)somme;
			}
			for (int q = 0; q < na; q++) {
				Bande &b = bandes[idx[q]];
				b.s1[0] = s1a[q];
				b.s2[0] = s2a[q];
				b.s1[1] = s1b[q];
				b.s2[1] = s2b[q];
				b.g = g[q];
				b.hasard = h[q];
			}
		}
		// 2. résonances
		int im[SyntheSon::MODES];
		int nm = 0;
		for (int i = 0; i < SyntheSon::MODES; i++) {
			const Mode &md = modes[i];
			if (md.actif && (md.b != 0.0 || pas_b[i] != 0.0 || md.y1 != 0.0 || md.y2 != 0.0)) {
				im[nm++] = i;
			}
		}
		if (nm > 0) {
			double a1[SyntheSon::MODES], a2[SyntheSon::MODES], y1[SyntheSon::MODES], y2[SyntheSon::MODES], b[SyntheSon::MODES],
					db[SyntheSon::MODES];
			uint32_t h[SyntheSon::MODES];
			for (int q = 0; q < nm; q++) {
				const Mode &md = modes[im[q]];
				a1[q] = md.a1;
				a2[q] = md.a2;
				y1[q] = md.y1;
				y2[q] = md.y2;
				b[q] = md.b;
				db[q] = pas_b[im[q]];
				h[q] = md.hasard;
			}
			if (!au_milieu) {
				double pl[SyntheSon::MODES], pr[SyntheSon::MODES], dpl[SyntheSon::MODES], dpr[SyntheSon::MODES];
				for (int q = 0; q < nm; q++) {
					const int j = modes[im[q]].bande;   // une résonance prend le côté de sa bande
					pl[q] = pl0[j];
					pr[q] = pr0[j];
					dpl[q] = pas_pl[j];
					dpr[q] = pas_pr[j];
				}
				for (int i = 0; i < k; i++) {
					double sg = 0.0, sd = 0.0;
					for (int q = 0; q < nm; q++) {
						const double y = a1[q] * y1[q] - a2[q] * y2[q] + b[q] * bruit(h[q]);
						y2[q] = y1[q];
						y1[q] = y;
						sg += y * pl[q];
						sd += y * pr[q];
						b[q] += db[q];
						pl[q] += dpl[q];
						pr[q] += dpr[q];
					}
					m[i] += (float)sg;
					md_[i] += (float)sd;
				}
			} else
			for (int i = 0; i < k; i++) {
				double somme = 0.0;
				for (int q = 0; q < nm; q++) {
					const double y = a1[q] * y1[q] - a2[q] * y2[q] + b[q] * bruit(h[q]);
					y2[q] = y1[q];
					y1[q] = y;
					somme += y;
					b[q] += db[q];
				}
				m[i] += (float)somme;
			}
			for (int q = 0; q < nm; q++) {
				Mode &md = modes[im[q]];
				md.y1 = y1[q];
				md.y2 = y2[q];
				md.b = std::max(0.0, b[q]);
				md.hasard = h[q];
			}
		}
		if (!au_milieu) {
			for (int j = 0; j < SyntheSon::BANDES; j++) {
				bandes[j].pl = pl0[j] + pas_pl[j] * k;
				bandes[j].pr = pr0[j] + pas_pr[j] * k;
			}
		}
		// 3. sons purs
		for (int r = 0; r < SyntheSon::RAIES; r++) {
			Raie &ra = raies[r];
			if (ra.a == 0.0 && pas_a[r] == 0.0) {
				continue;
			}
			double re = ra.re, imj = ra.im, a = ra.a;
			const double cr = rot_re[r], ci = rot_im[r], da = pas_a[r];
			for (int i = 0; i < k; i++) {
				m[i] += (float)(a * imj);
				if (!au_milieu) {
					md_[i] += (float)(a * imj);   // les sons purs restent au milieu
				}
				const double nr = re * cr - imj * ci;
				imj = re * ci + imj * cr;
				re = nr;
				a += da;
			}
			ra.re = re;
			ra.im = imj;
			ra.a = std::max(0.0, a);
		}
		// 4. sortie : gauche = le son ; droite = le même (ou sa voie droite) passé par 4 filtres passe-tout
		float pic = 0.0f;
		bool ok = true;
		const float *entree_d = au_milieu ? m : md_;
		for (int i = 0; i < k; i++) {
			const float x = m[i];
			float y = entree_d[i];
			for (int p = 0; p < 4; p++) {
				PasseTout &pt = passe_tout[p];
				const float ancien = pt.ligne[pt.pos];
				const float w = y + pt.g * ancien;
				y = -pt.g * w + ancien;
				pt.ligne[pt.pos] = w;
				pt.pos = pt.pos + 1 < (int)pt.ligne.size() ? pt.pos + 1 : 0;
			}
			if (!(std::fabs(x) < 1e6f) || !(std::fabs(y) < 1e6f)) {
				ok = false;
			}
			p_sortie[2 * (fait + i)] = x;
			p_sortie[2 * (fait + i) + 1] = y;
			pic = std::max(pic, std::max(std::fabs(x), std::fabs(y)));
		}
		if (!ok) {
			// valeur invalide (ne devrait jamais arriver) : silence propre plutôt qu'un bruit énorme
			for (int i = 0; i < k; i++) {
				p_sortie[2 * (fait + i)] = 0.0f;
				p_sortie[2 * (fait + i) + 1] = 0.0f;
			}
			flux->non_finis.fetch_add(1, std::memory_order_relaxed);
			remettre_a_zero();
		} else {
			max_atomique(flux->crete, pic);
		}
		fait += k;
		dans_bloc += k;
		if (dans_bloc >= SyntheSon::BLOC) {
			dans_bloc = 0;
		}
		temps += k / taux;
	}
}

void LectureSyntheSon::_start(double p_from_pos) {
	if (!pret) {
		preparer();
	} else {
		remettre_a_zero();   // relancé : on repart du silence (le son monte en ~10 ms, sans clic)
	}
	joue = true;
}

void LectureSyntheSon::_stop() {
	joue = false;
}

bool LectureSyntheSon::_is_playing() const {
	return joue;
}

int32_t LectureSyntheSon::_get_loop_count() const {
	return 0;
}

double LectureSyntheSon::_get_playback_position() const {
	return temps;
}

void LectureSyntheSon::_seek(double p_position) {
}

int32_t LectureSyntheSon::_mix(AudioFrame *p_buffer, float p_rate_scale, int32_t p_frames) {
	if (flux.is_null() || p_frames <= 0) {
		return 0;
	}
	if (!pret) {
		preparer();
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
	flux->appels.fetch_add(1, std::memory_order_relaxed);
	max_atomique(flux->us_max_appel, (float)(ns * 1e-3));
	return p_frames;
}

void LectureSyntheSon::_bind_methods() {
}

// =====================================================================
// AnalyseSon : outil des tests
// =====================================================================
AnalyseSon::AnalyseSon() {
	remettre();
}

void AnalyseSon::remettre() {
	for (Voie &v : voies) {
		v = Voie();
		v.morceau.assign(ORDRE + MORCEAU, 0.0);
	}
}

void AnalyseSon::pousser(Voie &p_v, double p_x) {
	if (!fini(p_x)) {
		p_v.non_finis++;
		p_x = 0.0;
	}
	p_v.somme2 += p_x * p_x;
	p_v.total++;
	p_v.crete = std::max(p_v.crete, std::fabs(p_x));
	p_v.morceau[ORDRE + p_v.n] = p_x;
	p_v.n++;
	if (p_v.n == MORCEAU) {
		examiner(p_v);
		// les ORDRE derniers échantillons servent d'« avant » au morceau suivant
		for (int i = 0; i < ORDRE; i++) {
			p_v.morceau[i] = p_v.morceau[MORCEAU + i];
		}
		p_v.n = 0;
	}
}

void AnalyseSon::examiner(Voie &p_v) {
	const double *x = p_v.morceau.data() + ORDRE;   // x[-ORDRE..-1] = avant
	// modèle de prédiction (Levinson-Durbin sur l'autocorrélation du morceau)
	double r[ORDRE + 1];
	for (int k = 0; k <= ORDRE; k++) {
		double s = 0.0;
		for (int i = k; i < MORCEAU; i++) {
			s += x[i] * x[i - k];
		}
		r[k] = s;
	}
	const int64_t debut = p_v.position;
	p_v.position += MORCEAU;
	if (r[0] < 1e-18 * MORCEAU) {
		return;   // silence
	}
	r[0] *= 1.0 + 1e-9;
	double a[ORDRE + 1] = { 1.0 };
	double erreur = r[0];
	for (int i = 1; i <= ORDRE; i++) {
		double acc = r[i];
		for (int j = 1; j < i; j++) {
			acc += a[j] * r[i - j];
		}
		const double k = -acc / erreur;
		double nouveau[ORDRE + 1];
		for (int j = 0; j <= ORDRE; j++) {
			nouveau[j] = a[j];
		}
		for (int j = 1; j < i; j++) {
			nouveau[j] = a[j] + k * a[i - j];
		}
		nouveau[i] = k;
		for (int j = 0; j <= ORDRE; j++) {
			a[j] = nouveau[j];
		}
		erreur *= (1.0 - k * k);
		if (erreur <= 0.0) {
			break;
		}
	}
	// écarts entre le son et sa prédiction
	std::vector<double> e(MORCEAU);
	std::vector<double> cumul(MORCEAU + 1, 0.0);
	for (int n = 0; n < MORCEAU; n++) {
		double s = x[n];
		for (int k = 1; k <= ORDRE; k++) {
			s += a[k] * x[n - k];
		}
		e[n] = s;
		cumul[n + 1] = cumul[n] + s * s;
	}
	// un clic : un écart isolé, bien plus grand que ceux de ses voisins (hors ±2 échantillons)
	for (int n = debut == 0 ? ORDRE : 0; n < MORCEAU; n++) {
		const double v = std::fabs(e[n]);
		if (v < 1e-6) {
			continue;
		}
		const int g0 = std::max(0, n - VOISINS), g1 = std::max(0, n - 2);
		const int d0 = std::min(MORCEAU, n + 3), d1 = std::min(MORCEAU, n + VOISINS + 1);
		const int nb = (g1 - g0) + (d1 - d0);
		if (nb < 16) {
			continue;
		}
		const double voisins = (cumul[g1] - cumul[g0]) + (cumul[d1] - cumul[d0]);
		const double rms = std::sqrt(voisins / nb);
		const double rapport = rms > 0.0 ? v / rms : 1e9;
		p_v.pire = std::max(p_v.pire, rapport);
		if (rapport > SEUIL) {
			const int64_t ici = debut + n;
			if (ici - p_v.dernier_clic > 32) {
				p_v.craquements++;
				if (p_v.premier_clic < 0.0) {
					p_v.premier_clic = (double)ici;
				}
			}
			p_v.dernier_clic = ici;
		}
	}
}

void AnalyseSon::ajouter(const PackedVector2Array &p_son) {
	const int n = (int)p_son.size();
	const Vector2 *s = p_son.ptr();
	for (int i = 0; i < n; i++) {
		pousser(voies[0], s[i].x);
		pousser(voies[1], s[i].y);
	}
}

void AnalyseSon::ajouter_mono(const PackedFloat32Array &p_son) {
	const int n = (int)p_son.size();
	const float *s = p_son.ptr();
	for (int i = 0; i < n; i++) {
		pousser(voies[0], s[i]);
		pousser(voies[1], s[i]);
	}
}

Dictionary AnalyseSon::resultat() const {
	Dictionary d;
	const char *noms[2] = { "gauche", "droite" };
	int craq = 0;
	int nf = 0;
	double pire = 0.0, crete = 0.0;
	for (int c = 0; c < 2; c++) {
		const Voie &v = voies[c];
		Dictionary dv;
		const double ms = v.total > 0 ? v.somme2 / (double)v.total : 0.0;
		dv["energie"] = ms;
		dv["db"] = ms > 0.0 ? 10.0 * std::log10(ms) : -400.0;
		dv["crete"] = v.crete;
		dv["craquements"] = v.craquements;
		dv["premier_clic"] = v.premier_clic;
		dv["pire"] = v.pire;
		dv["non_finis"] = v.non_finis;
		dv["echantillons"] = (int64_t)v.total;
		d[noms[c]] = dv;
		craq += v.craquements;
		nf += v.non_finis;
		pire = std::max(pire, v.pire);
		crete = std::max(crete, v.crete);
	}
	d["craquements"] = craq;
	d["non_finis"] = nf;
	d["pire"] = pire;
	d["crete"] = crete;
	return d;
}

namespace {
void fft(std::vector<std::complex<double>> &a) {
	const int n = (int)a.size();
	for (int i = 1, j = 0; i < n; i++) {
		int bit = n >> 1;
		for (; j & bit; bit >>= 1) {
			j ^= bit;
		}
		j ^= bit;
		if (i < j) {
			std::swap(a[i], a[j]);
		}
	}
	for (int len = 2; len <= n; len <<= 1) {
		const double ang = -2.0 * PI_D / len;
		const std::complex<double> wl(std::cos(ang), std::sin(ang));
		for (int i = 0; i < n; i += len) {
			std::complex<double> w(1.0);
			for (int j = 0; j < len / 2; j++) {
				const std::complex<double> u = a[i + j], v = a[i + j + len / 2] * w;
				a[i + j] = u + v;
				a[i + j + len / 2] = u - v;
				w *= wl;
			}
		}
	}
}
} // namespace

PackedFloat64Array AnalyseSon::spectre_tiers(const PackedVector2Array &p_son, double p_taux) const {
	PackedFloat64Array res;
	res.resize(SyntheSon::BANDES);
	for (int j = 0; j < SyntheSon::BANDES; j++) {
		res[j] = 0.0;
	}
	const int n = (int)p_son.size();
	const int N = 65536;   // raies de 0,73 Hz à 48 kHz : même le tiers d'octave de 31 Hz (7 Hz de large) en a 10
	if (n < N) {
		return res;
	}
	std::vector<double> fenetre(N);
	double w2 = 0.0;
	for (int i = 0; i < N; i++) {
		fenetre[i] = 0.5 - 0.5 * std::cos(2.0 * PI_D * i / N);
		w2 += fenetre[i] * fenetre[i];
	}
	std::vector<double> psd(N / 2 + 1, 0.0);
	int morceaux = 0;
	std::vector<std::complex<double>> a(N);
	for (int debut = 0; debut + N <= n; debut += N / 2) {
		for (int i = 0; i < N; i++) {
			a[i] = std::complex<double>(p_son[debut + i].x * fenetre[i], 0.0);
		}
		fft(a);
		for (int k = 0; k <= N / 2; k++) {
			const double p = std::norm(a[k]) * ((k == 0 || k == N / 2) ? 1.0 : 2.0);
			psd[k] += p;
		}
		morceaux++;
	}
	// Parseval : Σ |X_k|² / (N Σw²) = carré moyen
	const double norme = 1.0 / ((double)morceaux * N * w2);
	// chaque raie couvre [f − df/2, f + df/2] : partagée entre deux bandes si une limite tombe dedans
	const double df = p_taux / N;
	for (int k = 1; k <= N / 2; k++) {
		const double f0 = (k - 0.5) * df;
		const double f1 = (k + 0.5) * df;
		const double j0 = 3.0 * std::log2(f0 / 31.25) + 1.0 + 0.5;   // indice de bande (réel) + ½
		const int b0 = (int)std::floor(j0);
		const int b1 = (int)std::floor(3.0 * std::log2(f1 / 31.25) + 1.0 + 0.5);
		const double p = psd[k] * norme;
		if (b0 == b1) {
			if (b0 >= 0 && b0 < SyntheSon::BANDES) {
				res[b0] += p;
			}
		} else {
			const double limite = 31.25 * std::pow(2.0, (b1 - 1.5) / 3.0);   // bord bas de la bande b1
			const double part = (limite - f0) / df;
			if (b0 >= 0 && b0 < SyntheSon::BANDES) {
				res[b0] += p * part;
			}
			if (b1 >= 0 && b1 < SyntheSon::BANDES) {
				res[b1] += p * (1.0 - part);
			}
		}
	}
	return res;
}

void AnalyseSon::_bind_methods() {
	ClassDB::bind_method(D_METHOD("ajouter", "son"), &AnalyseSon::ajouter);
	ClassDB::bind_method(D_METHOD("ajouter_mono", "son"), &AnalyseSon::ajouter_mono);
	ClassDB::bind_method(D_METHOD("resultat"), &AnalyseSon::resultat);
	ClassDB::bind_method(D_METHOD("remettre"), &AnalyseSon::remettre);
	ClassDB::bind_method(D_METHOD("spectre_tiers", "son", "taux"), &AnalyseSon::spectre_tiers);
}
