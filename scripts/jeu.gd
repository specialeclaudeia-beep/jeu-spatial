extends Node3D
## Phase 1 — vol spatial réaliste.
## Un vaisseau à 5 moteurs, une planète avec sa gravité, un cockpit provisoire et des instruments.
## La physique est dans scripts/physique/vaisseau_physique.gd ; ce script ne fait que l'afficher
## et transmettre les commandes du pilote.
##
## Affichage « à origine flottante » : le vaisseau est toujours au centre de la scène et c'est
## la planète qu'on place autour de lui. Les grandes distances restent ainsi précises.

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const Commandes = preload("res://scripts/commandes.gd")
const EcranTouches = preload("res://scripts/ecran_touches.gd")

# =====================================================================
# CONSTANTES
# =====================================================================
const RAYON_PLANETE := 600000.0          # m (planète de test, plus petite que la Terre)
const GRAVITE_SURFACE := 9.81            # m/s² au sol
const ALTITUDE_DEPART := 100000.0        # m
const PAS := 1.0 / 120.0                 # s (120 calculs de physique par seconde)
const DISTANCE_RENDU_MAX := 200000.0     # au-delà, la planète est dessinée en réduction (même taille apparente)
const ALTITUDE_CALOTTE := 60000.0        # en dessous, on dessine une calotte détaillée sous le vaisseau
const DIRECTION_SOLEIL := Vector3(0.8, 0.3, 0.5)
const OEIL_PILOTE := Vector3(0.0, 0.55, -2.4)
const ACCELERATIONS_TEMPS := [1, 10, 100, 1000]

# =====================================================================
# ÉTAT
# =====================================================================
var vaisseau
var gaz := 0.0
var stabilisateur := false
var en_pause := false
var acc_temps := 1
var aide_visible := true
var ordres := Vector3.ZERO           # tangage, lacet, roulis demandés (-1..1)
var commandes                        # touches du clavier et de la manette (modifiables, sauvegardées)
var ecran_touches: Control = null    # écran de configuration, quand il est ouvert
var image_fermeture := -1

# calotte détaillée
var calotte_dir := Vector3.ZERO
var calotte_angle := 0.0

# =====================================================================
# NŒUDS
# =====================================================================
var pilote: Node3D
var camera: Camera3D
var planete: MeshInstance3D
var calotte: MeshInstance3D
var materiau_planete: ShaderMaterial
var hud: Label
var aide: Label
var message: Label
var marqueur_avant: Label
var marqueur_arriere: Label
var couche_hud: CanvasLayer

# =====================================================================
# DÉMARRAGE
# =====================================================================
func _ready() -> void:
	commandes = Commandes.new()
	commandes.charger()      # réglages de la dernière partie (sinon : disposition par défaut)
	commandes.appliquer()
	vaisseau = VaisseauPhysique.new()
	vaisseau.gm = GRAVITE_SURFACE * RAYON_PLANETE * RAYON_PLANETE
	vaisseau.rayon_planete = RAYON_PLANETE
	vaisseau.placer_en_orbite(ALTITUDE_DEPART)
	_creer_environnement()
	_creer_planete()
	_creer_pilote_et_cockpit()
	_creer_hud()


func _creer_environnement() -> void:
	var ciel := Sky.new()
	var mat_ciel := ShaderMaterial.new()
	mat_ciel.shader = load("res://shaders/etoiles.gdshader")
	ciel.sky_material = mat_ciel
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = ciel
	# aucune lumière d'ambiance : seul le Soleil éclaire (le vrai noir de l'espace)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var soleil := DirectionalLight3D.new()
	soleil.light_energy = 1.3
	add_child(soleil)
	soleil.basis = Basis.looking_at(-DIRECTION_SOLEIL.normalized(), Vector3.UP)


func _creer_planete() -> void:
	materiau_planete = ShaderMaterial.new()
	materiau_planete.shader = load("res://shaders/planete.gdshader")
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	planete = MeshInstance3D.new()
	planete.mesh = sphere
	planete.material_override = materiau_planete
	add_child(planete)
	calotte = MeshInstance3D.new()
	calotte.material_override = materiau_planete
	calotte.visible = false
	add_child(calotte)


