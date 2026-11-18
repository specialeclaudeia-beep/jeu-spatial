extends Node3D
## Scène principale du labo. Étape 3 : le vrai Soleil à 1 unité astronomique et l'œil du pilote.
## Étape 4 : la planète en rayons (600 km de rayon), calculée par la partie C++ (scripts/lumiere/planete.gd).
## Si la partie C++ manque, une boule grise de même taille la remplace (rien ne casse).
## Les positions sont en 64 bits ; la caméra reste au centre de l'affichage et le monde est dessiné
## autour d'elle. La planète tourne sur elle-même (un jour = 2 h, Q40) : on le voit au Soleil qui
## avance dans le ciel (l'œil tourne avec le sol, comme un vaisseau posé ou en vol stationnaire).
##
## Touches : Z Q S D (W A S D) pour bouger, Espace / C monter / descendre, Maj plus vite,
## clic droit maintenu + souris pour regarder, molette pour la vitesse, F3 le compteur.
## 1 vue d'orbite · 2 regarder le Soleil · 3 côté nuit · 4 coucher de Soleil (éclipse par la planète)
## 5 rase-mottes · H halo de l'œil oui / non · T adaptation au noir réelle ou accélérée
## R rotation de la planète oui / non
## Étape 5 : une petite lune (150 km) tourne autour de la planète (vraie gravité de Newton), sa lumière
## arrive avec retard (vitesse de la lumière), et elle fait des éclipses avec pénombre.
## 6 éclipse de Soleil vue du sol · 7 l'ombre de la lune vue d'orbite · 8 éclipse de lune
## V temps accéléré (×1, ×10, ×100, ×1000)
## Étape 6 : les étoiles (catalogue de Yale, 9 096 étoiles jusqu'à la magnitude 6,5), la Voie lactée,
## une étoile compagne (naine orange à 5 UA) qui éclaire aussi la planète, l'aberration et le Doppler.
## 9 la planète éclairée par l'étoile compagne seule · 0 ciel étoilé, côté nuit
## E étoile compagne oui / non · B essai à grande vitesse (0, 0,1 c, 0,5 c, 0,9 c, 0,99 c, droit devant)
## Étape 7 : la petite échelle, jusqu'au millimètre. L'œil descend jusqu'à 5 mm du sol ; des cailloux
## (de 1,5 m à 1 cm) et le grain du sable (jusqu'au mm) ; l'ombre du relief proche et des cailloux
## (horizon de chaque coin). Tous les calculs de position sont en 64 bits (avant : 4 cm d'erreur).
## L loupe : 3 cm au-dessus du sol, Soleil bas (ombres des cailloux) · G descente continue de
## l'orbite jusqu'à 3 cm du sol, en 40 s

const Compteur = preload("res://scripts/outils/compteur.gd")
const Soleil = preload("res://scripts/lumiere/soleil.gd")
const Oeil = preload("res://scripts/lumiere/oeil.gd")
const ShaderCiel = preload("res://scripts/lumiere/ciel.gdshader")
const ShaderAstre = preload("res://shaders/astre_essai.gdshader")
const Planete = preload("res://scripts/lumiere/planete.gd")
const Orbite = preload("res://scripts/lumiere/orbite.gd")
const ChronoBoucle = preload("res://scripts/lumiere/chrono_boucle.gd")
const Etoiles = preload("res://scripts/lumiere/etoiles.gd")
const EtoileProche = preload("res://scripts/lumiere/etoile_proche.gd")
const ShaderEtoiles = preload("res://scripts/lumiere/etoiles.gdshader")

const RAYON_ASTRE := 600000.0            # m : la planète d'essai (niveau 0 de l'arbre ≈ 630 km)
const GRAINE := 7
const ALBEDO_ASTRE := 0.12               # boule de secours (si la partie C++ manque)
const FOND_CIEL := 2.0e-4                # cd/m², le même que dans ciel.gdshader
const DUREE_JOUR := 7200.0               # s : un jour de 2 h pour les essais (Q40)
const ALTITUDE_MIN := 0.005              # m : l'œil ne descend pas sous le sol (étape 7 : 5 mm, avant 1,8 m)
## Étape 7 : descente continue (touche G), de l'orbite jusqu'à 3 cm du sol.
const DESCENTE_DEPART := 1.5e6           # m d'altitude
const DESCENTE_ARRIVEE := 0.03           # m
const DESCENTE_DUREE := 40.0             # s
const LOUPE_ALTITUDE := 0.03             # m (touche L)
const LOUPE_SOLEIL := 12.0               # degrés : Soleil bas, les cailloux font de longues ombres
## Direction de la planète vers le Soleil au départ (elle tourne ensuite avec le jour).
## Le disque du Soleil est minuscule : la rétine ne s'habitue pas à lui, elle sature à cet endroit
## (éblouissement). Il ne compte donc que très peu dans l'adaptation de tout l'œil.
const PART_DISQUE_ADAPTATION := 0.03
const VERS_SOLEIL := Vector3(1.0, 0.25, 0.2)
## La petite lune (Q42) : 150 km de rayon, à 6 000 km du centre de la planète (10 rayons).
## Vue du sol, elle paraît 6 fois plus grande que le Soleil : ses éclipses de Soleil sont totales.
const RAYON_LUNE := 150000.0
const GRAINE_LUNE := 23
const PLACES_LUNE := 512
const ORBITE_LUNE := 6.0e6
## Masse volumique de la planète (roche, comme la Lune) : donne sa masse, donc la vitesse de la lune.
const MASSE_VOLUMIQUE := 3000.0
const ACCELERATIONS: PackedFloat64Array = [1.0, 10.0, 100.0, 1000.0]
## L'étoile compagne (étape 6) : direction depuis la planète (repère fixe), à 125° du Soleil, et
## distance. 5 UA : assez loin pour que l'orbite de la planète autour du Soleil reste stable.
const VERS_COMPAGNE := Vector3(-0.55, 0.35, -0.75)
const DISTANCE_COMPAGNE := 5.0
## Vitesses de l'essai « grande vitesse » (touche B), en fraction de la vitesse de la lumière.
const VITESSES_ESSAI: PackedFloat64Array = [0.0, 0.1, 0.5, 0.9, 0.99]

