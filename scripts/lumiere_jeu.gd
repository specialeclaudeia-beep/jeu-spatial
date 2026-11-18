extends Node3D
## Branchement du système de lumière dans le jeu (étape 8 du programme du système de lumière).
## Le système lui-même est dans scripts/lumiere/ (copie exacte de labo-lumiere/scripts/lumiere/).
## Ce nœud fait, dans le jeu, ce que labo.gd fait dans le labo :
## - le vrai Soleil (1 UA), l'étoile compagne, les étoiles de Yale et la Voie lactée (ciel) ;
## - la planète en rayons (partie C++), au relief réel, placée autour de l'œil en 64 bits ;
## - l'œil du pilote (pupille, adaptation, vision de nuit, halo), avec un posemètre qui voit aussi
##   le cockpit (rayons lancés sur les formes du vaisseau) ;
## - le vaisseau et le cockpit éclairés par la même lumière (scripts/lumiere/objet.gdshader), avec
##   les ombres du vaisseau sur lui-même (la seule lumière de Godot : le Soleil) ;
## - la lumière renvoyée par la planète, les lampes du vaisseau, la visière du casque.
##
## Repère : celui de la physique (centre de la planète = 0, la planète ne tourne pas : le Soleil est
## fixe dans le ciel, comme la physique du vaisseau qui ne connaît pas de rotation de la planète).
## L'affichage est centré sur l'œil : la caméra est à l'origine, tout est placé autour d'elle.
## Si la partie C++ manque, preparer() renvoie false et le jeu garde son ancien affichage.

const Soleil = preload("res://scripts/lumiere/soleil.gd")
const Oeil = preload("res://scripts/lumiere/oeil.gd")
const ShaderCiel = preload("res://scripts/lumiere/ciel.gdshader")
const Planete = preload("res://scripts/lumiere/planete.gd")
const Etoiles = preload("res://scripts/lumiere/etoiles.gd")
const EtoileProche = preload("res://scripts/lumiere/etoile_proche.gd")
const ShaderEtoiles = preload("res://scripts/lumiere/etoiles.gdshader")
const Objets = preload("res://scripts/lumiere/objets.gd")
const ChronoBoucle = preload("res://scripts/lumiere/chrono_boucle.gd")
const Reflets = preload("res://scripts/lumiere/reflets.gd")

const GRAINE := 7                         # la même planète que dans le labo
const VERS_SOLEIL := Vector3(1.0, 0.25, 0.2)
const VERS_COMPAGNE := Vector3(-0.55, 0.35, -0.75)
const DISTANCE_COMPAGNE := 5.0            # UA
const FOND_CIEL := 2.0e-4                 # cd/m², comme le labo
const PART_DISQUE_ADAPTATION := 0.03      # voir labo.gd
const ALBEDO_PLANETE := 0.12              # part moyenne de lumière renvoyée par le sol
## Distance la plus proche dessinée (profondeur logarithmique) : le cockpit est à 20 cm de l'œil.
const PRES := 0.02
## Caméra de Godot : seulement pour le vaisseau (la planète et les étoiles ne sont jamais coupées).
const CAMERA_PRES := 0.05
const CAMERA_LOIN := 5000.0
## Visière du casque : part de la lumière transmise (rouge, vert, bleu). Visière claire : polycarbonate
## (≈ 90 %) ; visière solaire : couche d'or (≈ 20 % du visible, plus de rouge que de bleu).
const VISIERES := [Vector3(1.0, 1.0, 1.0), Vector3(0.9, 0.9, 0.9), Vector3(0.32, 0.22, 0.09)]
const NOMS_VISIERES := ["sans casque", "visière claire", "visière solaire (or)"]
## Lampes du vaisseau (vraies intensités) : projecteur d'atterrissage sous le nez, lampe du cockpit.
const PROJECTEUR_INTENSITE := 60000.0     # cd (un phare d'atterrissage d'avion : 50 000 à 200 000)
const PROJECTEUR_POSITION := Vector3(0.0, -0.55, -4.6)   # repère du vaisseau (m)
const PROJECTEUR_AXE := Vector3(0.0, -0.45, -1.0)
const PROJECTEUR_COS := Vector2(0.94, 0.87)               # pleine lumière jusqu'à 20°, noir à 30°
const LAMPE_COCKPIT_INTENSITE := 4.0      # cd (petite lampe de lecture)
const LAMPE_COCKPIT_SEUIL := 30.0         # lux : en dessous, la lampe du cockpit s'allume toute seule
const LAMPE_LUMINANCE := 3000.0           # cd/m² de la petite surface de la lampe allumée
const TUYERE_LUMINANCE := 2.0e5           # cd/m² d'une tuyère à pleine poussée (gaz très chauds)

