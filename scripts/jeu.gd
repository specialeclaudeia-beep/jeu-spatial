extends Node3D
## Phase 1 — vol spatial réaliste.
## Un vaisseau à 5 moteurs (modèle 3D v12), une planète avec sa gravité, le cockpit et des instruments.
## La physique est dans scripts/physique/vaisseau_physique.gd ; ce script ne fait que l'afficher
## et transmettre les commandes du pilote.
##
## Affichage « à origine flottante » : le vaisseau est toujours au centre de la scène et c'est
## la planète qu'on place autour de lui. Les grandes distances restent ainsi précises.

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const Commandes = preload("res://scripts/commandes.gd")
const EcranTouches = preload("res://scripts/ecran_touches.gd")
const LumiereJeu = preload("res://scripts/lumiere_jeu.gd")

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
const MODELE_EXTERIEUR := "res://modeles/vaisseau/vaisseau_exterieur.glb"
const MODELE_COCKPIT := "res://modeles/vaisseau/cockpit.glb"
const OEIL_PILOTE_DEFAUT := Vector3(0.0, 0.58, 0.38)   # remplacé par le point Oeil_pilote du modèle s'il existe
# vue extérieure : caméra qui tourne autour du vaisseau (stick droit), à cette distance du centre
const VUE_EXT_DISTANCE := 24.0
const VUE_EXT_HAUTEUR := deg_to_rad(-12.0)    # un peu au-dessus du vaisseau
const PART_TRAPPES := 0.3     # part du mouvement du train pendant laquelle les trappes s'ouvrent
const ACCELERATIONS_TEMPS := [1, 10, 100, 1000]
# tête du pilote (stick droit) : ne touche qu'à la caméra, jamais au vaisseau
const TETE_VITESSE := 2.5                     # rad/s quand le stick est poussé à fond (environ 140°/s)
const TETE_LACET_MAX := deg_to_rad(130.0)     # jusqu'où on peut tourner la tête à gauche / à droite
const TETE_HAUT_MAX := deg_to_rad(80.0)
const TETE_BAS_MAX := deg_to_rad(50.0)
const TETE_RETOUR := 2.0                      # vitesse du retour doux vers l'avant, stick lâché
# tête qui bouge avec les forces G (étape 8 du système de lumière) : le cou est un ressort amorti.
# Assis et sanglé, la tête recule d'environ 1,5 cm par g ; au plus 8 cm.
const TETE_G_METRES_PAR_G := 0.015
const TETE_G_MAX := 0.08
const TETE_G_FREQUENCE := 1.5                 # Hz (oscillation propre du cou)
const TETE_G_AMORTI := 0.7

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
var tete := Vector2.ZERO             # x = tête levée / baissée, y = tête tournée à gauche / à droite (radians)
var vue_interieure := true           # true = cockpit, false = vue extérieure (3e personne)
var oeil_pilote := OEIL_PILOTE_DEFAUT
# système de lumière (étape 8)
var lumiere = null                   # scripts/lumiere_jeu.gd (null : ancien affichage)
var avec_lumiere := false
var tete_g := true                   # la tête bouge avec les G (touche I)
var tete_g_pos := Vector3.ZERO       # m, repère du vaisseau
var tete_g_vit := Vector3.ZERO
var casque: CanvasLayer              # bord du casque (vue cockpit)
var lampe_ancienne: OmniLight3D
var temps_lumiere_ms := 0.0          # temps de calcul du système de lumière par image (moyenne)

# calotte détaillée
var calotte_dir := Vector3.ZERO
var calotte_angle := 0.0

