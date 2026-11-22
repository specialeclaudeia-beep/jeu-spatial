extends Node3D
## L'ATELIER : un écran à part du jeu. Le vaisseau est posé dans le hangar, sur ses roues ; on tourne autour
## comme dans Blender, on choisit une pièce (dans la liste de gauche ou en cliquant dessus) et sa fiche
## s'ouvre à droite. Le tableau ingénieur, en haut, donne les chiffres du vaisseau entier.
## « Lancer » charge le jeu (seulement à ce moment : l'atelier est alors libéré), vaisseau posé au sol
## devant le hangar. Dans le jeu, F3 ramène ici.
##
## Étape 3 : on CONSTRUIT. Les pièces toutes faites du catalogue (moteurs, propulseurs, ailes, boîtes,
## réservoirs, poutres, plaques) se posent sur le vaisseau : grille de 10 cm (Ctrl : sans grille), rotation
## par pas de 15° (R, T, E), symétrie gauche-droite (M). On les déplace (G), on les règle dans leur fiche,
## on les duplique (Maj + D), on les supprime (Suppr), et on enlève des modules entiers du chasseur (ailes,
## trains…). Ctrl + Z / Ctrl + Y : annuler / refaire. Une pièce qui ne touche rien est en rouge, et
## « Lancer » est refusé tant qu'il y en a. Plusieurs vaisseaux, chacun son nom, enregistrés dans
## user://vaisseaux/ (Ctrl + S, et tout seul toutes les 2 minutes, au lancement et en quittant).
##
## Étape 4 : l'ANALYSE INGÉNIEUR. Ctrl + clic choisit plusieurs pièces à la fois : la fiche analyse la
## sélection (masse, part, centre, inertie propre, ce que devient le vaisseau sans elle) et une petite boule
## bleue montre son centre de gravité. Un clic sur une tuile du tableau ouvre sa page détaillée : répartition
## des masses, poussées et couple (moteur par moteur et axe par axe, flèche violette du couple), symétrie
## gauche-droite (pièces sans jumelle en orange). La SALLE À PART (touche I, ou « / » du pavé) : la sélection
## (et ce qui est posé dessus) est montrée seule, sur un plateau, avec ses propres chiffres ; on peut y poser
## des pièces dessus, puis « Remettre en place » (I) : tout revient, rien n'a bougé dans le plan.
##
## Étape 5 : le CONTRÔLE AVANT LE VOL (scripts/atelier/controle_vol.gd). La 9e tuile du tableau, « AVANT LE
## VOL », dit si le vaisseau est prêt : vitesse du PC estimée (le jeu dessine désormais chaque pièce du plan,
## et fusionne les pièces posées de même matière), lumière (couleurs impossibles, vitres, pièce devant la
## verrière), au sol (il tient sur ses roues ?), en vol, symétrie. « Lancer » refuse ce qui casserait le
## jeu (pièce qui flotte, vaisseau trop lourd pour le PC) ; pour un simple avertissement, une fenêtre
## explique et propose « Lancer quand même ».
##
## Visuel PROVISOIRE (hangar, menus, couleurs, dessin des pièces posées). La physique, elle, est la vraie :
## après chaque changement, le vaisseau est reconstruit par le même code que le jeu (plan → physique), il se
## repose sur ses roues, et le tableau ingénieur est recalculé.

const Analyse = preload("res://scripts/atelier/analyse.gd")
const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const Plan = preload("res://scripts/atelier/plan.gd")
const Style = preload("res://scripts/atelier/style.gd")
const Hangar = preload("res://scripts/atelier/hangar.gd")
const CameraAtelier = preload("res://scripts/atelier/camera_atelier.gd")
const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const ModeleVaisseau = preload("res://scripts/modele_vaisseau.gd")
const Partie = preload("res://scripts/partie.gd")
const Edition = preload("res://scripts/atelier/edition.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")
const DessinVaisseau = preload("res://scripts/dessin_vaisseau.gd")
const ControleVol = preload("res://scripts/atelier/controle_vol.gd")

const MODELE_EXTERIEUR := "res://modeles/vaisseau/vaisseau_exterieur.glb"
const MODELE_COCKPIT := "res://modeles/vaisseau/cockpit.glb"
const MODELE_DROIDE := "res://modeles/vaisseau/droide.glb"
const REGLAGES := "user://atelier.cfg"
const COUCHE_PIECES := 2                 # couche des formes cliquables (une par maillage du vaisseau)
const COUCHE_SALLE := 3                  # en plus, celles de la salle à part (les seules qu'on touche alors)
const CALQUE_CACHE := 20                 # calque d'affichage des maillages cachés par la salle à part
const RAYON_PLANETE := 600000.0          # comme le jeu : le hangar est sur la planète
const GRAVITE_SURFACE := 9.81
const GRILLE := 0.1                      # m : pas de la grille de pose (Ctrl : pose libre)
const PAS_ROTATION := 15.0               # degrés
const MARGE_CONTACT := 0.04              # m : une pièce à moins de 4 cm d'une autre la touche
const SAUVEGARDE_AUTO_S := 120.0
const AIDE := "Molette (ou Alt + clic) : tourner   ·   Maj + molette : déplacer   ·   Roulette : zoom   ·   Clic : choisir (Ctrl : plusieurs)   ·   I : salle à part   ·   G : déplacer la pièce   ·   Maj + D : dupliquer   ·   Suppr : enlever   ·   Ctrl + Z / Ctrl + Y : annuler / refaire   ·   M : symétrie   ·   Ctrl + S : enregistrer"
const AIDE_POSE := "Clic : poser (Maj + clic : en poser d'autres)   ·   R / T / E : tourner de 15° (Maj : dans l'autre sens)   ·   Ctrl : sans la grille de 10 cm   ·   M : symétrie   ·   Échap ou clic droit : annuler"

var plan
var analyse
var edition                              # le plan en cours de construction (annuler, refaire, enregistrer)
var dessin                               # dessin du vaisseau : modules enlevés cachés, pièces posées dessinées
var dossier_vaisseaux := Edition.DOSSIER # où les vaisseaux sont enregistrés (les tests en prennent un autre)
var vaisseau_pose                        # la physique, posée sur le sol du hangar (donne la pose du modèle)
var hangar
var camera: CameraAtelier
var pilote: Node3D                       # le vaisseau, origine au centre de gravité
var corps: Node3D                        # repère du plan (décalé du centre de gravité)
var exterieur: Node3D
var cockpit: Node3D
var droide: Node3D
var modele
var maillages := {}                      # id de pièce (ou de pièce posée) → [MeshInstance3D]
## Ce qui est choisi : {"genre": piece / ajout / module / categorie / type / matiere, "id": …},
## ou {"genre": "groupe", "id": "groupe", "elements": [{genre, id}…]} (Ctrl + clic : plusieurs à la fois),
## ou {"genre": "analyse", "id": masses / poussees / symetrie} (clic sur une tuile du tableau).
var selection := {}
var salle := {}                          # salle à part : {elements, ids, cles, nom, camera} ; vide = hangar
var _caches_salle := {}                  # maillage caché par la salle à part → [calques, ombre] d'avant
var _corps_salle: Array = []             # formes cliquables du morceau isolé (couche COUCHE_SALLE en plus)
var symetrie := true                     # poser aussi la jumelle de l'autre côté
var flottantes := {}                     # pièces (ou pièces du chasseur) qui ne touchent rien → vrai
var nb_flottantes := 0                   # pièces posées et modules qui flottent
var controle                             # contrôle avant le vol (ControleVol), refait avec le tableau
var fenetre_controle: Control            # fenêtre « Contrôle avant le vol » (ouverte par Lancer), ou null
var _corps_v27 := {}                     # maillage du chasseur → [id de sa pièce, forme cliquable]
var _corps_ajouts := {}                  # pièce posée → [formes cliquables]
var _surlignes: Array = []
var _repere_selection: Node3D            # flèches et points des pièces sans dessin (moteurs, roues…)
var _centre_gravite: Node3D
var _cg_selection: Node3D                # boule bleue : centre de gravité de la sélection (ou du morceau isolé)
var _fleches_poussee: Node3D
var _fleche_couple: Node3D               # flèche courbe violette : couple des moteurs autour du centre de gravité
var _materiau_surligne: StandardMaterial3D
var _materiau_survol: StandardMaterial3D
var _materiau_flotte: StandardMaterial3D
var _materiau_fantome: StandardMaterial3D
var _materiau_fantome_rouge: StandardMaterial3D
var _survol_maillages: Array = []
var _survol_id := ""
var _clic_depart := Vector2(-1, -1)
var _demande_clic := Vector2(-1, -1)
var _demande_clic_ctrl := false          # Ctrl + clic : ajouter à la sélection (ou en retirer)
var _demande_survol := Vector2(-1, -1)
var _souris := Vector2(-1, -1)
var _verifier_dans := -1                 # images de physique avant de chercher les pièces qui flottent
var _rafraichir_demande := false
var pose := {}                           # pièce en train d'être posée (vide : aucune)
var _fantome: Node3D
var _fantome_jumeau: Node3D
var _cache_pendant_pose: Array = []

# interface
var ui: Control
var recherche: LineEdit
var arbre: Tree
var fiche: PanelContainer
var fiche_titre: Label
var fiche_sous_titre: Label
var fiche_outils: VBoxContainer
var fiche_grille: GridContainer
var fiche_note: Label
var fiche_sections: VBoxContainer        # listes de la fiche (pages d'analyse, sélection) : lignes cliquables
var bandeau_salle: PanelContainer
var texte_salle: Label
var bulle: Label
var chargement: ColorRect
var tableau: HBoxContainer
var champ_nom: LineEdit
var texte_etat: Label
var bouton_annuler: Button
var bouton_refaire: Button
var case_symetrie: CheckBox
var avis: PanelContainer
var texte_avis: Label
var aide: Label
var case_cg: CheckBox
var case_poussees: CheckBox
var case_neutre: CheckBox
var curseur_vitesse: HSlider
var texte_vitesse: Label
var minuterie: Timer
var _replies := {}                       # catégories repliées dans la liste (hors recherche)
var _remplissage := false
var _dernier_enregistrement := ""


func _ready() -> void:
	var p = _charger_plan()
	edition = Edition.new(p.donnees, p.chemin)
	edition.change.connect(_demander_rafraichir)
	plan = edition.plan() if p.valide() else p
	analyse = Analyse.new(plan)
	hangar = Hangar.new()
	add_child(hangar)
	_creer_vaisseau()
	camera = CameraAtelier.new()
	add_child(camera)
	camera.cull_mask &= ~(1 << (CALQUE_CACHE - 1))   # ce que la salle à part cache
	camera.make_current()
	camera.cadrer(boite_vaisseau())
	camera.vue("trois_quarts")
	_creer_interface()
	_lire_reglages()
	minuterie = Timer.new()
	minuterie.wait_time = SAUVEGARDE_AUTO_S
	minuterie.autostart = true
	minuterie.timeout.connect(_sauvegarde_auto)
	add_child(minuterie)
	_verifier_dans = 2
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


func _notification(what: int) -> void:
	# fenêtre fermée : on garde le travail
	if what == NOTIFICATION_WM_CLOSE_REQUEST and edition != null and edition.modifie:
		enregistrer()