var rayon := 600000.0
var camera: Camera3D
var planete: MultiMeshInstance3D
var avec_planete := false
var soleil = Soleil.new()
var compagne = EtoileProche.new()
var oeil = Oeil.new()
var etoiles = Etoiles.new()
var noeud_etoiles: MultiMeshInstance3D
var mat_ciel: ShaderMaterial
var lumiere_soleil: DirectionalLight3D
var objets = Objets.new()
var chrono = ChronoBoucle.new()
var reflets = Reflets.new()
var temps := 0.0

## État visible (instruments, tests).
var pos_oeil := PackedFloat64Array([0.0, 0.0, 0.0])   # m, repère de la physique, 64 bits
var altitude_oeil := 0.0
var luminance_vue := 1.0
var part_visible := 1.0              # disque du Soleil visible depuis le vaisseau (planète + relief)
var ombre_relief := 1.0
var eclairement_vaisseau := 0.0      # lux du Soleil reçus par le vaisseau, face à lui
var visiere := 1                     # 0 sans casque, 1 claire, 2 solaire
var vue_interieure := true           # vue extérieure : la caméra n'est pas dans le casque (pas de visière)
var projecteur := false
var lampe_cockpit := false
var _premier := true
var _e_autre := 0.0                  # lux venus d'ailleurs que du Soleil sur le cockpit (dernier posemètre)
var _soleil_cache := false           # Soleil caché par la coque, vu de l'œil
var reflet_visiere := Vector3.ZERO   # étape 9 : voile renvoyé par la visière (cd/m²)
var ms_reflets := 0.0                # temps de calcul des reflets (ms, dernière image)


