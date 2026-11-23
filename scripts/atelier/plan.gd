extends RefCounted
## Le PLAN d'un vaisseau : la liste de ses pièces (type, place, orientation, matière, réglages, pièces
## mobiles), sans aucun dessin. C'est ce que l'atelier écrira, et ce que le jeu lit pour construire le
## vaisseau : la physique (scripts/physique/vaisseau_physique.gd) ne connaît plus aucun vaisseau « en dur ».
##
## Fichier texte JSON (lisible et modifiable à la main) :
##   {"format": "plan-vaisseau", "version": 1, "nom": "…",
##    "commandes": {"ailes": {…}, "train": {…}, "vertical": {…}},   durées des mouvements
##    "articulations": [ … ],                                          pièces mobiles (charnières, vérins…)
##    "coque": {…}, "air": {…},                                        réglages d'ensemble de la coque
##    "modules": {clé: nom lisible},                                   morceaux du vaisseau (atelier)
##    "pieces": [ {"id": …, "type": …, …}, … ]}
## Les types de pièces et d'articulations sont décrits dans scripts/atelier/catalogue.gd.
##
## Une pièce de type « ensemble » contient elle-même des pièces (et ses propres articulations) : c'est un
## petit plan dans le plan, qu'on peut placer, tourner et retourner en miroir (miroir_x), ou lire dans un
## autre fichier ("plan": "res://…"). Au chargement, tout est « mis à plat » : chaque pièce reçoit sa place
## dans le repère du vaisseau, et un id complet « ensemble/pièce ».
##
## La masse, le centre de gravité et l'inertie (tableau complet 3×3) sont toujours RECALCULÉS à partir des
## pièces (théorème de Huygens : inertie propre de chaque pièce + masse × distance²). Rien n'est recopié.

const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const FORMAT := "plan-vaisseau"
## Version 2 (atelier, étape 3) : pièces toutes faites (ensembles avec « modele » et « reglages »), type
## « bloc », modules. Version 3 (étape 6) : l'ARMATURE (connecteurs, poutres entre deux connecteurs, panneaux
## remplis entre 3 ou 4 connecteurs : scripts/atelier/armature.gd), types « panneau », bloc en « boule »,
## poutres en tube. Un plan de version 1 ou 2 se lit toujours.
const VERSION := 3
const PLAN_PAR_DEFAUT := "res://vaisseaux/chasseur_v27.plan.json"

var donnees := {}                  # le plan tel qu'il est écrit
var chemin := ""
var erreurs := PackedStringArray()  # vide = plan valide
var pieces: Array = []             # pièces mises à plat, dans l'ordre du fichier (repère du vaisseau)
var articulations := {}            # id → articulation mise à plat (repère du vaisseau)
var _masse_cache = null            # propriétés de masse du plan entier (calculées une fois)

## Fichiers déjà lus (le jeu et les tests créent beaucoup de vaisseaux : on ne relit pas le disque).
static var _textes := {}
static var _par_defaut = null


## Le plan du vaisseau de départ (lu une seule fois, puis partagé : ne pas le modifier).
static func par_defaut():
	if _par_defaut == null:
		var p = load("res://scripts/atelier/plan.gd").new()
		p.charger(PLAN_PAR_DEFAUT)
		_par_defaut = p
	return _par_defaut


func charger(chemin_fichier: String) -> bool:
	chemin = chemin_fichier
	var texte := _lire(chemin_fichier)
	if texte == "":
		erreurs = PackedStringArray(["fichier introuvable ou vide : " + chemin_fichier])
		return false
	return lire_texte(texte)


func lire_texte(texte: String) -> bool:
	var d = JSON.parse_string(texte)
	if not d is Dictionary:
		erreurs = PackedStringArray(["le fichier n'est pas un plan lisible (JSON invalide)"])
		return false
	return lire_dictionnaire(d)


func lire_dictionnaire(d: Dictionary) -> bool:
	donnees = d
	erreurs = PackedStringArray()
	pieces = []
	articulations = {}
	_masse_cache = null
	if String(d.get("format", "")) != FORMAT:
		erreurs.append("ce n'est pas un plan de vaisseau (format « %s »)" % d.get("format", ""))
		return false
	var version := int(d.get("version", 0))
	if version > VERSION:
		erreurs.append("plan en version %d, fait par un jeu plus récent (ce jeu lit jusqu'à la version %d)" % [version, VERSION])
		return false
	if version < 1:
		erreurs.append("version du plan manquante")
		return false
	_aplatir(d.get("pieces", []), d.get("articulations", []), Transform3D.IDENTITY, "", "", 0)
	_verifier()
	return erreurs.is_empty()


