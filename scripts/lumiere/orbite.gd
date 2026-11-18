extends RefCounted
## Un astre sur une orbite autour d'une planète (étape 5) : vraie gravité de Newton (orbite circulaire
## de Kepler), et RETARD DE LA LUMIÈRE : on voit l'astre là où il était quand sa lumière est partie.
## Repère « fixe » (qui ne tourne pas avec la planète), centré sur la planète ; positions en mètres,
## 64 bits (float de GDScript). Ce fichier fait partie du système : il ne dépend de rien d'autre.

const G := 6.674e-11                  # constante de la gravitation, m³/(kg·s²)
const C := 299792458.0                # vitesse de la lumière, m/s

var gm := 1.0                         # G × masse de la planète, m³/s²
var rayon_orbite := 1.0               # m
var u := Vector3.RIGHT                # l'astre est dans cette direction au temps 0
var v := Vector3.FORWARD              # … et avance dans celle-ci (u et v perpendiculaires)
var phase := 0.0                      # rad, angle au temps 0


## Masse d'une boule de rayon r (m) et de masse volumique rho (kg/m³) → G × masse.
static func gm_boule(r: float, rho: float) -> float:
	return G * rho * 4.0 / 3.0 * PI * r * r * r


func configurer(p_gm: float, p_rayon_orbite: float, p_u: Vector3, p_v: Vector3) -> void:
	gm = p_gm
	rayon_orbite = p_rayon_orbite
	u = p_u.normalized()
	v = (p_v - u * u.dot(p_v)).normalized()


## Vitesse angulaire (rad/s) : loi de Kepler, ω² r³ = G M.
func vitesse_angulaire() -> float:
	return sqrt(gm / (rayon_orbite * rayon_orbite * rayon_orbite))


## Durée d'un tour (s).
func periode() -> float:
	return TAU / vitesse_angulaire()


## Vitesse sur l'orbite (m/s).
func vitesse() -> float:
	return sqrt(gm / rayon_orbite)


## Angle sur l'orbite au temps t (s).
func angle(t: float) -> float:
	return phase + vitesse_angulaire() * t


## Position vraie de l'astre au temps t (m, 64 bits, repère fixe).
func position(t: float) -> PackedFloat64Array:
	var a := angle(t)
	var ca := cos(a) * rayon_orbite
	var sa := sin(a) * rayon_orbite
	return PackedFloat64Array([u.x * ca + v.x * sa, u.y * ca + v.y * sa, u.z * ca + v.z * sa])


## Retard de la lumière : temps (s) mis par la lumière partie de l'astre pour arriver à l'œil au
## temps t (œil en repère fixe, m). On cherche t_e tel que |position(t_e) − œil| = c (t − t_e) ;
## quelques tours suffisent (l'astre va bien moins vite que la lumière).
func retard(t: float, oeil: PackedFloat64Array) -> float:
	var r := 0.0
	for i in 6:
		var p := position(t - r)
		var dx := p[0] - oeil[0]
		var dy := p[1] - oeil[1]
		var dz := p[2] - oeil[2]
		r = sqrt(dx * dx + dy * dy + dz * dz) / C
	return r


## Position où l'œil VOIT l'astre au temps t : là où il était quand sa lumière est partie.
func position_vue(t: float, oeil: PackedFloat64Array) -> PackedFloat64Array:
	return position(t - retard(t, oeil))


## Choisit la phase pour que l'astre soit dans la direction d au temps t (pour les points de vue d'essai).
func placer(t: float, d: Vector3) -> void:
	var a := atan2(d.dot(v), d.dot(u))
	phase = a - vitesse_angulaire() * t