func _boite(parent: Node3D, taille: Vector3, pos: Vector3, couleur: Color, rot_x_deg := 0.0) -> void:
	var m := BoxMesh.new()
	m.size = taille
	var mat := StandardMaterial3D.new()
	mat.albedo_color = couleur
	mat.roughness = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.x = rot_x_deg
	parent.add_child(mi)


func _creer_pilote_et_cockpit() -> void:
	pilote = Node3D.new()           # suit l'orientation du vaisseau ; centre de masse à l'origine
	add_child(pilote)
	camera = Camera3D.new()
	camera.position = OEIL_PILOTE
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 50000.0
	pilote.add_child(camera)
	camera.make_current()

	# Cockpit provisoire : tableau de bord, montants de verrière, nez du vaisseau
	var gris := Color(0.22, 0.23, 0.25)
	var fonce := Color(0.1, 0.1, 0.11)
	_boite(pilote, Vector3(1.3, 0.35, 0.5), Vector3(0, 0.05, -3.25), fonce, -20.0)       # tableau de bord
	_boite(pilote, Vector3(0.08, 0.9, 0.08), Vector3(-0.62, 0.65, -3.3), gris, -25.0)    # montant gauche
	_boite(pilote, Vector3(0.08, 0.9, 0.08), Vector3(0.62, 0.65, -3.3), gris, -25.0)     # montant droit
	_boite(pilote, Vector3(1.3, 0.06, 0.08), Vector3(0, 1.12, -3.0), gris)               # arceau du haut
	_boite(pilote, Vector3(0.7, 0.45, 3.2), Vector3(0, -0.2, -5.1), Color(0.6, 0.6, 0.62)) # nez
	_boite(pilote, Vector3(1.4, 0.2, 1.4), Vector3(0, -0.35, -2.3), fonce)               # plancher
	# petite lampe du cockpit (une vraie source de lumière, pour lire les instruments la nuit)
	var lampe := OmniLight3D.new()
	lampe.position = Vector3(0, 0.6, -2.9)
	lampe.light_color = Color(1.0, 0.75, 0.45)
	lampe.light_energy = 0.25
	lampe.omni_range = 2.0
	pilote.add_child(lampe)


func _label(taille: int, couleur := Color(0.75, 0.95, 0.8)) -> Label:
	var l := Label.new()
	var police := SystemFont.new()
	police.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	l.add_theme_font_override("font", police)
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _creer_hud() -> void:
	var couche := CanvasLayer.new()
	couche_hud = couche
	add_child(couche)
	hud = _label(15)
	hud.position = Vector2(16, 12)
	couche.add_child(hud)
	aide = _label(14, Color(0.8, 0.85, 1.0))
	aide.anchor_top = 1.0
	aide.anchor_bottom = 1.0
	aide.offset_left = 16
	aide.offset_top = -170
	couche.add_child(aide)
	_ecrire_aide()
	message = _label(28, Color(1.0, 0.45, 0.4))
	message.anchor_left = 0.5
	message.anchor_right = 0.5
	message.anchor_top = 0.3
	message.offset_left = -300
	message.offset_right = 300
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	couche.add_child(message)
	marqueur_avant = _label(22, Color(0.5, 1.0, 0.5))
	marqueur_avant.text = "(o)"
	couche.add_child(marqueur_avant)
	marqueur_arriere = _label(22, Color(1.0, 0.6, 0.4))
	marqueur_arriere.text = "(x)"
	couche.add_child(marqueur_arriere)