## Prépare tout. Faux si la partie C++ manque (le jeu garde alors son ancien affichage).
func preparer(p_camera: Camera3D, p_rayon: float) -> bool:
	camera = p_camera
	rayon = p_rayon
	if not Planete.cpp_disponible():
		return false
	soleil.position = _loin(VERS_SOLEIL, Soleil.UA)
	compagne.position = _loin(VERS_COMPAGNE, DISTANCE_COMPAGNE * Soleil.UA)

	var ciel := Sky.new()
	var table := Etoiles.table_corps_noir()
	mat_ciel = ShaderMaterial.new()
	mat_ciel.shader = ShaderCiel
	mat_ciel.set_shader_parameter("corps_noir", table)
	ciel.sky_material = mat_ciel
	ciel.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = ciel
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR   # l'œil fait lui-même ce travail
	var monde := WorldEnvironment.new()
	monde.name = "Monde"
	monde.environment = env
	add_child(monde)

	planete = Planete.new()
	planete.name = "Planete"
	avec_planete = planete.preparer(rayon, GRAINE)
	if not avec_planete:
		planete.free()
		planete = null
		return false
	add_child(planete)

	if etoiles.charger():
		noeud_etoiles = etoiles.creer_noeud(ShaderEtoiles, table)
		add_child(noeud_etoiles)

	# La seule lumière de Godot : le Soleil, pour les ombres du vaisseau sur lui-même ET sur le sol
	# (planete.gdshader). Son intensité ne sert pas (objet.gdshader et planete.gdshader calculent la vraie
	# lumière) ; seules sa direction et son ombre comptent. Deux zones : 0-20 m, fine, pour le cockpit ;
	# 20-200 m pour l'ombre sur le sol. Au-delà de ~170 m, l'ombre d'un fuselage de 1,6 m de large n'a
	# plus de cœur noir (le disque du Soleil, 0,53°, déborde de chaque côté) : elle s'efface doucement de
	# 160 à 200 m, à peu près comme la vraie.
	lumiere_soleil = DirectionalLight3D.new()
	lumiere_soleil.name = "OmbresSoleil"
	lumiere_soleil.light_energy = 1.0
	lumiere_soleil.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	lumiere_soleil.shadow_enabled = true
	lumiere_soleil.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	lumiere_soleil.directional_shadow_max_distance = 200.0
	lumiere_soleil.directional_shadow_split_1 = 0.1
	lumiere_soleil.directional_shadow_fade_start = 0.8
	lumiere_soleil.shadow_bias = 0.03
	lumiere_soleil.shadow_normal_bias = 1.0
	add_child(lumiere_soleil)

	reflets.preparer()

	camera.near = CAMERA_PRES
	camera.far = CAMERA_LOIN
	RenderingServer.global_shader_parameter_set("planete_rayon", rayon)
	RenderingServer.global_shader_parameter_set("planete_albedo", ALBEDO_PLANETE)
	RenderingServer.global_shader_parameter_set("affichage_pres", PRES)
	return true


static func _loin(d: Vector3, distance: float) -> PackedFloat64Array:
	var n := d.normalized()
	return PackedFloat64Array([float(n.x) * distance, float(n.y) * distance, float(n.z) * distance])


## Les matières du vaisseau (ou du cockpit) passent au système de lumière.
func ajouter_objets(racine: Node3D, reference: Node3D) -> void:
	objets.convertir(racine, reference)


## Hauteur du sol (m au-dessus du rayon) dans la direction (x, y, z) depuis le centre (64 bits).
func hauteur_sol(x: float, y: float, z: float) -> float:
	if not avec_planete:
		return 0.0
	return planete.hauteur_sol(PackedFloat64Array([x, y, z]))