# =====================================================================
# LE VAISSEAU POSÉ DANS LE HANGAR
# =====================================================================
func _creer_vaisseau() -> void:
	pilote = Node3D.new()
	pilote.name = "Vaisseau"
	add_child(pilote)
	corps = Node3D.new()
	pilote.add_child(corps)
	exterieur = (load(MODELE_EXTERIEUR) as PackedScene).instantiate()
	corps.add_child(exterieur)
	cockpit = (load(MODELE_COCKPIT) as PackedScene).instantiate()
	corps.add_child(cockpit)
	var logement := exterieur.find_child("Point_droide", true, false) as Node3D
	if logement != null and ResourceLoader.exists(MODELE_DROIDE):
		droide = (load(MODELE_DROIDE) as PackedScene).instantiate()
		logement.add_child(droide)
	_poser_physique()
	modele = ModeleVaisseau.new(exterieur, vaisseau_pose)
	modele.poser(vaisseau_pose)
	modele.amortir(vaisseau_pose, 0.0)
	dessin = DessinVaisseau.new(exterieur, modele, droide)
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
	# chaque maillage du chasseur → sa pièce du plan (même nom), et une forme cliquable (faite une fois :
	# elles sont longues à fabriquer ; une pièce enlevée garde la sienne, éteinte)
	for racine in [exterieur, cockpit]:
		for mi in (racine as Node).find_children("*", "MeshInstance3D", true, false):
			if droide != null and droide.is_ancestor_of(mi):
				continue
			var id := _piece_du_maillage(mi as MeshInstance3D, racine == cockpit)
			if id != "":
				_corps_v27[mi] = [id, _forme_cliquable(mi as MeshInstance3D, id)]
	if droide != null and DessinVaisseau.ids_depart().has("Masse_droide"):
		for mi in droide.find_children("*", "MeshInstance3D", true, false):
			_corps_v27[mi] = ["Masse_droide", _forme_cliquable(mi as MeshInstance3D, "Masse_droide")]
	_materiau_surligne = _materiau_calque(Style.SELECTION, 0.42)
	_materiau_survol = _materiau_calque(Color(1, 1, 1), 0.14)
	_materiau_flotte = _materiau_calque(Color(1.0, 0.12, 0.1), 0.55)
	_materiau_fantome = _materiau_calque(Color(0.35, 1.0, 0.55), 0.38)
	_materiau_fantome_rouge = _materiau_calque(Color(1.0, 0.25, 0.2), 0.45)
	_repere_selection = Node3D.new()
	corps.add_child(_repere_selection)
	_creer_centre_gravite()
	_cg_selection = _boule_cg(0.2, Color(0.35, 0.75, 1.0))
	_cg_selection.name = "Centre_gravite_selection"
	_cg_selection.visible = false
	corps.add_child(_cg_selection)
	_fleches_poussee = Node3D.new()
	_fleches_poussee.name = "Fleches_poussee"
	_fleches_poussee.visible = false
	corps.add_child(_fleches_poussee)
	_fleche_couple = Node3D.new()
	_fleche_couple.name = "Fleche_couple"
	_fleche_couple.visible = false
	corps.add_child(_fleche_couple)
	_dessiner()
	_refaire_fleches_poussee()


## Même physique que le jeu, sur la même planète (sol lisse) : le vaisseau se pose sur ses roues et ses
## amortisseurs s'écrasent sous son poids. Endroit : le pôle (le haut = +Y), nez vers −Z (la porte).
func _poser_physique() -> void:
	var v = VaisseauPhysique.new(plan)
	v.gm = GRAVITE_SURFACE * RAYON_PLANETE * RAYON_PLANETE
	v.rayon_planete = RAYON_PLANETE
	v.poser_au_sol(Vector3.UP, Vector3.FORWARD, 2.0)
	vaisseau_pose = v
	pilote.transform = Transform3D(Basis(v.orientation), Vector3(0.0, v.py - RAYON_PLANETE, 0.0))
	corps.position = -v.centre_gravite
	if modele != null:
		modele.poser(v)
		modele.amortir(v, 0.0)


## Le dessin pour le plan actuel : modules enlevés cachés, pièces posées dessinées, formes cliquables.
func _dessiner() -> void:
	dessin.construire(plan, vaisseau_pose)
	maillages.clear()
	_surlignes.clear()
	_survol_maillages.clear()
	for mi in _corps_v27:
		var id: String = _corps_v27[mi][0]
		var corps_clic = _corps_v27[mi][1]
		var la: bool = analyse.a_piece(id)
		if corps_clic != null:
			(corps_clic as StaticBody3D).collision_layer = (1 << (COUCHE_PIECES - 1)) if la else 0
		if la:
			if not maillages.has(id):
				maillages[id] = []
			(maillages[id] as Array).append(mi)
	# pièces écrites dans le plan sans dessin Blender (étape 5) : on les choisit comme les autres pièces,
	# et une pièce posée peut s'y fixer
	for id in dessin.maillages_bruts:
		var liste_b: Array = dessin.maillages_bruts[id]
		maillages[id] = liste_b.duplicate()
		for mi in liste_b:
			_forme_cliquable(mi as MeshInstance3D, id, true)
	_corps_ajouts.clear()
	for id in dessin.maillages_ajouts:
		var liste: Array = dessin.maillages_ajouts[id]
		maillages[id] = liste.duplicate()
		_corps_ajouts[id] = []
		for mi in liste:
			var b := _forme_cliquable(mi as MeshInstance3D, id, true)
			if b != null:
				(_corps_ajouts[id] as Array).append(b)


func _piece_du_maillage(mi: MeshInstance3D, dans_cockpit: bool) -> String:
	var nom := String(mi.name)
	if nom.begins_with("Lueur_") or nom.begins_with("Panache_"):
		return ""
	var ids := DessinVaisseau.ids_depart()
	var n: Node = mi
	while n != null and n != exterieur and n != cockpit:
		if ids.has(String(n.name)):
			return String(n.name)
		n = n.get_parent()
	if dans_cockpit and ids.has("Cockpit_details"):
		return "Cockpit_details"   # boutons, interrupteurs, voyants : les détails du cockpit
	return ""


func _forme_cliquable(mi: MeshInstance3D, id: String, convexe := false) -> StaticBody3D:
	if mi.mesh == null:
		return null
	var forme: Shape3D = mi.mesh.create_convex_shape() if convexe else mi.mesh.create_trimesh_shape()
	if forme == null:
		return null
	var corps_clic := StaticBody3D.new()
	corps_clic.collision_layer = 1 << (COUCHE_PIECES - 1)
	corps_clic.collision_mask = 0
	corps_clic.set_meta("piece", id)
	var cs := CollisionShape3D.new()
	cs.shape = forme
	corps_clic.add_child(cs)
	mi.add_child(corps_clic)
	return corps_clic


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
# APRÈS CHAQUE CHANGEMENT : tout est refait à partir du plan
# =====================================================================
func _demander_rafraichir() -> void:
	if not _rafraichir_demande:
		_rafraichir_demande = true
		_rafraichir.call_deferred()


func _rafraichir() -> void:
	_rafraichir_demande = false
	plan = edition.plan()
	analyse = Analyse.new(plan)
	_poser_physique()
	_dessiner()
	if not salle.is_empty():
		_appliquer_salle()
	_refaire_fleches_poussee()
	_remplir_tableau()
	_maj_barre_haut()
	remplir_catalogue()
	_rechoisir()
	if not pose.is_empty():
		_maj_pose_exclusions()
	_verifier_dans = 2


## Après un changement : la même sélection si elle existe encore (un groupe garde ce qui en reste).
func _rechoisir() -> void:
	if String(selection.get("genre", "")) == "groupe":
		var reste: Array = (selection.get("elements", []) as Array).filter(func(e): return _element_existe(e))
		if reste.size() > 1:
			choisir_groupe(reste, true)
			return
		if reste.size() == 1:
			choisir(String(reste[0]["genre"]), String(reste[0]["id"]), true)
			return
		deselectionner()
	elif _selection_existe():
		choisir(String(selection["genre"]), String(selection["id"]), true)
	else:
		deselectionner()


func _selection_existe() -> bool:
	if String(selection.get("genre", "")) == "groupe":
		return (selection.get("elements", []) as Array).any(func(e): return _element_existe(e))
	return _element_existe(selection)


func _element_existe(e: Dictionary) -> bool:
	var id := String(e.get("id", ""))
	match String(e.get("genre", "")):
		"piece":
			return analyse.a_piece(id)
		"ajout":
			return analyse.ajouts.has(id)
		"module":
			return not analyse.pieces_module(id).is_empty()
		"categorie", "type", "matiere":
			return true
		"analyse":
			return id in ["masses", "poussees", "symetrie"]
	return false


# =====================================================================
# REPÈRES 3D : centre de gravité, flèches de poussée, pièces sans dessin
# =====================================================================
func _creer_centre_gravite() -> void:
	_centre_gravite = _boule_cg(0.32, Color(0.95, 0.85, 0.2))
	_centre_gravite.name = "Centre_gravite"
	pilote.add_child(_centre_gravite)


## La boule à damier des plans d'avion (noir et couleur), visible à travers la coque.
static func _boule_cg(rayon: float, couleur: Color) -> Node3D:
	var n := Node3D.new()
	var s := SphereMesh.new()
	s.radius = rayon
	s.height = rayon * 2.0
	s.radial_segments = 24
	s.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = s
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	# la boule à damier des plans d'avion, visible à travers la coque
	sh.code = """shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_back;
uniform vec3 couleur = vec3(0.95, 0.85, 0.2);
varying vec3 p;
void vertex() { p = VERTEX; }
void fragment() {
	float d = step(0.0, p.x) == step(0.0, p.y) ? 1.0 : 0.0;
	d = step(0.0, p.z) > 0.5 ? d : 1.0 - d;
	ALBEDO = mix(vec3(0.05), couleur, d);
}"""
	m.shader = sh
	m.set_shader_parameter("couleur", Vector3(couleur.r, couleur.g, couleur.b))
	m.render_priority = 3
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	return n


func _refaire_fleches_poussee() -> void:
	for c in _fleches_poussee.get_children():
		_fleches_poussee.remove_child(c)
		c.queue_free()
	for c in _fleche_couple.get_children():
		_fleche_couple.remove_child(c)
		c.queue_free()
	var v = analyse.v
	var somme := Vector3.ZERO
	var dans_salle: Dictionary = salle.get("ids", {})
	for m in v.moteurs:
		if m["role"] == "levage":
			continue
		if not salle.is_empty() and not dans_salle.has(String(m["id"])):
			continue   # salle à part : seulement les moteurs du morceau isolé
		var f: Vector3 = (m["dir_ref"] as Vector3) * float(m["poussee_n"])
		somme += f
		var depart: Vector3 = vaisseau_pose.transformation_articulation(String(m["articulation"])) * (m["pos_ref"] as Vector3)
		var dir: Vector3 = vaisseau_pose.transformation_articulation(String(m["articulation"])).basis * (m["dir_ref"] as Vector3)
		_fleches_poussee.add_child(fleche(depart, dir, longueur_force(float(m["poussee_n"])), Color(1.0, 0.55, 0.15), 1.0, true))
	# la résultante, au centre de gravité (du vaisseau ; dans la salle à part : du morceau)
	var cg: Vector3 = v.centre_gravite if salle.is_empty() else centre_affiche(pieces_salle())
	if somme.length() > 0.0:
		_fleches_poussee.add_child(fleche(cg, somme.normalized(), longueur_force(somme.length()), Color(0.3, 1.0, 0.45), 1.6))
	# le couple des moteurs : une flèche courbe autour de son axe (sens de la main droite), au centre de gravité
	if salle.is_empty():
		var t: Dictionary = analyse.tableau()
		var c: Vector3 = t["couple_moteurs"]
		if c.length() > 100.0:
			var couleur := Color(0.78, 0.45, 1.0) if bool(t["couple_compense"]) else Color(1.0, 0.3, 0.3)
			_fleche_couple.add_child(fleche_couple(v.centre_gravite, c, couleur))


## Rayon de la flèche courbe d'un couple (m) : 1 kN·m → 0,9 m, 100 kN·m → 1,5 m, 10 MN·m → 2,1 m.
static func rayon_couple(nm: float) -> float:
	return clampf(0.9 + 0.3 * log(maxf(nm, 1000.0) / 1000.0) / log(10.0), 0.9, 2.4)


