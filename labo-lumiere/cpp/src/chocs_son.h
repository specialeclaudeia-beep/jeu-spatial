// Moteur audio, phase 3 : les sons BREFS (chocs, vannes, verrous, pneus…) fabriqués EN DIRECT, en C++, dans
// le fil audio de Godot (demande de Gwenaël du 21/11 : pas de sons enregistrés, tout calculé sur le moment).
//
// Un choc = une pièce frappée qui vibre selon ses « modes » propres (synthèse modale). Le GDScript
// (scripts/son/chocs.gd) calcule, pour chaque choc, à partir de la physique (masse, vitesse, matière de la pièce
// frappée, durée du contact), la liste de ses modes : fréquence, durée de résonance, force, retard (rebonds,
// grains qui crépitent). Ce fichier les fait sonner, échantillon par échantillon :
//   - chaque mode = a × sin(2π f t) × e^(−t/τ), calculé par une rotation complexe (pas de sinus à calculer) ;
//   - la force du choc monte pendant la durée du contact (demi-cosinus) : pas de marche brutale, pas de clic ;
//   - en option, une bouffée de bruit (gaz d'une vanne, huile d'un vérin) et un crissement de pneu (son presque
//     pur qui tremble, avec ses harmoniques).
// 16 chocs au plus en même temps, 48 modes chacun. Plein : le choc le moins important (puis le plus ancien)
// s'éteint en 30 ms pour laisser la place. Le fil principal dépose les chocs dans une file sans verrou ; le fil
// audio les prend au début de chaque appel.
#pragma once

#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <atomic>
#include <cstdint>
#include <vector>

namespace godot {

class LectureChocsSon;

class ChocsSon : public AudioStream {
	GDCLASS(ChocsSon, AudioStream)
	friend class LectureChocsSon;

public:
	static constexpr int CHOCS = 16;
	static constexpr int MODES = 48;
	static constexpr int FILE = 64;
	// options[] : montée (s), bruit : force, fréquence (Hz), montée (s), descente (s) ; crissement : force,
	// fréquence (Hz), durée (s) ; gain gauche, gain droit, priorité
	static constexpr int OPTIONS = 11;

	struct Choc {
		int n = 0;
		float f[MODES], tau[MODES], a[MODES], retard[MODES];
		float o[OPTIONS];
	};

	ChocsSon();

	// modes : n × [fréquence (Hz), durée de résonance τ (s), force, retard (s)]. Renvoie false si la file est pleine.
	bool frapper(const PackedFloat32Array &p_modes, const PackedFloat32Array &p_options);
	void couper();   // tout s'éteint en 30 ms

	void set_taux(int p_taux);   // 0 = taux du mixage de Godot (sinon : rendu hors ligne des tests)
	int get_taux() const;
	int actifs() const;          // chocs qui sonnent
	bool est_silencieux() const;
	Dictionary mesures() const;
	void remettre_mesures();

	Ref<AudioStreamPlayback> _instantiate_playback() const override;
	String _get_stream_name() const override;
	double _get_length() const override;
	bool _is_monophonic() const override;

protected:
	static void _bind_methods();

private:
	Choc file[FILE];
	std::atomic<uint32_t> tete{ 0 };    // écrit par le fil principal
	std::atomic<uint32_t> queue{ 0 };   // écrit par le fil audio
	std::atomic<uint32_t> coupures{ 0 };
	std::atomic<int> taux{ 0 };

	mutable std::atomic<int> n_actifs{ 0 };
	mutable std::atomic<uint64_t> ns_calcul{ 0 };
	mutable std::atomic<uint64_t> echantillons{ 0 };
	mutable std::atomic<float> crete{ 0.0f };
	mutable std::atomic<int> non_finis{ 0 };
	mutable std::atomic<int> joues{ 0 };
	mutable std::atomic<int> voles{ 0 };
	mutable std::atomic<int> refuses{ 0 };
	mutable std::atomic<int> actifs_max{ 0 };
};

class LectureChocsSon : public AudioStreamPlayback {
	GDCLASS(LectureChocsSon, AudioStreamPlayback)
	friend class ChocsSon;

public:
	void _start(double p_from_pos) override;
	void _stop() override;
	bool _is_playing() const override;
	int32_t _get_loop_count() const override;
	double _get_playback_position() const override;
	void _seek(double p_position) override;
	int32_t _mix(AudioFrame *p_buffer, float p_rate_scale, int32_t p_frames) override;

protected:
	static void _bind_methods() {}

private:
	struct Voix {
		bool actif = false;
		int n = 0;
		int64_t t = 0;           // échantillons depuis le début du choc
		int64_t fin = 0;         // échantillons : après, tout est sous −90 dB
		int64_t debut[ChocsSon::MODES];
		double re[ChocsSon::MODES], im[ChocsSon::MODES], cr[ChocsSon::MODES], ci[ChocsSon::MODES];
		double montee = 0.0;     // échantillons
		// bruit : résonateur AR(2) nourri de bruit, rendu de variance 1
		double b_a = 0.0, b_a1 = 0.0, b_a2 = 0.0, b_g = 0.0, b_y1 = 0.0, b_y2 = 0.0, b_km = 0.0, b_kd = 0.0;
		double b_em = 1.0, b_ed = 1.0;
		// crissement
		double c_a = 0.0, c_f = 0.0, c_n = 0.0, c_pr = 1.0, c_pi = 0.0, c_tremble = 0.0;
		double c_a1 = 0.0, c_a2 = 0.0, c_g = 0.0, c_y1 = 0.0, c_y2 = 0.0;
		float gauche = 1.0f, droite = 1.0f;
		float priorite = 0.0f;
		double fondu = -1.0;     // ≥ 0 : en train de s'éteindre (gain qui descend à chaque échantillon)
		uint32_t hasard = 1;
	};

	Ref<ChocsSon> flux;
	bool joue = false;
	double taux = 48000.0;
	double temps = 0.0;
	uint32_t coupures = 0;
	uint32_t hasard = 0x2545f491u;
	Voix voix[ChocsSon::CHOCS];
	std::vector<double> buf;

	void preparer();
	static constexpr int ATTENTE = 8;
	ChocsSon::Choc attente[ATTENTE];
	int n_attente = 0;
	int lancer(const ChocsSon::Choc &p_c);   // 0 = lancé, 1 = attend une place, 2 = perdu
	void calculer(float *p_sortie, int p_n);
};

} // namespace godot