## Une image. oeil64 = position de l'œil (repère de la physique, m, 64 bits) ; vitesse = du vaisseau
## (m/s) ; base = orientation du vaisseau ; oeil_local = œil dans le repère du vaisseau ; gaz = part
## de la poussée des moteurs (0 à 1, pour la lueur des tuyères) ; delta = temps réel (s).
func mettre_a_jour(delta: float, oeil64: PackedFloat64Array, vitesse: Vector3, base: Basis,
		oeil_local: Vector3, gaz := 0.0) -> void:
	temps += delta
	pos_oeil = oeil64
	var rel64 := PackedFloat64Array([-oeil64[0], -oeil64[1], -oeil64[2]])
	var d := sqrt(oeil64[0] * oeil64[0] + oeil64[1] * oeil64[1] + oeil64[2] * oeil64[2])
	altitude_oeil = d - rayon - hauteur_sol(oeil64[0], oeil64[1], oeil64[2])
	var rel := Vector3(rel64[0], rel64[1], rel64[2])

	# Profondeur logarithmique jusqu'aux montagnes derrière l'horizon (comme le labo).
	var h := 12000.0
	var bas := rayon - h
	var loin := sqrt(maxf(d * d - bas * bas, 0.0)) + sqrt((rayon + h) ** 2 - bas * bas) + 1000.0
	# Vitesse de l'œil : aberration et Doppler (invisibles aux vitesses du jeu, < 1/10 de pixel).
	var beta := vitesse / Etoiles.C
	if beta.length() < 0.1 * deg_to_rad(camera.fov) / maxf(get_viewport().get_visible_rect().size.y, 1.0):
		beta = Vector3.ZERO
	# Einstein A2 : la planète est vue là où sa lumière est partie, jusqu'à γ(1 + β) fois plus loin.
	planete.vitesse_oeil = beta
	if beta != Vector3.ZERO:
		var b := minf(beta.length(), 0.999999)
		loin *= (1.0 + b) / sqrt(1.0 - b * b)
	planete.profondeur_pres = PRES
	planete.profondeur_loin = loin
	var rs := RenderingServer
	rs.global_shader_parameter_set("affichage_loin", loin)
	rs.global_shader_parameter_set("planete_centre", rel)
	planete.mettre_a_jour(camera, oeil64, rel64, temps, chrono)

	# Le Soleil vu du vaisseau : direction, éclairement, part visible (planète + relief proche).
	var s: Vector3 = soleil.direction(oeil64)
	var e: float = soleil.eclairement(oeil64)
	var alpha: float = soleil.rayon_angle(oeil64)
	part_visible = soleil.part_visible(oeil64, PackedFloat64Array([0.0, 0.0, 0.0]), rayon)
	ombre_relief = _ombre_relief(oeil64, s, alpha) if part_visible > 0.0 else 0.0
	var vis := part_visible * ombre_relief
	eclairement_vaisseau = e * vis
	var sc: Vector3 = compagne.direction(oeil64)
	var ec: float = compagne.eclairement(oeil64)
	var vis_c := _part_sphere(oeil64, sc, compagne.rayon_angle(oeil64))
	rs.global_shader_parameter_set("soleil_direction", s)
	rs.global_shader_parameter_set("soleil_eclairement", e)
	rs.global_shader_parameter_set("soleil_luminance", Soleil.luminance_centre())
	rs.global_shader_parameter_set("soleil_rayon_angle", alpha)
	var c := Soleil.COULEUR
	rs.global_shader_parameter_set("soleil_couleur", Vector3(c.r, c.g, c.b))
	rs.global_shader_parameter_set("objets_soleil_visible", vis)
	rs.global_shader_parameter_set("objets_compagnon_visible", vis_c)
	rs.global_shader_parameter_set("compagnon_direction", sc)
	rs.global_shader_parameter_set("compagnon_eclairement", ec)
	rs.global_shader_parameter_set("compagnon_luminance", compagne.luminance_moyenne() if compagne.allumee else 0.0)
	rs.global_shader_parameter_set("compagnon_rayon_angle", compagne.rayon_angle(oeil64))
	rs.global_shader_parameter_set("compagnon_temperature", compagne.temperature)
	var cc: Color = compagne.couleur()
	rs.global_shader_parameter_set("compagnon_couleur", Vector3(cc.r, cc.g, cc.b))
	rs.global_shader_parameter_set("ciel_pole_galaxie", Etoiles.pole_galaxie())
	rs.global_shader_parameter_set("ciel_centre_galaxie", Etoiles.centre_galaxie())
	rs.global_shader_parameter_set("oeil_vitesse", beta)
	var vu: Array = Etoiles.aberration(s, beta)
	rs.global_shader_parameter_set("soleil_direction_vue", vu[0])
	if noeud_etoiles:
		var m := noeud_etoiles.material_override as ShaderMaterial
		m.set_shader_parameter("halo", 1.0 if oeil.halo else 0.0)
		m.set_shader_parameter("distance_dessin", sqrt(camera.near * camera.far))

	# La lumière de Godot suit le Soleil (seulement pour l'ombre).
	lumiere_soleil.basis = Basis.looking_at(-s, Vector3.UP if absf(s.y) < 0.99 else Vector3.RIGHT)
	# (toujours allumée : sans elle, Godot ne calcule plus la lumière des objets, même celle des lampes)

	_regler_lampes(base, oeil_local, gaz)
	var filtre: Vector3 = VISIERES[visiere_portee()]
	rs.global_shader_parameter_set("oeil_filtre", filtre)

	# L'œil : posemètre (planète, ciel, cockpit), puis adaptation.
	luminance_vue = _poser(rel, s, e, alpha, vis, ec * vis_c, sc, base, oeil_local)
	_mettre_a_jour_reflets(s, e, alpha, vis, base, oeil_local, filtre)
	if _premier:
		oeil.equilibrer(luminance_vue)
		_premier = false
	oeil.avancer(luminance_vue, delta)
	rs.global_shader_parameter_set("oeil_gain", oeil.gain())
	rs.global_shader_parameter_set("oeil_nuit", oeil.nuit())
	var b := camera.global_transform.basis
	rs.global_shader_parameter_set("oeil_droite", b.x)
	rs.global_shader_parameter_set("oeil_haut", b.y)
	rs.global_shader_parameter_set("oeil_pixel_angle", deg_to_rad(camera.fov) / maxf(get_viewport().get_visible_rect().size.y, 1.0))