## Flèche courbe (trois quarts de tour et une pointe) autour de l'axe du couple c, centrée sur « centre » :
## elle tourne dans le sens où le couple fait tourner le vaisseau (règle de la main droite).
static func fleche_couple(centre: Vector3, c: Vector3, couleur: Color) -> Node3D:
	var n := Node3D.new()
	var axe := c.normalized()
	var u := (Vector3.UP if absf(axe.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).cross(axe).normalized()
	var w := axe.cross(u)
	var r := rayon_couple(c.length())
	var tube := 0.05
	var fin := TAU * 0.75
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pas := 40
	var cotes := 8
	for i in pas:
		for k in cotes:
			var quad := []
			for di in [0, 1]:
				var a: float = fin * float(i + di) / pas
				var cc: Vector3 = (u * cos(a) + w * sin(a)) * r
				var radial: Vector3 = (u * cos(a) + w * sin(a))
				for dk in [0, 1]:
					var b := TAU * float(k + dk) / cotes
					quad.append(centre + cc + (radial * cos(b) + axe * sin(b)) * tube)
			for j in [0, 2, 1, 1, 2, 3]:
				st.add_vertex(quad[j])
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = couleur
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 2
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	# la pointe, au bout de l'arc, dans le sens de la rotation
	var bout: Vector3 = centre + (u * cos(fin) + w * sin(fin)) * r
	var tangente: Vector3 = (-u * sin(fin) + w * cos(fin)).normalized()
	var pointe := CylinderMesh.new()
	pointe.top_radius = 0.0
	pointe.bottom_radius = 0.16
	pointe.height = 0.42
	pointe.radial_segments = 12
	var mp := MeshInstance3D.new()
	mp.mesh = pointe
	var x := tangente.cross(axe).normalized()
	mp.transform = Transform3D(Basis(x, tangente, x.cross(tangente)), bout + tangente * 0.21)
	mp.material_override = m
	mp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mp)
	return n


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
	var n: Node3D = null
	match t:
		"moteur", "propulseur":
			n = fleche(p["point"], p["direction"], longueur_force(float(p["poussee_n"])), Color(1.0, 0.55, 0.15), 1.0, true)
		"roue":
			var r := float(p.get("rayon_m", 0.18))
			n = _point((p["point"] as Vector3) + Vector3(0, r, 0), r, Color(0.35, 0.8, 1.0, 0.8))
		"contact_coque":
			n = _point(p["point"], 0.12, Color(1.0, 0.35, 0.3, 0.9))
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
			n = mi
		"masse":
			var mp: Dictionary = p["masse_calculee"]
			n = _point(mp["centre"], 0.08 * pow(float(mp["masse"]), 1.0 / 3.0), Color(0.75, 0.55, 1.0, 0.55))
	# une pièce posée sur une aile (repliée dans le hangar) : le repère suit l'aile
	if n != null and String(p.get("articulation", "")) != "":
		var holder := Node3D.new()
		holder.transform = vaisseau_pose.transformation_articulation(String(p["articulation"]))
		holder.add_child(n)
		return holder
	return n


# =====================================================================
# SÉLECTION
# =====================================================================
## Choisir quelque chose : une pièce (genre "piece"), une pièce posée ("ajout"), un module du chasseur
## ("module"), une catégorie de pièces, un type ou une matière. La fiche s'ouvre, les pièces concernées
## s'allument en orange.
func choisir(genre: String, id: String, garder_pose := false) -> void:
	if not garder_pose and not pose.is_empty():
		finir_pose()
	selection = {"genre": genre, "id": id}
	var ids := _montrer_choix()
	match genre:
		"piece":
			_afficher_fiche(_avec_analyse(analyse.fiche_piece(id), ids))
			var p: Dictionary = analyse.piece(id)
			if p.has("module") and not p.has("ajout"):
				var cle := String(p["module"])
				_bouton_fiche("Choisir tout le module « %s »" % analyse.nom_module(cle), func(): choisir("module", cle))
		"ajout":
			_afficher_fiche(_avec_analyse(analyse.fiche_ajout(id), ids))
			_outils_ajout(id)
		"module":
			var enlevable := not Edition.MODULES_INDISPENSABLES.has(id)
			_afficher_fiche(_avec_analyse(analyse.fiche_module(id, enlevable), ids))
			var b := _bouton_fiche("Enlever le module   (Suppr)", func(): supprimer_selection())
			b.disabled = not enlevable
		"type":
			_afficher_fiche(_avec_analyse(analyse.fiche_type(id), ids))
		"matiere":
			_afficher_fiche(_avec_analyse(analyse.fiche_matiere(id), ids))
		"categorie":
			_afficher_fiche(_avec_analyse(fiche_categorie(id), ids))
		"analyse":
			match id:
				"masses":
					_afficher_fiche(analyse.fiche_masses())
				"poussees":
					_afficher_fiche(analyse.fiche_poussees())
				"symetrie":
					_afficher_fiche(analyse.fiche_symetrie())
				"controle":
					if controle == null:
						controle = controle_vol()
					_afficher_fiche(controle.fiche())
	if genre != "analyse":
		_bouton_salle(ids)
	_selectionner_dans_liste()


## Choisir plusieurs choses à la fois (Ctrl + clic) : la fiche analyse la sélection entière.
func choisir_groupe(elements: Array, garder_pose := false) -> void:
	if not garder_pose and not pose.is_empty():
		finir_pose()
	var propres := []
	var vus := {}
	for e in elements:
		var cle := "%s:%s" % [e["genre"], e["id"]]
		if not vus.has(cle):
			vus[cle] = true
			propres.append({"genre": String(e["genre"]), "id": String(e["id"])})
	selection = {"genre": "groupe", "id": "groupe", "elements": propres}
	var ids := _montrer_choix()
	var liste := []
	for e in propres:
		var ids_e := _pieces_de(e)
		var m := float(analyse._masse_de(ids_e)[0])
		liste.append(Analyse.ligne_liste(nom_choix(e), ("%s kg" % Analyse.nombre(m, 1)) if m > 0.0 else "%d pièce%s" % [ids_e.size(), "s" if ids_e.size() > 1 else ""],
			m / maxf(analyse.masse_totale, 1e-9) if m > 0.0 else -1.0, e))
	_afficher_fiche({"titre": "Sélection : %d éléments" % propres.size(), "sous_titre": "%d pièces du plan · Ctrl + clic pour en ajouter ou en retirer" % ids.size(),
		"lignes": analyse.lignes_groupe(ids), "sections": [{"titre": "DANS LA SÉLECTION (clic : choisir celui-là seul)", "liste": liste}],
		"note": "Les chiffres sont ceux de toute la sélection, calculés comme pour le vaisseau entier (pose de référence, ailes ouvertes). La boule bleue est son centre de gravité."})
	var b := _bouton_fiche("Enlever ce qui peut l'être   (Suppr)", supprimer_selection)
	b.disabled = not propres.any(func(e): return e["genre"] == "ajout" or (e["genre"] == "module" and not Edition.MODULES_INDISPENSABLES.has(e["id"])))
	_bouton_salle(ids)
	if arbre != null:
		arbre.deselect_all()


## Ctrl + clic : ajoute à la sélection, ou en retire ce qui y est déjà.
func basculer_dans_selection(genre: String, id: String) -> void:
	var elements := []
	match String(selection.get("genre", "")):
		"groupe":
			elements = (selection["elements"] as Array).duplicate()
		"piece", "ajout", "module", "categorie", "type", "matiere":
			elements = [{"genre": String(selection["genre"]), "id": String(selection["id"])}]
	var cle := "%s:%s" % [genre, id]
	var trouve := -1
	for k in elements.size():
		if "%s:%s" % [elements[k]["genre"], elements[k]["id"]] == cle:
			trouve = k
	if trouve >= 0:
		elements.remove_at(trouve)
	else:
		elements.append({"genre": genre, "id": id})
	if elements.is_empty():
		deselectionner()
	elif elements.size() == 1:
		choisir(String(elements[0]["genre"]), String(elements[0]["id"]))
	else:
		choisir_groupe(elements)


## Surligne ce qui est choisi, montre les repères des pièces sans dessin et la boule bleue de son centre
## de gravité. Renvoie les pièces choisies.
func _montrer_choix() -> Array:
	var ids := pieces_choisies()
	_surligner(ids)
	for c in _repere_selection.get_children():
		_repere_selection.remove_child(c)
		c.queue_free()
	for i in ids:
		var p: Dictionary = analyse.piece(i)
		if not maillages.has(i) and not p.is_empty():
			var r := _repere_piece(p)
			if r != null:
				_repere_selection.add_child(r)
	var genre := String(selection.get("genre", ""))
	var m := float(analyse._masse_de(ids)[0])
	_cg_selection.visible = genre != "analyse" and m > 0.0 and (ids.size() > 1 or genre != "piece") and salle.is_empty()
	if _cg_selection.visible:
		_cg_selection.position = centre_affiche(ids)
	return ids


## Le centre de gravité de ces pièces tel qu'on le voit dans l'atelier (repère du plan) : chaque pièce
## d'une aile repliée est déplacée avec son aile (le plan, lui, compte les ailes ouvertes).
func centre_affiche(ids: Array) -> Vector3:
	var m := 0.0
	var c := Vector3.ZERO
	for i in ids:
		var p: Dictionary = analyse.piece(i)
		var mp: Dictionary = p.get("masse_calculee", {})
		if mp.is_empty() or float(mp["masse"]) <= 0.0:
			continue
		var xf: Transform3D = vaisseau_pose.transformation_articulation(String(p.get("articulation", "")))
		m += float(mp["masse"])
		c += (xf * (mp["centre"] as Vector3)) * float(mp["masse"])
	return c / m if m > 0.0 else analyse.v.centre_gravite


## La fiche, avec en plus l'analyse de la sélection : son inertie propre, et le vaisseau sans elle.
func _avec_analyse(f: Dictionary, ids: Array) -> Dictionary:
	if ids.is_empty():
		return f
	var plus: Array = analyse.lignes_groupe(ids).filter(func(l): return String(l[0]).begins_with("Inertie") or l[0] == "Sans elle")
	var lignes: Array = (f.get("lignes", []) as Array).duplicate()
	lignes.append_array(plus)
	f["lignes"] = lignes
	return f


## Le bouton de la salle à part, dans la fiche (Remettre en place, si on y est déjà).
func _bouton_salle(ids: Array) -> void:
	if not salle.is_empty():
		_bouton_fiche("↩  Remettre en place   (I)", sortir_salle)
	elif not ids.is_empty():
		_bouton_fiche("Emmener seule dans la salle à part   (I)", entrer_salle)


# =====================================================================
# LA SALLE À PART : un morceau seul, pour l'analyser (et le compléter) sans le reste du vaisseau
# =====================================================================
## Emmène ce qui est choisi seul dans la salle à part, avec ce qui est posé dessus. Il ne bouge pas :
## c'est le reste du vaisseau et le hangar qui disparaissent, et un plateau s'allume dessous.
func entrer_salle() -> void:
	if not salle.is_empty():
		return
	var elements := []
	match String(selection.get("genre", "")):
		"groupe":
			elements = (selection["elements"] as Array).duplicate(true)
		"piece", "ajout", "module", "categorie", "type", "matiere":
			elements = [{"genre": String(selection["genre"]), "id": String(selection["id"])}]
	if elements.is_empty() or pieces_choisies().is_empty():
		montrer_avis("Choisis d'abord ce que tu veux emmener dans la salle à part (une pièce, une aile, plusieurs avec Ctrl + clic…), puis I.")
		return
	finir_pose()
	salle = {"elements": elements, "nom": nom_choix(elements[0]) if elements.size() == 1 else "%d éléments" % elements.size(),
		"ids": {}, "cles": {}, "camera": [camera.cible, camera.lacet, camera.tangage, camera.distance]}
	_appliquer_salle()
	if salle.is_empty():
		return
	camera.cadrer(boite_visible())
	_refaire_fleches_poussee()
	_remplir_tableau()
	_rechoisir()


## Remet le morceau à sa place : le vaisseau entier et le hangar reviennent, la caméra aussi.
func sortir_salle() -> void:
	if salle.is_empty():
		return
	finir_pose()
	var cam: Array = salle["camera"]
	salle = {}
	_restaurer_salle()
	hangar.salle_a_part(false)
	_centre_gravite.position = Vector3.ZERO
	camera.cible = cam[0]
	camera.lacet = cam[1]
	camera.tangage = cam[2]
	camera.distance = cam[3]
	camera.appliquer()
	_maj_bandeau_salle()
	_refaire_fleches_poussee()
	_remplir_tableau()
	_rechoisir()


## Cache tout ce qui n'est pas dans la salle à part (refait après chaque changement : une pièce posée sur
## le morceau isolé y entre aussi).
func _appliquer_salle() -> void:
	_restaurer_salle()
	if salle.is_empty():
		return
	salle["elements"] = (salle["elements"] as Array).filter(func(e): return _element_existe(e))
	var ids := {}
	var cles := {}
	for e in salle["elements"]:
		for i in _pieces_de(e):
			ids[i] = true
			cles[String(analyse.piece(i).get("ajout", i))] = true
	# ce qui est posé sur le morceau (et sur ce qui est posé dessus…)
	var encore := true
	while encore:
		encore = false
		for a in analyse.ajouts:
			var sur := String(analyse.ajouts[a].get("fixe_a", ""))
			if not cles.has(a) and sur != "" and cles.has(sur):
				cles[a] = true
				for i in _pieces_de({"genre": "ajout", "id": a}):
					ids[i] = true
				encore = true
	if ids.is_empty():
		sortir_salle()   # le morceau a été enlevé
		return
	salle["ids"] = ids
	salle["cles"] = cles
	var gardes := {}
	for cle in cles:
		for mi in maillages.get(cle, []):
			gardes[mi] = true
	var tous: Array = exterieur.find_children("*", "MeshInstance3D", true, false)
	tous.append_array(cockpit.find_children("*", "MeshInstance3D", true, false))
	for cle in maillages:
		tous.append_array(maillages[cle])
	for mi in tous:
		var m := mi as MeshInstance3D
		if gardes.has(m) or _caches_salle.has(m):
			continue
		_caches_salle[m] = [m.layers, m.cast_shadow]
		m.layers = 1 << (CALQUE_CACHE - 1)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# les formes cliquables du morceau : sur la couche de la salle (les seules que la souris touche alors)
	for mi in _corps_v27:
		if gardes.has(mi) and _corps_v27[mi][1] != null:
			_corps_salle.append(_corps_v27[mi][1])
	for a in cles:
		_corps_salle.append_array(_corps_ajouts.get(a, []))
	for b in _corps_salle:
		if is_instance_valid(b) and (b as StaticBody3D).collision_layer != 0:
			(b as StaticBody3D).collision_layer |= 1 << (COUCHE_SALLE - 1)
	# la boule jaune : le centre de gravité du morceau
	_centre_gravite.position = corps.transform * centre_affiche(pieces_salle())
	var bo := boite_visible()
	hangar.salle_a_part(true, bo.get_center(), bo.position.y - 0.25, maxf(bo.size.x, bo.size.z) * 0.62 + 1.0)
	_maj_bandeau_salle()


