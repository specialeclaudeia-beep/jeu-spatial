extends Node3D
## L'ATELIER (étape 2) : un écran à part du jeu. Le vaisseau est posé dans le hangar, sur ses roues ; on
## tourne autour comme dans Blender, on choisit une pièce (dans la liste de gauche ou en cliquant dessus)
## et sa fiche s'ouvre à droite. Le tableau ingénieur, en haut, donne les chiffres du vaisseau entier.
## « Lancer » charge le jeu (seulement à ce moment : l'atelier est alors libéré), vaisseau posé au sol
## devant le hangar. Dans le jeu, F3 ramène ici.
##
## Visuel PROVISOIRE (hangar, menus, couleurs : scripts/atelier/hangar.gd et style.gd). La physique, elle,
## est la vraie : la pose du vaisseau dans le hangar (amortisseurs écrasés par son poids) et tous les
## chiffres viennent du même code que le jeu (scripts/physique/vaisseau_physique.gd, via analyse.gd).
##
## Pour l'instant on regarde et on analyse ; placer, déplacer et régler des pièces viendra à l'étape
## suivante.

const Analyse = preload("res://scripts/atelier/analyse.gd")
const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const Plan = preload("res://scripts/atelier/plan.gd")
const Style = preload("res://scripts/atelier/style.gd")
const Hangar = preload("res://scripts/atelier/hangar.gd")
const CameraAtelier = preload("res://scripts/atelier/camera_atelier.gd")
const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const ModeleVaisseau = preload("res://scripts/modele_vaisseau.gd")
const Partie = preload("res://scripts/partie.gd")

const MODELE_EXTERIEUR := "res://modeles/vaisseau/vaisseau_exterieur.glb"
const MODELE_COCKPIT := "res://modeles/vaisseau/cockpit.glb"
const MODELE_DROIDE := "res://modeles/vaisseau/droide.glb"
const REGLAGES := "user://atelier.cfg"
const COUCHE_PIECES := 2                 # couche des formes cliquables (une par maillage du vaisseau)
const RAYON_PLANETE := 600000.0          # comme le jeu : le hangar est sur la planète
const GRAVITE_SURFACE := 9.81

var plan
var analyse
var vaisseau_pose                        # la physique, posée sur le sol du hangar (donne la pose du modèle)
var hangar
var camera: CameraAtelier
var pilote: Node3D                       # le vaisseau, origine au centre de gravité
var corps: Node3D                        # repère du plan (décalé du centre de gravité)
var exterieur: Node3D
var cockpit: Node3D
var modele
var maillages := {}                      # id de pièce → [MeshInstance3D]
var selection := {}                      # {"genre": piece / categorie / type / matiere, "id": …}
var _surlignes: Array = []
var _repere_selection: Node3D            # flèches et points des pièces sans dessin (moteurs, roues…)
var _centre_gravite: Node3D
var _fleches_poussee: Node3D
var _materiau_surligne: StandardMaterial3D
var _materiau_survol: StandardMaterial3D
var _survol_maillages: Array = []
var _survol_id := ""
var _clic_depart := Vector2(-1, -1)
var _demande_clic := Vector2(-1, -1)
var _demande_survol := Vector2(-1, -1)

# interface
var ui: Control
var recherche: LineEdit
var arbre: Tree
var fiche: PanelContainer
var fiche_titre: Label
var fiche_sous_titre: Label
var fiche_grille: GridContainer
var fiche_note: Label
var bulle: Label
var chargement: ColorRect
var case_cg: CheckBox
var case_poussees: CheckBox
var case_neutre: CheckBox
var curseur_vitesse: HSlider
var texte_vitesse: Label
var _replies := {}                       # catégories repliées dans la liste (hors recherche)
var _remplissage := false


func _ready() -> void:
	plan = _charger_plan()
	analyse = Analyse.new(plan)
	hangar = Hangar.new()
	add_child(hangar)
	_creer_vaisseau()
	camera = CameraAtelier.new()
	add_child(camera)
	camera.make_current()
	camera.cadrer(boite_vaisseau())
	camera.vue("trois_quarts")
	_creer_interface()
	_lire_reglages()
	if not plan.valide():
		_afficher_fiche({"titre": "Plan du vaisseau invalide", "sous_titre": plan.chemin,
			"lignes": [], "note": "\n".join(plan.erreurs)})


func _charger_plan():
	var chemin := Partie.plan_choisi()
	if chemin == Plan.PLAN_PAR_DEFAUT:
		return Plan.par_defaut()
	var p = Plan.new()
	if p.charger(chemin):
		return p
	push_warning("Plan « %s » illisible : chasseur de départ." % chemin)
	return Plan.par_defaut()