var camera: Camera3D
var compteur: CanvasLayer
var astre: MeshInstance3D               # boule de secours
var planete: MultiMeshInstance3D         # planète en rayons (partie C++)
var avec_planete := false
var lune: MultiMeshInstance3D            # la petite lune en rayons (partie C++)
var orbite = Orbite.new()
var temps_astres := 0.0                  # horloge des astres (s), qui peut être accélérée (V)
var acceleration := 1.0
var pos_lune := PackedFloat64Array([ORBITE_LUNE, 0.0, 0.0])   # où l'œil VOIT la lune (repère de la planète)
var rot_lune := Basis.IDENTITY           # orientation de la lune (elle montre toujours la même face)
var retard_lune := 0.0                   # s : temps mis par la lumière de la lune pour arriver à l'œil
var oeil_lune := PackedFloat64Array([0.0, 0.0, 0.0])   # l'œil dans le repère de la lune
var chrono_planete = ChronoBoucle.new()
var chrono_lune = ChronoBoucle.new()
var rotation_on := true
var temps := 0.0                         # horloge du labo (s)
var angle_jour := 0.0                    # rad : de combien la planète a tourné
var altitude := 0.0
var soleil = Soleil.new()
var oeil = Oeil.new()
var vitesse := 0.5                       # part de l'altitude parcourue par seconde (molette)
## Position de l'œil (caméra) et de l'astre, en mètres, 64 bits.
var pos_oeil := PackedFloat64Array([0.0, 0.0, 4000.0])
var pos_astre := PackedFloat64Array([0.0, 0.0, 0.0])
var luminance_vue := 1.0                 # dernière mesure du « posemètre » de l'œil, cd/m²
var part_visible := 1.0
## Étape 6.
var etoiles = Etoiles.new()
var noeud_etoiles: MultiMeshInstance3D
var table_corps_noir: ImageTexture
var compagne = EtoileProche.new()
var mat_ciel: ShaderMaterial
var vitesse_essai := 0.0                 # fraction de c (touche B)
var direction_essai := Vector3.FORWARD   # sens de l'essai, fixé au moment de l'appui
var vitesse_oeil := Vector3.ZERO         # m/s : vitesse de l'œil (déplacements au clavier)
var beta := Vector3.ZERO                 # vitesse totale de l'œil en fraction de c (0 si effet < 1/10 pixel)
var doppler_soleil := 1.0                # facteur Doppler du Soleil vu par l'œil
## Mesure automatique (option « -- --mesure ») : plusieurs survols enchaînés, résultats dans
## mesures/resultats-planete-pc.md, puis Godot se ferme.
const PHASES_MESURE := [
	["Vue d'orbite (1)", 1, 6.0, false],
	["Rase-mottes en avançant (5)", 5, 12.0, true],
	["Face au Soleil (2)", 2, 4.0, false],
	["Côté nuit (3)", 3, 4.0, false],
	["Coucher de Soleil (4)", 4, 4.0, false],
	["Éclipse de Soleil au sol (6)", 6, 4.0, false],
	["Ombre de la lune vue d'orbite (7)", 7, 4.0, false],
	["Éclipse de lune (8)", 8, 4.0, false],
	["Orbite, planète cachée (ciel seul)", -1, 4.0, false],
	["Ciel étoilé, côté nuit (0)", 0, 4.0, false],
	["Étoile compagne seule (9)", 9, 4.0, false],
	["Grande vitesse 0,9 c (1 + B)", 1, 4.0, false, 0.9],
	["Loupe : 3 cm au-dessus du sol (L)", 10, 6.0, false],
	["Descente continue jusqu'à 3 cm (G)", 11, 41.0, false],
]
var descente_t := -1.0                   # s depuis le début de la descente (G) ; < 0 : pas de descente
var descente_lieu := Vector3.UP          # direction (repère de la planète) du lieu où l'on descend
var descente_regard := Vector3.FORWARD
var mesure_auto := false
var _phase := -1
var _phase_t := 0.0
var _images := 0
var _sommes := PackedFloat64Array()
var _resultats: Array[String] = []


func _ready() -> void:
	_placer_soleil()

	var ciel := Sky.new()
	table_corps_noir = Etoiles.table_corps_noir()
	mat_ciel = ShaderMaterial.new()
	mat_ciel.shader = ShaderCiel
	mat_ciel.set_shader_parameter("corps_noir", table_corps_noir)
	ciel.sky_material = mat_ciel
	ciel.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = ciel
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR   # l'œil fait lui-même ce travail
	var monde := WorldEnvironment.new()
	monde.environment = env
	add_child(monde)

	planete = Planete.new()
	planete.name = "Planete"
	avec_planete = planete.preparer(RAYON_ASTRE, GRAINE)
	if avec_planete:
		add_child(planete)
	else:
		push_warning("Partie C++ du système de lumière absente : boule d'essai à la place de la planète.")
		planete.free()
		planete = null

	# La lune : orbite dans le plan qui contient la direction du Soleil, pour qu'il y ait une éclipse
	# de Soleil et une éclipse de lune à chaque tour.
	var s0 := VERS_SOLEIL.normalized()
	orbite.configurer(Orbite.gm_boule(RAYON_ASTRE, MASSE_VOLUMIQUE), ORBITE_LUNE, s0, Vector3.UP.cross(s0))
	orbite.phase = 1.2
	if avec_planete:
		lune = Planete.new()
		lune.name = "Lune"
		if lune.preparer(RAYON_LUNE, GRAINE_LUNE, PLACES_LUNE):
			lune.max_par_image = 48
			lune.budget_eclairer_ms = 1.5
			add_child(lune)
		else:
			lune.free()
			lune = null

	astre = MeshInstance3D.new()
	astre.name = "Astre"
	astre.visible = not avec_planete
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	astre.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = ShaderAstre
	mat.set_shader_parameter("albedo", ALBEDO_ASTRE)
	astre.material_override = mat
	add_child(astre)

	if etoiles.charger():
		noeud_etoiles = etoiles.creer_noeud(ShaderEtoiles, table_corps_noir)
		add_child(noeud_etoiles)
	else:
		push_warning("Catalogue d'étoiles absent : ciel sans étoiles.")

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.1
	camera.far = 1.0e7
	add_child(camera)
	camera.make_current()

	compteur = Compteur.new()
	compteur.name = "Compteur"
	add_child(compteur)

	aller_a(1)
	_mettre_a_jour_monde()
	if avec_planete:
		for i in 30:   # la planète s'affine sur quelques images avant le premier affichage
			_mettre_a_jour_monde()
	oeil.equilibrer(luminance_vue)
	_mettre_a_jour_monde()
	mesure_auto = "--mesure" in OS.get_cmdline_user_args()
	if mesure_auto:
		# Sans synchronisation avec l'écran : sinon une image un peu trop lente (17 ms) attend la
		# suivante et la mesure tombe à 30 images/s, ce qui cache le vrai temps de calcul.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0