func vers_texte() -> String:
	return JSON.stringify(donnees, "\t", false)


func sauver(chemin_fichier: String) -> Error:
	var f := FileAccess.open(chemin_fichier, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(vers_texte() + "\n")
	f.close()
	_textes.erase(chemin_fichier)
	return OK


func valide() -> bool:
	return erreurs.is_empty() and not donnees.is_empty()


func pieces_de_type(t: String) -> Array:
	return pieces.filter(func(p): return p["type"] == t)


## Valeur (0 à 1) d'une commande (ailes, train, vertical) dans la pose de référence du plan.
func valeur_reference(commande: String) -> float:
	return float((donnees.get("commandes", {}) as Dictionary).get(commande, {}).get("reference", 0.0))


## Valeur d'une commande au départ du jeu.
func valeur_depart(commande: String) -> float:
	return float((donnees.get("commandes", {}) as Dictionary).get(commande, {}).get("depart", valeur_reference(commande)))


## Durée (s) d'un mouvement complet d'une commande.
func duree_commande(commande: String) -> float:
	return float((donnees.get("commandes", {}) as Dictionary).get(commande, {}).get("duree_s", 1.0))


## Avancement (0 à 1) d'une articulation quand sa commande vaut c : la commande ramenée à sa phase.
static func progression(a: Dictionary, c: float) -> float:
	var ph: Array = a.get("phase", [0.0, 1.0])
	var debut := float(ph[0])
	var fin := float(ph[1])
	return clampf((c - debut) / (fin - debut), 0.0, 1.0) if fin > debut else (1.0 if c >= fin else 0.0)


# =====================================================================
# MISE À PLAT DES ENSEMBLES
# =====================================================================
const POINTS := ["centre", "point", "position", "pivot"]
const VECTEURS := ["direction", "normale", "course"]
const LISTES_POINTS := ["sommets"]   # listes de points (coins d'un panneau)


func _aplatir(liste: Array, arts: Array, xf: Transform3D, prefixe: String, art_herite: String, profondeur: int) -> void:
	if profondeur > 8:
		erreurs.append("ensembles imbriqués trop profondément (plus de 8 niveaux) : " + prefixe)
		return
	var locales := {}
	for a in arts:
		if not a is Dictionary or not a.has("id"):
			erreurs.append("articulation sans id dans « %s »" % (prefixe if prefixe != "" else "le plan"))
			continue
		var id := prefixe + String(a["id"])
		if articulations.has(id):
			erreurs.append("articulation « %s » en double" % id)
		locales[String(a["id"])] = id
		articulations[id] = _placer_articulation(a, xf, id)
	for i in liste.size():
		var p = liste[i]
		if not p is Dictionary:
			erreurs.append("pièce n° %d de « %s » illisible" % [i + 1, prefixe if prefixe != "" else "le plan"])
			continue
		var art := art_herite
		if p.has("articulation") and p["articulation"] != null and String(p["articulation"]) != "":
			var nom_art := String(p["articulation"])
			art = String(locales.get(nom_art, nom_art))
		var id := prefixe + String(p.get("id", "piece_%d" % (i + 1)))
		if String(p.get("type", "")) == "ensemble":
			var sous_pieces: Array = p.get("pieces", [])
			var sous_arts: Array = p.get("articulations", [])
			if p.has("plan"):
				var autre = load("res://scripts/atelier/plan.gd").new()
				var texte := _lire(String(p["plan"]))
				var dd = JSON.parse_string(texte) if texte != "" else null
				if not dd is Dictionary:
					erreurs.append("ensemble « %s » : plan « %s » illisible" % [id, p["plan"]])
					continue
				sous_pieces = dd.get("pieces", [])
				sous_arts = dd.get("articulations", [])
			var b := Catalogue.rotation(p.get("rotation_deg", [0.0, 0.0, 0.0]))
			if bool(p.get("miroir_x", false)):
				b = b * Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
			var xf2 := xf * Transform3D(b, Catalogue.vecteur(p.get("position", [0.0, 0.0, 0.0])))
			var debut := pieces.size()
			_aplatir(sous_pieces, sous_arts, xf2, id + "/", art, profondeur + 1)
			if p.has("modele"):
				# pièce toute faite (ou élément d'armature) posée dans l'atelier : ses morceaux savent de quelle
				# pièce ils viennent
				for k in range(debut, pieces.size()):
					pieces[k]["ajout"] = id
					pieces[k]["nom_ajout"] = String(p.get("nom", id))
					pieces[k]["modele_ajout"] = String(p["modele"])
			continue
		pieces.append(_placer_piece(p, xf, id, art))


## Copie de la pièce, placée dans le repère du vaisseau, avec sa masse calculée (« masse_calculee »).
func _placer_piece(p: Dictionary, xf: Transform3D, id: String, art: String) -> Dictionary:
	var q := p.duplicate(true)
	q["id"] = id
	q["articulation"] = art
	var mp := {"masse": 0.0, "centre": Vector3.ZERO, "inertie": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]}
	var t := String(p.get("type", ""))
	if Catalogue.TYPES.has(t) and _champs_presents(p, t, id):
		mp = Catalogue.masse_piece(p)
	var b := xf.basis
	for k in POINTS:
		if q.has(k):
			q[k] = xf * Catalogue.vecteur(q[k])
	for k in VECTEURS:
		if q.has(k):
			q[k] = b * Catalogue.vecteur(q[k])
	for k in LISTES_POINTS:
		if q.has(k) and q[k] is Array:
			var placees := []
			for x in q[k]:
				placees.append(xf * Catalogue.vecteur(x))
			q[k] = placees
	for k in ["direction", "normale"]:
		if q.has(k) and (q[k] as Vector3).length() > 0.0:
			q[k] = (q[k] as Vector3).normalized()
	# masse : centre placé, inertie tournée (B·I·Bᵀ, vrai aussi pour un miroir)
	# orientation complète de la pièce dans le vaisseau (ensembles compris) : sert à la DESSINER
	# (scripts/dessin_vaisseau.gd, étape 5) ; « position » est déjà placée, « rotation_deg » reste locale
	var rot = p.get("rotation_deg", [0.0, 0.0, 0.0])
	q["base"] = b * (Catalogue.rotation(rot) if rot is Array and (rot as Array).size() == 3 else Basis.IDENTITY)
	var c: Vector3 = xf * (mp["centre"] as Vector3)
	var inertie: Array = mp["inertie"]
	if xf.basis != Basis.IDENTITY:
		inertie = Catalogue.de_basis(b * Catalogue.vers_basis(inertie) * b.transposed())
	q["masse_calculee"] = {"masse": float(mp["masse"]), "centre": c, "inertie": inertie}
	return q


