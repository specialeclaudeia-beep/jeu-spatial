// Système de décomposition fractale de la lumière (idée de Gwenaël) : la partie en C++.
// Étape 4 du programme : les deux temps lourds de la boucle d'une image,
//   1. CHOISIR : quels triangles de la planète afficher (couper ceux qui sont trop gros à l'écran,
//      fusionner ceux qui sont devenus trop petits, oublier ceux qu'on ne voit pas) ;
//   2. ÉCLAIRER : calculer les rayons des nouveaux triangles (relief, couleur du sol, direction
//      moyenne de la surface et son étalement).
// L'envoi vers la carte graphique et le dessin restent en GDScript et dans le shader.
//
// Un seul arbre de triangles : les 20 faces d'un icosaèdre, chacune coupée en 4 à chaque niveau.
// L'adresse d'un triangle est un entier de 64 bits : un 1 de tête, 5 bits pour la face de départ,
// puis 2 bits par niveau. Elle sert aussi de graine : tout ce qui est calculé pour un triangle
// est refait à l'identique à partir de son adresse et de la graine de la planète.
//
// Un triangle affiché = un « morceau » : le triangle coupé 3 fois en 4 (64 petits triangles,
// 45 coins). Chaque petit triangle est un RAYON (sa couleur, sa direction moyenne).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>

#include <cstdint>
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace lumiere {

constexpr int COUPES = 8;              // 8 petits triangles par côté du morceau
constexpr int NB_COINS = 45;           // (8+1)(8+2)/2
constexpr int NB_RAYONS = 64;          // 8 × 8
constexpr int NIVEAU_MAX = 26;         // morceau de niveau 26 : côté ≈ 9 mm, rayons ≈ 1,2 mm sur la planète d'essai
// Étape 7 : couleur de départ, couleur visée, direction, horizon de départ, horizon visé.
constexpr int TEXELS_PAR_COIN_LUMIERE = 5;
constexpr int NB_AZIMUTS = 4;          // horizon mesuré vers l'est, le nord, l'ouest et le sud du coin
// Étape 7 : cailloux (des blocs de 1,5 m aux graviers de 1 cm) pour ces détails du relief.
constexpr int OCTAVE_CAILLOUX_MIN = 17;
constexpr int OCTAVE_CAILLOUX_MAX = 25;
constexpr int TEXELS_PAR_COIN = 2;     // position de départ, position visée

struct Vec3d {
	double x = 0, y = 0, z = 0;
	Vec3d() {}
	Vec3d(double a, double b, double c) : x(a), y(b), z(c) {}
	Vec3d operator+(const Vec3d &o) const { return Vec3d(x + o.x, y + o.y, z + o.z); }
	Vec3d operator-(const Vec3d &o) const { return Vec3d(x - o.x, y - o.y, z - o.z); }
	Vec3d operator*(double k) const { return Vec3d(x * k, y * k, z * k); }
	double dot(const Vec3d &o) const { return x * o.x + y * o.y + z * o.z; }
	Vec3d cross(const Vec3d &o) const { return Vec3d(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x); }
	double length() const;
	Vec3d normalized() const;
};

// Un triangle de l'arbre, calculé et gardé en mémoire (cache).
struct Morceau {
	uint64_t adresse = 0;
	int niveau = 0;
	Vec3d coins[3];               // directions (longueur 1) des 3 coins
	int naissance_coins[3] = {0, 0, 0}; // niveau où chaque coin est apparu dans l'arbre
	Vec3d centre;                 // m, repère de la planète (64 bits)
	double rayon_englobant = 0;   // m : boule qui contient tout le morceau et ses détails plus fins
	double cote = 0;              // m : longueur d'un côté du morceau
	float taille_rayon = 0;       // m : côté d'un petit triangle (un rayon)
	float jupe = 0;               // m : profondeur de la « jupe » qui cache les fentes entre morceaux
	float cible[NB_COINS][3];     // positions des coins, m, par rapport au centre
	float depart[NB_COINS][3];    // positions de départ du glissement (forme du parent)
	float centres[NB_RAYONS][3];  // centre de chaque rayon, par rapport au centre du morceau
	// La lumière des rayons est rangée sur leurs COINS partagés (doc « couleurs stables ») : deux
	// morceaux voisins ont exactement les mêmes valeurs sur leur bord commun, et la carte graphique
	// passe en douceur d'un coin à l'autre (pas de mosaïque).
	float albedo[NB_COINS][3];    // couleur du sol (part de lumière renvoyée), lumière linéaire
	float albedo_depart[NB_COINS][3];
	float direction[NB_COINS][3]; // direction moyenne de la surface, longueur = (1 + cos b) / 2
	// Étape 7 : hauteur de l'horizon (rad au-dessus de l'horizontale du lieu) vers l'est, le nord,
	// l'ouest et le sud. Ne dépend pas du Soleil : la carte graphique compare seulement la hauteur de
	// l'étoile à celle de l'horizon dans sa direction → ombres du relief proche et des cailloux,
	// qui suivent le Soleil sans rien recalculer.
	float horizon[NB_COINS][NB_AZIMUTS];
	float horizon_depart[NB_COINS][NB_AZIMUTS];
	uint64_t derniere_image = 0;  // pour oublier les morceaux inutiles les plus anciens
};

} // namespace lumiere