func _restaurer_salle() -> void:
	for mi in _caches_salle:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).layers = _caches_salle[mi][0]
			(mi as MeshInstance3D).cast_shadow = _caches_salle[mi][1]
	_caches_salle.clear()
	for b in _corps_salle:
		if is_instance_valid(b):
			(b as StaticBody3D).collision_layer &= ~(1 << (COUCHE_SALLE - 1))
	_corps_salle.clear()


## Les pièces du plan qui sont dans la salle à part (vide : on est dans le hangar).
func pieces_salle() -> Array:
	return (salle.get("ids", {}) as Dictionary).keys()


## Ce qu'on voit (repère du monde) : le vaisseau entier, ou le morceau de la salle à part.
func boite_visible() -> AABB:
	if salle.is_empty():
		return boite_vaisseau()
	var b := AABB()
	var premiere := true
	for cle in salle["cles"]:
		for mi in maillages.get(cle, []):
			var m := mi as MeshInstance3D
			if not is_instance_valid(m) or not m.is_visible_in_tree() or m.mesh == null:
				continue
			var bm: AABB = m.global_transform * m.get_aabb()
			b = bm if premiere else b.merge(bm)
			premiere = false
	# les pièces sans dessin (moteurs, roues…) : leur point
	for i in salle["ids"]:
		var p: Dictionary = analyse.piece(i)
		if p.is_empty() or maillages.has(String(p.get("ajout", i))):
			continue
		var pt: Vector3 = p.get("point", p["masse_calculee"]["centre"])
		pt = vaisseau_pose.transformation_articulation(String(p.get("articulation", ""))) * pt
		var bp := AABB(corps.global_transform * pt - Vector3.ONE * 0.4, Vector3.ONE * 0.8)
		b = bp if premiere else b.merge(bp)
		premiere = false
	if premiere:
		return AABB(corps.global_transform * centre_affiche(pieces_salle()) - Vector3.ONE, Vector3.ONE * 2.0)
	return b


## Bandeau du haut de la vue : on est dans la salle à part (et comment en sortir).
func _bandeau_salle() -> Control:
	bandeau_salle = PanelContainer.new()
	bandeau_salle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bandeau_salle.add_theme_stylebox_override("panel", Style.boite(Color(0.05, 0.1, 0.16, 0.92), Style.ACCENT, 6, 8.0))
	bandeau_salle.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bandeau_salle.add_child(h)
	texte_salle = Style.label("", 15, Color.WHITE)
	texte_salle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(texte_salle)
	var b := Style.bouton("↩  Remettre en place   (I)", 14)
	b.tooltip_text = "Le morceau retourne sur le vaisseau (ce que tu as posé dessus aussi). Échap marche aussi."
	b.pressed.connect(sortir_salle)
	h.add_child(b)
	return bandeau_salle


func _maj_bandeau_salle() -> void:
	if bandeau_salle == null:
		return
	bandeau_salle.visible = not salle.is_empty()
	if salle.is_empty():
		return
	var ids := pieces_salle()
	var m := float(analyse._masse_de(ids)[0])
	texte_salle.text = "SALLE À PART  ·  %s  ·  %s kg  ·  %d pièce%s" % [String(salle["nom"]), Analyse.nombre(m, 1), ids.size(), "s" if ids.size() > 1 else ""]


## Nom affiché de ce qu'on peut choisir ({genre, id}).
func nom_choix(e: Dictionary) -> String:
	var id := String(e["id"])
	match String(e["genre"]):
		"piece":
			return Analyse.nom_lisible(analyse.piece(id))
		"ajout":
			return analyse.nom_element(id)
		"module":
			return "Module " + analyse.nom_module(id)
		"categorie":
			return Analyse.titre_categorie(id)
		"type":
			return Analyse._majuscule(String(Catalogue.TYPES[id]["nom"])) if Catalogue.TYPES.has(id) else id
		"matiere":
			return Analyse._majuscule(String(Catalogue.MATIERES[id]["nom"])) if Catalogue.MATIERES.has(id) else id
	return id


func deselectionner() -> void:
	selection = {}
	_surligner([])
	for c in _repere_selection.get_children():
		_repere_selection.remove_child(c)
		c.queue_free()
	if _cg_selection != null:
		_cg_selection.visible = false
	if fiche != null:
		fiche.visible = false
	if arbre != null:
		arbre.deselect_all()


## Les pièces du plan concernées par la sélection actuelle.
func pieces_choisies() -> Array:
	match String(selection.get("genre", "")):
		"groupe":
			var vus := {}
			var ids := []
			for e in selection.get("elements", []):
				for i in _pieces_de(e):
					if not vus.has(i):
						vus[i] = true
						ids.append(i)
			return ids
		"analyse":
			match String(selection.get("id", "")):
				"symetrie":
					return (analyse.symetrie()["sans_jumelle"] as Array).duplicate()
				"poussees":
					return plan.pieces.filter(func(p): return p["type"] == "moteur").map(func(p): return p["id"])
				"controle":
					# en orange : les pièces de ce qui bloque ou avertit
					var vus := {}
					var ids := []
					if controle != null:
						for e in controle.a_montrer():
							var c: Dictionary = e["choix"]
							for el in (c["elements"] if String(c.get("genre", "")) == "groupe" else ([c] if not c.is_empty() else [])):
								for i in _pieces_de(el):
									if not vus.has(i):
										vus[i] = true
										ids.append(i)
					return ids
			return []
	return _pieces_de(selection)


## Les pièces du plan d'un élément qu'on peut choisir ({genre, id}).
func _pieces_de(e: Dictionary) -> Array:
	var genre := String(e.get("genre", ""))
	var id := String(e.get("id", ""))
	var ids := []
	for p in plan.pieces:
		var ok := false
		match genre:
			"piece":
				ok = p["id"] == id
			"ajout":
				ok = String(p.get("ajout", "")) == id
			"module":
				ok = not p.has("ajout") and String(p.get("module", "")) == id
			"categorie":
				ok = Analyse.categorie(p) == id
			"type":
				ok = p["type"] == id
			"matiere":
				ok = p.get("matiere", null) != null and String(p["matiere"]) == id
		if ok:
			ids.append(p["id"])
	return ids


## Orange sur ce qui est choisi ; rouge sur ce qui flotte (sauf si c'est choisi).
func _surligner(ids: Array) -> void:
	for mi in _surlignes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = null
	_surlignes.clear()
	var vus := {}
	for i in ids:
		var cle := String(analyse.piece(i).get("ajout", i))
		if vus.has(cle):
			continue
		vus[cle] = true
		for mi in maillages.get(cle, []):
			(mi as MeshInstance3D).material_overlay = _materiau_surligne
			_surlignes.append(mi)
	for cle in flottantes:
		if vus.has(cle):
			continue
		for mi in maillages.get(cle, []):
			(mi as MeshInstance3D).material_overlay = _materiau_flotte
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


## Le rayon de la souris dans la vue 3D (contre les formes cliquables du vaisseau).
func _rayon(pos_ecran: Vector2, exclure: Array = []) -> Dictionary:
	return _rayon_monde(camera.project_ray_origin(pos_ecran), camera.project_ray_normal(pos_ecran), exclure)


func _rayon_monde(depart: Vector3, dir: Vector3, exclure: Array = []) -> Dictionary:
	# dans la salle à part, on ne touche que le morceau isolé
	var couche := COUCHE_PIECES if salle.is_empty() else COUCHE_SALLE
	var q := PhysicsRayQueryParameters3D.create(depart, depart + dir.normalized() * 500.0, 1 << (couche - 1), exclure)
	q.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(q)


## Clic dans la vue 3D : la pièce sous la souris (ou rien). Pour une pièce posée : l'id de la pièce posée.
func piece_sous(pos_ecran: Vector2) -> String:
	var r := _rayon(pos_ecran)
	if r.is_empty():
		return ""
	var c = r["collider"]
	return String(c.get_meta("piece", "")) if c != null else ""


# =====================================================================
# ENTRÉES : caméra, clic, survol, raccourcis
# =====================================================================
func _unhandled_input(e: InputEvent) -> void:
	if chargement != null and chargement.visible:
		return
	var h := get_viewport().get_visible_rect().size.y
	if camera.traiter(e, h):
		get_viewport().set_input_as_handled()
		bulle.visible = false
		return
	if e is InputEventMouseButton:
		var b := e as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_LEFT:
			if b.pressed:
				_clic_depart = b.position
			elif _clic_depart.x >= 0.0 and b.position.distance_to(_clic_depart) < 5.0:
				_demande_clic = b.position
				_demande_clic_ctrl = b.ctrl_pressed or b.meta_pressed
				_clic_depart = Vector2(-1, -1)
			get_viewport().set_input_as_handled()
		elif b.button_index == MOUSE_BUTTON_RIGHT and b.pressed and not pose.is_empty():
			finir_pose()
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_souris = (e as InputEventMouseMotion).position
		_demande_survol = _souris
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		var ctrl := k.ctrl_pressed or k.meta_pressed
		if fenetre_controle != null:
			if k.keycode == KEY_ESCAPE:   # la fenêtre du contrôle avant le vol est ouverte : Échap la ferme
				fermer_fenetre_controle()
			get_viewport().set_input_as_handled()
			return
		match k.keycode:
			KEY_ESCAPE:
				if not pose.is_empty():
					finir_pose()
				elif selection.is_empty() and not salle.is_empty():
					sortir_salle()
				else:
					deselectionner()
			KEY_I, KEY_KP_DIVIDE, KEY_SLASH:
				if not salle.is_empty():
					sortir_salle()
				else:
					entrer_salle()
			KEY_KP_PERIOD, KEY_F:
				cadrer_selection()
			KEY_HOME:
				camera.cadrer(boite_visible())
			KEY_Z:
				if ctrl:
					if k.shift_pressed:
						refaire()
					else:
						annuler()
			KEY_Y:
				if ctrl:
					refaire()
			KEY_S:
				if ctrl:
					enregistrer()
			KEY_DELETE, KEY_BACKSPACE:
				supprimer_selection()
			KEY_G:
				deplacer_selection()
			KEY_D:
				if k.shift_pressed or ctrl:
					dupliquer_selection()
			KEY_M:
				case_symetrie.button_pressed = not case_symetrie.button_pressed
			KEY_R, KEY_T, KEY_E:
				if not pose.is_empty():
					var s := -1 if k.shift_pressed else 1
					var r: Vector3i = pose["rot"]
					match k.keycode:
						KEY_R:
							r.x += s
						KEY_T:
							r.y += s
						KEY_E:
							r.z += s
					pose["rot"] = r
					_demande_survol = _souris
			_:
				return
		get_viewport().set_input_as_handled()


