extends RefCounted
## Le DESSIN d'un vaisseau fait dans l'atelier, le même dans l'atelier et dans le jeu. Étape 5 : le jeu
## dessine TOUT le plan, pièce par pièce :
##   - le dessin du chasseur (modèle Blender) dont on cache les morceaux enlevés du plan (un module supprimé
##     dans l'atelier disparaît, ses lueurs et ses jets aussi) ;
##   - les pièces toutes faites posées dans l'atelier (moteurs, propulseurs, boîtes…), dessinées en formes
##     simples (PROVISOIRE) à partir de leurs réglages (scripts/atelier/pieces_toutes_faites.gd). Une pièce
##     posée sur une aile est rangée sous la charnière de l'aile dans le dessin : elle la suit quand l'aile
##     s'ouvre ou se replie, exactement comme sa physique (vaisseau_physique.gd, transformation_articulation) ;
##   - les pièces écrites directement dans le plan, sans dessin Blender (un plan fait à la main ou par un
##     autre outil) : blocs, poutres, plaques, structures (boîte qui a la même inertie), moteurs et petits
##     propulseurs (tuyère, lueur, jet), roues, surfaces d'air (plaque mince). Les masses ponctuelles et les
##     points de coque n'ont pas de forme : rien n'est dessiné pour eux ;
##   - les plaques en VERRE sont de vraies vitres : transparentes dans l'atelier, et dans le jeu le système
##     de lumière en fait une vitre (loi de Fresnel, on voit à travers, pas d'ombre) comme la verrière.
##
## Pour le PC (étape 5) : dans le jeu, les pièces posées qui ont la même matière sont FUSIONNÉES en un seul
## maillage (par charnière : une aile garde les siennes) ; 300 boîtes de la même couleur coûtent alors à la
## carte graphique autant qu'une seule (un « appel de dessin » au lieu de 300). Les petits cylindres ont moins
## de côtés, et les toutes petites formes ne font pas d'ombre. compter() donne ce que le jeu dessinera
## (surfaces, triangles, vitres) : le contrôle avant le vol (scripts/atelier/controle_vol.gd) s'en sert.
##
## Les lueurs et les jets des moteurs posés portent, comme ceux du modèle Blender, une étiquette « extras »
## (type lueur / panache) : le jeu les allume selon la vraie poussée de leur moteur (id_physique).
## Rien ici ne change la physique : le dessin suit le plan.

const Plan = preload("res://scripts/atelier/plan.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")
const Edition = preload("res://scripts/atelier/edition.gd")
const Catalogue = preload("res://scripts/atelier/catalogue.gd")

const MODELE_EXTERIEUR := "res://modeles/vaisseau/vaisseau_exterieur.glb"
const COULEUR_LUEUR_FAIBLE := [0.0, 0.25, 1.0]
const COULEUR_LUEUR_FORTE := [0.55, 0.0, 1.0]
const COULEUR_VERRE := Color(0.32, 0.46, 0.6, 0.28)   # (atelier ; dans le jeu, le système de lumière la refait)
const SANS_OMBRE_SOUS := 0.12                          # m : une forme plus petite que ça ne fait pas d'ombre
## Types de pièces du plan qui ont une forme à dessiner quand le modèle Blender ne les dessine pas.
const TYPES_DESSINES := ["bloc", "poutre", "plaque", "structure", "moteur", "propulseur", "roue", "surface_air"]

var exterieur: Node3D
var modele                       # ModeleVaisseau (pose des ailes, du train…)
var droide: Node3D = null        # le modèle du droïde (dans son logement)
var plan
var ajouts := {}                 # id de la pièce posée → son nœud (sous exterieur ou sous une charnière)
var maillages_ajouts := {}       # id de la pièce posée → [MeshInstance3D] (sans les lueurs et les jets)
var lueurs_ajouts := {}          # id de la pièce posée → [MeshInstance3D] (lueurs et jets)
var bruts := {}                  # id d'une pièce du plan sans dessin Blender → son nœud
var maillages_bruts := {}        # id → [MeshInstance3D] (sans les lueurs et les jets)
var lueurs_bruts := {}           # id → [MeshInstance3D] (lueurs et jets)
var fusions: Array = []          # maillages fusionnés (jeu : une matière par charnière)
var caches: Array = []           # maillages du chasseur cachés (pièces enlevées du plan)
var _piece_v27 := {}             # MeshInstance3D → id de la pièce du plan de départ qu'il dessine
var _moteur_v27 := {}            # lueur / jet du modèle → id du moteur ou propulseur de départ
var _maillages := []             # les maillages du chasseur (sans le droïde)
var _maillage_origine := {}      # maillage caché → son maillage (pour le remettre : annuler) ; seulement ceux-là