func _ecrire_aide() -> void:
	var c = commandes
	aide.text = (
		"%s : plus de poussée   %s : moins   %s : couper la poussée\n" % [c.resume("gaz_plus"), c.resume("gaz_moins"), c.resume("couper_gaz")]
		+ "Tangage %s      Lacet %s\n" % [_paire("tangage_haut", "tangage_bas"), _paire("lacet_gauche", "lacet_droite")]
		+ "Roulis %s\n" % _paire("roulis_gauche", "roulis_droite")
		+ "%s : stabilisateur   %s : pause   Temps : %s %s %s %s, ou %s / %s\n" % [c.resume("stabilisateur"), c.resume("pause"), c.resume("temps_x1"), c.resume("temps_x10"), c.resume("temps_x100"), c.resume("temps_x1000"), c.resume("temps_moins"), c.resume("temps_plus")]
		+ "%s : remettre en orbite   %s : recommencer   %s : tests   %s : cacher l'aide\n" % [c.resume("remettre_orbite"), c.resume("recommencer"), c.resume("tests"), c.resume("aide")]
		+ "%s : configurer les commandes (clavier et manette)" % c.resume("ecran_touches"))

## « Flèche haut / Flèche bas (manette : Stick gauche ↑ haut / Stick gauche ↓ bas) »
func _paire(a: String, b: String) -> String:
	var l: Dictionary = commandes.liaisons
	var txt := "%s / %s" % [Commandes.nom_lisible(l[a]["clavier"]), Commandes.nom_lisible(l[b]["clavier"])]
	if l[a]["manette"] != "" or l[b]["manette"] != "":
		txt += " (%s / %s)" % [Commandes.nom_lisible(l[a]["manette"]), Commandes.nom_lisible(l[b]["manette"])]
	return txt

# =====================================================================
# COMMANDES DU PILOTE
# =====================================================================
## Appuis simples (boutons, touches). On interroge Godot à chaque image : ça marche pareil
## pour une touche, un bouton de manette ou même un stick si le joueur en choisit un.
func _lire_boutons() -> void:
	if ecran_touches != null or Engine.get_process_frames() == image_fermeture:
		return
	if Input.is_action_just_pressed("ecran_touches"):
		_ouvrir_ecran_touches()
		return
	if Input.is_action_just_pressed("temps_x1"): acc_temps = ACCELERATIONS_TEMPS[0]
	if Input.is_action_just_pressed("temps_x10"): acc_temps = ACCELERATIONS_TEMPS[1]
	if Input.is_action_just_pressed("temps_x100"): acc_temps = ACCELERATIONS_TEMPS[2]
	if Input.is_action_just_pressed("temps_x1000"): acc_temps = ACCELERATIONS_TEMPS[3]
	if Input.is_action_just_pressed("temps_plus"):
		acc_temps = ACCELERATIONS_TEMPS[mini(ACCELERATIONS_TEMPS.find(acc_temps) + 1, ACCELERATIONS_TEMPS.size() - 1)]
	if Input.is_action_just_pressed("temps_moins"):
		acc_temps = ACCELERATIONS_TEMPS[maxi(ACCELERATIONS_TEMPS.find(acc_temps) - 1, 0)]
	if Input.is_action_just_pressed("couper_gaz"): gaz = 0.0
	if Input.is_action_just_pressed("stabilisateur"): stabilisateur = not stabilisateur
	if Input.is_action_just_pressed("pause"): en_pause = not en_pause
	if Input.is_action_just_pressed("aide"):
		aide_visible = not aide_visible
		aide.visible = aide_visible
	if Input.is_action_just_pressed("recommencer") or Input.is_action_just_pressed("remettre_orbite"):
		gaz = 0.0
		acc_temps = 1
		vaisseau.placer_en_orbite(ALTITUDE_DEPART)
	if Input.is_action_just_pressed("tests"):
		get_tree().change_scene_to_file("res://scenes/tests.tscn")


func _ouvrir_ecran_touches() -> void:
	ecran_touches = EcranTouches.new()
	ecran_touches.commandes = commandes
	ecran_touches.ferme.connect(_fermer_ecran_touches)
	couche_hud.add_child(ecran_touches)


func _fermer_ecran_touches() -> void:
	ecran_touches = null
	image_fermeture = Engine.get_process_frames()   # pour ne pas rouvrir l'écran avec le même appui
	_ecrire_aide()


