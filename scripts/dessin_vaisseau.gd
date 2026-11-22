extends RefCounted
## Le DESSIN d'un vaisseau fait dans l'atelier (étape 3), le même dans l'atelier et dans le jeu :
##   - le dessin du chasseur (modèle Blender) dont on cache les morceaux enlevés du plan (un module supprimé
##     dans l'atelier disparaît, ses lueurs et ses jets aussi) ;
##   - les pièces toutes faites posées dans l'atelier (moteurs, propulseurs, boîtes…), dessinées en formes
##     simples (PROVISOIRE) à partir de leurs réglages (scripts/atelier/pieces_toutes_faites.gd). Une pièce
##     posée sur une aile est rangée sous la charnière de l'aile dans le dessin : elle la suit quand l'aile
##     s'ouvre ou se replie, exactement comme sa physique (vaisseau_physique.gd, transformation_articulation).
##
## Les lueurs et les jets des moteurs posés portent, comme ceux du modèle Blender, une étiquette « extras »
## (type lueur / panache) : le jeu les allume selon la vraie poussée de leur moteur (id_physique).
## Rien ici ne change la physique : le dessin suit le plan.

const Plan = preload("res://scripts/atelier/plan.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")
const Edition = preload("res://scripts/atelier/edition.gd")

const COULEUR_LUEUR_FAIBLE := [0.0, 0.25, 1.0]
const COULEUR_LUEUR_FORTE := [0.55, 0.0, 1.0]

var exterieur: Node3D
var modele                       # ModeleVaisseau (pose des ailes, du train…)
var droide: Node3D = null        # le modèle du droïde (dans son logement)
var plan
var ajouts := {}                 # id de la pièce posée → son nœud (sous exterieur ou sous une charnière)
var maillages_ajouts := {}       # id de la pièce posée → [MeshInstance3D] (sans les lueurs et les jets)
var lueurs_ajouts := {}          # id de la pièce posée → [MeshInstance3D] (lueurs et jets)
var caches: Array = []           # maillages du chasseur cachés (pièces enlevées du plan)
var _piece_v27 := {}             # MeshInstance3D → id de la pièce du plan de départ qu'il dessine
var _moteur_v27 := {}            # lueur / jet du modèle → id du moteur ou propulseur de départ
var _maillages := []             # les maillages du chasseur (sans le droïde)
var _maillage_origine := {}      # maillage caché → son maillage (pour le remettre : annuler) ; seulement ceux-là


static var _ids_depart := {}


## Ids des pièces du plan de départ (celui du dessin Blender).
static func ids_depart() -> Dictionary:
	if _ids_depart.is_empty():
		for p in Plan.par_defaut().pieces:
			_ids_depart[String(p["id"])] = p
	return _ids_depart


func _init(p_exterieur: Node3D, p_modele, p_droide: Node3D = null) -> void:
	exterieur = p_exterieur
	modele = p_modele
	droide = p_droide
	var ids := ids_depart()
	for n in exterieur.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if droide != null and droide.is_ancestor_of(mi):
			continue   # le droïde a son propre modèle (caché avec sa masse, plus bas)
		_maillages.append(mi)
		var nom := String(mi.name)
		if nom.begins_with("Lueur_") or nom.begins_with("Panache_"):
			_moteur_v27[mi] = _moteur_de_lueur(mi, ids)
		var x: Node = mi
		while x != null and x != exterieur:
			if ids.has(String(x.name)):
				_piece_v27[mi] = String(x.name)
				break
			x = x.get_parent()


## La pièce du plan de départ qu'un maillage du chasseur dessine ("" : aucune).
func piece_v27(mi: MeshInstance3D) -> String:
	return String(_piece_v27.get(mi, ""))


