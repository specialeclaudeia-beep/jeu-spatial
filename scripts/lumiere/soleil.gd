extends RefCounted
## Le vrai Soleil (étape 3) : vraie distance, vraie taille, vraie lumière.
## Toutes les positions sont en mètres et en 64 bits (float de GDScript, rangés dans des
## PackedFloat64Array [x, y, z]) ; seules les directions partent vers la carte graphique.
## Ce fichier fait partie du système : il ne dépend de rien d'autre.

const UA := 1.495978707e11            # unité astronomique, m
const RAYON := 6.957e8                # rayon du Soleil, m
const ECLAIREMENT_1UA := 1361.0 * 93.0   # 1361 W/m² × 93 lm/W ≈ 126 600 lux (hors atmosphère)
const ASSOMBRISSEMENT_BORD := 0.6     # le bord du disque est 60 % plus sombre que le centre
## Couleur du Soleil vu de l'espace (presque blanc, à peine chaud), luminance 1.
const COULEUR := Color(1.06, 0.99, 0.93)

## Position du centre du Soleil, m (64 bits).
var position := PackedFloat64Array([UA, 0.0, 0.0])


## Distance (m) entre le point p et le centre du Soleil.
func distance(p: PackedFloat64Array) -> float:
	var dx := position[0] - p[0]
	var dy := position[1] - p[1]
	var dz := position[2] - p[2]
	return sqrt(dx * dx + dy * dy + dz * dz)


## Retard de la lumière (s) : la lumière du Soleil qui arrive en p est partie il y a distance / c
## (8 min 19 s à 1 UA). Le Soleil ne bouge pas dans le repère fixe du labo : on le voit donc bien
## à sa place, mais sa lumière a ce retard (Q « retard de la lumière des astres »).
func retard(p: PackedFloat64Array) -> float:
	return distance(p) / 299792458.0


## Direction (longueur 1) du point p vers le Soleil, calculée en 64 bits.
func direction(p: PackedFloat64Array) -> Vector3:
	var dx := position[0] - p[0]
	var dy := position[1] - p[1]
	var dz := position[2] - p[2]
	var d := sqrt(dx * dx + dy * dy + dz * dz)
	return Vector3(dx / d, dy / d, dz / d)


## Rayon apparent du disque vu depuis p, en radians (0,2666° à 1 UA).
func rayon_angle(p: PackedFloat64Array) -> float:
	return asin(minf(RAYON / distance(p), 1.0))


## Éclairement (lux) reçu face au Soleil depuis p : il baisse comme 1/distance².
func eclairement(p: PackedFloat64Array) -> float:
	var r := UA / distance(p)
	return ECLAIREMENT_1UA * r * r


## Luminance moyenne du disque (cd/m²) : la même à toute distance (≈ 1,9 milliard).
static func luminance_moyenne() -> float:
	var s := RAYON / UA
	return ECLAIREMENT_1UA / (PI * s * s)


## Luminance au centre du disque (le bord est plus sombre).
static func luminance_centre() -> float:
	return luminance_moyenne() / (1.0 - ASSOMBRISSEMENT_BORD / 3.0)


## Part du disque du Soleil (0 à 1) visible depuis p quand une sphère (centre c, rayon r, 64 bits)
## peut le cacher. Entre 0 et 1, on est dans la pénombre. Calcul par recouvrement de deux disques.
func part_visible(p: PackedFloat64Array, c: PackedFloat64Array, r: float) -> float:
	var vx := c[0] - p[0]
	var vy := c[1] - p[1]
	var vz := c[2] - p[2]
	var dc := sqrt(vx * vx + vy * vy + vz * vz)
	if dc <= r:
		return 0.0                                   # à l'intérieur de l'astre
	if dc > distance(p):
		return 1.0                                   # l'astre est derrière le Soleil
	var vers_astre := Vector3(vx / dc, vy / dc, vz / dc)
	var ecart := vers_astre.angle_to(direction(p))   # angle entre les deux centres
	return 1.0 - recouvrement(rayon_angle(p), asin(r / dc), ecart)


## Part d'un disque de rayon a cachée par un disque de rayon b dont le centre est à e (même unité).
static func recouvrement(a: float, b: float, e: float) -> float:
	if e >= a + b:
		return 0.0
	if e <= b - a:
		return 1.0                                   # le petit disque est entièrement caché
	if e <= a - b:
		return (b * b) / (a * a)                     # le cache est entièrement devant le disque
	var a2 := a * a
	var b2 := b * b
	var u := clampf((e * e + a2 - b2) / (2.0 * e * a), -1.0, 1.0)
	var v := clampf((e * e + b2 - a2) / (2.0 * e * b), -1.0, 1.0)
	var aire := a2 * acos(u) + b2 * acos(v) \
		- 0.5 * sqrt(maxf((-e + a + b) * (e + a - b) * (e - a + b) * (e + a + b), 0.0))
	return clampf(aire / (PI * a2), 0.0, 1.0)