## Téléportation vers un point de vue d'essai (1 à 5). L'œil n'est PAS remis à zéro :
## on le voit s'habituer à la nouvelle lumière.
func aller_a(n: int) -> void:
	descente_t = -1.0
	var s := _soleil_planete()
	var cote := s.cross(Vector3.UP).normalized()
	var r := RAYON_ASTRE
	match n:
		1:
			_placer(cote * r * 2.2 + s * r * 0.3, -(cote * 2.2 + s * 0.3))
		2:
			_placer(s * (r + _sol(s) + 4000.0), s)
		3:
			_placer(-s * (r + _sol(-s) + 3000.0), s)
		4:
			# On cherche, à 3 km d'altitude, l'endroit où la moitié du Soleil dépasse de l'horizon.
			var bas := 0.0
			var haut := 0.3
			for i in 40:
				var m := 0.5 * (bas + haut)
				var d := (cote * cos(m) - s * sin(m)).normalized()
				var p := d * (r + 3000.0)
				if soleil.part_visible(PackedFloat64Array([p.x, p.y, p.z]), pos_astre, r) > 0.5:
					bas = m
				else:
					haut = m
			var d := (cote * cos(bas) - s * sin(bas)).normalized()
			_placer(d * (r + 3000.0), s)
		5:
			var d := (s + cote * 1.6).normalized()
			var avant := d.cross(Vector3.UP).normalized()
			_placer(d * (r + _sol(d) + 200.0), (avant - d * 0.08).normalized())
		6, 7:
			# L'ombre de la lune tombe sur un lieu où le Soleil est à 35° au-dessus de l'horizon.
			var g_fixe := _lieu_eclipse()
			var g := _vers_planete(g_fixe)
			if n == 6:
				_placer(g * (r + _sol(g) + 30.0), (s - g * 0.25).normalized())
			else:
				var e := (g + s).normalized() * r * 3.0
				_placer(e, -e)
		8:
			# La lune au bord de l'ombre de la planète : une moitié dans le noir, une bande de pénombre.
			var s0 := VERS_SOLEIL.normalized()
			var est: Vector3 = orbite.v
			var bord := r - ORBITE_LUNE * soleil.rayon_angle(PackedFloat64Array([0.0, 0.0, 0.0]))
			var m: Vector3 = -s0 * sqrt(ORBITE_LUNE * ORBITE_LUNE - bord * bord) + est * bord
			orbite.placer(temps_astres, m)
			_placer_lune()
			var c := Vector3(pos_lune[0], pos_lune[1], pos_lune[2])
			var e := c + s * 500000.0 + _vers_planete(est) * 200000.0
			_placer(e, c - e)
			_garder_au_dessus_du_sol()
		9:
			# Côté nuit pour le Soleil, mais l'étoile compagne est à 35° au-dessus de l'horizon.
			var c0 := VERS_COMPAGNE.normalized()
			var s0 := VERS_SOLEIL.normalized()
			var w := -(s0 - c0 * c0.dot(s0)).normalized()
			var g := _vers_planete(c0 * cos(deg_to_rad(55.0)) + w * sin(deg_to_rad(55.0)))
			# On regarde vers elle, 10° au-dessus de l'horizon : le sol éclairé en bas, elle en haut.
			var vers := _vers_planete(c0)
			var horiz := (vers - g * vers.dot(g)).normalized()
			_placer(g * (r + _sol(g) + 30.0), horiz * cos(deg_to_rad(10.0)) + g * sin(deg_to_rad(10.0)))
		0:
			# Ni le Soleil ni la compagne au-dessus de l'horizon : le ciel étoilé, vers le centre de la galaxie.
			var g := _vers_planete(-(VERS_SOLEIL.normalized() + VERS_COMPAGNE.normalized()).normalized())
			var vers_centre := _vers_planete(Etoiles.centre_galaxie())
			var horizontal := (vers_centre - g * vers_centre.dot(g))
			if horizontal.length() < 0.01:
				horizontal = g.cross(Vector3.RIGHT)
			horizontal = horizontal.normalized()
			var hauteur := clampf(asin(clampf(vers_centre.dot(g), -1.0, 1.0)), deg_to_rad(20.0), deg_to_rad(35.0))
			_placer(g * (r + _sol(g) + 30.0), horizontal * cos(hauteur) + g * sin(hauteur))
		10, 11:
			# Étape 7 : un lieu où le Soleil est à 12° au-dessus de l'horizon ; on regarde de côté par
			# rapport au Soleil (les ombres des cailloux s'allongent en travers de la vue), un peu vers le bas.
			var g := (s * sin(deg_to_rad(LOUPE_SOLEIL)) + cote * cos(deg_to_rad(LOUPE_SOLEIL))).normalized()
			var travers := g.cross(s).normalized()
			var vers_soleil := (s - g * s.dot(g)).normalized()
			var horiz := (travers * 0.8 - vers_soleil * 0.6).normalized()
			var bas := 25.0 if n == 10 else 30.0
			var regard := horiz * cos(deg_to_rad(bas)) - g * sin(deg_to_rad(bas))
			if n == 10:
				_placer64(g, LOUPE_ALTITUDE, regard)
			else:
				_placer64(g, DESCENTE_DEPART, regard)
				descente_lieu = g
				descente_regard = regard
				descente_t = 0.0