## Le moteur (ou petit propulseur) de départ qu'une lueur ou un jet du modèle Blender montre.
func _moteur_de_lueur(mi: MeshInstance3D, ids: Dictionary) -> String:
	var e = mi.get_meta("extras", {})
	if not e is Dictionary:
		return ""
	var point := String(e.get("moteur", ""))
	if point.begins_with("Point_moteur_"):
		for id in ids:
			var p: Dictionary = ids[id]
			if p["type"] == "moteur" and "Point_moteur_" + String(p.get("nom", id)).replace(" ", "_") == point:
				return id
	elif point.begins_with("Point_rcs_"):
		# comme le jeu : le propulseur le plus proche (les noms haut / bas du nez sont inversés dans le modèle)
		var ici := _relatif(mi, exterieur).origin
		var meilleur := ""
		var d_min := 0.1
		for id in ids:
			var p: Dictionary = ids[id]
			if p["type"] == "propulseur" and String(p.get("articulation", "")) == "":
				var d := ((p["point"] as Vector3) - ici).length()
				if d < d_min:
					d_min = d
					meilleur = id
		return meilleur
	return ""


## Transformation d'un nœud dans le repère d'un de ses parents (sans passer par l'arbre de scène).
static func _relatif(n: Node3D, racine: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var x: Node = n
	while x != null and x != racine:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


# =====================================================================
# CONSTRUIRE LE DESSIN D'UN PLAN
# =====================================================================
## (Re)fait le dessin pour ce plan. v : la physique du vaisseau (pour la pose de référence des ailes).
func construire(p_plan, v) -> void:
	plan = p_plan
	var presents := {}
	for p in plan.pieces:
		presents[String(p["id"])] = true
	# 1. le chasseur : on cache ce qui a été enlevé (le maillage est retiré, pas le nœud : ce qui est rangé
	#    dessous, comme les ailes sous le fuselage, reste visible)
	caches.clear()
	for mi in _maillages:
		if not is_instance_valid(mi):
			continue
		var id := String(_piece_v27.get(mi, ""))
		var enleve := id != "" and not presents.has(id)
		if _moteur_v27.has(mi):
			var m := String(_moteur_v27[mi])
			enleve = enleve or (m != "" and not presents.has(m))
		# on ne touche au maillage que s'il change (le système de lumière a posé ses matières dessus)
		if enleve and not _maillage_origine.has(mi):
			_maillage_origine[mi] = (mi as MeshInstance3D).mesh
			(mi as MeshInstance3D).mesh = null
		elif not enleve and _maillage_origine.has(mi):
			(mi as MeshInstance3D).mesh = _maillage_origine[mi]
			_maillage_origine.erase(mi)
		if enleve:
			caches.append(mi)
	if droide != null:
		droide.visible = presents.has("Masse_droide") or not ids_depart().has("Masse_droide")
	# 2. les pièces posées
	for id in ajouts:
		var n: Node = ajouts[id]
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	ajouts.clear()
	maillages_ajouts.clear()
	lueurs_ajouts.clear()
	var e_liste: Array = (plan.donnees.get("pieces", []) as Array).filter(func(e): return e is Dictionary and e.has("modele"))
	if e_liste.is_empty():
		return
	# place des charnières dans la pose de référence du plan (ailes ouvertes…) : la pièce posée y est rangée
	var refs := _poses_reference(v)
	for e in e_liste:
		_dessiner_ajout(e, refs)


## Nœud du dessin et sa transformation (repère du plan) dans la pose de référence, pour chaque
## articulation du plan qui a un nœud dans le modèle.
func _poses_reference(v) -> Dictionary:
	var refs := {}
	if v == null or modele == null:
		return refs
	var avant := [v.ailes, v.train, v.vertical]
	v.ailes = plan.valeur_reference("ailes")
	v.train = plan.valeur_reference("train")
	v.vertical = plan.valeur_reference("vertical")
	modele.poser(v)
	for id in plan.articulations:
		var nom := String((plan.articulations[id] as Dictionary).get("modele_3d", ""))
		var n := exterieur.find_child(nom, true, false) as Node3D if nom != "" else null
		if n != null:
			refs[id] = [n, _relatif(n, exterieur)]
	v.ailes = avant[0]
	v.train = avant[1]
	v.vertical = avant[2]
	modele.poser(v)
	return refs


func _dessiner_ajout(e: Dictionary, refs: Dictionary) -> void:
	var id := String(e["id"])
	var modele_piece := String(e["modele"])
	if not Pieces.existe(modele_piece):
		return
	var xf := Edition.xf_de(e)
	var parent: Node3D = exterieur
	var art := String(e.get("articulation", ""))
	if refs.has(art):
		parent = refs[art][0]
		xf = (refs[art][1] as Transform3D).affine_inverse() * xf
	var racine := Node3D.new()
	racine.name = "Ajout_" + id
	racine.transform = xf
	racine.set_meta("ajout", id)
	parent.add_child(racine)
	ajouts[id] = racine
	var liste := []
	var brillants := []
	var r: Dictionary = e.get("reglages", {})
	for f in Pieces.dessin(modele_piece, r):
		var mi := MeshInstance3D.new()
		mi.transform = f["xf"]
		var role := String(f["role"])
		var t: Vector3 = f["taille"]
		match role:
			"panache":
				mi.name = "Panache_" + id.replace("/", "_")
				mi.mesh = cone(t.x, t.y, t.z)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("extras", {"type": "panache", "id_physique": id + "/poussee",
					"couleur_faible": COULEUR_LUEUR_FAIBLE, "couleur_forte": COULEUR_LUEUR_FORTE,
					"axe_longueur_godot": "Y", "longueur_max_m": t.z})
				mi.material_override = _matiere(f["couleur"], 0.0, 1.0)
				mi.visible = false
				brillants.append(mi)
			"lueur":
				mi.name = "Lueur_" + id.replace("/", "_")
				mi.mesh = _forme(String(f["forme"]), t)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("extras", {"type": "lueur", "id_physique": id + "/poussee",
					"couleur_faible": COULEUR_LUEUR_FAIBLE, "couleur_forte": COULEUR_LUEUR_FORTE,
					"energie_min": 1.0, "energie_max": 4.0})
				_poser_matiere(mi, _matiere(f["couleur"], 0.0, 1.0))
				brillants.append(mi)
			_:
				mi.name = "Piece_" + id.replace("/", "_") + "_%d" % liste.size()
				mi.mesh = _forme(String(f["forme"]), t)
				_poser_matiere(mi, _matiere(f["couleur"], float(f["metal"]), float(f["rugosite"])))
				liste.append(mi)
		racine.add_child(mi)
	maillages_ajouts[id] = liste
	lueurs_ajouts[id] = brillants


static func _forme(forme: String, t: Vector3) -> Mesh:
	match forme:
		"cylindre":
			var c := CylinderMesh.new()
			c.top_radius = maxf(t.x, 0.001)
			c.bottom_radius = maxf(t.y, 0.001)
			c.height = maxf(t.z, 0.001)
			c.radial_segments = 20
			c.rings = 1
			return c
		"gelule":
			var g := CapsuleMesh.new()
			g.radius = maxf(t.x, 0.001)
			g.height = maxf(t.y, 2.0 * g.radius + 0.001)
			g.radial_segments = 20
			g.rings = 6
			return g
	var b := BoxMesh.new()
	b.size = Vector3(maxf(t.x, 0.001), maxf(t.y, 0.001), maxf(t.z, 0.001))
	return b


## Matière simple : la même que celles du modèle Blender (le système de lumière du jeu la lit et la refait).
static func _matiere(c: Color, metal: float, rugosite: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rugosite
	m.resource_name = "Ajout"
	return m


## Sur le maillage lui-même (pas en « override ») : l'atelier et le jeu posent leurs calques par-dessus.
static func _poser_matiere(mi: MeshInstance3D, m: Material) -> void:
	if mi.mesh is PrimitiveMesh:
		(mi.mesh as PrimitiveMesh).material = m
	elif mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			mi.mesh.surface_set_material(i, m)


## Cône d'un jet : de r0 (à l'origine) à r1, sur la longueur l, le long de +Y (le jeu l'allonge selon Y).
static func cone(r0: float, r1: float, l: float, cotes := 16) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in cotes:
		var a0 := TAU * k / cotes
		var a1 := TAU * (k + 1) / cotes
		var p00 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var p01 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		var p10 := Vector3(cos(a0) * r1, l, sin(a0) * r1)
		var p11 := Vector3(cos(a1) * r1, l, sin(a1) * r1)
		for p in [p00, p10, p11, p00, p11, p01]:
			st.set_normal(Vector3(p.x, 0.0, p.z).normalized())
			st.add_vertex(p)
	return st.commit()
