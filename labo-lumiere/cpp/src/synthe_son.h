// Moteur audio, phase 2 : les sons continus du cockpit fabriqués EN DIRECT, en C++, dans le fil audio de Godot.
//
// Pourquoi en C++ : un son se calcule 48 000 fois par seconde ; en GDScript, ce serait des « trous » dans le son.
// Le GDScript (moteur_audio.gd) ne fait que DÉCIDER, 60 fois par seconde : il donne ici des cibles
// (l'énergie voulue dans chaque bande de fréquences, dans chaque résonance, dans chaque son pur), et ce
// fichier glisse doucement vers elles, par blocs de 256 échantillons (5 ms) : jamais de marche d'escalier.
// Rien ici ne lit ni n'écrit la physique.
//
// Une « couche » (classe SyntheSon, un AudioStream de Godot) contient trois sortes de sons, tous calibrés :
// on demande une énergie, elle sort exactement (énergie = carré moyen du signal, pleine échelle = 1).
//   1. Bruit filtré : 30 bandes d'un tiers d'octave (25 Hz à 20 kHz). Chaque bande a son propre bruit au
//      hasard (les bandes ne se mélangent pas) et un filtre de Butterworth d'ordre 4 (pentes de 12 dB par
//      octave) : la courbe des fréquences est celle que la physique a calculée, à un tiers d'octave près.
//      Le bruit ne se répète jamais (pas de boucle).
//   2. Résonances (« modes ») : jusqu'à 32 petits ressorts-amortisseurs numériques. Chacun vibre à sa
//      fréquence propre et s'amortit selon son facteur de perte (durée = 1 / (π f η)), nourri par un bruit :
//      c'est ainsi qu'une plaque de métal « chante » quand on la secoue. Une résonance met du temps à monter
//      et à s'éteindre, comme en vrai.
//   3. Sons purs (« raies ») : jusqu'à 8 sinusoïdes dont la fréquence glisse et tremble un peu (une vraie
//      machine n'est jamais parfaitement régulière).
// La voie droite est la même que la gauche, passée par 4 filtres « passe-tout » (même énergie, même couleur,
// mais décalée dans le temps différemment selon la fréquence) : comme dans un vrai cockpit où le son vient de
// toutes les parois, les deux oreilles n'entendent pas exactement la même chose dans les aigus.
// Côté (phase 4) : chaque bande a sa part d'énergie à gauche (0,5 = au milieu, 1 = tout à gauche) ; une résonance
// prend la part de sa bande. Un propulseur à gauche fait donc sonner plus fort l'oreille gauche dans ses
// fréquences à lui, pendant que le reste du son reste au milieu. Presque gratuit : un gain de plus par bande.
//
// AnalyseSon : outil des tests (craquements, niveau, spectre) ; il ne sert pas pendant le jeu.
#pragma once

#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <atomic>
#include <cstdint>
#include <vector>

namespace godot {

class LectureSyntheSon;

class SyntheSon : public AudioStream {
	GDCLASS(SyntheSon, AudioStream)
	friend class LectureSyntheSon;

public:
	static constexpr int BANDES = 30;
	static constexpr int MODES = 32;
	static constexpr int RAIES = 8;
	static constexpr int BLOC = 256;   // échantillons : les cibles sont relues et rejointes à chaque bloc

	SyntheSon();

	// Cibles (fil principal, à tout moment). Énergies = carré moyen de la sortie (pleine échelle = 1).
	void regler_bandes(const PackedFloat32Array &p_energies);
	void regler_modes(const PackedFloat32Array &p_frequences, const PackedFloat32Array &p_pertes);
	void regler_energie_modes(const PackedFloat32Array &p_energies);
	void regler_raie(int p_i, double p_frequence, double p_energie);
	void regler_gauche(const PackedFloat32Array &p_parts);   // part à gauche par bande (0..1), 0,5 = au milieu
	void couper();   // toutes les cibles à zéro