# =====================================================================
# LE VAISSEAU POSÉ DANS LE HANGAR
# =====================================================================
func _creer_vaisseau() -> void:
	# même physique que le jeu, sur la même planète (sol lisse) : le vaisseau se pose sur ses roues et ses
	# amortisseurs s'écrasent sous son poids. Endroit : le pôle (le haut = +Y), nez vers −Z (la porte).
	var v = VaisseauPhysique.new(plan)
	v.gm = GRAVITE_SURFACE * RAYON_PLANETE * RAYON_PLANETE
	v.rayon_planete = RAYON_PLANETE
	v.poser_au_sol(Vector3.UP, Vector3.FORWARD, 2.0)
	vaisseau_pose = v
	pilote = Node3D.new()
	pilote.name = "Vaisseau"
	add_child(pilote)
	pilote.transform = Transform3D(Basis(v.orientation), Vector3(0.0, v.py - RAYON_PLANETE, 0.0))
	corps = Node3D.new()
	corps.position = -v.centre_gravite
	pilote.add_child(corps)
	exterieur = (load(MODELE_EXTERIEUR) as PackedScene).instantiate()
	corps.add_child(exterieur)
	cockpit = (load(MODELE_COCKPIT) as PackedScene).instantiate()
	corps.add_child(cockpit)
	var logement := exterieur.find_child("Point_droide", true, false) as Node3D
	var droide: Node3D = null
	if logement != null and ResourceLoader.exists(MODELE_DROIDE):
		droide = (load(MODELE_DROIDE) as PackedScene).instantiate()
		logement.add_child(droide)
	modele = ModeleVaisseau.new(exterieur, v)
	modele.poser(v)
	modele.amortir(v, 0.0)
	# moteurs éteints : pas de jets, lueurs sombres ; verrière vue de dehors en verre (on voit le cockpit)
	var eteint := StandardMaterial3D.new()
	eteint.albedo_color = Color(0.05, 0.06, 0.08)
	for n in exterieur.find_children("Panache_*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).visible = false
	for n in exterieur.find_children("Lueur_*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = eteint
	var verriere := exterieur.find_child("Verriere", true, false) as MeshInstance3D
	if verriere != null:
		var verre := StandardMaterial3D.new()
		verre.albedo_color = Color(0.32, 0.46, 0.6, 0.28)
		verre.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		verre.roughness = 0.05
		verre.metallic_specular = 0.9
		verriere.material_override = verre
		verriere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# chaque maillage du dessin → sa pièce du plan (même nom), et une forme cliquable
	maillages.clear()
	for racine in [exterieur, cockpit]:
		for mi in (racine as Node).find_children("*", "MeshInstance3D", true, false):
			var id := _piece_du_maillage(mi as MeshInstance3D, racine == cockpit)
			if id != "":
				_rendre_cliquable(mi as MeshInstance3D, id)
	if droide != null and analyse.a_piece("Masse_droide"):
		for mi in droide.find_children("*", "MeshInstance3D", true, false):
			_rendre_cliquable(mi as MeshInstance3D, "Masse_droide")
	_materiau_surligne = _materiau_calque(Style.SELECTION, 0.42)
	_materiau_survol = _materiau_calque(Color(1, 1, 1), 0.14)
	_repere_selection = Node3D.new()
	corps.add_child(_repere_selection)
	_creer_centre_gravite()
	_creer_fleches_poussee()


func _piece_du_maillage(mi: MeshInstance3D, dans_cockpit: bool) -> String:
	var nom := String(mi.name)
	if nom.begins_with("Lueur_") or nom.begins_with("Panache_"):
		return ""
	var n: Node = mi
	while n != null and n != exterieur and n != cockpit:
		if analyse.a_piece(String(n.name)):
			return String(n.name)
		n = n.get_parent()
	if dans_cockpit and analyse.a_piece("Cockpit_details"):
		return "Cockpit_details"   # boutons, interrupteurs, voyants : les détails du cockpit
	return ""


func _rendre_cliquable(mi: MeshInstance3D, id: String) -> void:
	if not maillages.has(id):
		maillages[id] = []
	(maillages[id] as Array).append(mi)
	if mi.mesh == null:
		return
	var forme := mi.mesh.create_trimesh_shape()
	if forme == null:
		return
	var corps_clic := StaticBody3D.new()
	corps_clic.collision_layer = 1 << (COUCHE_PIECES - 1)
	corps_clic.collision_mask = 0
	corps_clic.set_meta("piece", id)
	var cs := CollisionShape3D.new()
	cs.shape = forme
	corps_clic.add_child(cs)
	mi.add_child(corps_clic)


static func _materiau_calque(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 1
	return m


## Boîte (repère du monde) qui contient tout le dessin du vaisseau.
func boite_vaisseau() -> AABB:
	var b := AABB()
	var premiere := true
	for mi in exterieur.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var bm: AABB = m.global_transform * m.get_aabb()
		b = bm if premiere else b.merge(bm)
		premiere = false
	return b


## Hauteur du point le plus bas des roues au-dessus du sol du hangar (m) : doit être ≈ 0 (posé).
func hauteur_roues() -> float:
	# bas de chaque roue = point du plan (amortisseur détendu) remonté de l'écrasement de l'amortisseur
	var h := INF
	var v = vaisseau_pose
	for k in v.roues.size():
		var bas: Vector3 = (v.roues[k] as Vector3) + Vector3(0.0, v.compression_roues[k], 0.0)
		h = minf(h, (pilote.transform * (bas - v.centre_gravite)).y)
	return h


# =====================================================================
# REPÈRES 3D : centre de gravité, flèches de poussée, pièces sans dessin
# =====================================================================
func _creer_centre_gravite() -> void:
	_centre_gravite = Node3D.new()
	_centre_gravite.name = "Centre_gravite"
	pilote.add_child(_centre_gravite)
	var s := SphereMesh.new()
	s.radius = 0.32
	s.height = 0.64
	s.radial_segments = 24
	s.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = s
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	# la boule à damier des plans d'avion, visible à travers la coque
	sh.code = """shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_back;
varying vec3 p;
void vertex() { p = VERTEX; }
void fragment() {
	float d = step(0.0, p.x) == step(0.0, p.y) ? 1.0 : 0.0;
	d = step(0.0, p.z) > 0.5 ? d : 1.0 - d;
	ALBEDO = mix(vec3(0.05), vec3(0.95, 0.85, 0.2), d);
}"""
	m.shader = sh
	m.render_priority = 3
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_centre_gravite.add_child(mi)


func _creer_fleches_poussee() -> void:
	_fleches_poussee = Node3D.new()
	_fleches_poussee.name = "Fleches_poussee"
	corps.add_child(_fleches_poussee)
	var v = analyse.v
	var somme := Vector3.ZERO
	for m in v.moteurs:
		if m["role"] == "levage":
			continue
		var f: Vector3 = (m["dir_ref"] as Vector3) * float(m["poussee_n"])
		somme += f
		_fleches_poussee.add_child(fleche(m["pos_ref"], m["dir_ref"], longueur_force(float(m["poussee_n"])), Color(1.0, 0.55, 0.15), 1.0, true))
	# la résultante, au centre de gravité
	if somme.length() > 0.0:
		_fleches_poussee.add_child(fleche(v.centre_gravite, somme.normalized(), longueur_force(somme.length()), Color(0.3, 1.0, 0.45), 1.6))
	_fleches_poussee.visible = false


## Longueur d'une flèche de force (m) : 6 kN → 1 m, 200 kN → 3,3 m, 1 000 kN → 4,7 m.
static func longueur_force(newtons: float) -> float:
	return 1.0 + 0.9 * log(maxf(newtons, 1.0) / 6000.0) / log(5.0)


## Flèche (tige + pointe) partant de « depart », dans la direction « dir », visible à travers la coque.
## pousse = vrai : c'est une force qui POUSSE en ce point (moteur, propulseur) : la pointe arrive sur le
## point, la flèche vient de derrière (du côté du jet), comme sur un schéma de forces.
static func fleche(depart: Vector3, dir: Vector3, longueur: float, couleur: Color, epaisseur := 1.0, pousse := false) -> Node3D:
	var n := Node3D.new()
	var d := dir.normalized()
	var haut := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := haut.cross(d).normalized()
	var origine := depart - d * longueur if pousse else depart
	n.transform = Transform3D(Basis(x, d, x.cross(d)), origine)   # +Y local = la direction
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = couleur
	m.no_depth_test = true
	m.render_priority = 2
	var tige := CylinderMesh.new()
	tige.top_radius = 0.045 * epaisseur
	tige.bottom_radius = 0.045 * epaisseur
	tige.height = longueur * 0.78
	tige.radial_segments = 10
	var mt := MeshInstance3D.new()
	mt.mesh = tige
	mt.position = Vector3(0, tige.height * 0.5, 0)
	mt.material_override = m
	mt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mt)
	var pointe := CylinderMesh.new()
	pointe.top_radius = 0.0
	pointe.bottom_radius = 0.14 * epaisseur
	pointe.height = longueur * 0.22
	pointe.radial_segments = 12
	var mp := MeshInstance3D.new()
	mp.mesh = pointe
	mp.position = Vector3(0, tige.height + pointe.height * 0.5, 0)
	mp.material_override = m
	mp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mp)
	return n


static func _point(position: Vector3, rayon: float, couleur: Color) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = rayon
	s.height = rayon * 2.0
	s.radial_segments = 16
	s.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.position = position
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = couleur
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Repère d'une pièce qui n'a pas de dessin à elle (moteur, propulseur, roue, surface d'air, point de
## coque, masse ponctuelle). Coordonnées du plan (pose de référence).
func _repere_piece(p: Dictionary) -> Node3D:
	var t := String(p["type"])
	match t:
		"moteur", "propulseur":
			return fleche(p["point"], p["direction"], longueur_force(float(p["poussee_n"])), Color(1.0, 0.55, 0.15), 1.0, true)
		"roue":
			var r := float(p.get("rayon_m", 0.18))
			return _point((p["point"] as Vector3) + Vector3(0, r, 0), r, Color(0.35, 0.8, 1.0, 0.8))
		"contact_coque":
			return _point(p["point"], 0.12, Color(1.0, 0.35, 0.3, 0.9))
		"surface_air":
			var s := float(p["surface_m2"])
			var corde := float(p.get("corde_m", sqrt(s)))
			var plaque := BoxMesh.new()
			plaque.size = Vector3(s / corde, 0.02, corde)
			var mi := MeshInstance3D.new()
			mi.mesh = plaque
			var nrm: Vector3 = p["normale"]
			var a := Vector3.BACK.cross(nrm).normalized()
			if a.length() < 0.5:
				a = Vector3.RIGHT
			mi.transform = Transform3D(Basis(a, nrm, a.cross(nrm)), p["point"])
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.35, 0.85, 1.0, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.no_depth_test = true
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.render_priority = 2
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return mi
		"masse":
			var mp: Dictionary = p["masse_calculee"]
			return _point(mp["centre"], 0.08 * pow(float(mp["masse"]), 1.0 / 3.0), Color(0.75, 0.55, 1.0, 0.55))
	return null


# =====================================================================
# SÉLECTION
# =====================================================================
## Choisir quelque chose : une pièce (genre "piece"), une catégorie de pièces, un type ou une matière.
## La fiche s'ouvre, les pièces concernées s'allument en orange.
func choisir(genre: String, id: String) -> void:
	selection = {"genre": genre, "id": id}
	var ids := pieces_choisies()
	_surligner(ids)
	for c in _repere_selection.get_children():
		c.queue_free()
	for i in ids:
		var p: Dictionary = analyse.piece(i)
		if not maillages.has(i) and not p.is_empty():
			var r := _repere_piece(p)
			if r != null:
				_repere_selection.add_child(r)
	match genre:
		"piece":
			_afficher_fiche(analyse.fiche_piece(id))
		"type":
			_afficher_fiche(analyse.fiche_type(id))
		"matiere":
			_afficher_fiche(analyse.fiche_matiere(id))
		"categorie":
			_afficher_fiche(fiche_categorie(id))
	_selectionner_dans_liste()


func deselectionner() -> void:
	selection = {}
	_surligner([])
	for c in _repere_selection.get_children():
		c.queue_free()
	fiche.visible = false
	if arbre != null:
		arbre.deselect_all()


## Les pièces du plan concernées par la sélection actuelle.
func pieces_choisies() -> Array:
	var genre := String(selection.get("genre", ""))
	var id := String(selection.get("id", ""))
	var ids := []
	for p in plan.pieces:
		var ok := false
		match genre:
			"piece":
				ok = p["id"] == id
			"categorie":
				ok = Analyse.categorie(p) == id
			"type":
				ok = p["type"] == id
			"matiere":
				ok = p.get("matiere", null) != null and String(p["matiere"]) == id
		if ok:
			ids.append(p["id"])
	return ids


func _surligner(ids: Array) -> void:
	for mi in _surlignes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = null
	_surlignes.clear()
	for i in ids:
		for mi in maillages.get(i, []):
			(mi as MeshInstance3D).material_overlay = _materiau_surligne
			_surlignes.append(mi)
	_survol_maillages.clear()   # le survol se redessine


func fiche_categorie(cle: String) -> Dictionary:
	var ids: Array = analyse.pieces_par_categorie()[cle]
	var m := 0.0
	for i in ids:
		m += float(analyse.piece(i)["masse_calculee"]["masse"])
	var lignes := [["Pièces", str(ids.size())],
		["Masse", "%s kg (%s %% du vaisseau)" % [Analyse.nombre(m, 1), Analyse.nombre(100.0 * m / analyse.masse_totale, 1)]]]
	return {"titre": Analyse.titre_categorie(cle), "sous_titre": "catégorie", "lignes": lignes,
		"note": "Les pièces de cette catégorie sont en orange. Celles qui n'ont pas de dessin (moteurs, propulseurs, roues, surfaces d'air, masses) sont montrées par une flèche ou un point."}


## Clic dans la vue 3D : la pièce sous la souris (ou rien).
func piece_sous(pos_ecran: Vector2) -> String:
	var depart := camera.project_ray_origin(pos_ecran)
	var fin := depart + camera.project_ray_normal(pos_ecran) * 500.0
	var q := PhysicsRayQueryParameters3D.create(depart, fin, 1 << (COUCHE_PIECES - 1))
	q.collide_with_areas = false
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return ""
	var c = r["collider"]
	return String(c.get_meta("piece", "")) if c != null else ""


# =====================================================================
# ENTRÉES : caméra, clic, survol
# =====================================================================
func _unhandled_input(e: InputEvent) -> void:
	if chargement != null and chargement.visible:
		return
	var h := get_viewport().get_visible_rect().size.y
	if camera.traiter(e, h):
		get_viewport().set_input_as_handled()
		bulle.visible = false
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var b := e as InputEventMouseButton
		if b.pressed:
			_clic_depart = b.position
		elif _clic_depart.x >= 0.0 and b.position.distance_to(_clic_depart) < 5.0:
			_demande_clic = b.position
			_clic_depart = Vector2(-1, -1)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_demande_survol = (e as InputEventMouseMotion).position
	elif e is InputEventKey and e.pressed and not e.echo:
		match (e as InputEventKey).keycode:
			KEY_ESCAPE:
				deselectionner()
			KEY_KP_PERIOD, KEY_F:
				cadrer_selection()
			KEY_HOME:
				camera.cadrer(boite_vaisseau())


## Les rayons de clic et de survol passent par la physique de Godot : on les lance ici, au bon moment.
func _physics_process(_delta: float) -> void:
	if _demande_clic.x >= 0.0:
		var id := piece_sous(_demande_clic)
		_demande_clic = Vector2(-1, -1)
		if id == "":
			deselectionner()
		else:
			choisir("piece", id)
	if _demande_survol.x >= 0.0:
		var pos := _demande_survol
		_demande_survol = Vector2(-1, -1)
		var id := "" if camera.glisse_en_cours() else piece_sous(pos)
		_survoler(id, pos)


func _survoler(id: String, pos: Vector2) -> void:
	if id != _survol_id or _survol_maillages.is_empty():
		for mi in _survol_maillages:
			if is_instance_valid(mi) and (mi as MeshInstance3D).material_overlay == _materiau_survol:
				(mi as MeshInstance3D).material_overlay = null
		_survol_maillages.clear()
		_survol_id = id
		for mi in maillages.get(id, []):
			if (mi as MeshInstance3D).material_overlay == null:
				(mi as MeshInstance3D).material_overlay = _materiau_survol
				_survol_maillages.append(mi)
	bulle.visible = id != ""
	if id != "":
		var p: Dictionary = analyse.piece(id)
		var m := float(p["masse_calculee"]["masse"])
		bulle.text = "%s · %s kg" % [Analyse.nom_lisible(p), Analyse.nombre(m, 1)]
		bulle.position = pos + Vector2(16, 14)


func cadrer_selection() -> void:
	var ids := pieces_choisies()
	var b := AABB()
	var premiere := true
	for i in ids:
		for mi in maillages.get(i, []):
			var bm: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			b = bm if premiere else b.merge(bm)
			premiere = false
		var p: Dictionary = analyse.piece(i)
		if not maillages.has(i) and not p.is_empty():
			var pt: Vector3 = p.get("point", p["masse_calculee"]["centre"])
			var bp := AABB(corps.global_transform * pt - Vector3.ONE * 0.5, Vector3.ONE)
			b = bp if premiere else b.merge(bp)
			premiere = false
	if not premiere:
		camera.cadrer(b)


# =====================================================================
# INTERFACE
# =====================================================================
func _creer_interface() -> void:
	var couche := CanvasLayer.new()
	add_child(couche)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Style.theme()
	couche.add_child(ui)
	var colonne := VBoxContainer.new()
	colonne.set_anchors_preset(Control.PRESET_FULL_RECT)
	colonne.offset_left = 10
	colonne.offset_right = -10
	colonne.offset_top = 8
	colonne.offset_bottom = -8
	colonne.add_theme_constant_override("separation", 8)
	colonne.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(colonne)
	colonne.add_child(_barre_haut())
	colonne.add_child(_tableau_ingenieur())
	var milieu := HBoxContainer.new()
	milieu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	milieu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	milieu.add_theme_constant_override("separation", 8)
	colonne.add_child(milieu)
	milieu.add_child(_panneau_catalogue())
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	milieu.add_child(centre)
	centre.add_child(_barre_vue())
	milieu.add_child(_panneau_fiche())
	colonne.add_child(_barre_aide())
	bulle = Style.label("", 13)
	bulle.add_theme_stylebox_override("normal", Style.boite(Style.FOND_CLAIR, Style.BORD, 4, 6.0))
	bulle.visible = false
	ui.add_child(bulle)
	chargement = ColorRect.new()
	chargement.color = Color(0.02, 0.025, 0.035, 0.92)
	chargement.set_anchors_preset(Control.PRESET_FULL_RECT)
	chargement.visible = false
	var lc := Style.label("Chargement du jeu…\nLe vaisseau part posé au sol, devant le hangar.\nDans le jeu, F3 ramène à l'atelier.", 22)
	lc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lc.set_anchors_preset(Control.PRESET_FULL_RECT)
	chargement.add_child(lc)
	ui.add_child(chargement)
	remplir_catalogue()


func _barre_haut() -> Control:
	var p := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var accueil := Style.bouton("⌂  Accueil")
	accueil.pressed.connect(func(): Partie.aller_accueil(get_tree()))
	h.add_child(accueil)
	var titre := Style.label("ATELIER", 20, Style.ACCENT)
	h.add_child(titre)
	var nom := Style.label("%s  ·  %d pièces" % [String(plan.donnees.get("nom", "vaisseau")), plan.pieces.size()], 16, Style.TEXTE)
	nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nom)
	var cam := Style.bouton("Caméra ▾")
	cam.pressed.connect(_ouvrir_menu_camera.bind(cam))
	h.add_child(cam)
	var lancer := Style.bouton_principal("▶  LANCER")
	lancer.tooltip_text = "Charge le jeu : le vaisseau part posé au sol, devant le hangar (F3 pour revenir)"
	lancer.pressed.connect(lancer_jeu)
	h.add_child(lancer)
	return p


func _tableau_ingenieur() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in analyse.tuiles():
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(120, 0)
		p.add_theme_stylebox_override("panel", Style.boite(Style.FOND, Style.BORD, 6, 9.0))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		p.add_child(v)
		v.add_child(Style.label(t[0], 11, Style.TEXTE_DOUX))
		v.add_child(Style.label(t[1], 19, Color.WHITE))
		var d := Style.label(t[2], 11, Style.TEXTE_DOUX)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(100, 0)
		v.add_child(d)
		p.tooltip_text = "%s : %s\n%s" % [t[0], t[1], t[2]]
		h.add_child(p)
	return h


func _panneau_catalogue() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(300, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(Style.label("CATALOGUE", 12, Style.TEXTE_DOUX))
	recherche = LineEdit.new()
	recherche.placeholder_text = "Rechercher une pièce, une matière…"
	recherche.clear_button_enabled = true
	recherche.text_changed.connect(func(_t): remplir_catalogue())
	v.add_child(recherche)
	arbre = Tree.new()
	arbre.hide_root = true
	arbre.columns = 2
	arbre.set_column_expand(0, true)
	arbre.set_column_expand(1, false)
	arbre.set_column_custom_minimum_width(1, 78)
	arbre.select_mode = Tree.SELECT_ROW
	arbre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arbre.item_selected.connect(_choix_dans_liste)
	arbre.item_collapsed.connect(_repli)
	v.add_child(arbre)
	return p


func _barre_vue() -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", Style.boite(Color(0.065, 0.075, 0.098, 0.82), Style.BORD, 6, 6.0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	p.add_child(h)
	h.add_child(Style.label("Vue ", 13, Style.TEXTE_DOUX))
	for b in [["Face", "face", "pavé numérique 1"], ["Côté", "droite", "pavé numérique 3"], ["Dessus", "dessus", "pavé numérique 7"],
			["3/4", "trois_quarts", ""]]:
		var bt := Style.bouton(b[0], 13)
		bt.tooltip_text = b[2]
		bt.pressed.connect(camera.vue.bind(b[1]))
		h.add_child(bt)
	var tout := Style.bouton("Tout voir", 13)
	tout.tooltip_text = "Origine (Home)"
	tout.pressed.connect(func(): camera.cadrer(boite_vaisseau()))
	h.add_child(tout)
	var sel := Style.bouton("Cadrer le choix", 13)
	sel.tooltip_text = "pavé numérique , ou F"
	sel.pressed.connect(cadrer_selection)
	h.add_child(sel)
	var sep := VSeparator.new()
	h.add_child(sep)
	case_cg = _case("Centre de gravité", true, func(on): _centre_gravite.visible = on; _sauver_reglages())
	h.add_child(case_cg)
	case_poussees = _case("Poussées", false, func(on): _fleches_poussee.visible = on; _sauver_reglages())
	h.add_child(case_poussees)
	case_neutre = _case("Fond neutre", false, func(on): hangar.vue_technique(on); _sauver_reglages())
	h.add_child(case_neutre)
	return p


func _case(texte: String, oui: bool, quand: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = texte
	c.button_pressed = oui
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 13)
	c.toggled.connect(quand)
	return c


func _panneau_fiche() -> Control:
	fiche = PanelContainer.new()
	fiche.custom_minimum_size = Vector2(340, 0)
	fiche.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	fiche.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := Style.label("FICHE", 12, Style.TEXTE_DOUX)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var fermer := Style.bouton("×", 14)
	fermer.pressed.connect(deselectionner)
	h.add_child(fermer)
	fiche_titre = Style.label("", 20, Color.WHITE)
	fiche_titre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(fiche_titre)
	fiche_sous_titre = Style.label("", 12, Style.TEXTE_DOUX)
	v.add_child(fiche_sous_titre)
	v.add_child(HSeparator.new())
	var defil := ScrollContainer.new()
	defil.size_flags_vertical = Control.SIZE_EXPAND_FILL
	defil.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(defil)
	var interieur := VBoxContainer.new()
	interieur.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interieur.add_theme_constant_override("separation", 10)
	defil.add_child(interieur)
	fiche_grille = GridContainer.new()
	fiche_grille.columns = 2
	fiche_grille.add_theme_constant_override("h_separation", 12)
	fiche_grille.add_theme_constant_override("v_separation", 7)
	fiche_grille.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interieur.add_child(fiche_grille)
	fiche_note = Style.label("", 13, Style.TEXTE_DOUX)
	fiche_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fiche_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interieur.add_child(fiche_note)
	return fiche


func _barre_aide() -> Control:
	var l := Style.label("Molette (ou Alt + clic) : tourner   ·   Maj + molette : déplacer   ·   Roulette ou Ctrl + molette : zoom   ·   Clic : choisir une pièce   ·   Échap : rien choisir   ·   Pavé numérique 1 / 3 / 7 : vues", 12, Style.TEXTE_DOUX)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", Style.boite(Style.FOND, Style.BORD, 6, 10.0))
	p.add_child(l)
	return p


func _afficher_fiche(f: Dictionary) -> void:
	fiche.visible = true
	fiche_titre.text = String(f["titre"])
	fiche_sous_titre.text = String(f["sous_titre"])
	for c in fiche_grille.get_children():
		c.queue_free()
	for ligne in f["lignes"]:
		var a := Style.label(String(ligne[0]), 13, Style.TEXTE_DOUX)
		a.custom_minimum_size = Vector2(120, 0)
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		a.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		fiche_grille.add_child(a)
		var b := Style.label(String(ligne[1]), 13, Style.TEXTE)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(160, 0)
		fiche_grille.add_child(b)
	fiche_note.text = String(f["note"])
	fiche_note.visible = fiche_note.text != ""


## (Re)remplit la liste de gauche selon la recherche. Hors recherche, les catégories gardent l'état
## plié / déplié choisi ; pendant une recherche, tout ce qui correspond est déplié.
func remplir_catalogue() -> void:
	if arbre == null:
		return
	_remplissage = true
	arbre.clear()
	var r := recherche.text if recherche != null else ""
	var cherche := r.strip_edges() != ""
	var racine := arbre.create_item()
	# 1. les pièces du vaisseau, par catégorie
	var section := _section(racine, "TON VAISSEAU", "vaisseau")
	var par_cat: Dictionary = analyse.pieces_par_categorie()
	var total := 0
	for c in Analyse.CATEGORIES:
		var ids: Array = par_cat[c[0]]
		var trouves := ids.filter(func(i): return analyse.correspond(i, r)) if cherche else ids
		if cherche and Analyse.correspond_texte(c[1], r):
			trouves = ids
		if trouves.is_empty():
			continue
		total += trouves.size()
		var cat := arbre.create_item(section)
		cat.set_text(0, c[1])
		cat.set_text(1, str(trouves.size()))
		cat.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		cat.set_custom_color(1, Style.TEXTE_DOUX)
		cat.set_metadata(0, {"genre": "categorie", "id": c[0]})
		cat.collapsed = false if cherche else bool(_replies.get(c[0], true))
		for i in trouves:
			var p: Dictionary = analyse.piece(i)
			var it := arbre.create_item(cat)
			it.set_text(0, Analyse.nom_lisible(p))
			var m := float(p["masse_calculee"]["masse"])
			it.set_text(1, ("%s kg" % Analyse.nombre(m, 1)) if m > 0.0 else _etiquette_type(p))
			it.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
			it.set_custom_color(1, Style.TEXTE_DOUX)
			it.set_metadata(0, {"genre": "piece", "id": i})
			it.set_tooltip_text(0, "%s (%s)" % [Analyse.nom_lisible(p), i])
	section.set_text(1, str(total))
	if total == 0:
		section.free()
	# 2. les types de pièces du catalogue (ce qu'on pourra placer à l'étape suivante)
	var types := _section(racine, "TYPES DE PIÈCES", "types")
	var n_types := 0
	for t in Catalogue.TYPES:
		var nom := Analyse._majuscule(String(Catalogue.TYPES[t]["nom"]))
		if cherche and not Analyse.correspond_texte(nom + " " + t + " " + String(Catalogue.TYPES[t]["description"]), r):
			continue
		var it := arbre.create_item(types)
		it.set_text(0, nom)
		it.set_metadata(0, {"genre": "type", "id": t})
		it.set_tooltip_text(0, String(Catalogue.TYPES[t]["description"]))
		n_types += 1
	if n_types == 0:
		types.free()
	# 3. les matières
	var mats := _section(racine, "MATIÈRES", "matieres")
	var n_mats := 0
	var par_matiere: Dictionary = plan.proprietes_masse()["masse_par_matiere"]
	for m in Catalogue.MATIERES:
		var d: Dictionary = Catalogue.MATIERES[m]
		if cherche and not Analyse.correspond_texte(String(d["nom"]) + " " + m + " " + String(d["usage"]), r):
			continue
		var it := arbre.create_item(mats)
		it.set_text(0, Analyse._majuscule(String(d["nom"])))
		it.set_text(1, "%s kg" % Analyse.nombre(float(par_matiere.get(m, 0.0)), 0))
		it.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		it.set_custom_color(1, Style.TEXTE_DOUX)
		it.set_metadata(0, {"genre": "matiere", "id": m})
		n_mats += 1
	if n_mats == 0:
		mats.free()
	_remplissage = false
	_selectionner_dans_liste()


func _section(racine: TreeItem, titre: String, cle: String) -> TreeItem:
	var s := arbre.create_item(racine)
	s.set_text(0, titre)
	s.set_custom_color(0, Style.ACCENT)
	s.set_custom_font_size(0, 12)
	s.set_selectable(0, false)
	s.set_selectable(1, false)
	s.set_metadata(0, {"genre": "section", "id": cle})
	s.collapsed = false if recherche != null and recherche.text.strip_edges() != "" else bool(_replies.get("section_" + cle, cle != "vaisseau"))
	return s


static func _etiquette_type(p: Dictionary) -> String:
	match String(p["type"]):
		"moteur", "propulseur":
			return "%s kN" % Analyse.nombre(float(p["poussee_n"]) / 1000.0)
		"surface_air":
			return "%s m²" % Analyse.nombre(float(p["surface_m2"]), 1)
		"roue":
			return "roue"
	return ""


func _choix_dans_liste() -> void:
	if _remplissage:
		return
	var it := arbre.get_selected()
	if it == null:
		return
	var m = it.get_metadata(0)
	if m is Dictionary and String(m["genre"]) != "section":
		if selection.get("genre", "") == m["genre"] and selection.get("id", "") == m["id"]:
			return
		choisir(String(m["genre"]), String(m["id"]))


func _repli(it: TreeItem) -> void:
	if _remplissage or (recherche != null and recherche.text.strip_edges() != ""):
		return
	var m = it.get_metadata(0)
	if m is Dictionary:
		var cle := String(m["id"]) if m["genre"] == "categorie" else "section_" + String(m["id"])
		_replies[cle] = it.collapsed


## Met en surbrillance, dans la liste, ce qui est choisi (et déplie sa catégorie).
func _selectionner_dans_liste() -> void:
	if arbre == null or selection.is_empty():
		return
	var it := _trouver_item(arbre.get_root())
	if it == null:
		return
	_remplissage = true
	var parent := it.get_parent()
	while parent != null:
		parent.collapsed = false
		parent = parent.get_parent()
	it.select(0)
	arbre.scroll_to_item(it)
	_remplissage = false


func _trouver_item(it: TreeItem) -> TreeItem:
	if it == null:
		return null
	var m = it.get_metadata(0)
	if m is Dictionary and m.get("genre", "") == selection.get("genre", "") and m.get("id", "") == selection.get("id", ""):
		return it
	var enfant := it.get_first_child()
	while enfant != null:
		var t := _trouver_item(enfant)
		if t != null:
			return t
		enfant = enfant.get_next()
	return null


# =====================================================================
# CAMÉRA : menu de vitesse
# =====================================================================
func _ouvrir_menu_camera(bouton: Button) -> void:
	var pp := PopupPanel.new()
	pp.theme = ui.theme
	pp.transparent_bg = false
	pp.add_theme_stylebox_override("panel", Style.boite(Color(Style.FOND_CLAIR, 1.0), Style.BORD, 6, 12.0))
	var cadre := PanelContainer.new()
	cadre.add_theme_stylebox_override("panel", Style.boite(Color(Style.FOND_CLAIR, 1.0), Color(0, 0, 0, 0), 0, 4.0, 0))
	pp.add_child(cadre)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(300, 0)
	cadre.add_child(v)
	v.add_child(Style.label("VITESSE DE LA CAMÉRA", 12, Style.TEXTE_DOUX))
	var h := HBoxContainer.new()
	v.add_child(h)
	curseur_vitesse = HSlider.new()
	curseur_vitesse.min_value = -2.0    # ×0,25
	curseur_vitesse.max_value = 2.0     # ×4
	curseur_vitesse.step = 0.05
	curseur_vitesse.value = log(camera.vitesse) / log(2.0)
	curseur_vitesse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	curseur_vitesse.custom_minimum_size = Vector2(190, 24)
	h.add_child(curseur_vitesse)
	texte_vitesse = Style.label("", 14)
	texte_vitesse.custom_minimum_size = Vector2(60, 0)
	h.add_child(texte_vitesse)
	curseur_vitesse.value_changed.connect(func(x): regler_vitesse(pow(2.0, x)))
	var defaut := Style.bouton("Vitesse normale (×1)", 13)
	defaut.pressed.connect(func(): curseur_vitesse.value = 0.0)
	v.add_child(defaut)
	var proj := _case("Vue en plan (sans perspective, pavé 5)", camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		func(_on): camera.basculer_projection())
	v.add_child(proj)
	regler_vitesse(camera.vitesse)
	ui.add_child(pp)
	pp.popup_hide.connect(pp.queue_free)
	var r := bouton.get_global_rect()
	pp.popup(Rect2i(Vector2i(int(r.position.x + r.size.x - 320), int(r.position.y + r.size.y + 6)), Vector2i(320, 0)))


func regler_vitesse(x: float) -> void:
	camera.vitesse = clampf(x, 0.25, 4.0)
	if texte_vitesse != null and is_instance_valid(texte_vitesse):
		texte_vitesse.text = "× %s" % Analyse.nombre(camera.vitesse, 2)
	_sauver_reglages()


func _lire_reglages() -> void:
	var f := ConfigFile.new()
	if f.load(REGLAGES) != OK:
		return
	camera.vitesse = clampf(float(f.get_value("camera", "vitesse", 1.0)), 0.25, 4.0)
	case_cg.button_pressed = bool(f.get_value("vue", "centre_gravite", true))
	case_poussees.button_pressed = bool(f.get_value("vue", "poussees", false))
	case_neutre.button_pressed = bool(f.get_value("vue", "fond_neutre", false))


func _sauver_reglages() -> void:
	if camera == null or case_cg == null or case_poussees == null or case_neutre == null:
		return
	var f := ConfigFile.new()
	f.set_value("camera", "vitesse", camera.vitesse)
	f.set_value("vue", "centre_gravite", case_cg.button_pressed)
	f.set_value("vue", "poussees", case_poussees.button_pressed)
	f.set_value("vue", "fond_neutre", case_neutre.button_pressed)
	f.save(REGLAGES)


# =====================================================================
# LANCER
# =====================================================================
func lancer_jeu() -> void:
	if chargement.visible:
		return
	chargement.visible = true
	# deux images pour que l'écran « Chargement » s'affiche avant que le jeu ne se construise
	await get_tree().process_frame
	await get_tree().process_frame
	Partie.lancer_jeu(get_tree(), Partie.DEPART_HANGAR)
