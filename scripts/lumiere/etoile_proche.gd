extends RefCounted
## Une étoile proche, en plus du Soleil (étape 6, « deux étoiles proches ») : l'étoile compagne.
## Vraie taille, vraie distance, vraie température : sa lumière est calculée comme celle du Soleil,
## à partir de la lumière d'un corps noir (etoiles.gd). Elle éclaire la planète et la lune en même temps
## que le Soleil : les deux lumières s'additionnent en chaque point.
## Ce fichier fait partie du système : il ne dépend que de son dossier.

const Etoiles = preload("res://scripts/lumiere/etoiles.gd")
const Soleil = preload("res://scripts/lumiere/soleil.gd")

var nom := "Compagne"
var rayon := 0.70 * Soleil.RAYON       # m
var temperature := 4400.0              # K (naine orange, type K5)
## Position du centre (m, 64 bits, repère du labo).
var position := PackedFloat64Array([5.0 * Soleil.UA, 0.0, 0.0])
var allumee := true


func distance(p: PackedFloat64Array) -> float:
	var dx := position[0] - p[0]
	var dy := position[1] - p[1]
	var dz := position[2] - p[2]
	return sqrt(dx * dx + dy * dy + dz * dz)


func direction(p: PackedFloat64Array) -> Vector3:
	var d := distance(p)
	return Vector3((position[0] - p[0]) / d, (position[1] - p[1]) / d, (position[2] - p[2]) / d)


func rayon_angle(p: PackedFloat64Array) -> float:
	return asin(minf(rayon / distance(p), 1.0))


## Retard de sa lumière (s).
func retard(p: PackedFloat64Array) -> float:
	return distance(p) / Etoiles.C


## Luminance moyenne de son disque (cd/m²) : celle du Soleil × (T / T☉)⁴ × efficacité relative.
func luminance_moyenne() -> float:
	var k := pow(temperature / Etoiles.T_SOLEIL, 4.0) * Etoiles.efficacite(temperature)
	return Soleil.luminance_moyenne() * k


## Éclairement (lux) qu'elle donne face à elle, depuis p.
func eclairement(p: PackedFloat64Array) -> float:
	if not allumee:
		return 0.0
	var a := rayon_angle(p)
	return luminance_moyenne() * PI * sin(a) * sin(a)


## Couleur de sa lumière (luminance 1), dans la même échelle que Soleil.COULEUR.
func couleur() -> Color:
	var c := Etoiles.corps_noir(temperature)
	var s := Etoiles.corps_noir(Etoiles.T_SOLEIL)
	var k := Soleil.COULEUR
	var v := Vector3(c.r / s.r * k.r, c.g / s.g * k.g, c.b / s.b * k.b)
	v /= v.dot(Vector3(0.2126, 0.7152, 0.0722))
	return Color(v.x, v.y, v.z)