func _placer_articulation(a: Dictionary, xf: Transform3D, id: String) -> Dictionary:
	var q := a.duplicate(true)
	q["id"] = id
	var b := xf.basis
	for k in ["point", "pivot"]:
		if q.has(k):
			q[k] = xf * Catalogue.vecteur(q[k])
	if q.has("course"):
		q["course"] = b * Catalogue.vecteur(q["course"])
	if q.has("axe"):
		# un axe de rotation est retourné par un miroir (la rotation change de sens) : signe du déterminant
		q["axe"] = ((b * Catalogue.vecteur(q["axe"])) * signf(b.determinant())).normalized()
	return q


func _champs_presents(p: Dictionary, t: String, id: String) -> bool:
	var ok := true
	for c in Catalogue.TYPES[t]["champs"]:
		if not p.has(c):
			erreurs.append("pièce « %s » (%s) : réglage « %s » manquant" % [id, t, c])
			ok = false
	if ok and p.has("matiere") and p["matiere"] != null and not Catalogue.MATIERES.has(String(p["matiere"])):
		erreurs.append("pièce « %s » : matière « %s » inconnue" % [id, p["matiere"]])
		ok = false
	if ok and t == "panneau" and (not p["sommets"] is Array or not ((p["sommets"] as Array).size() in [3, 4])):
		erreurs.append("panneau « %s » : il faut 3 ou 4 coins" % id)
		ok = false
	return ok