# =====================================================================
# NŒUDS
# =====================================================================
var pilote: Node3D
var camera: Camera3D
var exterieur: Node3D                # coque, ailes, train (visible dans les deux vues)
var cockpit: Node3D                  # intérieur du cockpit et grande verrière (vue intérieure seulement)
var charnieres := {}                 # nom de l'aile -> nœud Charniere_* du modèle
var trains: Array = []               # [nœud Train_*, angle rentré (degrés)]
var trappes: Array = []              # [nœud Charniere_Trappe_*, angle ouvert (degrés)]
var maillages_exterieurs: Array = [] # pour couper leurs ombres en vue cockpit
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
	_creer_pilote_et_cockpit()
	_brancher_lumiere()
	_creer_hud()


## Étape 8 : le système de lumière (vrai Soleil, planète en rayons, œil du pilote). Sans sa partie C++,
## le jeu garde son ancien affichage (planète lisse, Soleil de Godot).
func _brancher_lumiere() -> void:
	lumiere = LumiereJeu.new()
	lumiere.name = "Lumiere"
	add_child(lumiere)
	avec_lumiere = lumiere.preparer(camera, RAYON_PLANETE)
	if not avec_lumiere:
		lumiere.queue_free()
		lumiere = null
		_creer_environnement()
		_creer_planete()
		_appliquer_vue()
		return
	lumiere.ajouter_objets(exterieur, pilote)
	lumiere.ajouter_objets(cockpit, pilote)
	# La coque passe au-dessus du cockpit, sous la verrière : elle ne doit pas lui faire d'ombre.
	var vitre := cockpit.find_child("Cockpit_verriere", true, false) as MeshInstance3D
	var coque := exterieur.find_child("Fuselage", true, false) as MeshInstance3D
	if vitre and coque:
		var b: AABB = lumiere.objets.boite(vitre, pilote)
		b = b.grow(0.05)
		b.position.y -= 0.6
		b.size.y += 1.6
		lumiere.objets.percer_ombre(coque, b, pilote)
	if lampe_ancienne:
		lampe_ancienne.queue_free()   # remplacée par la vraie lampe du système
		lampe_ancienne = null
	# le sol de la physique suit le relief de la planète dessinée
	vaisseau.relief = lumiere.hauteur_sol
	_creer_casque()
	_appliquer_vue()


## Bord du casque, vu de l'intérieur : la visière ne laisse voir qu'un grand ovale, le reste est l'intérieur
## sombre du casque. (La couleur de la visière, elle, passe par l'œil : oeil_filtre.)
func _creer_casque() -> void:
	casque = CanvasLayer.new()
	casque.layer = 0
	add_child(casque)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, 2.0);
	p.x *= 0.80;
	p.y *= 1.10;
	float d = length(p);
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(1.02, 1.22, d) * 0.97);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	casque.add_child(r)


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


func _creer_pilote_et_cockpit() -> void:
	pilote = Node3D.new()           # suit l'orientation du vaisseau ; centre de masse à l'origine
	add_child(pilote)
	# le modèle 3D est exporté de Blender dans le même repère que la physique (-Z avant, +Y haut)
	exterieur = (load(MODELE_EXTERIEUR) as PackedScene).instantiate()
	pilote.add_child(exterieur)
	cockpit = (load(MODELE_COCKPIT) as PackedScene).instantiate()
	pilote.add_child(cockpit)
	for nom in VaisseauPhysique.AILES:
		var n := exterieur.find_child("Charniere_" + nom, true, false) as Node3D
		if n != null:
			charnieres[nom] = n
	for nom in ["Train_avant", "Train_arriere_gauche", "Train_arriere_droit"]:
		var n := exterieur.find_child(nom, true, false) as Node3D
		if n != null:
			# angle rentré lu dans le modèle (propriété angle_rentre_deg de Blender), sinon valeur connue
			var rentre := 90.0 if nom == "Train_avant" else -90.0
			var extras = n.get_meta("extras", {})
			if extras is Dictionary and extras.has("angle_rentre_deg"):
				rentre = float(extras["angle_rentre_deg"])
			trains.append([n, rentre])
	# trappes du train : elles tournent autour de l'axe avant-arrière (Y de Blender = -Z de Godot)
	for n in exterieur.find_children("Charniere_Trappe_*", "Node3D", true, false):
		var extras = n.get_meta("extras", {})
		var ouvert := 0.0
		if extras is Dictionary and extras.has("angle_ouvert_deg"):
			ouvert = -float(extras["angle_ouvert_deg"])
		trappes.append([n, ouvert])
	var oeil := cockpit.find_child("Oeil_pilote", true, false) as Node3D
	if oeil != null:
		oeil_pilote = oeil.position
	for m in exterieur.find_children("*", "GeometryInstance3D", true, false):
		maillages_exterieurs.append(m)

	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 50000.0
	pilote.add_child(camera)
	camera.make_current()

	# petite lampe du cockpit (une vraie source de lumière, pour lire les instruments la nuit)
	var lampe := OmniLight3D.new()
	lampe.position = oeil_pilote + Vector3(0, 0.3, -0.6)
	lampe.light_color = Color(1.0, 0.75, 0.45)
	lampe.light_energy = 0.25
	lampe.omni_range = 2.0
	cockpit.add_child(lampe)
	lampe_ancienne = lampe
	_appliquer_vue()
	_animer_modele()


