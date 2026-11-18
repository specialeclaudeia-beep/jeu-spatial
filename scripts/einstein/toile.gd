extends MeshInstance3D
## Einstein B : LA « TOILE DE L'ESPACE » (touche Y).
##
## Une grille posée dans le plan de l'orbite du vaisseau, autour de l'astre principal, creusée par sa
## vraie courbure : c'est le « diagramme de plongement » de Flamm (1916). L'espace autour d'un astre
## (solution de Schwarzschild) a exactement la forme d'un entonnoir : profondeur z(R) = 2·√(r_s·(R − r_s))
## (R = distance au centre, r_s = 2·G·M/c², rayon de l'horizon d'un trou noir de même masse). Dans
## l'astre (planète, étoile), la forme d'une boule de matière de même densité partout.
## La vraie courbure est minuscule près d'une planète (quelques centaines de mètres sur des milliers de
## km) : la profondeur est donc multipliée par un nombre affiché à l'écran (« exagérée × … »), jamais
## en cachette. La grille est posée un peu sous le vaisseau (15 % de sa distance à l'astre), pour qu'on
## la voie de haut et non par la tranche.
## Couleur des lignes : de combien le temps y ralentit (bleu : presque pas, rouge : le temps s'arrête,
## à l'horizon d'un trou noir). C'est le même ralentissement que celui de l'horloge du pilote.

const C := 299792458.0
const CERCLES := 22
const RAYONS := 36
const PAS_CERCLE := 96
const PAS_RAYON := 64
const DESSOUS := 0.15

var exageration := 1.0
var _cle := PackedFloat64Array()
var _materiau: ShaderMaterial


func _init() -> void:
	name = "Toile"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_materiau = ShaderMaterial.new()
	_materiau.shader = preload("res://scripts/einstein/toile.gdshader")
	material_override = _materiau
	custom_aabb = AABB(Vector3.ONE * -1.0e12, Vector3.ONE * 2.0e12)
	visible = false


## Profondeur de plongement (m, avant exagération) à la distance R du centre d'un astre de rayon rb
## (0 : trou noir) et d'horizon rs.
static func profondeur(r_aire: float, rs: float, rb: float) -> float:
	if rb > rs and r_aire < rb:
		# dans la matière : dz/dR = √(k·R² / (1 − k·R²)), k = r_s / rb³
		var k := rs / (rb * rb * rb)
		var s1 := sqrt(maxf(1.0 - k * rb * rb, 0.0))
		var s2 := sqrt(maxf(1.0 - k * r_aire * r_aire, 0.0))
		return 2.0 * sqrt(rs * (rb - rs)) - sqrt(k) * (rb * rb - r_aire * r_aire) / (s1 + s2)
	return 2.0 * sqrt(rs * maxf(r_aire - rs, 0.0))


## Rythme du temps (comme la physique : métrique isotrope) à la distance r (isotrope) du centre.
static func rythme(r: float, gm: float, rb: float) -> float:
	var u := gm / (r * C * C)
	if rb > 0.0 and r < rb:
		u = gm * (3.0 * rb * rb - r * r) / (2.0 * rb * rb * rb * C * C)   # dans une boule de même densité
	return (1.0 - 0.5 * u) / (1.0 + 0.5 * u)


## Couleur d'un ralentissement du temps 1 − N (de 10⁻¹² à 1) : bleu → vert → jaune → rouge.
static func couleur(ralenti: float) -> Color:
	var x := clampf((log(maxf(ralenti, 1e-15)) / log(10.0) + 12.0) / 12.0, 0.0, 1.0)
	return Color.from_hsv(0.62 * (1.0 - x), 0.85, 1.0)


## centre = position du centre de l'astre vue de l'œil (repère du monde) ; vaisseau = position du
## vaisseau par rapport au centre (64 bits) ; normale = axe perpendiculaire au plan de la grille.
func mettre_a_jour(centre: Vector3, vaisseau: PackedFloat64Array, gm: float, rb: float, normale: Vector3) -> void:
	if not visible or gm <= 0.0:
		return
	var r_v := sqrt(vaisseau[0] ** 2 + vaisseau[1] ** 2 + vaisseau[2] ** 2)
	var n := normale.normalized()
	var x_axe := Vector3(float(vaisseau[0]), float(vaisseau[1]), float(vaisseau[2])) / maxf(r_v, 1.0)
	x_axe = (x_axe - n * x_axe.dot(n))
	if x_axe.length() < 1e-3:
		x_axe = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD)
	x_axe = x_axe.normalized()
	transform = Transform3D(Basis(x_axe, n, x_axe.cross(n)), centre)
	var cle := PackedFloat64Array([r_v, gm, rb, n.x, n.y, n.z])
	if _cle.size() == cle.size() and absf(r_v / _cle[0] - 1.0) < 0.005 and gm == _cle[1] and rb == _cle[2]:
		return
	_cle = cle
	_construire(r_v, gm, rb)


func _construire(r_v: float, gm: float, rb: float) -> void:
	var m := gm / (C * C)
	var rs := 2.0 * m
	var r_grille := maxf(3.0 * r_v, 4.0 * rb)
	var r_in := maxf(0.5 * m * 1.02, 0.01 * r_grille) if rb <= 0.0 else 0.0
	var aire := func(r: float) -> float: return r * (1.0 + 0.5 * m / maxf(r, 1e-9)) ** 2
	var z_v := profondeur(aire.call(r_v), rs, rb)
	var dz := profondeur(aire.call(r_grille), rs, rb) - profondeur(aire.call(maxf(r_in, 1e-3)), rs, rb)
	# exagération : le creux le plus profond fait au plus 30 % du rayon de la grille (jamais moins que × 1)
	exageration = 1.0
	if dz > 0.0 and dz < 0.3 * r_grille:
		exageration = _joli(0.3 * r_grille / dz)
	var points := PackedVector3Array()
	var couleurs := PackedColorArray()
	var point := func(r: float, a: float) -> void:
		var y := exageration * (profondeur(aire.call(r), rs, rb) - z_v) - DESSOUS * r_v
		points.append(Vector3(r * cos(a), y, r * sin(a)))
		couleurs.append(couleur(1.0 - rythme(r, gm, rb)))
	for i in CERCLES:
		var f := float(i + 1) / CERCLES
		var r := r_in + (r_grille - r_in) * f * f
		for k in PAS_CERCLE:
			point.call(r, TAU * k / PAS_CERCLE)
			point.call(r, TAU * (k + 1) / PAS_CERCLE)
	for j in RAYONS:
		var a := TAU * j / RAYONS
		for k in PAS_RAYON:
			var f0 := float(k) / PAS_RAYON
			var f1 := float(k + 1) / PAS_RAYON
			point.call(r_in + (r_grille - r_in) * f0 * f0, a)
			point.call(r_in + (r_grille - r_in) * f1 * f1, a)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = couleurs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh = am


## Arrondit à 1, 2 ou 5 × une puissance de 10 (plus facile à lire).
static func _joli(x: float) -> float:
	if x <= 1.0:
		return 1.0
	var p := pow(10.0, floor(log(x) / log(10.0)))
	var f := x / p
	return p * (5.0 if f >= 5.0 else (2.0 if f >= 2.0 else 1.0))
