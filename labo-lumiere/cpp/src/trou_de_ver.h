// Einstein C : la lumière qui traverse un TROU DE VER (la partie lourde, en C++).
//
// Un trou de ver d'Ellis (1973), celui que Kip Thorne a fait calculer pour le film Interstellar
// (James, von Tunzelmann, Franklin et Thorne 2015, sans la « masse » de leur version) :
//     ds² = −c² dt² + dl² + (a² + l²)(dθ² + sin²θ dφ²)
// l va de −∞ (l'autre côté, un autre système d'étoile) à +∞ (ici) ; en l = 0, la « gorge » est une
// sphère de rayon a. Le temps passe au même rythme partout (pas de gravité) : seul l'espace est courbé.
//
// Un rayon de lumière (plan de son mouvement, paramètre d'impact b = r_o·sin θ) :
//     dφ/dl = b / (r·√(r² − b²)),  r² = a² + l².
// Les intégrales s'écrivent avec les intégrales elliptiques de Legendre F(φ, k) et K(k), calculées
// exactement (forme de Carlson, R_F) : aucune approximation, et très rapide.
//   - b < a et le rayon part vers le trou : il traverse la gorge et part à l'infini DE L'AUTRE CÔTÉ ;
//   - sinon il reste de notre côté (dévié, parfois après avoir tourné autour de la gorge).
// Table pour l'œil à la distance l_o (512 × 4 cases de 4 nombres, comme la table du trou noir) :
//   ligne 0 : rayon vu à θ < θ_c (θ_c = angle de la gorge, sin θ_c = a / r_o), θ = θ_c·(1 − (1 − x)²) :
//             ψ, angle d'origine (dans le ciel de l'autre côté, avant la symétrie des deux bouches) ;
//   ligne 1 : rayon vu à θ > θ_c, θ = θ_c + (π − θ_c)·x² : ψ dans notre ciel ;
//   ligne 2 : étoile de notre ciel à ψ = π·s² : ses 2 images de notre côté (θ1, μ1, θ2, μ2) ;
//   ligne 3 : étoile du ciel d'en face à ψ = π·s² : ses 2 images dans la gorge (θ1, μ1, θ2, μ2).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class TrouDeVer : public RefCounted {
	GDCLASS(TrouDeVer, RefCounted)

public:
	static constexpr int POINTS = 512;

	// Intégrale de Carlson R_F(x, y, z) et intégrales de Legendre.
	static double carlson_rf(double x, double y, double z);
	static double elliptique_f(double phi, double k);
	static double elliptique_k(double k);

	// Angle Φ parcouru par le rayon vu à θ (0 = droit vers le trou), et s'il passe de l'autre côté.
	static double angle_parcouru(double theta, double l_o, double a, bool &traverse);

	// GDScript : [ψ, côté] (côté 1 = ici, −1 = de l'autre côté).
	Vector2 angle_origine(double theta, double l_o, double a) const;
	// Angle de la gorge vu de l_o (rad).
	double angle_gorge(double l_o, double a) const;
	// Déviation totale d'un rayon venu de l'infini et reparti à l'infini de notre côté (b > a).
	double deviation(double b, double a) const;
	// La table complète : 512 × 4 × 4 nombres (ligne par ligne).
	PackedFloat32Array table(double l_o, double a) const;

protected:
	static void _bind_methods();
};

} // namespace godot