## Vue cockpit : on voit l'intérieur ; la coque ne fait pas d'ombre dans le cockpit (sinon il serait
## tout noir). Vue extérieure : le cockpit est caché, la coque fait de nouveau ses ombres.
func _appliquer_vue() -> void:
	cockpit.visible = vue_interieure
	tete = Vector2.ZERO
	if casque:
		casque.visible = vue_interieure and lumiere.visiere != 0
	if avec_lumiere:
		# système de lumière : la coque fait toujours ses ombres (la verrière, jamais : on voit à travers)
		for m in maillages_exterieurs:
			var nom := String((m as Node).name).to_lower()
			var vitre := nom.contains("verriere") and not nom.contains("cadre")
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if vitre else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if vitre:
				# la verrière vue de dehors (opaque, teintée) : en vue cockpit, c'est la vitre du cockpit qu'on voit
				(m as Node3D).visible = not vue_interieure
		return
	var ombre := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if vue_interieure else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for m in maillages_exterieurs:
		(m as GeometryInstance3D).cast_shadow = ombre
	tete = Vector2.ZERO


## Ailes et train : le modèle suit exactement l'état de la physique (mêmes angles que le calcul des poussées).
func _animer_modele() -> void:
	for nom in charnieres:
		(charnieres[nom] as Node3D).rotation = Vector3(0, 0, deg_to_rad(vaisseau.angle_aile(nom)))
	# sortie du train : d'abord les trappes s'ouvrent (premiers 30 %), puis les jambes descendent ;
	# en rentrant, c'est l'inverse (les jambes remontent, puis les trappes se ferment)
	var porte := clampf(vaisseau.train / PART_TRAPPES, 0.0, 1.0)
	var jambe := clampf((vaisseau.train - PART_TRAPPES) / (1.0 - PART_TRAPPES), 0.0, 1.0)
	for t in trains:
		(t[0] as Node3D).rotation = Vector3(deg_to_rad(lerpf(float(t[1]), 0.0, jambe)), 0, 0)
	for t in trappes:
		(t[0] as Node3D).rotation = Vector3(0, 0, deg_to_rad(float(t[1]) * porte))


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
	aide.offset_top = -232
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
		+ "%s : ailes   %s : train d'atterrissage   %s : vue cockpit / extérieure\n" % [c.resume("ailes"), c.resume("train"), c.resume("vue")]
		+ "Tourner la tête (ou la caméra) : %s   %s : regarder droit devant\n" % [_aide_tete(), c.resume("regard_centre")]
		+ "%s : projecteur   %s : casque et visière   %s : tête qui bouge avec les G\n" % [c.resume("phares"), c.resume("visiere"), c.resume("tete_g")]
		+ "%s : configurer les commandes (clavier et manette)" % c.resume("ecran_touches"))