	void set_lissage(double p_s);
	double get_lissage() const;
	void set_instabilite(double p_relative);
	double get_instabilite() const;
	void set_instabilite_temps(double p_s);
	double get_instabilite_temps() const;
	void set_taux(int p_taux);   // 0 = taux du mixage de Godot (sinon : rendu hors ligne des tests)
	int get_taux() const;
	void set_graine(int p_graine);
	int get_graine() const;

	// Lectures (pour le chef d'orchestre, les tests et le mode --mesure).
	static PackedFloat32Array centres();
	double energie_cible() const;      // Σ des cibles
	double energie_en_cours() const;   // Σ des énergies lissées (là où en est le son)
	bool est_silencieux() const;
	Dictionary mesures() const;        // charge, µs max par appel, crête, valeurs invalides…
	void remettre_mesures();

	// AudioStream
	Ref<AudioStreamPlayback> _instantiate_playback() const override;
	String _get_stream_name() const override;
	double _get_length() const override;
	bool _is_monophonic() const override;

protected:
	static void _bind_methods();

private:
	std::atomic<float> cible_bandes[BANDES];
	std::atomic<float> cible_gauche[BANDES];
	std::atomic<float> cible_modes[MODES];
	std::atomic<float> modes_f[MODES];
	std::atomic<float> modes_perte[MODES];
	std::atomic<int> nombre_modes{ 0 };
	std::atomic<uint32_t> version_modes{ 0 };
	std::atomic<float> raies_f[RAIES];
	std::atomic<float> raies_e[RAIES];
	std::atomic<float> lissage{ 0.01f };
	std::atomic<float> instabilite{ 0.002f };
	std::atomic<float> instabilite_temps{ 0.5f };
	std::atomic<int> taux{ 0 };
	std::atomic<int> graine{ 1 };
	mutable std::atomic<int> lectures{ 0 };

	// écrit par le fil audio
	mutable std::atomic<float> en_cours{ 0.0f };
	mutable std::atomic<bool> silencieux{ true };
	mutable std::atomic<uint64_t> ns_calcul{ 0 };
	mutable std::atomic<uint64_t> echantillons{ 0 };
	mutable std::atomic<uint64_t> appels{ 0 };
	mutable std::atomic<float> ns_max_par_echantillon{ 0.0f };
	mutable std::atomic<float> us_max_appel{ 0.0f };
	mutable std::atomic<float> crete{ 0.0f };
	mutable std::atomic<int> non_finis{ 0 };
};

class LectureSyntheSon : public AudioStreamPlayback {
	GDCLASS(LectureSyntheSon, AudioStreamPlayback)
	friend class SyntheSon;

public:
	LectureSyntheSon();

	void _start(double p_from_pos) override;
	void _stop() override;
	bool _is_playing() const override;
	int32_t _get_loop_count() const override;
	double _get_playback_position() const override;
	void _seek(double p_position) override;
	int32_t _mix(AudioFrame *p_buffer, float p_rate_scale, int32_t p_frames) override;

protected:
	static void _bind_methods();

private:
	struct Bande {
		bool active = false;
		double b0 = 0.0;                     // gain du numérateur (1 − z⁻²) de la 1re section
		double a1[2] = { 0, 0 }, a2[2] = { 0, 0 };
		double s1[2] = { 0, 0 }, s2[2] = { 0, 0 };   // états (forme transposée II)
		double echelle = 0.0;                // énergie → gain : 1 / (σ² Σh²)
		uint32_t hasard = 1;
		double e = 0.0;                      // énergie lissée
		double g = 0.0;                      // gain appliqué (amplitude)
		double gc = 0.0;                     // gain visé à la fin du bloc en cours
		double w = 0.5;                      // part de l'énergie à gauche, lissée
		double pl = 1.0, pr = 1.0;           // gains gauche et droite (√(2w), √(2(1 − w)))
		double plc = 1.0, prc = 1.0;         // visés à la fin du bloc
	};
	struct Mode {
		bool actif = false;
		double a1 = 0.0, a2 = 0.0, k = 0.0;  // y = a1·y1 − a2·y2 + b·x ; carré moyen de y = b² σ² k
		double y1 = 0.0, y2 = 0.0;
		uint32_t hasard = 1;
		double e = 0.0, b = 0.0, bc = 0.0;
		int bande = 0;                       // tiers d'octave de sa fréquence (pour le côté)
	};
	struct Raie {
		double f = 0.0;              // Hz, lissée
		double tremble = 0.0;        // écart relatif de fréquence (processus d'Ornstein-Uhlenbeck)
		double re = 1.0, im = 0.0;   // phaseur
		double e = 0.0, a = 0.0, ac = 0.0;
	};
	struct PasseTout {
		std::vector<float> ligne;
		int pos = 0;
		float g = 0.6f;
	};