## Lit le clavier et la manette. Sticks et gâchettes sont analogiques : à moitié = la moitié.
func _lire_ordres(delta: float) -> void:
	var t := Input.get_axis("tangage_bas", "tangage_haut")
	var l := Input.get_axis("lacet_droite", "lacet_gauche")
	var r := Input.get_axis("roulis_droite", "roulis_gauche")
	# la poussée monte ou descend d'autant plus vite qu'on appuie fort (Z / S ou gâchettes R2 / L2)
	gaz += 0.5 * delta * (Input.get_action_strength("gaz_plus") - Input.get_action_strength("gaz_moins"))
	gaz = clampf(gaz, 0.0, 1.0)
	# Stabilisateur : sur chaque axe non commandé, il allume les propulseurs qui freinent la rotation.
	# Il n'agit QUE par les propulseurs (aucune rotation imposée directement).
	if stabilisateur:
		var w: Vector3 = vaisseau.omega
		if t == 0.0: t = clampf(-w.x * 6.0, -1.0, 1.0)
		if l == 0.0: l = clampf(-w.y * 6.0, -1.0, 1.0)
		if r == 0.0: r = clampf(-w.z * 6.0, -1.0, 1.0)
	ordres = Vector3(t, l, r)

# =====================================================================
# SIMULATION
# =====================================================================
func _physics_process(delta: float) -> void:
	if en_pause or vaisseau.ecrase or ecran_touches != null:
		return
	_lire_ordres(delta)
	vaisseau.commander(gaz, ordres.x, ordres.y, ordres.z)
	if acc_temps == 1:
		vaisseau.pas(PAS)
	else:
		var n: int = mini(acc_temps, 25)
		var dt: float = PAS * acc_temps / n
		for i in n:
			vaisseau.pas(dt)

# =====================================================================
# AFFICHAGE
# =====================================================================
func _process(_delta: float) -> void:
	_lire_boutons()
	pilote.basis = Basis(vaisseau.orientation)
	_placer_planete()
	_mettre_a_jour_hud()
	_placer_marqueurs()


func _placer_planete() -> void:
	var px: float = vaisseau.px
	var py: float = vaisseau.py
	var pz: float = vaisseau.pz
	var d := sqrt(px * px + py * py + pz * pz)
	var s := minf(1.0, DISTANCE_RENDU_MAX / d)   # réduction : même taille apparente, plus près
	planete.position = Vector3(-px * s, -py * s, -pz * s)
	planete.scale = Vector3.ONE * (RAYON_PLANETE * s)
	camera.far = maxf(1000.0, (d + RAYON_PLANETE) * s * 1.05)

	var alt := d - RAYON_PLANETE
	if alt < ALTITUDE_CALOTTE:
		var dir := Vector3(px / d, py / d, pz / d)
		var angle := clampf(acos(clampf(RAYON_PLANETE / d, -1.0, 1.0)) * 1.3, 0.003, 0.6)
		var a_refaire := calotte.mesh == null
		if not a_refaire:
			a_refaire = dir.angle_to(calotte_dir) > calotte_angle * 0.15 or angle / calotte_angle > 1.4 or angle / calotte_angle < 0.7
		if a_refaire:
			_construire_calotte(dir, angle)
		calotte.visible = true
		planete.visible = false
		calotte.position = Vector3(
			(calotte_dir.x * RAYON_PLANETE - px) * s,
			(calotte_dir.y * RAYON_PLANETE - py) * s,
			(calotte_dir.z * RAYON_PLANETE - pz) * s)
		calotte.scale = Vector3.ONE * s
	else:
		calotte.visible = false
		planete.visible = true