## « stick droit » si les 4 directions de la tête sont sur le stick droit, sinon la liste.
func _aide_tete() -> String:
	var noms := ["regard_gauche", "regard_droite", "regard_haut", "regard_bas"]
	var tout_stick_droit := true
	for n in noms:
		var m: String = commandes.liaisons[n]["manette"]
		if not (m.begins_with("a:%d:" % JOY_AXIS_RIGHT_X) or m.begins_with("a:%d:" % JOY_AXIS_RIGHT_Y)):
			tout_stick_droit = false
	if tout_stick_droit and noms.all(func(n): return commandes.liaisons[n]["clavier"] == ""):
		return "stick droit"
	var morceaux := PackedStringArray()
	for n in noms:
		morceaux.append(commandes.resume(n))
	return ", ".join(morceaux)


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
	if Input.is_action_just_pressed("ailes"): vaisseau.ouvrir_ailes(vaisseau.ailes_consigne < 0.5)
	if Input.is_action_just_pressed("train"): vaisseau.sortir_train(vaisseau.train_consigne < 0.5)
	if Input.is_action_just_pressed("vue"):
		vue_interieure = not vue_interieure
		_appliquer_vue()
	if Input.is_action_just_pressed("pause"): en_pause = not en_pause
	if Input.is_action_just_pressed("tete_g"):
		tete_g = not tete_g
	if avec_lumiere and Input.is_action_just_pressed("phares"):
		lumiere.projecteur = not lumiere.projecteur
	if avec_lumiere and Input.is_action_just_pressed("visiere"):
		lumiere.changer_visiere()
		casque.visible = vue_interieure and lumiere.visiere != 0
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


## Tourner la tête dans le cockpit (stick droit). Stick lâché : la tête revient doucement droit devant.
func _bouger_tete(delta: float) -> void:
	if ecran_touches != null:
		return
	if Input.is_action_just_pressed("regard_centre"):
		tete = Vector2.ZERO
	var dx := Input.get_axis("regard_bas", "regard_haut")
	var dy := Input.get_axis("regard_droite", "regard_gauche")
	if dx == 0.0 and dy == 0.0:
		tete = tete.lerp(Vector2.ZERO, minf(1.0, TETE_RETOUR * delta))
	else:
		tete.x = clampf(tete.x + dx * TETE_VITESSE * delta, -TETE_BAS_MAX, TETE_HAUT_MAX)
		if vue_interieure:
			tete.y = clampf(tete.y + dy * TETE_VITESSE * delta, -TETE_LACET_MAX, TETE_LACET_MAX)
		else:
			tete.y = wrapf(tete.y + dy * TETE_VITESSE * delta, -PI, PI)   # dehors : on peut faire le tour
	if vue_interieure:
		camera.position = oeil_pilote + tete_g_pos
		camera.rotation = Vector3(tete.x, tete.y, 0.0)
	else:
		# caméra derrière le vaisseau, qui tourne autour de lui ; elle regarde toujours son centre
		var b := Basis.from_euler(Vector3(clampf(VUE_EXT_HAUTEUR - tete.x, -1.5, 1.5), tete.y, 0.0))
		camera.position = b * Vector3(0, 0, VUE_EXT_DISTANCE)
		camera.basis = b


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
	# En temps accéléré, l'ordre dure plus longtemps (PAS × acc_temps) : le stabilisateur en tient compte.
	if stabilisateur:
		var s: Vector3 = vaisseau.ordres_stabilisateur(PAS * acc_temps)
		if t == 0.0: t = s.x
		if l == 0.0: l = s.y
		if r == 0.0: r = s.z
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
func _process(delta: float) -> void:
	_lire_boutons()
	pilote.basis = Basis(vaisseau.orientation)
	_suivre_g(delta)
	_bouger_tete(delta)
	_animer_modele()
	if avec_lumiere:
		_placer_lumiere(delta)
	else:
		_placer_planete()
	_mettre_a_jour_hud()
	_placer_marqueurs()