## Part visible d'une étoile (direction s, rayon apparent a) derrière la planète, vue de p.
func _part_sphere(p: PackedFloat64Array, s: Vector3, a: float) -> float:
	var d := sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2])
	var vers_centre := Vector3(-p[0] / d, -p[1] / d, -p[2] / d)
	var b := asin(minf(rayon / d, 1.0))
	var ecart := atan2(vers_centre.cross(s).length(), vers_centre.dot(s))
	if ecart >= a + b:
		return 1.0
	return 1.0 - Soleil.recouvrement(a, b, ecart)


## Les montagnes et les cailloux entre le vaisseau et le Soleil : on avance vers le Soleil par pas de
## plus en plus grands (2 m à 120 km) et on regarde de combien le sol passe au-dessus de la ligne de
## visée (en angle). Même bord adouci que l'horizon des coins dans planete.gdshader.
func _ombre_relief(p: PackedFloat64Array, s: Vector3, alpha: float) -> float:
	var marge := PI
	var t := 2.0
	while t < 120000.0:
		var qx := p[0] + float(s.x) * t
		var qy := p[1] + float(s.y) * t
		var qz := p[2] + float(s.z) * t
		var dq := sqrt(qx * qx + qy * qy + qz * qz)
		var dessus := dq - rayon - hauteur_sol(qx, qy, qz)
		marge = minf(marge, atan2(dessus, t))
		if marge < -0.1:
			return 0.0
		t *= 1.6
	return clampf(marge / (2.0 * (alpha + 0.005)) + 0.5, 0.0, 1.0)


## Lampes du vaisseau : le projecteur (touche J), la lampe du cockpit (seule, quand il fait sombre),
## et la lueur des tuyères (selon la poussée).
func _regler_lampes(base: Basis, oeil_local: Vector3, gaz: float) -> void:
	var rs := RenderingServer
	# Le vaisseau est dessiné autour de l'œil : son centre est à -base × oeil_local.
	var centre := -(base * oeil_local)
	rs.global_shader_parameter_set("lampe_a_position", centre + base * PROJECTEUR_POSITION)
	rs.global_shader_parameter_set("lampe_a_direction", (base * PROJECTEUR_AXE).normalized())
	rs.global_shader_parameter_set("lampe_a_intensite", PROJECTEUR_INTENSITE if projecteur else 0.0)
	rs.global_shader_parameter_set("lampe_a_cos_bord", PROJECTEUR_COS)
	rs.global_shader_parameter_set("lampe_a_couleur", Vector3(1.0, 0.97, 0.92))
	lampe_cockpit = eclairement_vaisseau < LAMPE_COCKPIT_SEUIL
	var pos_lampe := oeil_local + Vector3(0.0, 0.3, -0.6)
	rs.global_shader_parameter_set("lampe_b_position", centre + base * pos_lampe)
	rs.global_shader_parameter_set("lampe_b_direction", base * Vector3.DOWN)
	rs.global_shader_parameter_set("lampe_b_intensite", LAMPE_COCKPIT_INTENSITE if lampe_cockpit else 0.0)
	rs.global_shader_parameter_set("lampe_b_cos_bord", Vector2(-0.2, -0.6))
	rs.global_shader_parameter_set("lampe_b_couleur", Vector3(1.0, 0.8, 0.55))
	objets.regler_emission("Lampe", LAMPE_LUMINANCE if lampe_cockpit else 0.0)
	objets.regler_emission("Tuyere", TUYERE_LUMINANCE * clampf(gaz, 0.0, 1.0))


