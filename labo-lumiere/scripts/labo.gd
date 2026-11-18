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

const Compteur = preload("res://scripts/outils/compteur.gd")
const Soleil = preload("res://scripts/lumiere/soleil.gd")
const Oeil = preload("res://scripts/lumiere/oeil.gd")
const ShaderCiel = preload("res://scripts/lumiere/ciel.gdshader")
const ShaderAstre = preload("res://shaders/astre_essai.gdshader")
const Planete = preload("res://scripts/lumiere/planete.gd")

const RAYON_ASTRE := 600000.0            # m : la planète d'essai (niveau 0 de l'arbre ≈ 630 km)
const GRAINE := 7
const ALBEDO_ASTRE := 0.12               # boule de secours (si la partie C++ manque)
const FOND_CIEL := 2.0e-4                # cd/m², le même que dans ciel.gdshader
const DUREE_JOUR := 7200.0               # s : un jour de 2 h pour les essais (Q40)
const ALTITUDE_MIN := 1.8                # m : l'œil ne descend pas sous le sol
## Direction de la planète vers le Soleil au départ (elle tourne ensuite avec le jour).
## Le disque du Soleil est minuscule : la rétine ne s'habitue pas à lui, elle sature à cet endroit
## (éblouissement). Il ne compte donc que très peu dans l'adaptation de tout l'œil.
const PART_DISQUE_ADAPTATION := 0.03
const VERS_SOLEIL := Vector3(1.0, 0.25, 0.2)

var camera: Camera3D
var compteur: CanvasLayer
var astre: MeshInstance3D               # boule de secours
var planete: MultiMeshInstance3D         # planète en rayons (partie C++)
var avec_planete := false
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
## Mesure automatique (option « -- --mesure ») : plusieurs survols enchaînés, résultats dans
## mesures/resultats-planete-pc.md, puis Godot se ferme.
const PHASES_MESURE := [
	["Vue d'orbite (1)", 1, 6.0, false],
	["Rase-mottes en avançant (5)", 5, 12.0, true],
	["Face au Soleil (2)", 2, 4.0, false],
	["Côté nuit (3)", 3, 4.0, false],
	["Coucher de Soleil (4)", 4, 4.0, false],
	["Orbite, planète cachée (ciel seul)", -1, 4.0, false],
]
var mesure_auto := false
var _phase := -1
var _phase_t := 0.0
var _images := 0
var _sommes := PackedFloat64Array()
var _resultats: Array[String] = []


func _ready() -> void:
	_placer_soleil()

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

	planete = Planete.new()
	planete.name = "Planete"
	avec_planete = planete.preparer(RAYON_ASTRE, GRAINE)
	if avec_planete:
		add_child(planete)
	else:
		push_warning("Partie C++ du système de lumière absente : boule d'essai à la place de la planète.")
		planete.free()
		planete = null

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


## Direction vers le Soleil dans le repère de la planète, compte tenu de la rotation.
func _soleil_planete() -> Vector3:
	return VERS_SOLEIL.normalized().rotated(Vector3.UP, -angle_jour)


func _placer_soleil() -> void:
	var d := _soleil_planete()
	soleil.position = PackedFloat64Array([d.x * Soleil.UA, d.y * Soleil.UA, d.z * Soleil.UA])


## Hauteur du sol sous une direction (0 sans la partie C++).
func _sol(d: Vector3) -> float:
	if not avec_planete:
		return 0.0
	return planete.hauteur_sol(PackedFloat64Array([d.x, d.y, d.z]))


func _placer(p: Vector3, regard: Vector3) -> void:
	pos_oeil = PackedFloat64Array([p.x, p.y, p.z])
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
	if rotation_on:
		angle_jour = fmod(angle_jour + TAU * delta / DUREE_JOUR, TAU)
	_placer_soleil()
	if dir != Vector3.ZERO:
		# Vitesse proportionnelle à l'altitude : lent au ras du sol, rapide en orbite.
		var v := vitesse * maxf(altitude, 5.0) * (5.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		var pas := camera.global_transform.basis * dir.normalized() * v * delta
		pos_oeil[0] += pas.x
		pos_oeil[1] += pas.y
		pos_oeil[2] += pas.z
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
	compteur.infos = infos_planete + "Œil : pupille %.1f mm · habitué à %s cd/m² · vision de nuit %d %% · Soleil visible %d %%\n" % [
		oeil.pupille_mm, _nombre(oeil.luminance_adaptation()), roundi(oeil.nuit() * 100.0), roundi(part_visible * 100.0)] \
		+ "1-5 points de vue · R rotation · H halo %s · T adaptation au noir %s" % [
		"oui" if oeil.halo else "non", "réelle (lente)" if oeil.temps_reel else "accélérée"]


## Place le monde autour de la caméra, envoie le Soleil aux shaders et mesure la lumière vue.
func _mettre_a_jour_monde() -> void:
	camera.position = Vector3.ZERO
	var rel := Vector3(pos_astre[0] - pos_oeil[0], pos_astre[1] - pos_oeil[1], pos_astre[2] - pos_oeil[2])
	var d := rel.length()
	altitude = d - RAYON_ASTRE - _sol(-rel / maxf(d, 1.0))
	# Plan proche et plan lointain de la caméra : jusqu'aux montagnes derrière l'horizon.
	var h := 12000.0
	camera.near = clampf(altitude * 0.05, 0.05, 20000.0)
	var bas := RAYON_ASTRE - h
	camera.far = sqrt(maxf(d * d - bas * bas, 0.0)) + sqrt((RAYON_ASTRE + h) ** 2 - bas * bas) + 1000.0
	if avec_planete:
		planete.mettre_a_jour(camera, pos_oeil, PackedFloat64Array([rel.x, rel.y, rel.z]), temps, compteur.chrono)
	else:
		astre.position = rel
		astre.scale = Vector3.ONE * RAYON_ASTRE

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


## L'œil ne passe pas sous le sol.
func _garder_au_dessus_du_sol() -> void:
	var p := Vector3(pos_oeil[0] - pos_astre[0], pos_oeil[1] - pos_astre[1], pos_oeil[2] - pos_astre[2])
	var d := p.length()
	var mini := RAYON_ASTRE + _sol(p / maxf(d, 1.0)) + ALTITUDE_MIN
	if d < mini:
		var q := p / maxf(d, 1.0) * mini
		pos_oeil = PackedFloat64Array([pos_astre[0] + q.x, pos_astre[1] + q.y, pos_astre[2] + q.z])


static func _distance(m: float) -> String:
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
	if avec_planete:
		cases = planete.posemetre(camera, pos_oeil, s, e, FOND_CIEL)
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
			en_plus = Soleil.luminance_moyenne() * PI * alpha * alpha / champ * part_visible * PART_DISQUE_ADAPTATION
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
	var vue: int = PHASES_MESURE[_phase][1]
	if vue < 0:
		aller_a(1)
		if avec_planete:
			planete.visible = false
	else:
		aller_a(vue)


func _ecrire_mesure() -> void:
	var texte := "# Mesure de la planète en rayons (étape 4)\n\n"
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
