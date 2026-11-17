extends Node3D
## Scène principale du labo. Étape 3 : le vrai Soleil à 1 unité astronomique et l'œil du pilote.
## Un astre d'essai gris (comme la Lune, 1 km de rayon) sert de repère en attendant la planète en
## rayons (étape 4). Les positions sont en 64 bits ; la caméra reste au centre de l'affichage et
## le monde est dessiné autour d'elle (les objets lointains sont dessinés plus près et plus petits).
##
## Touches : Z Q S D (W A S D) pour bouger, Espace / C monter / descendre, Maj plus vite,
## clic droit maintenu + souris pour regarder, molette pour la vitesse, F3 le compteur.
## 1 départ · 2 regarder le Soleil · 3 dans l'ombre de l'astre (nuit) · 4 au bord de l'ombre (éclipse)
## H halo de l'œil oui / non · T adaptation au noir à la vraie vitesse (lente) ou accélérée

const Compteur = preload("res://scripts/outils/compteur.gd")
const Soleil = preload("res://scripts/lumiere/soleil.gd")
const Oeil = preload("res://scripts/lumiere/oeil.gd")
const ShaderCiel = preload("res://scripts/lumiere/ciel.gdshader")
const ShaderAstre = preload("res://shaders/astre_essai.gdshader")

const RAYON_ASTRE := 1000.0              # m
const ALBEDO_ASTRE := 0.12               # comme la Lune
const FOND_CIEL := 2.0e-4                # cd/m², le même que dans ciel.gdshader
const DESSIN_MAX := 20000.0              # au-delà, l'astre est dessiné plus près et plus petit
## Direction de l'astre vers le Soleil (fixe pour l'étape 3 ; la rotation viendra à l'étape 5).
const VERS_SOLEIL := Vector3(1.0, 0.25, 0.2)

var camera: Camera3D
var compteur: CanvasLayer
var astre: MeshInstance3D
var soleil = Soleil.new()
var oeil = Oeil.new()
var vitesse := 50.0                      # m/s, changée avec la molette
## Position de l'œil (caméra) et de l'astre, en mètres, 64 bits.
var pos_oeil := PackedFloat64Array([0.0, 0.0, 4000.0])
var pos_astre := PackedFloat64Array([0.0, 0.0, 0.0])
var luminance_vue := 1.0                 # dernière mesure du « posemètre » de l'œil, cd/m²
var part_visible := 1.0
var _lacet := 0.0
var _tangage := 0.0


func _ready() -> void:
	var d := VERS_SOLEIL.normalized()
	soleil.position = PackedFloat64Array([d.x * Soleil.UA, d.y * Soleil.UA, d.z * Soleil.UA])

	var ciel := Sky.new()
	var mat_ciel := ShaderMaterial.new()
	mat_ciel.shader = ShaderCiel
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

	astre = MeshInstance3D.new()
	astre.name = "Astre"
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

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.1
	camera.far = DESSIN_MAX * 2.0
	add_child(camera)
	camera.make_current()

	compteur = Compteur.new()
	compteur.name = "Compteur"
	add_child(compteur)

	aller_a(1)
	_mettre_a_jour_monde()
	oeil.equilibrer(luminance_vue)
	_mettre_a_jour_monde()


## Téléportation vers un point de vue d'essai (1 à 4). L'œil n'est PAS remis à zéro :
## on le voit s'habituer à la nouvelle lumière.
func aller_a(n: int) -> void:
	var s := VERS_SOLEIL.normalized()
	match n:
		1:
			_placer(Vector3(0, 0, 4000), Vector3(0, 0, -1))
		2:
			_placer(Vector3(0, 0, 4000), s)
		3:
			_placer(-s * 3000.0, s)
		4:
			# On cherche le décalage où la moitié du Soleil dépasse du bord de l'astre.
			var cote := s.cross(Vector3.UP).normalized()
			var bas := 0.0
			var haut := 3000.0
			for i in 40:
				var m := 0.5 * (bas + haut)
				var p := -s * 3000.0 + cote * m
				if soleil.part_visible(PackedFloat64Array([p.x, p.y, p.z]), pos_astre, RAYON_ASTRE) < 0.5:
					bas = m
				else:
					haut = m
			_placer(-s * 3000.0 + cote * bas, s)