## Lieu (repère fixe, longueur 1) où tombe l'ombre de la lune aux points de vue 6 et 7 : à 55° du point
## sous le Soleil, en matinée. La lune est placée sur la droite qui va de ce lieu vers le Soleil.
func _lieu_eclipse() -> Vector3:
	var s0 := VERS_SOLEIL.normalized()
	# Le matin (côté où le sol tourne vers le Soleil) : après l'éclipse, il fait encore jour longtemps.
	var g: Vector3 = (s0 * cos(deg_to_rad(55.0)) - orbite.v * sin(deg_to_rad(55.0))).normalized()
	# m = R g + t s0, avec |m| = rayon de l'orbite.
	var b: float = RAYON_ASTRE * g.dot(s0)
	var t: float = -b + sqrt(b * b - RAYON_ASTRE * RAYON_ASTRE + ORBITE_LUNE * ORBITE_LUNE)
	orbite.placer(temps_astres, g * RAYON_ASTRE + s0 * t)
	_placer_lune()
	return g


## Repère fixe (qui ne tourne pas) → repère de la planète (qui tourne avec le jour).
func _vers_planete(v: Vector3) -> Vector3:
	return v.rotated(Vector3.UP, -angle_jour)


## Position et orientation de la lune telles que l'œil les VOIT (retard de la lumière compris).
func _placer_lune() -> void:
	var o := Vector3(pos_oeil[0], pos_oeil[1], pos_oeil[2]).rotated(Vector3.UP, angle_jour)
	var oeil_fixe := PackedFloat64Array([o.x, o.y, o.z])
	retard_lune = orbite.retard(temps_astres, oeil_fixe)
	var t_vu := temps_astres - retard_lune
	var p_fixe: PackedFloat64Array = orbite.position(t_vu)
	# Rotation en 64 bits (la lune est loin : une rotation en 32 bits la décalerait de plusieurs mètres).
	var ca := cos(-angle_jour)
	var sa := sin(-angle_jour)
	pos_lune = PackedFloat64Array([ca * p_fixe[0] + sa * p_fixe[2], p_fixe[1], -sa * p_fixe[0] + ca * p_fixe[2]])
	# Elle montre toujours la même face à la planète : elle tourne sur elle-même une fois par tour.
	var normale: Vector3 = orbite.u.cross(orbite.v).normalized()
	rot_lune = Basis(Vector3.UP, -angle_jour) * Basis(normale, orbite.angle(t_vu))
	var dx := pos_oeil[0] - pos_lune[0]
	var dy := pos_oeil[1] - pos_lune[1]
	var dz := pos_oeil[2] - pos_lune[2]
	oeil_lune = _vers_lune(dx, dy, dz)


## Vecteur du repère de la planète → repère de la lune (en 64 bits).
func _vers_lune(dx: float, dy: float, dz: float) -> PackedFloat64Array:
	var b := rot_lune
	return PackedFloat64Array([b.x.x * dx + b.x.y * dy + b.x.z * dz, b.y.x * dx + b.y.y * dy + b.y.z * dz,
		b.z.x * dx + b.z.y * dy + b.z.z * dz])


## Direction vers le Soleil dans le repère de la planète, compte tenu de la rotation.
func _soleil_planete() -> Vector3:
	return VERS_SOLEIL.normalized().rotated(Vector3.UP, -angle_jour)


func _placer_soleil() -> void:
	var d := _soleil_planete()
	soleil.position = PackedFloat64Array([d.x * Soleil.UA, d.y * Soleil.UA, d.z * Soleil.UA])
	var c := _vers_planete(VERS_COMPAGNE.normalized()) * (DISTANCE_COMPAGNE * Soleil.UA)
	compagne.position = PackedFloat64Array([c.x, c.y, c.z])


## Hauteur du sol sous une direction (0 sans la partie C++).
func _sol(d: Vector3) -> float:
	if not avec_planete:
		return 0.0
	return planete.hauteur_sol(PackedFloat64Array([d.x, d.y, d.z]))


## Hauteur du sol sous une direction donnée en 64 bits (la partie C++ la ramène à la longueur 1).
func _sol64(x: float, y: float, z: float) -> float:
	if not avec_planete:
		return 0.0
	return planete.hauteur_sol(PackedFloat64Array([x, y, z]))


## Étape 7 : place l'œil à une altitude donnée au-dessus du sol, dans la direction g, en 64 bits
## (en 32 bits, la position sur une planète de 600 km a 4 cm d'erreur).
func _placer64(g: Vector3, alt: float, regard: Vector3) -> void:
	var gx := float(g.x)
	var gy := float(g.y)
	var gz := float(g.z)
	var n := sqrt(gx * gx + gy * gy + gz * gz)
	var k := (RAYON_ASTRE + _sol64(gx, gy, gz) + alt) / n
	pos_oeil = PackedFloat64Array([pos_astre[0] + gx * k, pos_astre[1] + gy * k, pos_astre[2] + gz * k])
	_orienter(regard)


func _placer(p: Vector3, regard: Vector3) -> void:
	pos_oeil = PackedFloat64Array([p.x, p.y, p.z])
	_orienter(regard)


func _orienter(regard: Vector3) -> void:
	var haut := _verticale()
	var f := regard.normalized()
	var aide := haut if absf(f.dot(haut)) < 0.99 else haut.cross(Vector3.RIGHT).normalized()
	camera.basis = Basis.looking_at(f, aide)
	_niveler()


## Verticale du lieu : du centre de la planète vers l'œil.
func _verticale() -> Vector3:
	var v := Vector3(pos_oeil[0] - pos_astre[0], pos_oeil[1] - pos_astre[1], pos_oeil[2] - pos_astre[2])
	return v.normalized() if v.length() > 1.0 else Vector3.UP