static var _ids_depart := {}
static var _table_v27: Array = []    # [{piece, moteur, surfaces, triangles, ombre}] : un par maillage du chasseur
static var _triangles_forme := {}    # clé de forme → nombre de triangles (cache de compter())


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
# CE QU'IL Y A À DESSINER (sans le modèle Blender)
# =====================================================================
## Les éléments d'un plan à dessiner en formes simples : les pièces posées dans l'atelier, et les pièces
## écrites dans le plan que le modèle Blender ne dessine pas. Chaque élément :
##   {"id", "genre" ("ajout" ou "piece"), "articulation", "xf" (repère du plan, pose de référence),
##    "formes": [{forme, taille, xf (dans l'élément), couleur, metal, rugosite, role ("", "lueur", "panache"),
##                vitre (bool), id_physique (moteur relié aux lueurs et aux jets)}]}
## Le même calcul sert au dessin (construire) et au compte de ce que le PC devra dessiner (compter).
static func elements(p_plan) -> Array:
	var sortie := []
	var ids := ids_depart()
	for e in p_plan.donnees.get("pieces", []):
		if not (e is Dictionary and e.has("modele")) or not Pieces.existe(String(e["modele"])):
			continue
		var id := String(e["id"])
		var formes := Pieces.dessin(String(e["modele"]), e.get("reglages", {}))
		for f in formes:
			f["id_physique"] = id + "/poussee"
		sortie.append({"id": id, "genre": "ajout", "articulation": String(e.get("articulation", "")),
			"xf": Edition.xf_de(e), "formes": formes})
	for p in p_plan.pieces:
		var id := String(p["id"])
		if p.has("ajout") or ids.has(id) or not TYPES_DESSINES.has(String(p.get("type", ""))):
			continue
		var el := _element_brut(p)
		if not el.is_empty():
			sortie.append(el)
	return sortie