## Les rayons de clic et de survol passent par la physique de Godot : on les lance ici, au bon moment.
func _physics_process(_delta: float) -> void:
	if _demande_clic.x >= 0.0:
		var pos := _demande_clic
		_demande_clic = Vector2(-1, -1)
		if not pose.is_empty():
			calculer_pose(pos)
			valider_pose()
		else:
			var id := piece_sous(pos)
			var genre := "ajout" if analyse.ajouts.has(id) else "piece"
			if id == "":
				if not _demande_clic_ctrl:
					deselectionner()
			elif _demande_clic_ctrl:
				basculer_dans_selection(genre, id)
			else:
				choisir(genre, id)
	if _demande_survol.x >= 0.0:
		var pos := _demande_survol
		_demande_survol = Vector2(-1, -1)
		if not pose.is_empty():
			if not camera.glisse_en_cours():
				calculer_pose(pos)
			bulle.visible = false
		else:
			var id := "" if camera.glisse_en_cours() else piece_sous(pos)
			_survoler(id, pos)
	if _verifier_dans > 0:
		_verifier_dans -= 1
	elif _verifier_dans == 0:
		_verifier_dans = -1
		verifier_flottantes()


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
	if id == "":
		return
	if analyse.ajouts.has(id):
		var e: Dictionary = analyse.ajouts[id]
		bulle.text = "%s · %s%s" % [String(e.get("nom", id)), Pieces.resume(String(e["modele"]), e.get("reglages", {})),
			"   (ne touche rien)" if flottantes.has(id) else ""]
	else:
		var p: Dictionary = analyse.piece(id)
		if p.is_empty():
			bulle.visible = false
			return
		var m := float(p["masse_calculee"]["masse"])
		bulle.text = "%s · %s kg" % [Analyse.nom_lisible(p), Analyse.nombre(m, 1)]
	bulle.position = pos + Vector2(16, 14)


func cadrer_selection() -> void:
	var ids := pieces_choisies()
	var b := AABB()
	var premiere := true
	var vus := {}
	for i in ids:
		var cle := String(analyse.piece(i).get("ajout", i))
		if not vus.has(cle):
			vus[cle] = true
			for mi in maillages.get(cle, []):
				var bm: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
				b = bm if premiere else b.merge(bm)
				premiere = false
		var p: Dictionary = analyse.piece(i)
		if not maillages.has(cle) and not p.is_empty():
			var pt: Vector3 = p.get("point", p["masse_calculee"]["centre"])
			var bp := AABB(corps.global_transform * pt - Vector3.ONE * 0.5, Vector3.ONE)
			b = bp if premiere else b.merge(bp)
			premiere = false
	if not premiere:
		camera.cadrer(b)


# =====================================================================
# POSER UNE PIÈCE TOUTE FAITE
# =====================================================================
## Commence à poser une pièce du catalogue (deplace = "" : une nouvelle ; sinon l'id d'une pièce posée
## qu'on déplace). Un fantôme suit la souris : vert s'il touche le vaisseau, rouge sinon.
func commencer_pose(modele_piece: String, reglages: Dictionary, deplace := "") -> void:
	if not Pieces.existe(modele_piece):
		return
	if not pose.is_empty():
		finir_pose()
	if deplace == "":
		deselectionner()
	var base := Basis.IDENTITY
	if deplace != "" and analyse.ajouts.has(deplace):
		base = Edition.xf_de(analyse.ajouts[deplace]).basis
		if base.determinant() < 0.0:
			base = Edition.MIROIR * base   # côté droit : la même pièce vue sans miroir
	pose = {"modele": modele_piece, "reglages": Pieces.reglages_complets(modele_piece, reglages), "deplace": deplace,
		"rot": Vector3i.ZERO, "base": base, "xf": Transform3D.IDENTITY, "fixe_a": "", "articulation": "",
		"touche": false, "pret": false, "exclure": []}
	_fantome = _creer_fantome(modele_piece, pose["reglages"])
	_fantome_jumeau = _creer_fantome(modele_piece, pose["reglages"])
	corps.add_child(_fantome)
	corps.add_child(_fantome_jumeau)
	_fantome.visible = false
	_fantome_jumeau.visible = false
	# la pièce déplacée (et sa jumelle) disparaît pendant qu'on la déplace
	_cache_pendant_pose.clear()
	if deplace != "":
		for i in [deplace, String(analyse.ajouts[deplace].get("symetrique", ""))]:
			if dessin.ajouts.has(i):
				(dessin.ajouts[i] as Node3D).visible = false
				_cache_pendant_pose.append(i)
	_maj_pose_exclusions()
	aide.text = AIDE_POSE
	if fiche != null and deplace == "":
		_afficher_fiche({"titre": Pieces.nom(modele_piece), "sous_titre": "pièce à poser · " + Pieces.resume(modele_piece, pose["reglages"]),
			"lignes": [], "note": String(Pieces.MODELES[modele_piece]["description"]) + "\n\nClique sur le vaisseau pour la poser. Elle se colle à la surface sous la souris, sur une grille de 10 cm (Ctrl : sans grille). R, T, E : la tourner de 15°."})
	_demande_survol = _souris if _souris.x >= 0.0 else get_viewport().get_visible_rect().size * 0.5


func _maj_pose_exclusions() -> void:
	var ex := []
	for i in _cache_pendant_pose:
		for b in _corps_ajouts.get(i, []):
			if is_instance_valid(b):
				ex.append((b as StaticBody3D).get_rid())
		if dessin.ajouts.has(i):
			(dessin.ajouts[i] as Node3D).visible = false
	pose["exclure"] = ex


## Arrête de poser (Échap, clic droit, ou après la pose).
func finir_pose() -> void:
	for f in [_fantome, _fantome_jumeau]:
		if f != null and is_instance_valid(f):
			f.get_parent().remove_child(f)
			f.queue_free()
	_fantome = null
	_fantome_jumeau = null
	for i in _cache_pendant_pose:
		if dessin.ajouts.has(i) and is_instance_valid(dessin.ajouts[i]):
			(dessin.ajouts[i] as Node3D).visible = true
	_cache_pendant_pose.clear()
	pose = {}
	if aide != null:
		aide.text = AIDE
	if arbre != null:
		var it := arbre.get_selected()
		if it != null and it.get_metadata(0) is Dictionary and String(it.get_metadata(0)["genre"]) == "modele":
			arbre.deselect_all()
	if selection.is_empty() and fiche != null:
		fiche.visible = false