## Garde l'horizon droit : la tête ne penche ni à gauche ni à droite par rapport à la verticale du lieu.
func _niveler() -> void:
	var haut := _verticale()
	var f := -camera.basis.z
	if absf(f.dot(haut)) > 0.995:
		return
	var droite := f.cross(haut).normalized()
	camera.basis = Basis(droite, droite.cross(f).normalized(), -f)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var m := e as InputEventMouseMotion
		# Tourner autour de la verticale du lieu, puis lever / baisser les yeux.
		var b := Basis(_verticale(), -m.relative.x * 0.004) * camera.basis
		var nb := b * Basis(Vector3.RIGHT, -m.relative.y * 0.004)
		if absf((-nb.z).dot(_verticale())) < 0.995:
			b = nb
		camera.basis = b.orthonormalized()
		_niveler()
	elif e is InputEventMouseButton and e.is_pressed():
		var b := e as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_UP:
			vitesse = minf(vitesse * 1.25, 20.0)
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			vitesse = maxf(vitesse / 1.25, 0.005)
	elif e is InputEventKey and e.is_pressed() and not e.is_echo():
		var k := (e as InputEventKey).physical_keycode
		match k:
			KEY_1, KEY_KP_1: aller_a(1)
			KEY_2, KEY_KP_2: aller_a(2)
			KEY_3, KEY_KP_3: aller_a(3)
			KEY_4, KEY_KP_4: aller_a(4)
			KEY_5, KEY_KP_5: aller_a(5)
			KEY_6, KEY_KP_6: aller_a(6)
			KEY_7, KEY_KP_7: aller_a(7)
			KEY_8, KEY_KP_8: aller_a(8)
			KEY_9, KEY_KP_9: aller_a(9)
			KEY_0, KEY_KP_0: aller_a(0)
			KEY_L: aller_a(10)
			KEY_G: aller_a(11)
			KEY_E: compagne.allumee = not compagne.allumee
			KEY_B: changer_vitesse_essai()
			KEY_V:
				var i := ACCELERATIONS.find(acceleration)
				acceleration = ACCELERATIONS[(i + 1) % ACCELERATIONS.size()]
			KEY_R: rotation_on = not rotation_on
			KEY_H: oeil.halo = not oeil.halo
			KEY_T: oeil.temps_reel = not oeil.temps_reel