## Une pièce du plan sans dessin Blender : ses formes simples, d'après ses dimensions et sa matière.
static func _element_brut(p: Dictionary) -> Dictionary:
	var t := String(p["type"])
	var id := String(p["id"])
	var base: Basis = p.get("base", Basis.IDENTITY)
	var mat := String(p.get("matiere", ""))
	var couleur := Pieces._couleur(mat) if mat != "" else Color(0.55, 0.57, 0.6)
	var metal := Pieces._metal(mat) if mat != "" else 0.5
	var vitre := mat == "verre_aluminosilicate"
	var formes := []
	var xf := Transform3D.IDENTITY
	var vers_z := Basis(Vector3.RIGHT, PI * 0.5)   # axe Y du cylindre → axe Z de la pièce
	match t:
		"bloc":
			xf = Transform3D(base, Catalogue.vecteur(p["position"]))
			var dim: Array = p["dimensions_m"]
			if String(p["forme"]) == "cylindre":
				var r := float(dim[0]) * 0.5
				formes.append(_f("cylindre", Vector3(r, r, float(dim[1])), Transform3D(vers_z, Vector3.ZERO), couleur, metal, 0.45, vitre))
			else:
				formes.append(_f("boite", Vector3(float(dim[0]), float(dim[1]), float(dim[2])), Transform3D.IDENTITY, couleur, metal, 0.45, vitre))
		"poutre":
			xf = Transform3D(base, Catalogue.vecteur(p["position"]))
			formes.append(_f("boite", Vector3(float(p["largeur_m"]), float(p["hauteur_m"]), float(p["longueur_m"])), Transform3D.IDENTITY,
				couleur, metal, 0.45, vitre))
		"plaque":
			xf = Transform3D(base, Catalogue.vecteur(p["position"]))
			formes.append(_f("boite", Vector3(float(p["largeur_m"]), float(p["epaisseur_m"]), float(p["longueur_m"])), Transform3D.IDENTITY,
				couleur, metal, 0.5, vitre))
		"structure":
			# boîte pleine qui a la même masse et la même inertie propre (axes du vaisseau)
			var m := maxf(float(p["masse_kg"]), 1e-6)
			var i: Array = p["inertie_propre"]
			var ix := float(i[0])
			var iy := float(i[1])
			var iz := float(i[2])
			var cote := Vector3(sqrt(maxf(6.0 * (iy + iz - ix) / m, 4e-4)), sqrt(maxf(6.0 * (ix + iz - iy) / m, 4e-4)),
				sqrt(maxf(6.0 * (ix + iy - iz) / m, 4e-4)))
			xf = Transform3D(Basis.IDENTITY, Catalogue.vecteur(p["centre"]))
			formes.append(_f("boite", cote, Transform3D.IDENTITY, couleur, metal, 0.5, vitre))
		"moteur":
			# tuyère au point de poussée, jet vers l'arrière (repère : +Z = sortie du jet, comme un moteur posé)
			var dir: Vector3 = p["direction"]
			xf = Transform3D(_base_vers(-dir, 2), p["point"])
			var d := Pieces.dimensions_ionique(float(p["poussee_n"]) / 1000.0).x
			var titane := Pieces._couleur("titane")
			formes.append(_f("cylindre", Vector3(d * 0.46, d * 0.36, d * 0.6), Transform3D(vers_z, Vector3(0, 0, -d * 0.3)), titane, 0.85, 0.35))
			formes.append(_f("cylindre", Vector3(d * 0.42, d * 0.42, 0.02), Transform3D(vers_z, Vector3(0, 0, -0.01)), Color.BLACK, 0.0, 1.0, false, "lueur"))
			formes.append(_f("panache", Vector3(d * 0.42, d * 0.08, d * 2.5), Transform3D(vers_z, Vector3.ZERO), Color(0.0, 0.25, 1.0), 0.0, 1.0, false, "panache"))
		"propulseur":
			# petite buse au point de poussée, qui souffle à l'opposé de la poussée (repère : +Y = sortie)
			var dir2: Vector3 = p["direction"]
			xf = Transform3D(_base_vers(-dir2, 1), p["point"])
			var s := sqrt(float(p["poussee_n"]) / 6000.0)
			if not bool(p.get("encastre", false)):
				formes.append(_f("cylindre", Vector3(0.07, 0.035, 0.14) * s, Transform3D(Basis.IDENTITY, Vector3(0, -0.07 * s, 0)), Color(0.3, 0.3, 0.33), 0.9, 0.3))
			formes.append(_f("cylindre", Vector3(0.06 * s, 0.06 * s, 0.005), Transform3D(Basis.IDENTITY, Vector3(0, -0.003, 0)), Color.BLACK, 0.0, 1.0, false, "lueur"))
			formes.append(_f("panache", Vector3(0.06, 0.012, 0.6) * s, Transform3D.IDENTITY, Color(0.0, 0.25, 1.0), 0.0, 1.0, false, "panache"))
		"roue":
			var r := float(p.get("rayon_m", 0.18))
			xf = Transform3D(Basis.IDENTITY, (p["point"] as Vector3) + Vector3(0, r, 0))
			formes.append(_f("cylindre", Vector3(r, r, r * 0.6), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), Color(0.08, 0.08, 0.09), 0.0, 0.9))
			formes.append(_f("cylindre", Vector3(r * 0.55, r * 0.55, r * 0.62), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), Pieces._couleur("acier"), 0.9, 0.4))
		"surface_air":
			# plaque mince qui porte : envergure perpendiculaire à l'avancement, point au quart de la corde
			var sm := maxf(float(p["surface_m2"]), 0.01)
			var corde := float(p.get("corde_m", sqrt(sm / maxf(float(p["allongement"]), 0.1))))
			var env := sm / maxf(corde, 0.01)
			var n: Vector3 = p["normale"]
			var cote2 := n.cross(Vector3.FORWARD)
			if cote2.length() < 1e-3:
				cote2 = Vector3.RIGHT
			cote2 = cote2.normalized()
			var avant := cote2.cross(n).normalized()
			xf = Transform3D(Basis(n.cross(-avant).normalized(), n, -avant), (p["point"] as Vector3) - avant * corde * 0.25)
			formes.append(_f("boite", Vector3(env, 0.03, corde), Transform3D.IDENTITY, Pieces._couleur("composite_carbone"), 0.1, 0.55))
	if formes.is_empty():
		return {}
	for f in formes:
		f["id_physique"] = id
	return {"id": id, "genre": "piece", "articulation": String(p.get("articulation", "")), "xf": xf, "formes": formes}