namespace godot {

class ArbreLumiere : public RefCounted {
	GDCLASS(ArbreLumiere, RefCounted)

public:
	ArbreLumiere();
	~ArbreLumiere();

	// Réglages de la planète.
	void configurer(double p_rayon, int64_t p_graine, int p_places);
	double get_rayon() const { return rayon; }
	double get_relief_max() const { return relief_max; }
	// Taille d'un rayon à l'écran (pixels) au-delà de laquelle on coupe, et en dessous de laquelle on
	// refusionne (programme : couper à 8 px, fusionner à 6 px ; l'écart évite les clignotements).
	void regler_seuils(double p_couper, double p_fusion);

	// 1. CHOISIR. camera = position de l'œil dans le repère de la planète (m, 64 bits) ;
	// axes = devant, droite, haut (9 nombres, repère de la planète) ; tan_h / tan_v = demi-champ ;
	// hauteur_px = hauteur de l'écran ; temps = horloge du labo (s), pour le glissement.
	int choisir(const PackedFloat64Array &p_camera, const PackedFloat32Array &p_axes, double p_tan_h,
			double p_tan_v, double p_hauteur_px, double p_temps);
	// 2. ÉCLAIRER : calcule jusqu'à max_morceaux nouveaux morceaux demandés (sur plusieurs fils),
	// en s'arrêtant quand le temps donné (ms) est dépassé.
	int eclairer(int p_max_morceaux, double p_budget_ms = 3.0);

	// Envoi (préparé ici, fait par GDScript).
	PackedFloat32Array tampon_instances(const Basis &p_rotation, const PackedFloat64Array &p_decalage) const;
	PackedByteArray donnees_rayons() const { return tampon_rayons; }
	PackedByteArray donnees_coins() const { return tampon_coins; }
	bool a_change();

	// Le « posemètre » de l'œil : luminance moyenne (cd/m²) de 16 × 9 cases de l'écran.
	// Étape 5 : occulteur = [x, y, z, rayon] d'un astre qui peut cacher le Soleil (repère de cette
	// planète, m ; vide = aucun) et soleil_angle = rayon apparent du Soleil (rad) : chaque rayon
	// reçoit seulement la part du disque solaire qu'il voit (ombre et pénombre d'une éclipse).
	PackedFloat32Array posemetre(const PackedFloat64Array &p_camera, const PackedFloat32Array &p_axes,
			double p_tan_h, double p_tan_v, const Vector3 &p_soleil, double p_eclairement, double p_fond,
			const PackedFloat64Array &p_occulteur = PackedFloat64Array(), double p_soleil_angle = 0.004652) const;
	// Part de chaque case (0 à 1) couverte par cette planète au dernier posemètre : sert à mettre
	// deux astres l'un devant l'autre (la lune devant la planète, par exemple).
	PackedFloat32Array couverture() const { return derniere_couverture; }
	// Étape 9 (reflets) : « carte du ciel » vue de l'œil, tirée des mêmes rayons que le posemètre, mais
	// dans TOUTES les directions (pas seulement l'écran). Carte en longitude-latitude de largeur × hauteur
	// cases, dans le repère d'affichage (rotation = repère de l'astre → affichage, comme
	// tampon_instances). Direction d → u = atan2(d.x, −d.z) / 2π + 0,5 ; v = acos(d.y) / π.
	// Rend 4 nombres par case : luminance rouge, verte, bleue (cd/m², moyenne des rayons de la case) et
	// la part de la case couverte par l'astre (0 à 1, calculée par la géométrie de la boule). Une case
	// de l'astre sans rayon (rayon trop gros près de l'œil, morceau grossier hors de l'écran) prend la
	// moyenne de ses voisines, sinon la loi de Lambert. Les vitres et les métaux s'en servent pour
	// refléter la planète (verrière, visière, coque).
	PackedFloat32Array carte_ciel(const PackedFloat64Array &p_camera, const Basis &p_rotation, int p_largeur,
			int p_hauteur, const Vector3 &p_soleil, double p_eclairement,
			const PackedFloat64Array &p_occulteur = PackedFloat64Array(), double p_soleil_angle = 0.004652) const;
	// Part du disque du Soleil (0 à 1) vue depuis le point p quand une sphère (centre c, rayon r) peut
	// le cacher. s = direction du Soleil, a = son rayon apparent (rad). Recouvrement de deux disques.
	static double part_soleil_visible(const lumiere::Vec3d &p, const lumiere::Vec3d &c, double r,
			const lumiere::Vec3d &s, double a);
	static double recouvrement(double a, double b, double e);
	double part_visible(const PackedFloat64Array &p_point, const PackedFloat64Array &p_occulteur,
			const Vector3 &p_soleil, double p_soleil_angle) const;