## Le posemètre : 16 × 9 directions dans le champ de vision. Chaque case prend la lumière du cockpit
## si son rayon le touche, sinon celle de la planète et du ciel (rayons de la partie C++).
func _poser(rel: Vector3, s: Vector3, e: float, alpha: float, vis: float, ec_vis: float, sc: Vector3,
		base: Basis, oeil_local: Vector3) -> float:
	var taille := get_viewport().get_visible_rect().size
	var cases: PackedFloat32Array = planete.posemetre(camera, pos_oeil, s, e, FOND_CIEL, alpha)
	if ec_vis > 0.0:
		var en_plus: PackedFloat32Array = planete.posemetre(camera, pos_oeil, sc, ec_vis, 0.0, compagne.rayon_angle(pos_oeil))
		for k in cases.size():
			cases[k] += en_plus[k]
	var inv := base.inverse()
	var s_local := inv * s
	# Lumière moyenne venue d'ailleurs que du Soleil sur une surface du cockpit (lux).
	var dp := rel.length()
	var sb := minf(rayon / dp, 1.0)
	var cos_phase := clampf(-rel.normalized().dot(s), -1.0, 1.0)
	var a := acos(cos_phase)
	var e_planete := ALBEDO_PLANETE * e * vis * (2.0 / 3.0) * (sin(a) + (PI - a) * cos_phase) / PI * sb * sb
	var e_autre := 0.5 * (e_planete + ec_vis) + (0.5 * LAMPE_COCKPIT_INTENSITE / 0.36 if lampe_cockpit else 0.0)
	_e_autre = e_autre
	# Le Soleil est-il caché par la coque (vu de l'œil) ? Alors pas de halo ni de disque dans l'œil.
	var soleil_cache: bool = objets.nb_faces > 0 and not objets.toucher(oeil_local, s_local).is_empty()
	_soleil_cache = soleil_cache
	var e_oeil := 0.0
	if oeil.halo and not soleil_cache:
		var devant := -camera.global_transform.basis.z
		e_oeil = e * vis * Oeil.part_dans_le_champ(devant.dot(s))
	RenderingServer.global_shader_parameter_set("soleil_eclairement_oeil", e_oeil)
	var echantillons := PackedFloat32Array()
	var poids := PackedFloat32Array()
	for j in 9:
		for i in 16:
			var u := (i + 0.5) / 16.0 * 2.0 - 1.0
			var v := (j + 0.5) / 9.0 * 2.0 - 1.0
			var dir := camera.project_ray_normal(Vector2((u + 1.0) * 0.5 * taille.x, (v + 1.0) * 0.5 * taille.y))
			var l: float = cases[j * 16 + i]
			if objets.nb_faces > 0:
				var lv: float = objets.luminance_vue(oeil_local, inv * dir, s_local, e * vis, e_autre)
				if lv >= 0.0:
					l = lv
			l += Oeil.voile(e_oeil, rad_to_deg(dir.angle_to(s)))
			echantillons.append(l)
			poids.append(0.05 + exp(-(u * u + v * v) / (2.0 * 0.2 * 0.2)))   # le regard compte le plus
	var en_plus_disque := 0.0
	var devant := -camera.global_transform.basis.z
	if devant.dot(s) > 0.0 and not soleil_cache:
		var ecran := camera.unproject_position(s * 1000.0)
		if Rect2(Vector2.ZERO, taille).has_point(ecran):
			var demi_v := deg_to_rad(camera.fov) * 0.5
			var demi_h := atan(tan(demi_v) * taille.x / taille.y)
			var champ := 4.0 * asin(sin(demi_h) * sin(demi_v))
			en_plus_disque = Soleil.luminance_moyenne() * PI * alpha * alpha / champ * vis * PART_DISQUE_ADAPTATION
	# La visière filtre toute la lumière qui arrive à l'œil : il s'y habitue.
	var f: Vector3 = VISIERES[visiere_portee()]
	var t := 0.2126 * f.x + 0.7152 * f.y + 0.0722 * f.z
	return Oeil.luminance_scene(echantillons, poids, en_plus_disque) * t