	Ref<SyntheSon> flux;
	bool joue = false;
	bool pret = false;
	double taux = 48000.0;
	int dans_bloc = 0;                  // position dans le bloc en cours
	double k_lissage = 1.0;             // part de l'écart rattrapée à chaque bloc
	uint32_t version_modes = 0xffffffffu;
	uint32_t hasard_raies = 12345;
	double temps = 0.0;
	Bande bandes[SyntheSon::BANDES];
	Mode modes[SyntheSon::MODES];
	Raie raies[SyntheSon::RAIES];
	double pas_g[SyntheSon::BANDES];
	double pas_pl[SyntheSon::BANDES], pas_pr[SyntheSon::BANDES];
	bool au_milieu = true;               // toutes les bandes au milieu : un seul calcul pour les deux oreilles
	double pas_b[SyntheSon::MODES];
	double pas_a[SyntheSon::RAIES];
	double rot_re[SyntheSon::RAIES], rot_im[SyntheSon::RAIES];
	PasseTout passe_tout[4];
	std::vector<float> mono;     // voie gauche (ou les deux, si tout est au milieu)
	std::vector<float> droite;

	void preparer();
	void preparer_modes();
	void debut_bloc();
	void calculer(float *p_sortie, int p_n);
	void remettre_a_zero();
};

// Outil des tests : niveau, crête, craquements (clics) et spectre d'un son.
// Craquements : chaque morceau de 4 096 échantillons est prédit par un modèle de 16 coefficients (un son
// régulier se prédit bien) ; un clic est un écart soudain, au moins 9 fois plus grand que les écarts de ses
// voisins immédiats (±64 échantillons). Une montée rapide mais douce (vanne qui s'ouvre) n'en est pas un.
class AnalyseSon : public RefCounted {
	GDCLASS(AnalyseSon, RefCounted)

public:
	static constexpr int MORCEAU = 4096;
	static constexpr int ORDRE = 16;
	static constexpr int VOISINS = 64;
	static constexpr double SEUIL = 9.0;

	AnalyseSon();
	void ajouter(const PackedVector2Array &p_son);
	void ajouter_mono(const PackedFloat32Array &p_son);
	Dictionary resultat() const;
	void remettre();
	// Énergie (carré moyen) dans chacune des 30 bandes d'un tiers d'octave (méthode de Welch, voie gauche).
	PackedFloat64Array spectre_tiers(const PackedVector2Array &p_son, double p_taux) const;

protected:
	static void _bind_methods();

private:
	struct Voie {
		std::vector<double> morceau;    // ORDRE échantillons d'avant + MORCEAU
		int n = 0;
		double somme2 = 0.0;
		uint64_t total = 0;
		double crete = 0.0;
		int non_finis = 0;
		int craquements = 0;
		double pire = 0.0;
		int64_t dernier_clic = -1000000;
		int64_t position = 0;
		double premier_clic = -1.0;
	};
	Voie voies[2];
	void pousser(Voie &p_v, double p_x);
	void examiner(Voie &p_v);
};

} // namespace godot