	// Relief (m au-dessus du rayon de la planète) sous une direction, au détail le plus fin.
	double hauteur_sol(const PackedFloat64Array &p_direction) const;

	// Compteurs.
	int nb_morceaux() const { return (int)affiches.size(); }
	int nb_rayons() const { return (int)affiches.size() * lumiere::NB_RAYONS; }
	int nb_en_cache() const { return (int)cache.size(); }
	int nb_demandes() const { return (int)demandes.size(); }
	int get_places() const { return places; }
	int largeur_rayons() const { return lumiere::NB_COINS * lumiere::TEXELS_PAR_COIN_LUMIERE; }
	int hauteur_rayons() const { return places; }
	int largeur_coins() const { return lumiere::NB_COINS * lumiere::TEXELS_PAR_COIN; }
	int niveau_max_affiche() const;

	// Pour les tests.
	PackedInt64Array racines() const;
	PackedInt64Array morceaux_affiches() const;
	static int64_t adresse_enfant(int64_t p_adresse, int p_i) { return (p_adresse << 2) | (p_i & 3); }
	static int niveau_de(int64_t p_adresse);
	PackedFloat64Array coins_morceau(int64_t p_adresse);       // 45 × 3, positions visées (m, planète)
	PackedFloat64Array coins_depart_morceau(int64_t p_adresse); // 45 × 3, positions de départ
	PackedFloat32Array couleurs_morceau(int64_t p_adresse);    // 64 × 3, albédo
	PackedFloat32Array directions_morceau(int64_t p_adresse);  // 64 × 3
	PackedFloat32Array horizons_morceau(int64_t p_adresse);    // 45 × 4 (rad)
	// Étape 7 : part du disque d'une étoile (direction s, rayon apparent a) au-dessus de l'horizon du
	// relief proche, au coin de direction d né au niveau nais (même loi que planete.gdshader).
	double part_horizon(const PackedFloat64Array &p_direction, int p_naissance, const Vector3 &p_etoile, double p_a) const;
	PackedFloat32Array horizon_point(const PackedFloat64Array &p_direction, int p_naissance) const;
	// Repère du lieu : t1 = « est », t2 = « nord » (le même dans le shader).
	static void repere_lieu(const lumiere::Vec3d &d, lumiere::Vec3d &t1, lumiere::Vec3d &t2);
	// Lumière reçue par le rayon t du morceau m (point p, repère de l'astre) : part de l'étoile vue
	// (cône de petites faces, ombre de l'astre, horizon proche, occulteur) ; rend aussi la direction
	// moyenne n (non normée) et l'albédo moyen. Commun au posemètre et à la carte du ciel.
	double eclairage_rayon(const lumiere::Morceau &m, int t, const lumiere::Vec3d &p, const lumiere::Vec3d &s,
			bool avec_occ, const lumiere::Vec3d &occ_c, double occ_r, double angle, lumiere::Vec3d &n,
			float al[3]) const;
	// Rebonds de la lumière sur le sol (Q38) : voir arbre_lumiere.cpp.
	static double rebond_lieu(double cos_penche, double longueur, const float hz[lumiere::NB_AZIMUTS],
			double haut_soleil, double albedo);
	static double rebond_test(double p_cos_penche, double p_longueur, const PackedFloat32Array &p_horizons,
			double p_haut_soleil, double p_albedo);
	static double part_sous_horizon(const lumiere::Vec3d &up, const lumiere::Vec3d &t1, const lumiere::Vec3d &t2,
			const float h[lumiere::NB_AZIMUTS], const lumiere::Vec3d &s, double a);
	PackedFloat64Array centre_morceau(int64_t p_adresse);      // 3 nombres + rayon englobant

protected:
	static void _bind_methods();

private:
	// Planète.
	double rayon = 600000.0;
	uint64_t graine = 1;
	int places = 1024;
	double relief_max = 0;
	double seuil_couper = 8.0;
	double seuil_fusion = 6.0;
	mutable PackedFloat32Array derniere_couverture;