static func _f(forme: String, taille: Vector3, xf: Transform3D, couleur: Color, metal: float, rugosite: float, vitre := false, role := "") -> Dictionary:
	return {"forme": forme, "taille": taille, "xf": xf, "couleur": couleur, "metal": metal, "rugosite": rugosite, "role": role, "vitre": vitre}


## Base orthonormée dont l'axe n° axe (0 = X, 1 = Y, 2 = Z) est dans la direction d.
static func _base_vers(d: Vector3, axe: int) -> Basis:
	var a := d.normalized() if d.length() > 1e-6 else Vector3.BACK
	var autre := Vector3.UP if absf(a.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := autre.cross(a).normalized()
	var w := a.cross(u).normalized()
	match axe:
		0:
			return Basis(a, u, a.cross(u))
		1:
			return Basis(w, a, w.cross(a))
	return Basis(u, w, a)


# =====================================================================
# CONSTRUIRE LE DESSIN D'UN PLAN
# =====================================================================
## (Re)fait le dessin pour ce plan. v : la physique du vaisseau (pour la pose de référence des ailes).
## fusion (jeu) : les formes de même matière sont fusionnées en un seul maillage par charnière (plus léger
## pour la carte graphique ; on ne peut plus les choisir une par une, ce que seul l'atelier fait).
func construire(p_plan, v, fusion := false) -> void:
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
	# 2. les pièces posées et les pièces sans dessin Blender
	for liste in [ajouts, bruts]:
		for id in liste:
			var n: Node = liste[id]
			if is_instance_valid(n):
				n.get_parent().remove_child(n)
				n.queue_free()
		liste.clear()
	for f in fusions:
		if is_instance_valid(f):
			(f as Node).get_parent().remove_child(f)
			(f as Node).queue_free()
	fusions.clear()
	maillages_ajouts.clear()
	lueurs_ajouts.clear()
	maillages_bruts.clear()
	lueurs_bruts.clear()
	var els := elements(plan)
	if els.is_empty():
		return
	# place des charnières dans la pose de référence du plan (ailes ouvertes…) : la pièce posée y est rangée
	var refs := _poses_reference(v)
	for el in els:
		_dessiner_element(el, refs)
	if fusion:
		_fusionner()


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


func _dessiner_element(el: Dictionary, refs: Dictionary) -> void:
	var id := String(el["id"])
	var ajout := String(el["genre"]) == "ajout"
	var xf: Transform3D = el["xf"]
	var parent: Node3D = exterieur
	var art := String(el["articulation"])
	if refs.has(art):
		parent = refs[art][0]
		xf = (refs[art][1] as Transform3D).affine_inverse() * xf
	var racine := Node3D.new()
	racine.name = ("Ajout_" if ajout else "Piece_plan_") + id.replace("/", "_")
	racine.transform = xf
	racine.set_meta("ajout" if ajout else "piece_plan", id)
	parent.add_child(racine)
	var liste := []
	var brillants := []
	var nom := id.replace("/", "_")
	for f in el["formes"]:
		var mi := MeshInstance3D.new()
		mi.transform = f["xf"]
		var role := String(f["role"])
		var t: Vector3 = f["taille"]
		var id_phys := String(f.get("id_physique", id))
		match role:
			"panache":
				mi.name = "Panache_" + nom
				mi.mesh = cone(t.x, t.y, t.z)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("extras", {"type": "panache", "id_physique": id_phys,
					"couleur_faible": COULEUR_LUEUR_FAIBLE, "couleur_forte": COULEUR_LUEUR_FORTE,
					"axe_longueur_godot": "Y", "longueur_max_m": t.z})
				mi.material_override = _matiere(f["couleur"], 0.0, 1.0)
				mi.visible = false
				brillants.append(mi)
			"lueur":
				mi.name = "Lueur_" + nom
				mi.mesh = _forme(String(f["forme"]), t)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("extras", {"type": "lueur", "id_physique": id_phys,
					"couleur_faible": COULEUR_LUEUR_FAIBLE, "couleur_forte": COULEUR_LUEUR_FORTE,
					"energie_min": 1.0, "energie_max": 4.0})
				_poser_matiere(mi, _matiere(f["couleur"], 0.0, 1.0))
				brillants.append(mi)
			_:
				mi.name = ("Piece_" if ajout else "Forme_") + nom + "_%d" % liste.size()
				mi.mesh = _forme(String(f["forme"]), t)
				if bool(f.get("vitre", false)):
					# vitre : transparente ; dans le jeu, le système de lumière la remplace par une vraie vitre
					var verre := StandardMaterial3D.new()
					verre.albedo_color = COULEUR_VERRE
					verre.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					verre.roughness = 0.05
					verre.metallic_specular = 0.9
					verre.resource_name = "Vitre"
					_poser_matiere(mi, verre)
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.set_meta("vitre", true)
				else:
					_poser_matiere(mi, _matiere(f["couleur"], float(f["metal"]), float(f["rugosite"])))
					if _plus_grand_cote(String(f["forme"]), t) < SANS_OMBRE_SOUS:
						mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("cle_matiere", cle_matiere(f))
				liste.append(mi)
		racine.add_child(mi)
	if ajout:
		ajouts[id] = racine
		maillages_ajouts[id] = liste
		lueurs_ajouts[id] = brillants
	else:
		bruts[id] = racine
		maillages_bruts[id] = liste
		lueurs_bruts[id] = brillants


## Ce qui distingue deux matières pour la fusion (même couleur, même métal, même rugosité).
static func cle_matiere(f: Dictionary) -> String:
	if bool(f.get("vitre", false)):
		return "vitre"
	var c: Color = f["couleur"]
	return "%.3f %.3f %.3f %.2f %.2f" % [c.r, c.g, c.b, float(f["metal"]), float(f["rugosite"])]


static func _plus_grand_cote(forme: String, t: Vector3) -> float:
	match forme:
		"cylindre":
			return maxf(2.0 * maxf(t.x, t.y), t.z)
		"gelule":
			return maxf(2.0 * t.x, t.y)
	return maxf(t.x, maxf(t.y, t.z))


## Jeu : les formes (sans les vitres, les lueurs et les jets) de même matière sous la même charnière
## deviennent un seul maillage. Une forme vue en miroir est retournée (l'ordre de ses triangles aussi,
## sinon on verrait son intérieur).
func _fusionner() -> void:
	var groupes := {}   # clé → [parent, matière, [MeshInstance3D], ombre]
	for dico in [maillages_ajouts, maillages_bruts]:
		for id in dico:
			for mi in dico[id]:
				var m := mi as MeshInstance3D
				if bool(m.get_meta("vitre", false)) or m.mesh == null:
					continue
				var racine := m.get_parent() as Node3D
				var parent := racine.get_parent() as Node3D
				var ombre := m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var cle := "%d|%s|%s" % [parent.get_instance_id(), String(m.get_meta("cle_matiere", "")), ombre]
				if not groupes.has(cle):
					groupes[cle] = [parent, m.mesh.surface_get_material(0), [], ombre]
				(groupes[cle][2] as Array).append(m)
	for cle in groupes:
		var g: Array = groupes[cle]
		var parent: Node3D = g[0]
		var sommets := PackedVector3Array()
		var normales := PackedVector3Array()
		var indices := PackedInt32Array()
		for m in g[2]:
			var mi := m as MeshInstance3D
			var xf: Transform3D = (mi.get_parent() as Node3D).transform * mi.transform
			var nb := xf.basis.inverse().transposed()
			var retourne := xf.basis.determinant() < 0.0
			for s in mi.mesh.get_surface_count():
				var a := mi.mesh.surface_get_arrays(s)
				var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var ns = a[Mesh.ARRAY_NORMAL]
				var ix = a[Mesh.ARRAY_INDEX]
				var debut := sommets.size()
				for k in vs.size():
					sommets.append(xf * vs[k])
					normales.append((nb * (ns[k] as Vector3)).normalized() if ns != null and k < (ns as PackedVector3Array).size() else Vector3.UP)
				var liste: PackedInt32Array = ix if ix != null and (ix as PackedInt32Array).size() > 0 else PackedInt32Array(range(vs.size()))
				for k in range(0, liste.size() - 2, 3):
					if retourne:
						indices.append_array([debut + liste[k], debut + liste[k + 2], debut + liste[k + 1]])
					else:
						indices.append_array([debut + liste[k], debut + liste[k + 1], debut + liste[k + 2]])
			mi.get_parent().remove_child(mi)
			mi.queue_free()
		if sommets.is_empty():
			continue
		var tableaux := []
		tableaux.resize(Mesh.ARRAY_MAX)
		tableaux[Mesh.ARRAY_VERTEX] = sommets
		tableaux[Mesh.ARRAY_NORMAL] = normales
		tableaux[Mesh.ARRAY_INDEX] = indices
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tableaux)
		am.surface_set_material(0, g[1])
		var f := MeshInstance3D.new()
		f.name = "Fusion_%d" % fusions.size()
		f.mesh = am
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(g[3]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(f)
		fusions.append(f)
	for dico in [maillages_ajouts, maillages_bruts]:
		for id in dico:
			dico[id] = (dico[id] as Array).filter(func(m): return is_instance_valid(m) and not (m as Node).is_queued_for_deletion())


## Nombre de côtés d'un cylindre : moins pour les petits (une buse de 6 cm n'a pas besoin de 20 côtés).
static func cotes_cylindre(rayon: float) -> int:
	return clampi(roundi(6.0 + 28.0 * rayon), 8, 20)


static func _forme(forme: String, t: Vector3) -> Mesh:
	match forme:
		"cylindre":
			var c := CylinderMesh.new()
			c.top_radius = maxf(t.x, 0.001)
			c.bottom_radius = maxf(t.y, 0.001)
			c.height = maxf(t.z, 0.001)
			c.radial_segments = cotes_cylindre(maxf(t.x, t.y))
			c.rings = 1
			return c
		"gelule":
			var g := CapsuleMesh.new()
			g.radius = maxf(t.x, 0.001)
			g.height = maxf(t.y, 2.0 * g.radius + 0.001)
			g.radial_segments = cotes_cylindre(t.x)
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


# =====================================================================
# CE QUE LE PC DEVRA DESSINER (contrôle avant le vol)
# =====================================================================
## Ce que le jeu dessine pour ce plan : {surfaces, triangles, surfaces_ombre, triangles_ombre, vitres,
## lueurs, jets, formes, pieces_dessinees}. surfaces = « appels de dessin » de la carte graphique (une
## matière d'un maillage) ; les surfaces qui font de l'ombre sont dessinées une fois de plus (carte d'ombre).
## Compte le chasseur (ses maillages encore présents), les pièces posées et les pièces sans dessin, comme le
## jeu les dessine (fusionnées si fusion). Le cockpit (toujours là) est compté à part : compter_cockpit().
static func compter(p_plan, fusion := true) -> Dictionary:
	var r := {"surfaces": 0, "triangles": 0, "surfaces_ombre": 0, "triangles_ombre": 0, "vitres": 0, "lueurs": 0,
		"jets": 0, "formes": 0, "elements": 0}
	var presents := {}
	for p in p_plan.pieces:
		presents[String(p["id"])] = true
	for m in table_v27():
		if String(m["piece"]) != "" and not presents.has(String(m["piece"])):
			continue
		if String(m["moteur"]) != "" and not presents.has(String(m["moteur"])):
			continue
		r["surfaces"] += int(m["surfaces"])
		r["triangles"] += int(m["triangles"])
		if bool(m["ombre"]):
			r["surfaces_ombre"] += int(m["surfaces"])
			r["triangles_ombre"] += int(m["triangles"])
	var groupes := {}
	for el in elements(p_plan):
		r["elements"] += 1
		var art := String(el["articulation"])
		for f in el["formes"]:
			var role := String(f["role"])
			var t: Vector3 = f["taille"]
			var tri := triangles_forme(String(f["forme"]) if role != "panache" else "cone", t)
			r["formes"] += 1
			match role:
				"panache":
					r["jets"] += 1
					r["surfaces"] += 1
					r["triangles"] += tri
				"lueur":
					r["lueurs"] += 1
					r["surfaces"] += 1
					r["triangles"] += tri
				_:
					var vitre := bool(f.get("vitre", false))
					var ombre := not vitre and _plus_grand_cote(String(f["forme"]), t) >= SANS_OMBRE_SOUS
					r["triangles"] += tri
					if ombre:
						r["triangles_ombre"] += tri
					if vitre:
						r["vitres"] += 1
						r["surfaces"] += 1
					elif fusion:
						var cle := "%s|%s|%s" % [art, cle_matiere(f), ombre]
						if not groupes.has(cle):
							groupes[cle] = true
							r["surfaces"] += 1
							if ombre:
								r["surfaces_ombre"] += 1
					else:
						r["surfaces"] += 1
						if ombre:
							r["surfaces_ombre"] += 1
	return r


## Nombre de triangles d'une forme simple (le même maillage que celui du dessin).
static func triangles_forme(forme: String, t: Vector3) -> int:
	var cle := forme
	match forme:
		"cylindre":
			cle += str(cotes_cylindre(maxf(t.x, t.y)))
		"gelule":
			cle += str(cotes_cylindre(t.x))
		"cone":
			return 32   # (cone() : 16 côtés, 2 triangles chacun)
	if not _triangles_forme.has(cle):
		var m := _forme(forme, t)
		var a := (m as PrimitiveMesh).get_mesh_arrays()
		var ix = a[Mesh.ARRAY_INDEX]
		_triangles_forme[cle] = ((ix as PackedInt32Array).size() if ix != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return int(_triangles_forme[cle])


## Le cockpit (toujours là : le pilote est dedans) : {surfaces, triangles, surfaces_ombre} de son modèle.
static var _cockpit := {}


static func compter_cockpit() -> Dictionary:
	if _cockpit.is_empty():
		var ck: Node3D = (load("res://modeles/vaisseau/cockpit.glb") as PackedScene).instantiate()
		_cockpit = {"surfaces": 0, "triangles": 0, "surfaces_ombre": 0, "triangles_ombre": 0}
		for n in ck.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.mesh == null:
				continue
			var tri := 0
			for s in m.mesh.get_surface_count():
				var a := m.mesh.surface_get_arrays(s)
				var ix = a[Mesh.ARRAY_INDEX]
				tri += ((ix as PackedInt32Array).size() if ix != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			_cockpit["surfaces"] += m.mesh.get_surface_count()
			_cockpit["triangles"] += tri
			if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and not String(m.name).to_lower().contains("verriere"):
				_cockpit["surfaces_ombre"] += m.mesh.get_surface_count()
				_cockpit["triangles_ombre"] += tri
		ck.free()
	return _cockpit


## Ce que dessine chaque maillage du modèle du chasseur (lu une fois dans le modèle Blender) : la pièce et
## le moteur qu'il montre, ses surfaces, ses triangles, s'il fait de l'ombre.
static func table_v27() -> Array:
	if not _table_v27.is_empty():
		return _table_v27
	var ext: Node3D = (load(MODELE_EXTERIEUR) as PackedScene).instantiate()
	var d = load("res://scripts/dessin_vaisseau.gd").new(ext, null)
	for mi in d._maillages:
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var tri := 0
		for s in m.mesh.get_surface_count():
			var a := m.mesh.surface_get_arrays(s)
			var ix = a[Mesh.ARRAY_INDEX]
			tri += ((ix as PackedInt32Array).size() if ix != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var nom := String(m.name)
		var brillant := nom.begins_with("Lueur_") or nom.begins_with("Panache_")
		_table_v27.append({"piece": d.piece_v27(m), "moteur": String(d._moteur_v27.get(m, "")),
			"surfaces": m.mesh.get_surface_count(), "triangles": tri,
			"ombre": not brillant and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				and not nom.to_lower().contains("verriere")})
	ext.free()
	return _table_v27