## Étape 9 : les reflets. Carte du ciel (la planète vue de l'œil, tirée des rayons), sonde du cockpit
## (rayons lancés sur les formes du vaisseau, quelques cases par image) et voile de la visière.
func _mettre_a_jour_reflets(s: Vector3, e: float, alpha: float, vis: float, base: Basis, oeil_local: Vector3,
		filtre: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	Reflets.regler_base(base)
	reflets.mettre_a_jour_ciel([{"planete": planete, "oeil": pos_oeil, "soleil": s, "eclairement": e, "angle": alpha}])
	var s_local := base.inverse() * s
	reflets.mettre_a_jour_cockpit(objets, oeil_local, s_local, e * vis, _e_autre)
	# Le visage du pilote : Soleil (s'il n'est pas caché par la coque), lumière venue d'ailleurs et
	# lumière renvoyée par le cockpit, sur une demi-boule tournée vers l'avant.
	var devant := -camera.global_transform.basis.z
	var e_visage := 0.5 * _e_autre + 0.5 * PI * reflets.luminance_cockpit()
	if not _soleil_cache:
		e_visage += Reflets.eclairement_visage(devant, s, e * vis)
	reflet_visiere = Reflets.reflet_visiere(visiere_portee(), filtre, e_visage)
	RenderingServer.global_shader_parameter_set("oeil_reflet_visiere", reflet_visiere)
	# L'œil voit aussi ce voile : il s'y habitue.
	luminance_vue += 0.2126 * reflet_visiere.x + 0.7152 * reflet_visiere.y + 0.0722 * reflet_visiere.z
	ms_reflets = (Time.get_ticks_usec() - t0) / 1000.0


## Visière suivante : claire → solaire → sans casque → claire.
## La visière devant l'œil : aucune en vue extérieure (la caméra n'est pas dans le casque).
func visiere_portee() -> int:
	return visiere if vue_interieure else 0


func changer_visiere() -> void:
	visiere = [1, 2, 0][visiere]


func infos() -> String:
	return "LUMIÈRE       Soleil %s lux sur le vaisseau (%d %% visible)   œil : pupille %.1f mm, nuit %d %%\n              %s (reflet %s cd/m²)   projecteur %s   lampe cockpit %s   reflets %.1f ms" % [
		_nombre(eclairement_vaisseau), roundi(part_visible * ombre_relief * 100.0), oeil.pupille_mm,
		roundi(oeil.nuit() * 100.0), NOMS_VISIERES[visiere], _nombre(reflet_visiere.y),
		"allumé" if projecteur else "éteint", "allumée" if lampe_cockpit else "éteinte", ms_reflets]


static func _nombre(x: float) -> String:
	if x >= 1000.0:
		return "%d %03d" % [floori(x / 1000.0), roundi(fmod(x, 1000.0)) % 1000]
	if x >= 1.0:
		return "%d" % roundi(x)
	return "moins de 1" if x > 0.0 else "0"


func _exit_tree() -> void:
	objets.liberer()