	// Arbre.
	std::unordered_map<uint64_t, std::unique_ptr<lumiere::Morceau>> cache;
	std::unordered_set<uint64_t> interieurs_prec; // triangles coupés à l'image d'avant
	std::unordered_set<uint64_t> interieurs;
	std::vector<lumiere::Morceau *> affiches;     // morceaux affichés (feuilles)
	std::unordered_set<uint64_t> affiches_prec;
	std::unordered_map<uint64_t, int> place_de;   // adresse → place (ligne des textures)
	std::vector<uint64_t> occupant;               // place → adresse (0 = libre)
	std::vector<float> naissance;                 // place → heure d'arrivée (glissement)
	std::vector<int> places_libres;
	std::vector<std::pair<double, uint64_t>> demandes; // (taille à l'écran, adresse) à calculer
	std::unordered_set<uint64_t> deja_demande;
	uint64_t image = 0;
	bool change = true;

	// Tampons envoyés à la carte graphique.
	PackedByteArray tampon_rayons;
	PackedByteArray tampon_coins;

	// Œil pendant le choix.
	lumiere::Vec3d cam;
	lumiere::Vec3d devant, droite, haut;
	double tan_h = 1, tan_v = 1, px_par_radian = 1;
	int budget_coupes = 0;

	// Calcul.
	void calculer(lumiere::Morceau &m, const lumiere::Morceau *parent, int quel_enfant) const;
	void calculer_racine(lumiere::Morceau &m, int face) const;
	void finir_calcul(lumiere::Morceau &m, const lumiere::Morceau *parent, int quel_enfant) const;
	lumiere::Morceau *assurer(uint64_t adresse);
	void visiter(lumiere::Morceau *m);
	void considerer(lumiere::Morceau *m);
	double taille_ecran(const lumiere::Morceau &m) const;
	std::vector<std::pair<double, lumiere::Morceau *>> file; // morceaux à couper, le plus gros d'abord
	bool visible(const lumiere::Morceau &m) const;
	void ecrire_place(int place, const lumiere::Morceau &m);
	void vider_place(int place);
	void oublier_anciens();

public:
	// Relief et couleurs (fonctions déterministes de la position et de la graine).
	double hauteur(const lumiere::Vec3d &dir, int octaves) const;
	// Un seul détail (octave n) du relief au point p (m, repère de la planète), en m.
	double octave(const lumiere::Vec3d &p, int n) const;
	// Cailloux de l'octave n autour de q (coordonnées en tailles de cellule) : 0 hors d'un caillou,
	// jusqu'à 1 au sommet ; teinte = de -1 à 1 (pierre plus claire ou plus sombre).
	double caillou(const lumiere::Vec3d &q, int n, double *teinte) const;
	void couleur_sol(const lumiere::Vec3d &dir, int octaves, float out[3]) const;
	double amplitude(int octave) const;
	// Renvoie la hauteur du coin (m) ; remplit couleur, direction moyenne et horizon (4 azimuts).
	double lumiere_coin(const lumiere::Vec3d &dir, int naissance, float albedo[3], float direction[3],
			float horizon[lumiere::NB_AZIMUTS]) const;
	double longueur_onde(int octave) const;

	// Pour la tâche des fils de calcul.
	struct Travail {
		ArbreLumiere *arbre;
		std::vector<lumiere::Morceau *> sortie;
		std::vector<const lumiere::Morceau *> parents;
		std::vector<int> enfants;
	};
	static void tache_eclairer(void *p_travail, uint32_t p_i);
};

} // namespace godot