func _creer_fantome(modele_piece: String, reglages: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = "Fantome"
	for f in Pieces.dessin(modele_piece, reglages):
		if String(f["role"]) != "":
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = DessinVaisseau._forme(String(f["forme"]), f["taille"])
		mi.transform = f["xf"]
		mi.material_override = _materiau_fantome
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	return n


## La place de la pièce sous la souris : collée à la surface touchée (repère du plan, pose de référence).
func calculer_pose(pos_ecran: Vector2) -> void:
	calculer_pose_rayon(camera.project_ray_origin(pos_ecran), camera.project_ray_normal(pos_ecran))


## Pareil, pour un rayon donné (repère du monde) : sert aussi aux tests.
func calculer_pose_rayon(depart: Vector3, dir_cam: Vector3) -> void:
	if pose.is_empty():
		return
	dir_cam = dir_cam.normalized()
	var r := _rayon_monde(depart, dir_cam, pose["exclure"])
	var vers_corps := corps.global_transform.affine_inverse()
	var support := ""
	var art := ""
	var point: Vector3
	var n: Vector3
	if not r.is_empty():
		support = String(r["collider"].get_meta("piece", ""))
		art = _articulation_de(support)
		# une aile repliée dans le hangar : on ramène le point dans la pose du plan (ailes ouvertes)
		var a_inv: Transform3D = vaisseau_pose.transformation_articulation(art).affine_inverse()
		point = a_inv * (vers_corps * (r["position"] as Vector3))
		n = (a_inv.basis * (vers_corps.basis * (r["normal"] as Vector3))).normalized()
		var d := (a_inv.basis * (vers_corps.basis * dir_cam)).normalized()
		if n.dot(d) > 0.0:
			n = -n   # face vue de dos : la normale vers la caméra
	else:
		# dans le vide : sur le plan qui passe par le centre de gravité, face à la caméra
		var pl := Plane(-dir_cam, pilote.global_position)
		var x = pl.intersects_ray(depart, dir_cam)
		if x == null:
			return
		point = vers_corps * (x as Vector3)
		n = (vers_corps.basis * -dir_cam).normalized()
	if not Input.is_key_pressed(KEY_CTRL):
		point = sur_grille(point, n)
	var b := orientation_pose(String(pose["modele"]), n, pose["rot"], pose["base"])
	var bb := Pieces.boite(String(pose["modele"]), pose["reglages"])
	var h := -INF
	for k in 8:
		h = maxf(h, -((b * bb.get_endpoint(k)).dot(n)))
	pose["xf"] = Transform3D(b, point + n * h)
	pose["fixe_a"] = support
	pose["articulation"] = art
	pose["touche"] = support != ""
	pose["pret"] = true
	_placer_fantomes()


## Grille de 10 cm le long de la surface (le point reste sur le plan tangent).
static func sur_grille(point: Vector3, n: Vector3) -> Vector3:
	var s := point.snapped(Vector3.ONE * GRILLE)
	return s - n * n.dot(s - point)


## Orientation de la pièce posée : son axe d'attache suit la normale de la surface (« garde » : elle garde
## son orientation), puis les pas de 15° demandés (R autour de la normale, T autour de l'axe gauche-droite,
## E autour de l'axe avant-arrière).
static func orientation_pose(modele_piece: String, n: Vector3, rot: Vector3i, base := Basis.IDENTITY) -> Basis:
	var b := base
	match Pieces.attache(modele_piece):
		"x":
			b = base_alignee(0, n)
		"y":
			b = base_alignee(1, n)
		"z":
			b = base_alignee(2, n)
	var a := Vector3(rot) * deg_to_rad(PAS_ROTATION)
	return Basis(n.normalized(), a.x) * Basis(Vector3.RIGHT, a.y) * Basis(Vector3.BACK, a.z) * b


## Repère dont l'axe n° axe est n ; les deux autres suivent au mieux les axes du vaisseau (sans les
## retourner : une aile posée à gauche est l'image en miroir d'une aile posée à droite).
static func base_alignee(axe: int, n: Vector3) -> Basis:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var cols := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	cols[axe] = n.normalized()
	var autres := [0, 1, 2].filter(func(k): return k != axe)
	autres.sort_custom(func(i, j): return absf((axes[i] as Vector3).dot(n)) < absf((axes[j] as Vector3).dot(n)))
	var a: int = autres[0]
	var c: int = autres[1]
	var u: Vector3 = (axes[a] as Vector3) - cols[axe] * (axes[a] as Vector3).dot(cols[axe])
	u = u.normalized()
	cols[a] = u
	var w: Vector3 = (axes[c] as Vector3) - cols[axe] * (axes[c] as Vector3).dot(cols[axe]) - u * (axes[c] as Vector3).dot(u)
	if w.length() > 1e-3:
		cols[c] = w.normalized()
	else:
		cols[c] = (cols[axe] as Vector3).cross(u)
		if Basis(cols[0], cols[1], cols[2]).determinant() < 0.0:
			cols[c] = -cols[c]
	return Basis(cols[0], cols[1], cols[2])


func _articulation_de(support: String) -> String:
	if analyse.ajouts.has(support):
		return String(analyse.ajouts[support].get("articulation", ""))
	return String(analyse.piece(support).get("articulation", ""))


func _placer_fantomes() -> void:
	if _fantome == null:
		return
	var xf: Transform3D = pose["xf"]
	var art := String(pose["articulation"])
	_fantome.transform = vaisseau_pose.transformation_articulation(art) * xf
	_fantome.visible = true
	var m: StandardMaterial3D = _materiau_fantome if bool(pose["touche"]) else _materiau_fantome_rouge
	for c in _fantome.get_children():
		(c as MeshInstance3D).material_override = m
	# la jumelle, de l'autre côté
	var jumelle := absf(xf.origin.x) > Edition.SUR_L_AXE and (symetrie if String(pose["deplace"]) == "" \
		else String(analyse.ajouts.get(pose["deplace"], {}).get("symetrique", "")) != "")
	_fantome_jumeau.visible = jumelle
	if jumelle:
		var art2: String = edition.nom_miroir(art)
		_fantome_jumeau.transform = vaisseau_pose.transformation_articulation(art2) * Edition.miroir(xf)
		for c in _fantome_jumeau.get_children():
			(c as MeshInstance3D).material_override = m


## Pose la pièce là où est le fantôme.
func valider_pose() -> void:
	if pose.is_empty() or not bool(pose.get("pret", false)):
		return
	var p := pose
	var deplace := String(p["deplace"])
	if deplace != "":
		selection = {"genre": "ajout", "id": deplace}
		finir_pose()
		edition.placer(deplace, p["xf"], String(p["fixe_a"]), String(p["articulation"]))
		return
	var encore := Input.is_key_pressed(KEY_SHIFT)
	var ids: Array = edition.ajouter(String(p["modele"]), p["reglages"], p["xf"], String(p["fixe_a"]), String(p["articulation"]), symetrie)
	if ids.is_empty():
		return
	selection = {"genre": "ajout", "id": String(ids[0])}
	if not encore:
		finir_pose()


# =====================================================================
# MODIFIER : enlever, déplacer, dupliquer, régler, annuler
# =====================================================================
func supprimer_selection() -> void:
	var genre := String(selection.get("genre", ""))
	var id := String(selection.get("id", ""))
	match genre:
		"groupe":
			# tout ce qui peut s'enlever d'un coup (pièces posées, modules du chasseur sauf le cockpit) ; un seul
			# Ctrl + Z remet tout
			var a_enlever := []
			var gardes := 0
			for e in selection["elements"]:
				if e["genre"] == "ajout":
					a_enlever.append(String(e["id"]))
				elif e["genre"] == "module" and not Edition.MODULES_INDISPENSABLES.has(e["id"]):
					a_enlever.append("module:" + String(e["id"]))
				else:
					gardes += 1
			if a_enlever.is_empty():
				montrer_avis("Rien à enlever : choisis des pièces posées ou des modules du chasseur (le cockpit reste).")
				return
			finir_pose()
			edition.supprimer(a_enlever)
			selection = {}
			montrer_avis("%d élément%s enlevé%s (Ctrl + Z pour tout remettre)%s." % [a_enlever.size(), "s" if a_enlever.size() > 1 else "",
				"s" if a_enlever.size() > 1 else "", (" ; %d gardé%s (pièce du chasseur ou cockpit)" % [gardes, "s" if gardes > 1 else ""]) if gardes > 0 else ""])
		"ajout":
			finir_pose()
			edition.supprimer([id])
			selection = {}
		"module":
			if Edition.MODULES_INDISPENSABLES.has(id):
				montrer_avis("Le cockpit ne peut pas être enlevé : le pilote est dedans.")
				return
			finir_pose()
			var nom: String = analyse.nom_module(id)
			edition.supprimer(["module:" + id])
			selection = {}
			montrer_avis("Module « %s » enlevé (Ctrl + Z pour le remettre)." % nom)
		"piece":
			var p: Dictionary = analyse.piece(id)
			if p.has("ajout"):
				selection = {"genre": "ajout", "id": String(p["ajout"])}
				supprimer_selection()
			elif p.has("module"):
				montrer_avis("Pour enlever une pièce du chasseur, choisis son module (bouton dans la fiche), puis Suppr.")


func deplacer_selection() -> void:
	var id := _ajout_choisi()
	if id != "":
		var e: Dictionary = analyse.ajouts[id]
		commencer_pose(String(e["modele"]), e.get("reglages", {}), id)


func dupliquer_selection() -> void:
	var id := _ajout_choisi()
	if id != "":
		var e: Dictionary = analyse.ajouts[id]
		commencer_pose(String(e["modele"]), e.get("reglages", {}))


func _ajout_choisi() -> String:
	var genre := String(selection.get("genre", ""))
	var id := String(selection.get("id", ""))
	if genre == "ajout" and analyse.ajouts.has(id):
		return id
	if genre == "piece" and analyse.piece(id).has("ajout"):
		return String(analyse.piece(id)["ajout"])
	return ""


func annuler() -> void:
	finir_pose()
	if not edition.annuler():
		montrer_avis("Rien à annuler.")


func refaire() -> void:
	finir_pose()
	if not edition.refaire():
		montrer_avis("Rien à refaire.")


# =====================================================================
# PIÈCES QUI FLOTTENT
# =====================================================================
## Cherche ce qui ne touche rien : les pièces posées qui ne sont reliées au chasseur par aucune chaîne de
## pièces qui se touchent (à 4 cm près), et les modules du chasseur qui ne tiennent plus (sans fuselage,
## tout le reste tombe, sauf le cockpit). En rouge ; « Lancer » est refusé tant qu'il y en a.
func verifier_flottantes() -> void:
	var avant: Array = flottantes.keys()
	avant.sort()
	flottantes = {}
	nb_flottantes = 0
	var tenus := {}
	var fuselage: bool = not analyse.pieces_module("fuselage").is_empty()
	var mods: Dictionary = edition.modules()
	for cle in mods:
		var ids: Array = analyse.pieces_module(cle)
		if fuselage or cle == "fuselage" or Edition.MODULES_INDISPENSABLES.has(cle):
			for i in ids:
				tenus[i] = true
		else:
			nb_flottantes += 1
			for i in ids:
				flottantes[i] = true
	for p in plan.pieces:
		if not p.has("ajout") and not p.has("module"):
			tenus[String(p["id"])] = true   # pièce d'un plan fait à la main, sans module
	var contacts := {}
	var espace := get_world_3d().direct_space_state
	for id in analyse.ajouts:
		contacts[id] = contacts_de(id, espace)
	var encore := true
	while encore:
		encore = false
		for id in contacts:
			if tenus.has(id):
				continue
			for w in contacts[id]:
				if tenus.has(w):
					tenus[id] = true
					encore = true
					break
	for id in contacts:
		if not tenus.has(id):
			flottantes[id] = true
			nb_flottantes += 1
	var apres: Array = flottantes.keys()
	apres.sort()
	if apres != avant:
		# la liste et la fiche disent aussi ce qui ne touche rien (en rouge), la tuile AVANT LE VOL aussi
		_remplir_tableau()
		remplir_catalogue()
		if not selection.is_empty() and _selection_existe():
			choisir(String(selection["genre"]), String(selection["id"]), true)
	_surligner(pieces_choisies())
	_maj_barre_haut()


## Ce que touche une pièce posée (ids des pièces du chasseur ou des autres pièces posées).
func contacts_de(id: String, espace: PhysicsDirectSpaceState3D) -> Array:
	var e: Dictionary = analyse.ajouts[id]
	var bb := Pieces.boite(String(e["modele"]), e.get("reglages", {}))
	var xf: Transform3D = corps.global_transform * vaisseau_pose.transformation_articulation(String(e.get("articulation", ""))) * Edition.xf_de(e)
	var centre := xf * bb.get_center()
	var b := xf.basis.orthonormalized()
	if b.determinant() < 0.0:
		b = b * Edition.MIROIR   # une boîte est la même vue en miroir
	var exclure := []
	for c in _corps_ajouts.get(id, []):
		exclure.append((c as StaticBody3D).get_rid())
	var forme := BoxShape3D.new()
	forme.size = bb.size + Vector3.ONE * (2.0 * MARGE_CONTACT)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = forme
	q.transform = Transform3D(b, centre)
	q.collision_mask = 1 << (COUCHE_PIECES - 1)
	q.exclude = exclure
	var voisins := {}
	for r in espace.intersect_shape(q, 64):
		var c = r.get("collider")
		if c != null:
			var w := String(c.get_meta("piece", ""))
			if w != "" and w != id:
				voisins[w] = true
	if voisins.is_empty():
		# dedans une coque creuse (posée à l'intérieur du fuselage) : touchée de tous les côtés à la fois
		var autour := {}
		var coups := 0
		for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
			var rq := PhysicsRayQueryParameters3D.create(centre, centre + b * d * 30.0, 1 << (COUCHE_PIECES - 1), exclure)
			var rr := espace.intersect_ray(rq)
			if not rr.is_empty() and rr["collider"] != null:
				coups += 1
				autour[String(rr["collider"].get_meta("piece", ""))] = true
		if coups == 6:
			voisins = autour
	return voisins.keys()


# =====================================================================
# ENREGISTRER
# =====================================================================
func enregistrer() -> bool:
	if edition == null:
		return false
	if not edition.modifie and edition.chemin != "":
		_maj_barre_haut()
		return true
	if not edition.modifie and edition.chemin == "":
		return true   # vaisseau du jeu pas changé : rien à écrire
	# ce que l'atelier voit flotter : l'accueil (« Jouer ») le relit pour son contrôle avant le vol
	var vues: Array = flottantes.keys()
	vues.sort()
	edition.donnees["atelier"] = {"flottantes": vues}
	var err: Error = edition.enregistrer(dossier_vaisseaux)
	if err != OK:
		montrer_avis("Impossible d'enregistrer (%s)." % error_string(err))
		return false
	Partie.choisir_plan(edition.chemin)
	_dernier_enregistrement = Time.get_time_string_from_system().substr(0, 5).replace(":", " h ")
	_maj_barre_haut()
	return true


func enregistrer_copie() -> void:
	var err: Error = edition.enregistrer_copie(dossier_vaisseaux)
	if err != OK:
		montrer_avis("Impossible d'enregistrer la copie (%s)." % error_string(err))
		return
	Partie.choisir_plan(edition.chemin)
	_dernier_enregistrement = Time.get_time_string_from_system().substr(0, 5).replace(":", " h ")
	montrer_avis("Copie enregistrée : « %s ». C'est elle que tu modifies maintenant." % edition.nom())


func _sauvegarde_auto() -> void:
	if edition != null and edition.modifie and edition.plan().valide():
		enregistrer()


func renommer(nouveau: String) -> void:
	edition.renommer(nouveau)
	_maj_barre_haut()


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
	centre.add_child(_bandeau_salle())
	centre.add_child(_barre_vue())
	centre.add_child(_avis())
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
	_maj_barre_haut()


func _barre_haut() -> Control:
	var p := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var accueil := Style.bouton("⌂  Accueil")
	accueil.tooltip_text = "Retour à l'accueil (le vaisseau est enregistré s'il a changé)"
	accueil.pressed.connect(func():
		if edition.modifie:
			enregistrer()
		Partie.aller_accueil(get_tree()))
	h.add_child(accueil)
	h.add_child(Style.label("ATELIER", 20, Style.ACCENT))
	champ_nom = LineEdit.new()
	champ_nom.text = edition.nom()
	champ_nom.custom_minimum_size = Vector2(230, 0)
	champ_nom.tooltip_text = "Nom du vaisseau (Entrée pour le changer). Chaque vaisseau a son fichier."
	champ_nom.text_submitted.connect(func(t): renommer(t); champ_nom.release_focus())
	champ_nom.focus_exited.connect(func(): renommer(champ_nom.text))
	h.add_child(champ_nom)
	texte_etat = Style.label("", 13, Style.TEXTE_DOUX)
	texte_etat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texte_etat.clip_text = true
	texte_etat.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(texte_etat)
	bouton_annuler = Style.bouton("↶", 16)
	bouton_annuler.tooltip_text = "Annuler (Ctrl + Z)"
	bouton_annuler.pressed.connect(annuler)
	h.add_child(bouton_annuler)
	bouton_refaire = Style.bouton("↷", 16)
	bouton_refaire.tooltip_text = "Refaire (Ctrl + Y)"
	bouton_refaire.pressed.connect(refaire)
	h.add_child(bouton_refaire)
	case_symetrie = _case("Symétrie", symetrie, func(on):
		symetrie = on
		if not pose.is_empty():
			_placer_fantomes()
		_sauver_reglages())
	case_symetrie.tooltip_text = "Poser aussi la même pièce de l'autre côté, en miroir (M)"
	h.add_child(case_symetrie)
	var sauver := Style.bouton("Enregistrer", 14)
	sauver.tooltip_text = "Enregistrer le vaisseau (Ctrl + S). Il s'enregistre aussi tout seul toutes les 2 minutes."
	sauver.pressed.connect(enregistrer)
	h.add_child(sauver)
	var copie := Style.bouton("Copie", 14)
	copie.tooltip_text = "Enregistrer une copie sous un autre nom (l'original reste)"
	copie.pressed.connect(enregistrer_copie)
	h.add_child(copie)
	var cam := Style.bouton("Caméra ▾", 14)
	cam.pressed.connect(_ouvrir_menu_camera.bind(cam))
	h.add_child(cam)
	var lancer := Style.bouton_principal("▶  LANCER")
	lancer.tooltip_text = "Charge le jeu : le vaisseau part posé au sol, devant le hangar (F3 pour revenir)"
	lancer.pressed.connect(lancer_jeu)
	h.add_child(lancer)
	return p


func _maj_barre_haut() -> void:
	if texte_etat == null:
		return
	if not champ_nom.has_focus():
		champ_nom.text = edition.nom()
	var morceaux := PackedStringArray(["%d pièces" % plan.pieces.size()])
	if nb_flottantes > 0:
		morceaux.append("⚠ %d pièce%s ne touche%s rien (en rouge)" % [nb_flottantes, "s" if nb_flottantes > 1 else "",
			"nt" if nb_flottantes > 1 else ""])
	if edition.modifie:
		morceaux.append("modifié, pas encore enregistré")
	elif edition.chemin != "":
		morceaux.append(("enregistré à " + _dernier_enregistrement) if _dernier_enregistrement != "" else "enregistré")
	else:
		morceaux.append("vaisseau du jeu")
	texte_etat.text = "  ·  ".join(morceaux)
	texte_etat.add_theme_color_override("font_color", Style.ROUGE if nb_flottantes > 0 else Style.TEXTE_DOUX)
	texte_etat.tooltip_text = edition.chemin if edition.chemin != "" else "Pas encore de fichier : il sera créé au premier enregistrement."
	bouton_annuler.disabled = not edition.peut_annuler()
	bouton_refaire.disabled = not edition.peut_refaire()


func _tableau_ingenieur() -> Control:
	tableau = HBoxContainer.new()
	tableau.add_theme_constant_override("separation", 6)
	tableau.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_remplir_tableau()
	return tableau


func _remplir_tableau() -> void:
	if tableau == null:
		return
	for c in tableau.get_children():
		tableau.remove_child(c)
		c.queue_free()
	var en_salle := not salle.is_empty()
	var tuiles: Array = analyse.tuiles_groupe(pieces_salle()) if en_salle else analyse.tuiles()
	var details: Array = [] if en_salle else Analyse.DETAIL_TUILES.duplicate()
	if not en_salle:
		controle = controle_vol()
		tuiles.append(controle.tuile())
		details.append("controle")
	for k in tuiles.size():
		var t: Array = tuiles[k]
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(120, 0)
		var bord := Style.ACCENT.darkened(0.45) if en_salle else Style.BORD
		var normal := Style.boite(Style.FOND, bord, 6, 9.0)
		var survol := Style.boite(Style.FOND_CLAIR, Style.ACCENT.darkened(0.2), 6, 9.0)
		p.add_theme_stylebox_override("panel", normal)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		p.add_child(v)
		v.add_child(Style.label(t[0], 11, Style.ACCENT if en_salle else Style.TEXTE_DOUX))
		v.add_child(Style.label(t[1], 19, t[3] if t.size() > 3 else Color.WHITE))
		var d := Style.label(t[2], 11, Style.TEXTE_DOUX)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(100, 0)
		v.add_child(d)
		# un clic ouvre la page d'analyse détaillée (dans la salle à part : la fiche du morceau)
		var detail: String = details[k] if k < details.size() else ""
		p.tooltip_text = "%s : %s\n%s\n\nClic : %s" % [t[0], t[1], t[2], "le détail" if not en_salle else "la fiche du morceau"]
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.mouse_entered.connect(func(): p.add_theme_stylebox_override("panel", survol))
		p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", normal))
		p.gui_input.connect(func(e):
			if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (e as InputEventMouseButton).pressed:
				ouvrir_detail(detail))
		tableau.add_child(p)


## La page d'analyse détaillée d'une tuile : masses, poussees, symetrie ("" : la fiche du morceau isolé).
func ouvrir_detail(detail: String) -> void:
	if detail == "":
		if not salle.is_empty():
			var e: Array = salle["elements"]
			if e.size() == 1:
				choisir(String(e[0]["genre"]), String(e[0]["id"]))
			else:
				choisir_groupe(e)
		return
	finir_pose()
	choisir("analyse", detail)
	if detail == "poussees" and case_poussees != null:
		case_poussees.button_pressed = true


func _panneau_catalogue() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(320, 0)
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
	arbre.set_column_custom_minimum_width(1, 84)
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
	tout.pressed.connect(func(): camera.cadrer(boite_visible()))
	h.add_child(tout)
	var sel := Style.bouton("Cadrer le choix", 13)
	sel.tooltip_text = "pavé numérique , ou F"
	sel.pressed.connect(cadrer_selection)
	h.add_child(sel)
	var sep := VSeparator.new()
	h.add_child(sep)
	case_cg = _case("Centre de gravité", true, func(on): _centre_gravite.visible = on; _sauver_reglages())
	h.add_child(case_cg)
	case_poussees = _case("Poussées", false, func(on): _fleches_poussee.visible = on; _fleche_couple.visible = on; _sauver_reglages())
	h.add_child(case_poussees)
	case_neutre = _case("Fond neutre", false, func(on): hangar.vue_technique(on); _sauver_reglages())
	h.add_child(case_neutre)
	return p


## Bandeau d'avis (ce qui vient de se passer, ou pourquoi c'est refusé), sous la barre de vue.
func _avis() -> Control:
	avis = PanelContainer.new()
	avis.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avis.add_theme_stylebox_override("panel", Style.boite(Color(0.16, 0.08, 0.07, 0.94), Style.ROUGE, 6, 10.0))
	avis.visible = false
	texte_avis = Style.label("", 15, Color.WHITE)
	texte_avis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texte_avis.custom_minimum_size = Vector2(420, 0)
	avis.add_child(texte_avis)
	return avis


func montrer_avis(texte: String, duree := 6.0) -> void:
	if avis == null:
		return
	texte_avis.text = texte
	avis.visible = true
	var moi := texte
	get_tree().create_timer(duree).timeout.connect(func():
		if is_instance_valid(avis) and texte_avis.text == moi:
			avis.visible = false)


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
	fiche.custom_minimum_size = Vector2(350, 0)
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
	fermer.pressed.connect(func():
		finir_pose()
		deselectionner())
	h.add_child(fermer)
	fiche_titre = Style.label("", 20, Color.WHITE)
	fiche_titre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(fiche_titre)
	fiche_sous_titre = Style.label("", 12, Style.TEXTE_DOUX)
	fiche_sous_titre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	fiche_outils = VBoxContainer.new()
	fiche_outils.add_theme_constant_override("separation", 6)
	fiche_outils.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interieur.add_child(fiche_outils)
	fiche_grille = GridContainer.new()
	fiche_grille.columns = 2
	fiche_grille.add_theme_constant_override("h_separation", 12)
	fiche_grille.add_theme_constant_override("v_separation", 7)
	fiche_grille.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interieur.add_child(fiche_grille)
	fiche_sections = VBoxContainer.new()
	fiche_sections.add_theme_constant_override("separation", 2)
	fiche_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interieur.add_child(fiche_sections)
	fiche_note = Style.label("", 13, Style.TEXTE_DOUX)
	fiche_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fiche_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interieur.add_child(fiche_note)
	return fiche


func _barre_aide() -> Control:
	aide = Style.label(AIDE, 12, Style.TEXTE_DOUX)
	aide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# toute la largeur : un texte qui passe à la ligne n'a pas de largeur à lui (sinon : une lettre par ligne,
	# et la barre mange la hauteur du catalogue)
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_FILL
	p.add_theme_stylebox_override("panel", Style.boite(Style.FOND, Style.BORD, 6, 10.0))
	p.add_child(aide)
	return p


func _afficher_fiche(f: Dictionary) -> void:
	fiche.visible = true
	fiche_titre.text = String(f["titre"])
	fiche_sous_titre.text = String(f["sous_titre"])
	for c in fiche_outils.get_children():
		fiche_outils.remove_child(c)
		c.queue_free()
	for c in fiche_grille.get_children():
		fiche_grille.remove_child(c)
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
	for c in fiche_sections.get_children():
		fiche_sections.remove_child(c)
		c.queue_free()
	for sec in f.get("sections", []):
		var t := Style.label(String(sec["titre"]), 11, Style.TEXTE_DOUX)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(200, 0)
		fiche_sections.add_child(HSeparator.new())
		fiche_sections.add_child(t)
		for l in sec["liste"]:
			fiche_sections.add_child(_ligne_cliquable(l))
	fiche_sections.visible = fiche_sections.get_child_count() > 0
	fiche_note.text = String(f["note"])
	fiche_note.visible = fiche_note.text != ""


## Une ligne d'une liste de la fiche : texte, valeur, petite barre (part), et un clic qui choisit.
func _ligne_cliquable(l: Dictionary) -> Control:
	var choix: Dictionary = l.get("choix", {})
	var p := PanelContainer.new()
	var normal := Style.boite(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 6.0, 0)
	var survol := Style.boite(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 4, 6.0, 0)
	p.add_theme_stylebox_override("panel", normal)
	p.mouse_filter = Control.MOUSE_FILTER_STOP if not choix.is_empty() else Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	var a := Style.label(String(l["texte"]), 13, l["couleur"] if l.has("couleur") else (Style.ACCENT if not choix.is_empty() else Style.TEXTE))
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.custom_minimum_size = Vector2(60, 0)
	if l.has("detail"):
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # contrôle avant le vol : le titre entier
	else:
		a.clip_text = true
		a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(a)
	var b := Style.label(String(l["valeur"]), 12, Style.TEXTE_DOUX)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(b)
	var part := float(l.get("part", -1.0))
	if part >= 0.0:
		var barre := HBoxContainer.new()
		barre.add_theme_constant_override("separation", 0)
		barre.custom_minimum_size = Vector2(0, 4)
		barre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plein := ColorRect.new()
		plein.color = Style.ROUGE if bool(l.get("alerte", false)) else Style.ACCENT.darkened(0.15)
		plein.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plein.size_flags_stretch_ratio = maxf(part, 0.002)
		plein.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vide := ColorRect.new()
		vide.color = Color(1, 1, 1, 0.06)
		vide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vide.size_flags_stretch_ratio = maxf(1.0 - part, 0.002)
		vide.mouse_filter = Control.MOUSE_FILTER_IGNORE
		barre.add_child(plein)
		barre.add_child(vide)
		v.add_child(barre)
	if l.has("detail"):
		var d := Style.label(String(l["detail"]), 12, Style.TEXTE_DOUX)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(200, 0)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
	p.tooltip_text = "%s : %s" % [l["texte"], l["valeur"]]
	if not choix.is_empty():
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.mouse_entered.connect(func(): p.add_theme_stylebox_override("panel", survol))
		p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", normal))
		p.gui_input.connect(func(e):
			if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (e as InputEventMouseButton).pressed:
				choisir_ligne(choix))
	return p


## Ce que fait un clic sur une ligne de liste (Ctrl : ajouter à la sélection).
func choisir_ligne(choix: Dictionary) -> void:
	if String(choix.get("genre", "")) == "groupe":
		choisir_groupe(choix["elements"])
	elif Input.is_key_pressed(KEY_CTRL) and String(choix["genre"]) in ["piece", "ajout", "module"]:
		basculer_dans_selection(String(choix["genre"]), String(choix["id"]))
	else:
		choisir(String(choix["genre"]), String(choix["id"]))


func _bouton_fiche(texte: String, quand: Callable, parent: Control = null) -> Button:
	var b := Style.bouton(texte, 13)
	b.pressed.connect(quand)
	(parent if parent != null else fiche_outils).add_child(b)
	return b


## Les réglages d'une pièce posée (poussée, dimensions, matière…), sa place, et ses boutons.
func _outils_ajout(id: String) -> void:
	var e: Dictionary = analyse.ajouts[id]
	var modele_piece := String(e["modele"])
	var r: Dictionary = Pieces.reglages_complets(modele_piece, e.get("reglages", {}))
	var boutons := HBoxContainer.new()
	boutons.add_theme_constant_override("separation", 4)
	fiche_outils.add_child(boutons)
	_bouton_fiche("Déplacer (G)", deplacer_selection, boutons)
	_bouton_fiche("Dupliquer (Maj+D)", dupliquer_selection, boutons)
	_bouton_fiche("Enlever (Suppr)", supprimer_selection, boutons)
	if flottantes.has(id):
		var l := Style.label("Elle ne touche rien : pose-la contre le vaisseau (G), ou enlève-la.", 13, Style.ROUGE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fiche_outils.add_child(l)
	fiche_outils.add_child(Style.label("RÉGLAGES", 11, Style.TEXTE_DOUX))
	for d in Pieces.MODELES[modele_piece]["reglages"]:
		var cle: String = d["cle"]
		var ligne := HBoxContainer.new()
		var nom := Style.label(String(d["nom"]), 13, Style.TEXTE)
		nom.custom_minimum_size = Vector2(130, 0)
		ligne.add_child(nom)
		if d.has("choix"):
			var o := OptionButton.new()
			o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			o.focus_mode = Control.FOCUS_NONE
			# un nom de matière long (« Verre aluminosilicate feuilleté ») ne doit pas élargir la fiche (elle
			# pousserait le bouton LANCER hors de l'écran) : le texte est coupé, le menu le montre en entier
			o.fit_to_longest_item = false
			o.clip_text = true
			o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			o.custom_minimum_size = Vector2(150, 0)
			var choix: Array = d["choix"]
			for k in choix.size():
				var c := String(choix[k])
				var texte := c
				if Catalogue.MATIERES.has(c):
					texte = Analyse._majuscule(String(Catalogue.MATIERES[c]["nom"]))
				elif Pieces.CONTENUS.has(c):
					texte = Analyse._majuscule(String(Pieces.CONTENUS[c]["nom"]))
				o.add_item(texte, k)
				if c == String(r[cle]):
					o.select(k)
			o.item_selected.connect(func(k): edition.regler(id, cle, String(choix[k])))
			ligne.add_child(o)
		else:
			var s := SpinBox.new()
			s.min_value = float(d["min"])
			s.max_value = float(d["max"])
			s.step = float(d["pas"])
			s.value = float(r[cle])
			s.suffix = String(d["unite"])
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.value_changed.connect(func(x): edition.regler(id, cle, x))
			ligne.add_child(s)
		fiche_outils.add_child(ligne)
	# place et orientation, à la main (repère du vaisseau, ailes ouvertes)
	fiche_outils.add_child(Style.label("PLACE (m, repère du vaisseau, ailes ouvertes)  ·  ROTATION (°)", 11, Style.TEXTE_DOUX))
	var pos: Array = e.get("position", [0.0, 0.0, 0.0])
	var rot: Array = e.get("rotation_deg", [0.0, 0.0, 0.0])
	for ligne_def in [["Place", pos, 0.01, -40.0, 40.0, " m"], ["Rotation", rot, 1.0, -180.0, 180.0, "°"]]:
		var ligne := HBoxContainer.new()
		ligne.add_theme_constant_override("separation", 3)
		var l := Style.label(String(ligne_def[0]), 13, Style.TEXTE)
		l.custom_minimum_size = Vector2(70, 0)
		ligne.add_child(l)
		for k in 3:
			var s := SpinBox.new()
			s.min_value = float(ligne_def[3])
			s.max_value = float(ligne_def[4])
			s.step = float(ligne_def[2])
			s.value = float((ligne_def[1] as Array)[k])
			s.prefix = ["X", "Y", "Z"][k]
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.custom_minimum_size = Vector2(80, 0)
			var est_rotation: bool = ligne_def[0] == "Rotation"
			s.value_changed.connect(func(x): _regler_place(id, est_rotation, k, x))
			ligne.add_child(s)
		fiche_outils.add_child(ligne)
	if String(e.get("symetrique", "")) != "" and analyse.ajouts.has(String(e["symetrique"])):
		_bouton_fiche("Séparer de sa jumelle (elles bougeront chacune de leur côté)", func(): edition.separer_symetrie(id))
	fiche_outils.add_child(HSeparator.new())


func _regler_place(id: String, rotation: bool, k: int, x: float) -> void:
	var e: Dictionary = edition.element(id)
	if e.is_empty():
		return
	var pos: Array = (e.get("position", [0.0, 0.0, 0.0]) as Array).duplicate()
	var rot: Array = (e.get("rotation_deg", [0.0, 0.0, 0.0]) as Array).duplicate()
	if rotation:
		rot[k] = x
	else:
		pos[k] = x
	var b := Catalogue.rotation(rot)
	if bool(e.get("miroir_x", false)):
		b = b * Edition.MIROIR
	edition.deplacer_a_la_main(id, Transform3D(b, Catalogue.vecteur(pos)))


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
	# 0. les pièces toutes faites, à poser sur le vaisseau
	var poser := _section(racine, "PIÈCES À POSER", "poser")
	var n_poser := 0
	var cats := {}
	for k in Pieces.PROPOSITIONS.size():
		var pr: Array = Pieces.PROPOSITIONS[k]
		var description := String(Pieces.MODELES[pr[2]]["description"])
		if cherche and not Analyse.correspond_texte("%s %s %s %s" % [pr[0], pr[1], Pieces.nom(pr[2]), description], r):
			continue
		if not cats.has(pr[0]):
			var c := arbre.create_item(poser)
			c.set_text(0, String(pr[0]))
			c.set_selectable(0, false)
			c.set_selectable(1, false)
			c.set_custom_color(0, Style.TEXTE_DOUX)
			c.set_metadata(0, {"genre": "section", "id": "poser_" + String(pr[0])})
			c.collapsed = false if cherche else bool(_replies.get("section_poser_" + String(pr[0]), false))
			cats[pr[0]] = c
		var it := arbre.create_item(cats[pr[0]])
		it.set_text(0, String(pr[1]))
		it.set_text(1, "%s kg" % Analyse.nombre(Pieces.masse(pr[2], pr[3]), 0))
		it.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		it.set_custom_color(1, Style.TEXTE_DOUX)
		it.set_custom_color(0, Style.ACCENT)
		it.set_metadata(0, {"genre": "modele", "id": str(k)})
		it.set_tooltip_text(0, "%s\n%s\n\nClic : la poser sur le vaisseau." % [Pieces.resume(pr[2], pr[3]), description])
		n_poser += 1
	poser.set_text(1, str(n_poser))
	if n_poser == 0:
		poser.free()
	# 1. les pièces du vaisseau, par catégorie
	var section := _section(racine, "TON VAISSEAU", "vaisseau")
	var par_cat: Dictionary = analyse.pieces_par_categorie()
	var total := 0
	for c in Analyse.CATEGORIES:
		var ids: Array = par_cat[c[0]]
		var genre := "piece"
		if c[0] == "ajouts":
			ids = analyse.ajouts.keys()   # les pièces posées entières, pas leurs morceaux
			genre = "ajout"
		var trouves: Array
		if not cherche or Analyse.correspond_texte(c[1], r):
			trouves = ids
		elif genre == "ajout":
			trouves = ids.filter(func(i): return Analyse.correspond_texte("%s %s" % [analyse.nom_element(i),
				Pieces.nom(String(analyse.ajouts[i]["modele"]))], r))
		else:
			trouves = ids.filter(func(i): return analyse.correspond(i, r))
		if trouves.is_empty():
			continue
		total += trouves.size()
		var cat := arbre.create_item(section)
		cat.set_text(0, c[1])
		cat.set_text(1, str(trouves.size()))
		cat.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		cat.set_custom_color(1, Style.TEXTE_DOUX)
		cat.set_metadata(0, {"genre": "categorie", "id": c[0]})
		cat.collapsed = false if cherche else bool(_replies.get(c[0], c[0] != "ajouts"))
		for i in trouves:
			var it := arbre.create_item(cat)
			if genre == "ajout":
				it.set_text(0, analyse.nom_element(i))
				it.set_text(1, "%s kg" % Analyse.nombre(analyse.masse_ajout(i), 0))
				it.set_tooltip_text(0, "%s (%s)" % [Pieces.resume(String(analyse.ajouts[i]["modele"]), analyse.ajouts[i].get("reglages", {})), i])
				if flottantes.has(i):
					it.set_custom_color(0, Style.ROUGE)
			else:
				var p: Dictionary = analyse.piece(i)
				it.set_text(0, Analyse.nom_lisible(p))
				var m := float(p["masse_calculee"]["masse"])
				it.set_text(1, ("%s kg" % Analyse.nombre(m, 1)) if m > 0.0 else _etiquette_type(p))
				it.set_tooltip_text(0, "%s (%s)" % [Analyse.nom_lisible(p), i])
			it.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
			it.set_custom_color(1, Style.TEXTE_DOUX)
			it.set_metadata(0, {"genre": genre, "id": i})
	section.set_text(1, str(total))
	if total == 0:
		section.free()
	# 2. les modules du chasseur (on les enlève d'un bloc)
	var mods := _section(racine, "MODULES DU CHASSEUR", "modules")
	var n_mods := 0
	for cle in edition.modules():
		var nom: String = analyse.nom_module(cle)
		if cherche and not Analyse.correspond_texte(nom + " module", r):
			continue
		var it := arbre.create_item(mods)
		it.set_text(0, nom)
		it.set_text(1, "%s kg" % Analyse.nombre(float(analyse._masse_de(analyse.pieces_module(cle))[0]), 0))
		it.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		it.set_custom_color(1, Style.TEXTE_DOUX)
		it.set_metadata(0, {"genre": "module", "id": cle})
		if flottantes.has(analyse.pieces_module(cle)[0] if not analyse.pieces_module(cle).is_empty() else ""):
			it.set_custom_color(0, Style.ROUGE)
		n_mods += 1
	mods.set_text(1, str(n_mods))
	if n_mods == 0:
		mods.free()
	# 3. les types de pièces du catalogue
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
	# 4. les matières
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
	s.collapsed = false if recherche != null and recherche.text.strip_edges() != "" else bool(_replies.get("section_" + cle, cle != "vaisseau" and cle != "poser"))
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
	if not m is Dictionary or String(m["genre"]) == "section":
		return
	if String(m["genre"]) == "modele":
		var pr: Array = Pieces.PROPOSITIONS[int(m["id"])]
		commencer_pose(String(pr[2]), pr[3])
		return
	if Input.is_key_pressed(KEY_CTRL) and String(m["genre"]) in ["piece", "ajout", "module"]:
		basculer_dans_selection(String(m["genre"]), String(m["id"]))
		return
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
	case_symetrie.button_pressed = bool(f.get_value("pose", "symetrie", true))


func _sauver_reglages() -> void:
	if camera == null or case_cg == null or case_poussees == null or case_neutre == null or case_symetrie == null:
		return
	var f := ConfigFile.new()
	f.set_value("camera", "vitesse", camera.vitesse)
	f.set_value("vue", "centre_gravite", case_cg.button_pressed)
	f.set_value("vue", "poussees", case_poussees.button_pressed)
	f.set_value("vue", "fond_neutre", case_neutre.button_pressed)
	f.set_value("pose", "symetrie", case_symetrie.button_pressed)
	f.save(REGLAGES)


# =====================================================================
# LANCER
# =====================================================================
## Le contrôle avant le vol du vaisseau tel qu'il est (avec les pièces que l'atelier voit flotter).
func controle_vol():
	return ControleVol.new(plan, analyse if analyse != null and analyse.plan == plan else null, {"flottantes": flottantes.keys()})


## Lance le jeu ; le vaisseau est enregistré avant. Le contrôle avant le vol passe d'abord : ce qui casserait
## le jeu (plan avec des erreurs, pièce qui flotte, vaisseau trop lourd pour le PC) est refusé ; un
## avertissement ouvre la fenêtre du contrôle, avec « Lancer quand même » (forcer = vrai).
func lancer_jeu(forcer := false) -> bool:
	if chargement.visible:
		return false
	fermer_fenetre_controle()
	if not plan.valide():
		montrer_avis("Impossible de lancer : le plan du vaisseau a des erreurs (voir la fiche).")
		return false
	if _verifier_dans >= 0:
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
	controle = controle_vol()
	if nb_flottantes > 0:
		montrer_avis("Impossible de lancer : %d pièce%s ne touche%s rien (en rouge). Pose-les contre le vaisseau (G), ou enlève-les (Suppr)." % [
			nb_flottantes, "s" if nb_flottantes > 1 else "", "nt" if nb_flottantes > 1 else ""], 8.0)
		ouvrir_fenetre_controle()
		return false
	if controle.bloque() or (controle.avertit() and not forcer):
		ouvrir_fenetre_controle()
		return false
	finir_pose()
	if not salle.is_empty():
		sortir_salle()
	if edition.modifie and not enregistrer():
		return false
	chargement.visible = true
	# deux images pour que l'écran « Chargement » s'affiche avant que le jeu ne se construise
	await get_tree().process_frame
	await get_tree().process_frame
	Partie.lancer_jeu(get_tree(), Partie.DEPART_HANGAR)
	return true


## La fenêtre « Contrôle avant le vol », au milieu de l'écran : ce qui bloque (en rouge) ou avertit (en
## orange), expliqué ; « Lancer quand même » seulement s'il n'y a pas de blocage.
func ouvrir_fenetre_controle() -> void:
	fermer_fenetre_controle()
	if controle == null:
		controle = controle_vol()
	var boutons := [["Voir le détail", func():
			fermer_fenetre_controle()
			ouvrir_detail("controle"), false],
		["Revenir à l'atelier", fermer_fenetre_controle, false]]
	if not controle.bloque():
		boutons.append(["▶  Lancer quand même", func(): lancer_jeu(true), true])
	fenetre_controle = controle.fenetre(boutons, "Tout le contrôle : tuile « AVANT LE VOL » du tableau.")
	ui.add_child(fenetre_controle)


func fermer_fenetre_controle() -> void:
	if fenetre_controle != null and is_instance_valid(fenetre_controle):
		fenetre_controle.queue_free()
	fenetre_controle = null