func _process(delta: float) -> void:
	# Touches physiques : la même position de touche sur un clavier français ou anglais.
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S): dir.z += 1
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1
	if Input.is_physical_key_pressed(KEY_SPACE): dir.y += 1
	if Input.is_physical_key_pressed(KEY_C): dir.y -= 1
	if mesure_auto:
		_avancer_mesure(delta)
		if _phase >= 0 and _phase < PHASES_MESURE.size() and PHASES_MESURE[_phase][3]:
			dir.z -= 1
	temps += delta
	temps_astres += delta * acceleration
	if rotation_on:
		angle_jour = fmod(angle_jour + TAU * delta * acceleration / DUREE_JOUR, TAU)
	_placer_soleil()
	if descente_t >= 0.0:
		_avancer_descente(delta)
		dir = Vector3.ZERO
	if dir != Vector3.ZERO:
		# Vitesse proportionnelle à l'altitude : lent au ras du sol, rapide en orbite (étape 7 : jusqu'à
		# quelques millimètres par seconde au ras du sol).
		var v := vitesse * maxf(altitude, 0.005) * (5.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		var pas := camera.global_transform.basis * dir.normalized() * v * delta
		pos_oeil[0] += pas.x
		pos_oeil[1] += pas.y
		pos_oeil[2] += pas.z
		vitesse_oeil = pas / maxf(delta, 1e-6)
	else:
		vitesse_oeil = Vector3.ZERO
	_garder_au_dessus_du_sol()
	_niveler()
	_mettre_a_jour_monde()
	oeil.avancer(luminance_vue, delta)
	_envoyer_oeil()
	var infos_planete := ""
	if avec_planete:
		infos_planete = "Planète : %d morceaux, %d rayons, niveau %d · altitude %s · jour %s\n" % [
			planete.arbre.nb_morceaux(), planete.arbre.nb_rayons(), planete.arbre.niveau_max_affiche(),
			_distance(altitude), "%d %%" % roundi(angle_jour / TAU * 100.0) if rotation_on else "arrêté (R)"]
	else:
		infos_planete = "Planète : partie C++ absente, boule d'essai\n"
	if lune:
		infos_planete += "Lune : à %s · sa lumière met %s à arriver (celle du Soleil %s) · temps ×%d (V)\n" % [
			_distance(_distance_lune()), _duree(retard_lune), _duree(soleil.retard(pos_oeil)), roundi(acceleration)]
	infos_planete += "Étoiles : %d (Yale) · compagne %s · vitesse de l'œil %s%s\n" % [etoiles.nombre,
		"%d lux, sa lumière met %s (E)" % [roundi(compagne.eclairement(pos_oeil)), _duree(compagne.retard(pos_oeil))] if compagne.allumee else "éteinte (E)",
		_vitesse(beta.length() * Etoiles.C if beta != Vector3.ZERO else vitesse_oeil.length()),
		" · Doppler du Soleil ×%.2f" % doppler_soleil if beta != Vector3.ZERO else ""]
	compteur.infos = infos_planete + "Œil : pupille %.1f mm · habitué à %s cd/m² · vision de nuit %d %% · Soleil visible %d %%\n" % [
		oeil.pupille_mm, _nombre(oeil.luminance_adaptation()), roundi(oeil.nuit() * 100.0), roundi(part_visible * 100.0)] \
		+ "0-9 points de vue · L loupe · G descente · B grande vitesse · R rotation · H halo %s · T adaptation au noir %s" % [
		"oui" if oeil.halo else "non", "réelle (lente)" if oeil.temps_reel else "accélérée"]


## Étape 7 : descente continue (G). L'altitude baisse en suivant une loi exponentielle (le même temps
## pour passer de 1 000 km à 100 km que de 10 cm à 1 cm) : on doit voir les triangles s'affiner sans
## à-coup, de l'orbite jusqu'aux grains de sable.
func _avancer_descente(delta: float) -> void:
	descente_t += delta
	var f := clampf(descente_t / DESCENTE_DUREE, 0.0, 1.0)
	var alt := DESCENTE_DEPART * pow(DESCENTE_ARRIVEE / DESCENTE_DEPART, f)
	var avant := PackedFloat64Array(pos_oeil)
	_placer64(descente_lieu, alt, descente_regard)
	vitesse_oeil = Vector3(pos_oeil[0] - avant[0], pos_oeil[1] - avant[1], pos_oeil[2] - avant[2]) / maxf(delta, 1e-6)
	if f >= 1.0:
		descente_t = -1.0


## Place le monde autour de la caméra, envoie le Soleil aux shaders et mesure la lumière vue.
func _mettre_a_jour_monde() -> void:
	camera.position = Vector3.ZERO
	_placer_lune()
	var rel := Vector3(pos_astre[0] - pos_oeil[0], pos_astre[1] - pos_oeil[1], pos_astre[2] - pos_oeil[2])
	# Étape 7 : le centre de la planète vu de l'œil, en 64 bits (en 32 bits : 4 cm d'erreur à 600 km,
	# les morceaux de quelques millimètres tremblaient et l'altitude était fausse au ras du sol).
	var rel64 := PackedFloat64Array([pos_astre[0] - pos_oeil[0], pos_astre[1] - pos_oeil[1], pos_astre[2] - pos_oeil[2]])
	var d := sqrt(rel64[0] * rel64[0] + rel64[1] * rel64[1] + rel64[2] * rel64[2])
	altitude = d - RAYON_ASTRE - _sol64(-rel64[0], -rel64[1], -rel64[2])
	var rel_lune := _rel_lune()
	if lune:
		altitude = minf(altitude, _altitude_lune())
	# Plan proche et plan lointain de la caméra : jusqu'aux montagnes derrière l'horizon (et la lune).
	var h := 12000.0
	var bas := RAYON_ASTRE - h
	camera.far = sqrt(maxf(d * d - bas * bas, 0.0)) + sqrt((RAYON_ASTRE + h) ** 2 - bas * bas) + 1000.0
	if lune:
		camera.far = maxf(camera.far, rel_lune.length() + RAYON_LUNE * 1.1)
	# Étape 7 : le sol est dessiné jusqu'à 0,2 mm de l'œil (profondeur logarithmique des astres), mais la
	# caméra de Godot ne supporte pas un écart si grand entre ses plans proche et lointain (plus rien ne
	# s'affichait sous 3 m d'altitude) : son plan proche reste à 1/100 000 du plan lointain, et les
	# astres ne sont pas coupés par lui (planete.gdshader).
	var pres := clampf(altitude * 0.05, 0.0002, 20000.0)
	camera.near = maxf(pres, camera.far * 1.0e-5)
	if avec_planete:
		planete.profondeur_pres = pres
		if lune:
			lune.profondeur_pres = pres
	if avec_planete:
		chrono_planete.nb_rayons = 0
		if lune:
			planete.occulteur = PackedFloat64Array([pos_lune[0], pos_lune[1], pos_lune[2], RAYON_LUNE])
		planete.mettre_a_jour(camera, pos_oeil, rel64, temps, chrono_planete,
			Vector4(rel_lune.x, rel_lune.y, rel_lune.z, RAYON_LUNE if lune else 0.0))
		if lune:
			lune.rotation_astre = rot_lune
			var c := _vers_lune(pos_astre[0] - pos_lune[0], pos_astre[1] - pos_lune[1], pos_astre[2] - pos_lune[2])
			lune.occulteur = PackedFloat64Array([c[0], c[1], c[2], RAYON_ASTRE])
			lune.mettre_a_jour(camera, oeil_lune, PackedFloat64Array([rel_lune.x, rel_lune.y, rel_lune.z]), temps,
				chrono_lune, Vector4(rel.x, rel.y, rel.z, RAYON_ASTRE))
		# Le compteur montre la somme des deux astres.
		for i in 3:
			compteur.chrono.enregistrer(i, chrono_planete.derniers_ms[i] + (chrono_lune.derniers_ms[i] if lune else 0.0))
		compteur.chrono.nb_rayons = chrono_planete.nb_rayons + (chrono_lune.nb_rayons if lune else 0)
	else:
		astre.position = rel
		astre.scale = Vector3.ONE * RAYON_ASTRE

	var s: Vector3 = soleil.direction(pos_oeil)
	part_visible = soleil.part_visible(pos_oeil, pos_astre, RAYON_ASTRE)
	if lune:
		# Deux astres peuvent cacher le Soleil : on retire la part cachée par chacun.
		part_visible = clampf(part_visible + soleil.part_visible(pos_oeil, pos_lune, RAYON_LUNE) - 1.0, 0.0, 1.0)
	var e: float = soleil.eclairement(pos_oeil)
	var alpha: float = soleil.rayon_angle(pos_oeil)
	var rs := RenderingServer
	rs.global_shader_parameter_set("soleil_direction", s)
	rs.global_shader_parameter_set("soleil_eclairement", e)
	rs.global_shader_parameter_set("soleil_luminance", Soleil.luminance_centre())
	rs.global_shader_parameter_set("soleil_rayon_angle", alpha)
	rs.global_shader_parameter_set("soleil_eclairement_oeil", _eclairement_oeil(e, s))
	var c := Soleil.COULEUR
	rs.global_shader_parameter_set("soleil_couleur", Vector3(c.r, c.g, c.b))
	_mettre_a_jour_etoiles(s)
	luminance_vue = _poser(rel, s, e, alpha)


## Étape 6 : le ciel tourne avec le jour, l'étoile compagne, et la vitesse de l'œil (aberration, Doppler).
func _mettre_a_jour_etoiles(s: Vector3) -> void:
	var rs := RenderingServer
	var rot := Basis(Vector3.UP, -angle_jour)
	if noeud_etoiles:
		noeud_etoiles.basis = rot
		var m := noeud_etoiles.material_override as ShaderMaterial
		m.set_shader_parameter("halo", 1.0 if oeil.halo else 0.0)
		m.set_shader_parameter("distance_dessin", sqrt(camera.near * camera.far))
	rs.global_shader_parameter_set("ciel_pole_galaxie", rot * Etoiles.pole_galaxie())
	rs.global_shader_parameter_set("ciel_centre_galaxie", rot * Etoiles.centre_galaxie())
	# La compagne : deux lumières s'additionnent sur la planète et la lune.
	var ec: float = compagne.eclairement(pos_oeil)
	rs.global_shader_parameter_set("compagnon_direction", compagne.direction(pos_oeil))
	rs.global_shader_parameter_set("compagnon_eclairement", ec)
	rs.global_shader_parameter_set("compagnon_luminance", compagne.luminance_moyenne() if compagne.allumee else 0.0)
	rs.global_shader_parameter_set("compagnon_rayon_angle", compagne.rayon_angle(pos_oeil))
	rs.global_shader_parameter_set("compagnon_temperature", compagne.temperature)
	var cc: Color = compagne.couleur()
	rs.global_shader_parameter_set("compagnon_couleur", Vector3(cc.r, cc.g, cc.b))
	# Vitesse de l'œil : ses déplacements + l'essai à grande vitesse (B). Un effet n'est calculé que
	# s'il dépasse 1/10 de pixel (l'aberration penche les directions d'environ v/c radians).
	beta = vitesse_oeil / Etoiles.C + direction_essai * vitesse_essai
	if beta.length() < 0.1 * deg_to_rad(camera.fov) / maxf(get_viewport().get_visible_rect().size.y, 1.0):
		beta = Vector3.ZERO
	if beta.length() > 0.999999:
		beta = beta.normalized() * 0.999999
	rs.global_shader_parameter_set("oeil_vitesse", beta)
	var vu: Array = Etoiles.aberration(s, beta)
	doppler_soleil = vu[1]
	rs.global_shader_parameter_set("soleil_direction_vue", vu[0])


## Essai « grande vitesse » (touche B) : vitesse suivante, droit devant (là où l'on regarde).
func changer_vitesse_essai() -> void:
	var i := VITESSES_ESSAI.find(vitesse_essai)
	vitesse_essai = VITESSES_ESSAI[(i + 1) % VITESSES_ESSAI.size()]
	direction_essai = -camera.global_transform.basis.z


static func _vitesse(v: float) -> String:
	if v >= 0.001 * Etoiles.C:
		return "%.3f c" % (v / Etoiles.C)
	if v >= 1000.0:
		return "%.1f km/s" % (v / 1000.0)
	return "%d m/s" % roundi(v)


## La lune par rapport à l'œil, dans le repère d'affichage.
func _rel_lune() -> Vector3:
	return Vector3(pos_lune[0] - pos_oeil[0], pos_lune[1] - pos_oeil[1], pos_lune[2] - pos_oeil[2])


func _distance_lune() -> float:
	return _rel_lune().length()


## Altitude de l'œil au-dessus du sol de la lune.
func _altitude_lune() -> float:
	var d := sqrt(oeil_lune[0] * oeil_lune[0] + oeil_lune[1] * oeil_lune[1] + oeil_lune[2] * oeil_lune[2])
	return d - RAYON_LUNE - lune.hauteur_sol(PackedFloat64Array([oeil_lune[0] / d, oeil_lune[1] / d, oeil_lune[2] / d]))


static func _duree(s: float) -> String:
	if s >= 60.0:
		return "%d min %02d s" % [floori(s / 60.0), roundi(fmod(s, 60.0))]
	if s >= 1.0:
		return "%.1f s" % s
	return "%.1f ms" % (s * 1000.0)


## L'œil ne passe pas sous le sol.
func _garder_au_dessus_du_sol() -> void:
	# En 64 bits (étape 7) : l'œil peut descendre à 5 mm du sol.
	var px := pos_oeil[0] - pos_astre[0]
	var py := pos_oeil[1] - pos_astre[1]
	var pz := pos_oeil[2] - pos_astre[2]
	var d := sqrt(px * px + py * py + pz * pz)
	var mini := RAYON_ASTRE + _sol64(px, py, pz) + ALTITUDE_MIN
	if d < mini:
		var k := mini / maxf(d, 1.0)
		pos_oeil = PackedFloat64Array([pos_astre[0] + px * k, pos_astre[1] + py * k, pos_astre[2] + pz * k])
	if lune:
		_placer_lune()
		var alt := _altitude_lune()
		if alt < ALTITUDE_MIN:
			var dl := sqrt(oeil_lune[0] ** 2 + oeil_lune[1] ** 2 + oeil_lune[2] ** 2)
			var k := (dl + ALTITUDE_MIN - alt) / dl
			var v := Vector3(pos_oeil[0] - pos_lune[0], pos_oeil[1] - pos_lune[1], pos_oeil[2] - pos_lune[2]) * (k - 1.0)
			pos_oeil = PackedFloat64Array([pos_oeil[0] + v.x, pos_oeil[1] + v.y, pos_oeil[2] + v.z])
			_placer_lune()


static func _distance(m: float) -> String:
	if m < 0.01:
		return "%.1f mm" % (m * 1000.0)
	if m < 1.0:
		return "%.1f cm" % (m * 100.0)
	if m >= 10000.0:
		return "%d km" % roundi(m / 1000.0)
	if m >= 1000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d m" % roundi(m)


## Le « posemètre » de l'œil : 16 × 9 directions dans le champ de vision, plus fortes au centre
## (là où le pilote regarde). Depuis l'étape 4, ce sont les rayons de la planète qui donnent la
## lumière de chaque case (calculée par la partie C++ pendant qu'elle les parcourt).
func _poser(rel: Vector3, s: Vector3, e: float, alpha: float) -> float:
	var taille := get_viewport().get_visible_rect().size
	var echantillons := PackedFloat32Array()
	var poids := PackedFloat32Array()
	var e_oeil := _eclairement_oeil(e, s)
	var cases := PackedFloat32Array()
	var ec: float = compagne.eclairement(pos_oeil)
	var sc: Vector3 = compagne.direction(pos_oeil)
	var ac: float = compagne.rayon_angle(pos_oeil)
	if avec_planete:
		cases = _posemetre_astre(planete, pos_oeil, s, e, alpha, ec, sc, ac)
		if lune:
			# Deux astres : celui de devant cache celui de derrière, case par case.
			var cov_p: PackedFloat32Array = planete.couverture()
			var cases_l: PackedFloat32Array = _posemetre_astre(lune, oeil_lune, s, e, alpha, ec, sc, ac)
			var cov_l: PackedFloat32Array = lune.couverture()
			var lune_devant := _distance_lune() < rel.length()
			for k in cases.size():
				if lune_devant:
					cases[k] = cases_l[k] - FOND_CIEL * (1.0 - cov_l[k]) + (1.0 - cov_l[k]) * cases[k]
				else:
					cases[k] = cases[k] - FOND_CIEL * (1.0 - cov_p[k]) + (1.0 - cov_p[k]) * cases_l[k]
	for j in 9:
		for i in 16:
			var u := (i + 0.5) / 16.0 * 2.0 - 1.0
			var v := (j + 0.5) / 9.0 * 2.0 - 1.0
			var dir := camera.project_ray_normal(Vector2((u + 1.0) * 0.5 * taille.x, (v + 1.0) * 0.5 * taille.y))
			var l := FOND_CIEL
			if avec_planete:
				l = cases[j * 16 + i]
			else:
				# Rayon contre la boule (sphère).
				var b := dir.dot(rel)
				var c2 := rel.length_squared() - RAYON_ASTRE * RAYON_ASTRE
				var disc := b * b - c2
				if disc >= 0.0 and b - sqrt(disc) > 0.0:
					var n := (dir * (b - sqrt(disc)) - rel) / RAYON_ASTRE
					l = ALBEDO_ASTRE * (e * maxf(n.dot(s), 0.0) + ec * maxf(n.dot(sc), 0.0)) / PI
			l += Oeil.voile(e_oeil, rad_to_deg(dir.angle_to(s)))
			echantillons.append(l)
			poids.append(0.05 + exp(-(u * u + v * v) / (2.0 * 0.2 * 0.2)))   # le regard compte le plus
	# Le disque du Soleil lui-même, s'il est dans le champ : une toute petite source très vive.
	var en_plus := 0.0
	var devant := -camera.global_transform.basis.z
	if devant.dot(s) > 0.0:
		var ecran := camera.unproject_position(s * 1000.0)
		if Rect2(Vector2.ZERO, taille).has_point(ecran):
			var demi_v := deg_to_rad(camera.fov) * 0.5
			var demi_h := atan(tan(demi_v) * taille.x / taille.y)
			var champ := 4.0 * asin(sin(demi_h) * sin(demi_v))
			en_plus = Soleil.luminance_moyenne() * PI * alpha * alpha / champ * part_visible * PART_DISQUE_ADAPTATION
	rs_angle_pixel(taille)
	return Oeil.luminance_scene(echantillons, poids, en_plus)


## Posemètre d'un astre éclairé par les deux étoiles : les deux lumières s'additionnent (le fond du ciel
## n'est compté qu'une fois). La partie C++ ne connaît qu'une étoile à la fois : on l'appelle deux fois.
func _posemetre_astre(a: MultiMeshInstance3D, oeil_astre: PackedFloat64Array, s: Vector3, e: float,
		alpha: float, ec: float, sc: Vector3, ac: float) -> PackedFloat32Array:
	var cases: PackedFloat32Array = a.posemetre(camera, oeil_astre, s, e, FOND_CIEL, alpha)
	if ec > 0.0:
		var en_plus: PackedFloat32Array = a.posemetre(camera, oeil_astre, sc, ec, 0.0, ac)
		for k in cases.size():
			cases[k] += en_plus[k]
	return cases


## Lux du Soleil qui entrent vraiment dans l'œil : la part visible du disque, et moins de lumière
## quand le Soleil est sur le côté (il sort du champ de l'œil vers 100° du regard).
func _eclairement_oeil(e: float, s: Vector3) -> float:
	if not oeil.halo:
		return 0.0
	var devant := -camera.global_transform.basis.z
	return e * part_visible * Oeil.part_dans_le_champ(devant.dot(s))


func rs_angle_pixel(taille: Vector2) -> void:
	RenderingServer.global_shader_parameter_set("oeil_pixel_angle", deg_to_rad(camera.fov) / taille.y)


func _envoyer_oeil() -> void:
	var rs := RenderingServer
	rs.global_shader_parameter_set("oeil_gain", oeil.gain())
	rs.global_shader_parameter_set("oeil_nuit", oeil.nuit())
	var b := camera.global_transform.basis
	rs.global_shader_parameter_set("oeil_droite", b.x)
	rs.global_shader_parameter_set("oeil_haut", b.y)


static func _nombre(x: float) -> String:
	if x >= 100.0:
		return "%d" % roundi(x)
	if x >= 1.0:
		return "%.1f" % x
	return "%.4f" % x


func _avancer_mesure(delta: float) -> void:
	if _phase >= 0:
		_phase_t += delta
		if _phase_t > 1.0:     # la première seconde de chaque phase ne compte pas (téléportation)
			_images += 1
			_sommes[0] += delta * 1000.0
			for i in 4:
				_sommes[1 + i] += compteur.chrono.derniers_ms[i]
			_sommes[5] += compteur.chrono.nb_rayons
			_sommes[6] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			var vp := get_viewport().get_viewport_rid()
			_sommes[7] += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			_sommes[8] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		if _phase_t < PHASES_MESURE[_phase][2]:
			return
		var n := maxf(_images, 1)
		_resultats.append("| %s | %.0f | %.1f | %.2f | %.2f | %.2f | %.2f | %d | %.2f | %.2f | %.2f |" % [
			PHASES_MESURE[_phase][0], 1000.0 / (_sommes[0] / n), _sommes[0] / n, _sommes[1] / n, _sommes[2] / n,
			_sommes[3] / n, _sommes[4] / n, roundi(_sommes[5] / n), _sommes[6] / n, _sommes[7] / n, _sommes[8] / n])
	_phase += 1
	if _phase >= PHASES_MESURE.size():
		_ecrire_mesure()
		mesure_auto = false
		get_tree().quit()
		return
	_phase_t = 0.0
	_images = 0
	_sommes = PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
	vitesse = 0.5
	vitesse_essai = 0.0
	var vue: int = PHASES_MESURE[_phase][1]
	if vue < 0:
		aller_a(1)
		if avec_planete:
			planete.visible = false
		if lune:
			lune.visible = false
	else:
		if avec_planete:
			planete.visible = true
		if lune:
			lune.visible = true
		aller_a(vue)
	if PHASES_MESURE[_phase].size() > 4:
		vitesse_essai = PHASES_MESURE[_phase][4]
		direction_essai = -camera.global_transform.basis.z


func _ecrire_mesure() -> void:
	var texte := "# Mesure de la planète en rayons, de sa lune et des étoiles (étapes 4 à 7)\n\n"
	texte += "Date : %s · %s · %s\n\n" % [Time.get_datetime_string_from_system(), OS.get_processor_name(),
		RenderingServer.get_video_adapter_name()]
	texte += "Sans synchronisation avec l'écran (vsync coupée). Dessiner = processeur + carte graphique (Godot) ;\n"
	texte += "Processus = tout le GDScript de l'image (choisir/éclairer compris).\n\n"
	texte += "| Essai | Images/s | Image (ms) | Choisir | Éclairer | Envoyer | Dessiner | Rayons | Processus | Dessin processeur | Dessin carte graphique |\n"
	texte += "|---|---|---|---|---|---|---|---|---|---|---|\n"
	texte += "\n".join(_resultats) + "\n"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://mesures"))
	var f := FileAccess.open("res://mesures/resultats-planete-pc.md", FileAccess.WRITE)
	if f:
		f.store_string(texte)
		f.close()
	print(texte)