func _verifier() -> void:
	var vus := {}
	for p in pieces:
		var id: String = p["id"]
		var t := String(p.get("type", ""))
		if vus.has(id):
			erreurs.append("pièce « %s » en double" % id)
		vus[id] = true
		if not Catalogue.TYPES.has(t):
			erreurs.append("pièce « %s » : type « %s » inconnu" % [id, t])
			continue
		var art: String = p["articulation"]
		if art != "" and not articulations.has(art):
			erreurs.append("pièce « %s » : articulation « %s » introuvable" % [id, art])
		for k in ["direction", "normale"]:
			if p.has(k) and (p[k] as Vector3).length() == 0.0:
				erreurs.append("pièce « %s » : %s nulle" % [id, k])
		if float(p["masse_calculee"]["masse"]) < 0.0:
			erreurs.append("pièce « %s » : masse négative" % id)
	for id in articulations:
		var a: Dictionary = articulations[id]
		var t := String(a.get("type", ""))
		if not Catalogue.ARTICULATIONS.has(t):
			erreurs.append("articulation « %s » : type « %s » inconnu" % [id, t])
			continue
		for c in Catalogue.ARTICULATIONS[t]["champs"]:
			if not a.has(c):
				erreurs.append("articulation « %s » (%s) : réglage « %s » manquant" % [id, t, c])
		if not (donnees.get("commandes", {}) as Dictionary).has(String(a.get("commande", ""))):
			erreurs.append("articulation « %s » : commande « %s » inconnue" % [id, a.get("commande", "")])
		elif t == "tuyere_anneaux" and progression(a, valeur_reference(String(a["commande"]))) > 0.0:
			erreurs.append("tuyère « %s » : elle doit être droite dans la pose de référence du plan" % id)


# =====================================================================
# MASSE, CENTRE DE GRAVITÉ, INERTIE
# =====================================================================
## Calculés à partir des pièces, en double précision, dans la pose de référence du plan.
## Renvoie {masse (kg), centre (Vector3), inertie (Basis 3×3 autour du centre de gravité, kg·m²),
## inertie_liste ([Ixx, Iyy, Izz, Ixy, Ixz, Iyz]), masse_par_matiere ({matière: kg}), pieces_pesantes}.
func proprietes_masse(liste := []) -> Dictionary:
	if liste.is_empty():
		if _masse_cache != null:
			return _masse_cache
		_masse_cache = _calculer_masse(pieces)
		return _masse_cache
	return _calculer_masse(liste)


func _calculer_masse(liste: Array) -> Dictionary:
	var m := 0.0
	var s := [0.0, 0.0, 0.0]
	var par_matiere := {}
	var n := 0
	for p in liste:
		var mp: Dictionary = p["masse_calculee"]
		var mi: float = mp["masse"]
		if mi <= 0.0:
			continue
		n += 1
		var c: Vector3 = mp["centre"]
		m += mi
		s[0] += mi * c.x
		s[1] += mi * c.y
		s[2] += mi * c.z
		var mat := String(p.get("matiere", "")) if p.get("matiere", null) != null else ""
		if mat == "":
			mat = "équipements"
		par_matiere[mat] = float(par_matiere.get(mat, 0.0)) + mi
	if m <= 0.0:
		return {"masse": 0.0, "centre": Vector3.ZERO, "inertie": Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO),
			"inertie_liste": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "masse_par_matiere": {}, "pieces_pesantes": 0}
	var g := [s[0] / m, s[1] / m, s[2] / m]
	var i6 := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # xx, yy, zz, xy, xz, yz
	for p in liste:
		var mp: Dictionary = p["masse_calculee"]
		var mi: float = mp["masse"]
		if mi <= 0.0:
			continue
		var c: Vector3 = mp["centre"]
		var dx: float = c.x - g[0]
		var dy: float = c.y - g[1]
		var dz: float = c.z - g[2]
		var propre: Array = mp["inertie"]
		# Huygens : I = I_propre + m · (d² · 1 − d · dᵀ)
		i6[0] += float(propre[0]) + mi * (dy * dy + dz * dz)
		i6[1] += float(propre[1]) + mi * (dx * dx + dz * dz)
		i6[2] += float(propre[2]) + mi * (dx * dx + dy * dy)
		i6[3] += float(propre[3]) - mi * dx * dy
		i6[4] += float(propre[4]) - mi * dx * dz
		i6[5] += float(propre[5]) - mi * dy * dz
	return {"masse": m, "centre": Vector3(g[0], g[1], g[2]), "inertie": Catalogue.vers_basis(i6), "inertie_liste": i6,
		"masse_par_matiere": par_matiere, "pieces_pesantes": n}


static func _lire(chemin_fichier: String) -> String:
	if _textes.has(chemin_fichier):
		return _textes[chemin_fichier]
	if not FileAccess.file_exists(chemin_fichier):
		return ""
	var texte := FileAccess.get_file_as_string(chemin_fichier)
	_textes[chemin_fichier] = texte
	return texte