## Morceau de sphère très détaillé sous le vaisseau (la sphère entière serait trop grossière près du sol).
func _construire_calotte(c: Vector3, angle: float) -> void:
	var n := 64
	var u := c.cross(Vector3.UP)
	if u.length() < 0.1:
		u = c.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := c.cross(u)
	var t := tan(angle)
	var sommets := PackedVector3Array()
	var normales := PackedVector3Array()
	var indices := PackedInt32Array()
	for j in n + 1:
		for i in n + 1:
			var a := (float(i) / n * 2.0 - 1.0) * t
			var b := (float(j) / n * 2.0 - 1.0) * t
			var d := (c + u * a + v * b).normalized()
			sommets.append((d - c) * RAYON_PLANETE)
			normales.append(d)
	for j in n:
		for i in n:
			var k := j * (n + 1) + i
			indices.append_array([k, k + 1, k + n + 1, k + 1, k + n + 2, k + n + 1])
	var tableaux := []
	tableaux.resize(Mesh.ARRAY_MAX)
	tableaux[Mesh.ARRAY_VERTEX] = sommets
	tableaux[Mesh.ARRAY_NORMAL] = normales
	tableaux[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tableaux)
	calotte.mesh = m
	calotte_dir = c
	calotte_angle = angle


func _distance(m: float) -> String:
	if absf(m) >= 10000.0:
		return "%.1f km" % (m / 1000.0)
	return "%.0f m" % m


func _barre(x: float) -> String:
	var n := int(round(clampf(x, 0.0, 1.0) * 10.0))
	return "#".repeat(n) + ".".repeat(10 - n)


func _mettre_a_jour_hud() -> void:
	var o: Dictionary = vaisseau.orbite()
	var orbite_txt := ""
	if vaisseau.au_sol:
		orbite_txt = "posé au sol"
	elif o["apo"] == INF:
		orbite_txt = "trajectoire d'évasion (périapside %s)" % _distance(o["peri"])
	else:
		orbite_txt = "périapside %s   apoapside %s" % [_distance(o["peri"]), _distance(o["apo"])]
	var w: Vector3 = vaisseau.omega * (180.0 / PI)
	var m: Array = vaisseau.moteurs
	var lignes := PackedStringArray()
	lignes.append("VITESSE       %.1f m/s   (verticale %+.1f   horizontale %.1f)" % [vaisseau.vitesse(), vaisseau.vitesse_verticale(), vaisseau.vitesse_horizontale()])
	lignes.append("ALTITUDE      %s" % _distance(vaisseau.altitude()))
	lignes.append("ORBITE        %s" % orbite_txt)
	lignes.append("RESSENTI      %.2f g" % (vaisseau.acceleration_ressentie.length() / VaisseauPhysique.G0))
	lignes.append("GAZ           %s %3d %%" % [_barre(gaz), int(round(gaz * 100.0))])
	lignes.append("MOTEURS       HG %s  HD %s" % [_barre(m[0]["actuel"]), _barre(m[1]["actuel"])])
	lignes.append("              BG %s  BD %s   C %s" % [_barre(m[2]["actuel"]), _barre(m[3]["actuel"]), _barre(m[4]["actuel"])])
	lignes.append("ROTATION      tangage %+.1f°/s   lacet %+.1f°/s   roulis %+.1f°/s" % [w.x, w.y, w.z])
	lignes.append("STABILISATEUR %s      TEMPS x%d%s" % ["activé" if stabilisateur else "désactivé", acc_temps, "   (PAUSE)" if en_pause else ""])
	hud.text = "\n".join(lignes)
	if vaisseau.ecrase:
		message.text = "ÉCRASÉ (impact à %.0f m/s)\nR pour recommencer" % vaisseau.vitesse_impact
	elif vaisseau.au_sol:
		message.text = "Posé (impact à %.1f m/s)" % vaisseau.vitesse_impact
	else:
		message.text = ""


## Marqueurs de direction du mouvement : (o) = où l'on va, (x) = d'où l'on vient.
func _placer_marqueurs() -> void:
	var v := Vector3(vaisseau.vx, vaisseau.vy, vaisseau.vz)
	if v.length() < 0.5:
		marqueur_avant.visible = false
		marqueur_arriere.visible = false
		return
	v = v.normalized()
	_placer_un(marqueur_avant, v)
	_placer_un(marqueur_arriere, -v)


func _placer_un(l: Label, dir: Vector3) -> void:
	var cible := camera.global_position + dir * 100.0
	if camera.is_position_behind(cible):
		l.visible = false
		return
	l.visible = true
	l.position = camera.unproject_position(cible) - l.size * 0.5