## La tête du pilote, sur son cou (ressort amorti), recule quand le vaisseau accélère : on sent les G.
## Elle ne touche qu'à la caméra, jamais à la physique du vaisseau.
func _suivre_g(delta: float) -> void:
	var cible := Vector3.ZERO
	if tete_g and not en_pause:
		cible = cible_tete_g(pilote.basis.inverse() * vaisseau.acceleration_ressentie)
	var r := pas_tete_g(tete_g_pos, tete_g_vit, cible, delta)
	tete_g_pos = r[0]
	tete_g_vit = r[1]


## Où la tête irait, à l'équilibre, sous l'accélération ressentie a_local (m/s², repère du vaisseau) :
## à l'opposé de l'accélération (on est poussé dans le siège), 1,5 cm par g, au plus 8 cm.
static func cible_tete_g(a_local: Vector3) -> Vector3:
	return (-a_local / VaisseauPhysique.G0 * TETE_G_METRES_PAR_G).limit_length(TETE_G_MAX)


## Un pas du cou (ressort amorti) : renvoie [position, vitesse].
static func pas_tete_g(pos: Vector3, vit: Vector3, cible: Vector3, delta: float) -> Array:
	var w := TAU * TETE_G_FREQUENCE
	var dt := minf(delta, 0.05)
	vit += (w * w * (cible - pos) - 2.0 * TETE_G_AMORTI * w * vit) * dt
	pos += vit * dt
	return [pos.limit_length(TETE_G_MAX), vit]


## Étape 8 : l'affichage est centré sur l'œil (la caméra reste à l'origine, comme dans le labo) ; la
## position de l'œil par rapport à la planète est calculée en 64 bits (centre du vaisseau + œil).
func _placer_lumiere(delta: float) -> void:
	var oeil_local := camera.position
	var decalage := pilote.basis * oeil_local
	pilote.position = -decalage
	var oeil64 := PackedFloat64Array([vaisseau.px + float(decalage.x), vaisseau.py + float(decalage.y),
		vaisseau.pz + float(decalage.z)])
	var gaz_moteurs := 0.0
	for m in vaisseau.moteurs:
		gaz_moteurs += float(m["actuel"])
	gaz_moteurs /= maxf(vaisseau.moteurs.size(), 1)
	var t0 := Time.get_ticks_usec()
	lumiere.mettre_a_jour(delta, oeil64, Vector3(vaisseau.vx, vaisseau.vy, vaisseau.vz), pilote.basis,
		oeil_local, gaz_moteurs)
	temps_lumiere_ms = lerpf(temps_lumiere_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.05)


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
			# sens des triangles : face avant vers l'extérieur (vers le pilote). Dans l'autre sens,
			# Godot voyait l'envers, retournait la normale et la calotte restait noire (invisible).
			indices.append_array([k, k + n + 1, k + 1, k + 1, k + n + 1, k + n + 2])
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


func _etat(valeur: float, consigne: float, plein: String, vide: String) -> String:
	if valeur == consigne:
		return plein if valeur >= 1.0 else vide
	return "en mouvement (%d %%)" % int(round(valeur * 100.0))


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
	lignes.append("AILES         %s      TRAIN %s      VUE %s" % [_etat(vaisseau.ailes, vaisseau.ailes_consigne, "ouvertes", "repliées"),
		_etat(vaisseau.train, vaisseau.train_consigne, "sorti", "rentré"), "cockpit" if vue_interieure else "extérieure"])
	lignes.append("STABILISATEUR %s      TEMPS x%d%s" % ["activé" if stabilisateur else "désactivé", acc_temps, "   (PAUSE)" if en_pause else ""])
	if avec_lumiere:
		lignes.append(lumiere.infos())
		lignes.append("TÊTE          %s (déplacement %.1f cm)      calcul de la lumière %.1f ms par image" % ["bouge avec les G" if tete_g else "fixe", tete_g_pos.length() * 100.0, temps_lumiere_ms])
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