func _placer(p: Vector3, regard: Vector3) -> void:
	pos_oeil = PackedFloat64Array([p.x, p.y, p.z])
	var b := Basis.looking_at(regard.normalized(), Vector3.UP if absf(regard.normalized().y) < 0.99 else Vector3.BACK)
	var e := b.get_euler()
	_tangage = e.x
	_lacet = e.y
	camera.rotation = Vector3(_tangage, _lacet, 0)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var m := e as InputEventMouseMotion
		_lacet -= m.relative.x * 0.004
		_tangage = clampf(_tangage - m.relative.y * 0.004, -1.55, 1.55)
		camera.rotation = Vector3(_tangage, _lacet, 0)
	elif e is InputEventMouseButton and e.is_pressed():
		var b := e as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_UP:
			vitesse = minf(vitesse * 1.25, 1.0e6)
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			vitesse = maxf(vitesse / 1.25, 0.01)
	elif e is InputEventKey and e.is_pressed() and not e.is_echo():
		var k := (e as InputEventKey).physical_keycode
		match k:
			KEY_1, KEY_KP_1: aller_a(1)
			KEY_2, KEY_KP_2: aller_a(2)
			KEY_3, KEY_KP_3: aller_a(3)
			KEY_4, KEY_KP_4: aller_a(4)
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
	if dir != Vector3.ZERO:
		var v := vitesse * (5.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		var pas := camera.global_transform.basis * dir.normalized() * v * delta
		pos_oeil[0] += pas.x
		pos_oeil[1] += pas.y
		pos_oeil[2] += pas.z
	_mettre_a_jour_monde()
	oeil.avancer(luminance_vue, delta)
	_envoyer_oeil()
	compteur.infos = "Œil : pupille %.1f mm · habitué à %s cd/m² · vision de nuit %d %% · Soleil visible %d %%\n" % [
		oeil.pupille_mm, _nombre(oeil.luminance_adaptation()), roundi(oeil.nuit() * 100.0), roundi(part_visible * 100.0)] \
		+ "1-4 points de vue · H halo %s · T adaptation au noir %s" % [
		"oui" if oeil.halo else "non", "réelle (lente)" if oeil.temps_reel else "accélérée"]


## Place le monde autour de la caméra, envoie le Soleil aux shaders et mesure la lumière vue.
func _mettre_a_jour_monde() -> void:
	camera.position = Vector3.ZERO
	var rel := Vector3(pos_astre[0] - pos_oeil[0], pos_astre[1] - pos_oeil[1], pos_astre[2] - pos_oeil[2])
	var d := rel.length()
	var k := 1.0 if d < DESSIN_MAX else DESSIN_MAX / d
	astre.position = rel * k
	astre.scale = Vector3.ONE * RAYON_ASTRE * k

	var s: Vector3 = soleil.direction(pos_oeil)
	part_visible = soleil.part_visible(pos_oeil, pos_astre, RAYON_ASTRE)
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
	luminance_vue = _poser(rel, s, e, alpha)


## Le « posemètre » de l'œil : 16 × 9 directions dans le champ de vision, plus fortes au centre
## (là où le pilote regarde). À l'étape 4, ce seront les rayons de la planète qui donneront ces mesures.
func _poser(rel: Vector3, s: Vector3, e: float, alpha: float) -> float:
	var taille := get_viewport().get_visible_rect().size
	var echantillons := PackedFloat32Array()
	var poids := PackedFloat32Array()
	var e_oeil := _eclairement_oeil(e, s)
	for j in 9:
		for i in 16:
			var u := (i + 0.5) / 16.0 * 2.0 - 1.0
			var v := (j + 0.5) / 9.0 * 2.0 - 1.0
			var dir := camera.project_ray_normal(Vector2((u + 1.0) * 0.5 * taille.x, (v + 1.0) * 0.5 * taille.y))
			var l := FOND_CIEL
			# Rayon contre l'astre (sphère).
			var b := dir.dot(rel)
			var c2 := rel.length_squared() - RAYON_ASTRE * RAYON_ASTRE
			var disc := b * b - c2
			if disc >= 0.0 and b - sqrt(disc) > 0.0:
				var n := (dir * (b - sqrt(disc)) - rel) / RAYON_ASTRE
				l = ALBEDO_ASTRE * e * maxf(n.dot(s), 0.0) / PI
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
			en_plus = Soleil.luminance_moyenne() * PI * alpha * alpha / champ * part_visible
	rs_angle_pixel(taille)
	return Oeil.luminance_scene(echantillons, poids, en_plus)


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
