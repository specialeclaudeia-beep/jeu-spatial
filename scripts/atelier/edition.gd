extends RefCounted
## Atelier, étape 3 : l'ÉDITION du plan d'un vaisseau. Tout ce qu'on fait dans l'atelier passe par ici :
## poser une pièce toute faite, la déplacer, la régler, la supprimer (et enlever des pièces ou des modules
## du chasseur), annuler et refaire, renommer, enregistrer.
##
## On travaille sur une copie du plan (donnees, le texte du fichier) ; après chaque changement, le plan est
## relu (plan()) et l'atelier refait la physique, le dessin et le tableau ingénieur avec le même code que le
## jeu. Rien n'est écrit sur le disque avant « Enregistrer » (ou la sauvegarde automatique, ou « Lancer »).
##
## Symétrie : une pièce posée en symétrie a une jumelle, de l'autre côté du plan gauche-droite du vaisseau
## (x = 0). Les deux sont liées (« symetrique ») : déplacer, régler ou supprimer l'une fait pareil pour l'autre.
## Positions et orientations : repère du plan, dans sa pose de référence (ailes ouvertes, train rentré).
##
## Étape 6 : l'ARMATURE (scripts/atelier/armature.gd). On trace des poutres d'un point à un autre (un
## connecteur se fabrique à chaque bout ; finir sur une poutre la coupe et fait un connecteur en T), on
## remplit une zone fermée par 3 ou 4 poutres d'un panneau, on déplace un connecteur (ses poutres et ses
## panneaux suivent). En symétrie, tout a sa jumelle de l'autre côté. Enlever un connecteur enlève ses
## poutres ; enlever une poutre enlève les panneaux qu'elle bordait.

signal change

const Plan = preload("res://scripts/atelier/plan.gd")
const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")
const Armature = preload("res://scripts/atelier/armature.gd")

const DOSSIER := "user://vaisseaux/"
const HISTOIRE_MAX := 80                          # nombre de retours en arrière possibles
const MIROIR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))   # gauche ↔ droite (x → −x)
const SUR_L_AXE := 0.05                           # m : une pièce posée à moins de 5 cm du milieu n'a pas de jumelle
## Modules qu'on ne peut pas enlever : le jeu en a besoin (le pilote est dans le cockpit).
const MODULES_INDISPENSABLES := ["cockpit"]

var donnees := {}
var chemin := ""          # fichier où le vaisseau est enregistré (user://vaisseaux/…) ; "" = pas encore
var source := ""          # fichier d'où il a été ouvert
var modifie := false      # changé depuis le dernier enregistrement
var _passe: Array = []    # états d'avant (pour annuler)
var _futur: Array = []    # états annulés (pour refaire)
var _plan = null          # le plan relu (gardé jusqu'au prochain changement)
var _nom_source := ""     # nom du vaisseau ouvert (celui du jeu ne s'écrase pas : la copie s'appelle « … modifié »)


func _init(d: Dictionary = {}, chemin_source := "") -> void:
	donnees = d.duplicate(true)
	source = chemin_source
	chemin = chemin_source if chemin_source.begins_with(DOSSIER) else ""
	if not donnees.has("pieces"):
		donnees["pieces"] = []
	_nom_source = nom()
	# les pièces toutes faites sont refabriquées à partir de leurs réglages (si le catalogue a changé)
	for e in donnees["pieces"]:
		if e is Dictionary and e.has("modele") and Pieces.existe(String(e["modele"])):
			e["reglages"] = Pieces.reglages_complets(String(e["modele"]), e.get("reglages", {}))
			Pieces.remplir(e, String(e["modele"]), e["reglages"])
	if Armature.a_armature(donnees):
		Armature.refaire(donnees)


## Le plan relu à partir du texte actuel (scripts/atelier/plan.gd).
func plan():
	if _plan == null:
		_plan = Plan.new()
		_plan.lire_dictionnaire(donnees.duplicate(true))
		_plan.chemin = chemin if chemin != "" else source
	return _plan


func nom() -> String:
	return String(donnees.get("nom", "Vaisseau"))


# =====================================================================
# HISTOIRE : annuler / refaire
# =====================================================================
func _avant() -> void:
	_passe.append(donnees.duplicate(true))
	if _passe.size() > HISTOIRE_MAX:
		_passe.pop_front()
	_futur.clear()


func _apres() -> void:
	# le vaisseau du jeu (res://) ne peut pas être écrit : ses changements deviennent un vaisseau à toi
	if chemin == "" and source.begins_with("res://") and nom() == _nom_source:
		donnees["nom"] = _nom_source + " modifié"
	modifie = true
	_plan = null
	change.emit()


func peut_annuler() -> bool:
	return not _passe.is_empty()


func peut_refaire() -> bool:
	return not _futur.is_empty()


func annuler() -> bool:
	if _passe.is_empty():
		return false
	_futur.append(donnees)
	donnees = _passe.pop_back()
	_apres()
	return true


func refaire() -> bool:
	if _futur.is_empty():
		return false
	_passe.append(donnees)
	donnees = _futur.pop_back()
	_apres()
	return true


# =====================================================================
# LES PIÈCES DU PLAN (premier niveau)
# =====================================================================
func pieces_racine() -> Array:
	return donnees["pieces"]


## La pièce de premier niveau qui a cet id (vide si aucune).
func element(id: String) -> Dictionary:
	for e in donnees["pieces"]:
		if e is Dictionary and String(e.get("id", "")) == id:
			return e
	return {}


func est_ajout(id: String) -> bool:
	var e := element(id)
	return not e.is_empty() and e.has("modele")


## Les pièces toutes faites posées (ensembles avec un modèle, sans l'armature), dans l'ordre du plan.
func ajouts() -> Array:
	return (donnees["pieces"] as Array).filter(func(e): return e is Dictionary and e.has("modele") and not Armature.est(e))


## L'armature (connecteurs, poutres, panneaux), dans l'ordre du plan ; modele : seulement ceux-là.
func armature(modele := "") -> Array:
	return (donnees["pieces"] as Array).filter(func(e): return Armature.est(e) and (modele == "" or String(e["modele"]) == modele))


## Les modules du chasseur : {clé: {"nom": …, "ids": [pièces de premier niveau]}} (dans l'ordre du plan).
func modules() -> Dictionary:
	var noms: Dictionary = donnees.get("modules", {})
	var d := {}
	for e in donnees["pieces"]:
		if not e is Dictionary or e.has("modele") or not e.has("module"):
			continue
		var m := String(e["module"])
		if not d.has(m):
			d[m] = {"nom": String(noms.get(m, m)), "ids": []}
		(d[m]["ids"] as Array).append(String(e["id"]))
	return d


func nom_module(cle: String) -> String:
	return String((donnees.get("modules", {}) as Dictionary).get(cle, cle))


# =====================================================================
# PLACE ET ORIENTATION D'UNE PIÈCE TOUTE FAITE
# =====================================================================
## Transformation d'un ensemble (repère du plan) : position, rotation, miroir.
static func xf_de(e: Dictionary) -> Transform3D:
	var b := Catalogue.rotation(e.get("rotation_deg", [0.0, 0.0, 0.0]))
	if bool(e.get("miroir_x", false)):
		b = b * MIROIR
	return Transform3D(b, Catalogue.vecteur(e.get("position", [0.0, 0.0, 0.0])))


## Écrit une transformation dans un ensemble (une orientation « en miroir » devient rotation + miroir_x).
static func ecrire_xf(e: Dictionary, xf: Transform3D) -> void:
	var b := xf.basis.orthonormalized()
	var miroir := b.determinant() < 0.0
	if miroir:
		b = b * MIROIR
	var eu := b.get_euler()
	e["position"] = [snappedf(xf.origin.x, 0.0001), snappedf(xf.origin.y, 0.0001), snappedf(xf.origin.z, 0.0001)]
	e["rotation_deg"] = [snappedf(rad_to_deg(eu.x), 0.001), snappedf(rad_to_deg(eu.y), 0.001), snappedf(rad_to_deg(eu.z), 0.001)]
	for i in 3:
		if absf(float(e["rotation_deg"][i])) < 0.0005:
			e["rotation_deg"][i] = 0.0
	if miroir:
		e["miroir_x"] = true
	else:
		e.erase("miroir_x")


## La même place, de l'autre côté (gauche ↔ droite).
static func miroir(xf: Transform3D) -> Transform3D:
	return Transform3D(MIROIR * xf.basis, MIROIR * xf.origin)


## Le nom de la pièce (ou de l'articulation) qui est de l'autre côté : « Aile_haut_gauche » ↔
## « Aile_haut_droit », « Aileron_g » ↔ « Aileron_d ». Pour une pièce toute faite : sa jumelle. S'il n'y
## en a pas (pièce du milieu, comme le fuselage), le même nom.
func nom_miroir(id: String) -> String:
	if id == "":
		return ""
	var e := element(id)
	if not e.is_empty() and e.has("symetrique") and not element(String(e["symetrique"])).is_empty():
		return String(e["symetrique"])
	var candidats := []
	for paire in [["gauche", "droite"], ["gauche", "droit"]]:
		if id.contains(paire[0]):
			candidats.append(id.replace(paire[0], paire[1]))
		if id.contains(paire[1]):
			candidats.append(id.replace(paire[1], paire[0]))
	if id.ends_with("_g"):
		candidats.append(id.trim_suffix("_g") + "_d")
	if id.ends_with("_d"):
		candidats.append(id.trim_suffix("_d") + "_g")
	var p = plan()
	for c in candidats:
		if not element(c).is_empty() or p.articulations.has(c) or _a_piece(p, c):
			return c
	# étape 7 : partie d'une pièce posée (« charniere_1/mouvement ») : la même partie de sa jumelle
	var i := id.rfind("/")
	if i > 0:
		var base := id.substr(0, i)
		var m := nom_miroir(base)
		if m != base:
			return m + id.substr(i)
	return id


static func _a_piece(p, id: String) -> bool:
	for q in p.pieces:
		if q["id"] == id:
			return true
	return false


func _numero_libre(prefixe: String) -> int:
	var n := 1
	var pris := {}
	for e in donnees["pieces"]:
		if e is Dictionary:
			pris[String(e.get("id", ""))] = true
	while pris.has("%s_%d" % [prefixe, n]):
		n += 1
	return n


# =====================================================================
# OPÉRATIONS (chacune peut être annulée)
# =====================================================================
## Pose une pièce toute faite. xf : sa place (repère du plan) ; fixe_a : la pièce sur laquelle elle est
## posée ; articulation : la pièce mobile qu'elle suit (aile…) ; symetrie : poser aussi sa jumelle de
## l'autre côté. Renvoie les ids des pièces posées.
func ajouter(modele: String, reglages: Dictionary, xf: Transform3D, fixe_a := "", articulation := "", symetrie := false) -> Array:
	if not Pieces.existe(modele):
		return []
	_avant()
	var r := Pieces.reglages_complets(modele, reglages)
	var jumelle := symetrie and absf(xf.origin.x) > SUR_L_AXE
	var n := _numero_libre(modele)
	var id := "%s_%d" % [modele, n]
	var e := _nouvel_ensemble(id, modele, r, xf, fixe_a, articulation)
	e["nom"] = _nom_ajout(modele, n, xf.origin.x if jumelle else 0.0)
	pieces_racine().append(e)
	var ids := [id]
	if jumelle:
		var id2 := "%s_%d" % [modele, _numero_libre(modele)]
		var e2 := _nouvel_ensemble(id2, modele, r, miroir(xf), nom_miroir(fixe_a), nom_miroir(articulation))
		e2["nom"] = _nom_ajout(modele, n, -xf.origin.x)
		e["symetrique"] = id2
		e2["symetrique"] = id
		pieces_racine().append(e2)
		ids.append(id2)
	_apres()
	return ids


func _nouvel_ensemble(id: String, modele: String, r: Dictionary, xf: Transform3D, fixe_a: String, articulation: String) -> Dictionary:
	var e := {"id": id, "type": "ensemble", "modele": modele, "nom": Pieces.nom(modele), "reglages": r.duplicate()}
	ecrire_xf(e, xf)
	if fixe_a != "":
		e["fixe_a"] = fixe_a
	if articulation != "":
		e["articulation"] = articulation
	Pieces.remplir(e, modele, r)
	return e


static func _nom_ajout(modele: String, n: int, x: float) -> String:
	var cote := ""
	if x < -SUR_L_AXE:
		cote = " gauche"
	elif x > SUR_L_AXE:
		cote = " droite"
	return "%s %d%s" % [Pieces.nom(modele), n, cote]


## Déplace (et tourne) une pièce toute faite ; sa jumelle suit, de l'autre côté.
func placer(id: String, xf: Transform3D, fixe_a := "", articulation := "") -> void:
	var e := element(id)
	if e.is_empty() or not e.has("modele") or Armature.est(e):
		return   # (l'armature se déplace par ses connecteurs : deplacer_noeud)
	_avant()
	_poser(e, xf, fixe_a, articulation)
	var j := element(String(e.get("symetrique", "")))
	if not j.is_empty():
		_poser(j, miroir(xf), nom_miroir(fixe_a), nom_miroir(articulation))
	_apres()


func _poser(e: Dictionary, xf: Transform3D, fixe_a: String, articulation: String) -> void:
	ecrire_xf(e, xf)
	if fixe_a != "":
		e["fixe_a"] = fixe_a
	else:
		e.erase("fixe_a")
	if articulation != "":
		e["articulation"] = articulation
	else:
		e.erase("articulation")


## Change la place sans changer la fixation (réglage à la main des coordonnées dans la fiche).
func deplacer_a_la_main(id: String, xf: Transform3D) -> void:
	var e := element(id)
	if e.is_empty():
		return
	placer(id, xf, String(e.get("fixe_a", "")), String(e.get("articulation", "")))


## Change un réglage (poussée, dimension, matière…) ; la jumelle prend le même.
func regler(id: String, cle: String, valeur) -> void:
	var e := element(id)
	if e.is_empty() or not e.has("modele"):
		return
	if Armature.est(e):
		regler_armature([id], {cle: valeur})
		return
	var modele := String(e["modele"])
	var r: Dictionary = (e.get("reglages", {}) as Dictionary).duplicate()
	r[cle] = valeur
	r = Pieces.reglages_complets(modele, r)
	if r == e.get("reglages", {}):
		return
	_avant()
	for x in [e, element(String(e.get("symetrique", "")))]:
		if (x as Dictionary).is_empty():
			continue
		x["reglages"] = r.duplicate()
		Pieces.remplir(x, modele, r)
	_apres()


## Supprime des pièces de premier niveau (une pièce toute faite part avec sa jumelle) ou des modules entiers
## du chasseur (« module:clé »). Les pièces qui étaient posées dessus restent (elles ne touchent plus rien).
func supprimer(ids: Array) -> int:
	var a_enlever := {}
	var mods := modules()
	for id in ids:
		var s := String(id)
		if s.begins_with("module:"):
			if MODULES_INDISPENSABLES.has(s.trim_prefix("module:")):
				continue
			for i in mods.get(s.trim_prefix("module:"), {}).get("ids", []):
				a_enlever[i] = true
			continue
		var e := element(s)
		if e.is_empty() or MODULES_INDISPENSABLES.has(String(e.get("module", ""))):
			continue
		a_enlever[s] = true
		if e.has("symetrique"):
			a_enlever[String(e["symetrique"])] = true
	_cascade_armature(a_enlever)
	if a_enlever.is_empty():
		return 0
	_avant()
	var reste := []
	for e in donnees["pieces"]:
		if e is Dictionary and a_enlever.has(String(e.get("id", ""))):
			continue
		reste.append(e)
	donnees["pieces"] = reste
	# une jumelle dont l'autre a disparu devient une pièce seule
	for e in reste:
		if e is Dictionary and e.has("symetrique") and a_enlever.has(String(e["symetrique"])):
			e.erase("symetrique")
		# étape 7 : posée sur une pièce mobile enlevée (« charniere_1/mouvement ») : elle ne bouge plus
		if e is Dictionary and e.has("articulation"):
			var art := String(e["articulation"])
			var k := art.rfind("/")
			if k > 0 and a_enlever.has(art.substr(0, k)):
				e.erase("articulation")
	if Armature.a_armature(donnees):
		Armature.refaire(donnees)   # les connecteurs qui n'ont plus de poutre partent aussi
	_apres()
	return a_enlever.size()


## Étape 7 : durée (s) d'un mouvement complet d'une commande (ailes, train, vol vertical), dans le plan.
func regler_duree_commande(c: String, s: float) -> void:
	if not Catalogue.COMMANDES.has(c):
		return
	s = clampf(s, 0.2, 30.0)
	var cmds: Dictionary = donnees.get("commandes", {})
	var d: Dictionary = cmds.get(c, {})
	if is_equal_approx(float(d.get("duree_s", -1.0)), s):
		return
	_avant()
	if not donnees.has("commandes"):
		donnees["commandes"] = {}
	if not (donnees["commandes"] as Dictionary).has(c):
		donnees["commandes"][c] = {"nom": String(Catalogue.COMMANDES[c]["nom"])}
	donnees["commandes"][c]["duree_s"] = snappedf(s, 0.1)
	_apres()


## Délie une pièce de sa jumelle (elles deviennent deux pièces indépendantes).
func separer_symetrie(id: String) -> void:
	var e := element(id)
	if e.is_empty() or not e.has("symetrique"):
		return
	_avant()
	var j := element(String(e["symetrique"]))
	e.erase("symetrique")
	if not j.is_empty():
		j.erase("symetrique")
	_apres()


# =====================================================================
# L'ARMATURE : poutres, connecteurs, panneaux (étape 6)
# =====================================================================
## Le connecteur à cette place (à 1 cm près), ou "".
func connecteur_a(p: Vector3, sauf := "") -> String:
	var meilleur := ""
	var d_min := Armature.MEME_POINT
	for e in armature(Armature.CONNECTEUR):
		var d := Armature.position(e).distance_to(p)
		if d <= d_min and String(e["id"]) != sauf:
			d_min = d
			meilleur = String(e["id"])
	return meilleur


## La poutre qui passe à moins de 2 cm de ce point (loin de ses bouts), ou "".
func poutre_par(p: Vector3) -> String:
	var g := Armature.graphe(donnees)
	var meilleur := ""
	var d_min := 0.02
	for id in g["poutres"]:
		var n: Array = g["poutres"][id]["noeuds"]
		var a := Armature.position(g["connecteurs"][String(n[0])])
		var b := Armature.position(g["connecteurs"][String(n[1])])
		var q := Geometry3D.get_closest_point_to_segment(p, a, b)
		if q.distance_to(a) < Armature.LONGUEUR_MIN or q.distance_to(b) < Armature.LONGUEUR_MIN:
			continue
		if q.distance_to(p) <= d_min:
			d_min = q.distance_to(p)
			meilleur = String(id)
	return meilleur


func _nouveau_connecteur(p: Vector3, fixe_a: String, art: String) -> String:
	var n := _numero_libre(Armature.CONNECTEUR)
	var id := "%s_%d" % [Armature.CONNECTEUR, n]
	var e := {"id": id, "type": "ensemble", "modele": Armature.CONNECTEUR, "nom": "Connecteur %d" % n,
		"position": [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)], "rotation_deg": [0.0, 0.0, 0.0],
		"reglages": {}, "pieces": []}
	if fixe_a != "":
		e["fixe_a"] = fixe_a
		if art != "":
			e["articulation_appui"] = art
	pieces_racine().append(e)
	return id


func _nouvelle_poutre(a: String, b: String, r: Dictionary) -> String:
	var n := _numero_libre(Armature.POUTRE)
	var id := "%s_%d" % [Armature.POUTRE, n]
	pieces_racine().append({"id": id, "type": "ensemble", "modele": Armature.POUTRE, "nom": "Poutre %d" % n,
		"noeuds": [a, b], "reglages": Armature.reglages_complets(Armature.POUTRE, r), "pieces": []})
	return id


## Coupe une poutre au point le plus proche de p : un connecteur (en T) au milieu, deux poutres de part et
## d'autre (mêmes réglages). Renvoie le connecteur (ou le bout de la poutre, si p en est tout près).
func _couper(pid: String, p: Vector3) -> String:
	var e := element(pid)
	var n: Array = e["noeuds"]
	var a := Armature.position(element(String(n[0])))
	var b := Armature.position(element(String(n[1])))
	var q := Geometry3D.get_closest_point_to_segment(p, a, b)
	if q.distance_to(a) < Armature.LONGUEUR_MIN:
		return String(n[0])
	if q.distance_to(b) < Armature.LONGUEUR_MIN:
		return String(n[1])
	var c := _nouveau_connecteur(q, "", "")
	var fin := String(n[1])
	e["noeuds"] = [String(n[0]), c]
	var id2 := _nouvelle_poutre(c, fin, e.get("reglages", {}))
	# la jumelle de la poutre coupée sera coupée au même endroit (de l'autre côté) : les morceaux se
	# retrouvent par leur place (_lier_poutres)
	if e.has("symetrique"):
		element(id2)["symetrique"] = "?"
	return c


## Un bout de poutre → l'id de son connecteur (créé s'il le faut). Bout : {"noeud": id} (un connecteur
## qui existe), {"point": Vector3, "fixe_a", "articulation"} (un nouveau, posé sur cette pièce), ou
## {"point": Vector3, "poutre": id} (sur une poutre : elle est coupée là).
func _connecteur_du_bout(b: Dictionary, sym: bool) -> String:
	if b.has("noeud"):
		return String(b["noeud"]) if not element(String(b["noeud"])).is_empty() else ""
	var p: Vector3 = b["point"]
	if sym and absf(p.x) <= Armature.SUR_L_AXE:
		p.x = 0.0   # sur l'axe du vaisseau : le connecteur est sa propre jumelle
	var deja := connecteur_a(p)
	if deja != "":
		return deja
	var par := poutre_par(p)   # (celle d'un bout « poutre » a pu être coupée par l'autre bout)
	if par != "":
		return _couper(par, p)
	if b.has("poutre") and not element(String(b["poutre"])).is_empty():
		return _couper(String(b["poutre"]), p)
	return _nouveau_connecteur(p, String(b.get("fixe_a", "")), String(b.get("articulation", "")))


static func _point_du_bout(b: Dictionary, donnees_: Dictionary) -> Variant:
	if b.has("point"):
		return b["point"]
	for e in donnees_["pieces"]:
		if Armature.est(e) and String(e["id"]) == String(b.get("noeud", "")):
			return Armature.position(e)
	return null


## Le jumeau d'un connecteur (de l'autre côté du vaisseau) : lui-même s'il est sur l'axe ; sinon celui qui
## est déjà au point miroir, ou une poutre coupée là, ou un nouveau, posé sur la pièce miroir de la sienne.
func _jumeau_noeud(id: String) -> String:
	var e := element(id)
	var p := Armature.position(e)
	if absf(p.x) <= Armature.SUR_L_AXE:
		return id
	if e.has("symetrique") and not element(String(e["symetrique"])).is_empty():
		return String(e["symetrique"])
	var q := Vector3(-p.x, p.y, p.z)
	var c := connecteur_a(q, id)
	if c == "":
		var par := poutre_par(q)
		if par != "":
			c = _couper(par, q)
		else:
			c = _nouveau_connecteur(q, nom_miroir(String(e.get("fixe_a", ""))), nom_miroir(String(e.get("articulation_appui", ""))))
	if c != id:
		e["symetrique"] = c
		element(c)["symetrique"] = id
	return c


## Les jumelles des poutres (et des connecteurs) retrouvées par leur place : après une coupe, les deux
## morceaux de chaque côté se reconnaissent.
func _lier_poutres() -> void:
	var g := Armature.graphe(donnees)
	for id in g["connecteurs"]:
		var e: Dictionary = g["connecteurs"][id]
		var p := Armature.position(e)
		if String(e.get("symetrique", "")) == "" and absf(p.x) > Armature.SUR_L_AXE:
			var c := connecteur_a(Vector3(-p.x, p.y, p.z), id)
			if c != "" and String(g["connecteurs"][c].get("symetrique", "")) == "":
				e["symetrique"] = c
				g["connecteurs"][c]["symetrique"] = id
	# chaque poutre qui avait une jumelle (ou un morceau de poutre coupée, « ? ») retrouve celle qui est
	# vraiment à sa place miroir ; sinon elle devient seule
	for id in g["poutres"]:
		var e: Dictionary = g["poutres"][id]
		if not e.has("symetrique"):
			continue
		var n: Array = e["noeuds"]
		var ja := _sym_noeud(String(n[0]))
		var jb := _sym_noeud(String(n[1]))
		var j := Armature.poutre_entre(g, ja, jb) if ja != "" and jb != "" else ""
		if j == "" or j == id:
			e.erase("symetrique")
		else:
			e["symetrique"] = j
			g["poutres"][j]["symetrique"] = id


## La jumelle d'un connecteur s'il en a une (lui-même s'il est sur l'axe), sinon "".
func _sym_noeud(id: String) -> String:
	var e := element(id)
	if e.is_empty():
		return ""
	if absf(Armature.position(e).x) <= Armature.SUR_L_AXE:
		return id
	var s := String(e.get("symetrique", ""))
	return s if not element(s).is_empty() else ""


## Trace une poutre de a à b (bouts : voir _connecteur_du_bout), avec ces réglages (matière, profil,
## section, paroi) ; symetrie : sa jumelle aussi, de l'autre côté. Renvoie {"poutres": [ids], "debut":
## connecteur de départ, "fin": connecteur d'arrivée (pour enchaîner), "erreur": texte ("" : posée)}.
func tracer_poutre(a: Dictionary, b: Dictionary, reglages := {}, sym := false) -> Dictionary:
	var pa = _point_du_bout(a, donnees)
	var pb = _point_du_bout(b, donnees)
	if pa == null or pb == null:
		return {"poutres": [], "erreur": "connecteur introuvable"}
	var l := (pa as Vector3).distance_to(pb)
	if l < Armature.LONGUEUR_MIN:
		return {"poutres": [], "erreur": "trop courte (5 cm au moins)"}
	if l > Armature.LONGUEUR_MAX:
		return {"poutres": [], "erreur": "trop longue (25 m au plus)"}
	_avant()
	var ida := _connecteur_du_bout(a, sym)
	var idb := _connecteur_du_bout(b, sym)
	var g := Armature.graphe(donnees)
	if ida == "" or idb == "" or ida == idb or Armature.poutre_entre(g, ida, idb) != "":
		donnees = _passe.pop_back()   # rien n'a changé
		return {"poutres": [], "erreur": "il y a déjà une poutre entre ces deux connecteurs" if ida != idb else "les deux bouts sont au même endroit"}
	var r := Armature.reglages_complets(Armature.POUTRE, reglages)
	var id := _nouvelle_poutre(ida, idb, r)
	var ids := [id]
	if sym:
		var ja := _jumeau_noeud(ida)
		var jb := _jumeau_noeud(idb)
		if Armature.cle([ja, jb]) != Armature.cle([ida, idb]) and ja != jb:
			var g2 := Armature.graphe(donnees)
			var j := Armature.poutre_entre(g2, ja, jb)
			if j == "":
				j = _nouvelle_poutre(ja, jb, r)
				ids.append(j)
			element(id)["symetrique"] = j
			element(j)["symetrique"] = id
	_lier_poutres()
	Armature.refaire(donnees)
	_apres()
	return {"poutres": ids, "debut": ida, "fin": idb, "erreur": ""}


## Remplit une zone fermée de l'armature (ses 3 ou 4 connecteurs) d'un panneau ; symetrie : la zone
## jumelle aussi. Renvoie les panneaux posés (vide : ce n'est pas une zone libre).
func remplir(noeuds: Array, reglages := {}, sym := false) -> Array:
	var zones := Armature.zones(donnees)
	var z := _zone(zones, Armature.cle(noeuds))
	if z.is_empty() or String(z["rempli"]) != "":
		return []
	_avant()
	var ids := [_nouveau_panneau(z["noeuds"], reglages)]
	if sym:
		var jn: Array = (z["noeuds"] as Array).map(func(i): return _sym_noeud(String(i)))
		if not jn.has("") and Armature.cle(jn) != String(z["cle"]):
			var zj := _zone(zones, Armature.cle(jn))
			if not zj.is_empty() and String(zj["rempli"]) == "":
				ids.append(_nouveau_panneau(zj["noeuds"], reglages))
				element(ids[0])["symetrique"] = ids[1]
				element(ids[1])["symetrique"] = ids[0]
	Armature.refaire(donnees)
	_apres()
	return ids


## Remplit toutes les zones libres de l'armature (une seule fois Ctrl + Z pour tout enlever).
func remplir_tout(reglages := {}, sym := false) -> int:
	var libres := Armature.zones(donnees).filter(func(z): return String(z["rempli"]) == "")
	if libres.is_empty():
		return 0
	_avant()
	var faits := {}
	for z in libres:
		faits[String(z["cle"])] = _nouveau_panneau(z["noeuds"], reglages)
	if sym:
		for z in libres:
			var jn: Array = (z["noeuds"] as Array).map(func(i): return _sym_noeud(String(i)))
			var k := Armature.cle(jn)
			if not jn.has("") and k != String(z["cle"]) and faits.has(k):
				element(faits[String(z["cle"])])["symetrique"] = faits[k]
	Armature.refaire(donnees)
	_apres()
	return faits.size()


static func _zone(zones: Array, k: String) -> Dictionary:
	for z in zones:
		if String(z["cle"]) == k:
			return z
	return {}


func _nouveau_panneau(noeuds: Array, r: Dictionary) -> String:
	var n := _numero_libre(Armature.PANNEAU)
	var id := "%s_%d" % [Armature.PANNEAU, n]
	pieces_racine().append({"id": id, "type": "ensemble", "modele": Armature.PANNEAU, "nom": "Panneau %d" % n,
		"noeuds": noeuds.duplicate(), "reglages": Armature.reglages_complets(Armature.PANNEAU, r), "pieces": []})
	return id


## Repeint un panneau (et sa jumelle) avec d'autres réglages : matière, épaisseur, porte dans l'air.
func repeindre(id: String, reglages: Dictionary) -> void:
	var e := element(id)
	if e.is_empty() or String(e.get("modele", "")) != Armature.PANNEAU:
		return
	var r := Armature.reglages_complets(Armature.PANNEAU, reglages)
	if r == e.get("reglages", {}):
		return
	_avant()
	for x in [e, element(String(e.get("symetrique", "")))]:
		if not (x as Dictionary).is_empty():
			x["reglages"] = r.duplicate()
	Armature.refaire(donnees)
	_apres()


## Déplace un connecteur (repère du plan, ailes ouvertes) ; ses poutres et ses panneaux suivent, sa
## jumelle aussi (en miroir). fixe_a : la pièce sur laquelle il est maintenant posé ("" : sur rien). Renvoie
## "" ou ce qui l'empêche.
func deplacer_noeud(id: String, p: Vector3, fixe_a := "", art := "") -> String:
	var e := element(id)
	if e.is_empty() or String(e.get("modele", "")) != Armature.CONNECTEUR:
		return "ce n'est pas un connecteur"
	var j := _sym_noeud(id)
	var sur_axe := j == id
	if sur_axe and absf(p.x) <= Armature.SUR_L_AXE:
		p.x = 0.0
	var autre := connecteur_a(p, id)
	if autre != "" and autre != j:
		return "il y a déjà un connecteur à cet endroit"
	_avant()
	_poser_noeud(e, p, fixe_a, art)
	if j != "" and j != id:
		_poser_noeud(element(j), Vector3(-p.x, p.y, p.z), nom_miroir(fixe_a), nom_miroir(art))
	var g := Armature.graphe(donnees)
	for pid in g["poutres"]:
		var n: Array = g["poutres"][pid]["noeuds"]
		var l := Armature.position(g["connecteurs"][String(n[0])]).distance_to(Armature.position(g["connecteurs"][String(n[1])]))
		if l < Armature.LONGUEUR_MIN or l > Armature.LONGUEUR_MAX:
			donnees = _passe.pop_back()
			return "une de ses poutres serait trop courte ou trop longue"
	Armature.refaire(donnees)
	_apres()
	return ""


func _poser_noeud(e: Dictionary, p: Vector3, fixe_a: String, art: String) -> void:
	e["position"] = [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)]
	if fixe_a != "" and fixe_a != String(e["id"]):
		e["fixe_a"] = fixe_a
	else:
		e.erase("fixe_a")
	if fixe_a != "" and art != "":
		e["articulation_appui"] = art
	else:
		e.erase("articulation_appui")


## Change des réglages de plusieurs éléments de l'armature à la fois (et de leurs jumelles) : un seul
## Ctrl + Z. Chacun ne prend que les réglages qu'il a (une poutre n'a pas d'épaisseur de panneau).
func regler_armature(ids: Array, reglages: Dictionary) -> int:
	var a_changer := []
	for id in ids:
		for x in [element(String(id)), element(String(element(String(id)).get("symetrique", "")))]:
			var e := x as Dictionary
			if not Armature.est(e) or a_changer.has(e):
				continue
			if _nouveaux_reglages(e, reglages) != Armature.reglages_complets(String(e["modele"]), e.get("reglages", {})):
				a_changer.append(e)
	if a_changer.is_empty():
		return 0
	_avant()
	for x in a_changer:
		var e := x as Dictionary
		e["reglages"] = _nouveaux_reglages(e, reglages)
	Armature.refaire(donnees)
	_apres()
	return a_changer.size()


static func _nouveaux_reglages(e: Dictionary, reglages: Dictionary) -> Dictionary:
	var r: Dictionary = (e.get("reglages", {}) as Dictionary).duplicate()
	for cle in reglages:
		if not Armature.definition_reglage(String(e["modele"]), String(cle)).is_empty():
			r[cle] = reglages[cle]
	return Armature.reglages_complets(String(e["modele"]), r)


## Ce qui part avec un élément de l'armature qu'on enlève : un connecteur emmène ses poutres et les
## panneaux dont il est un coin ; une poutre, les panneaux qu'elle borde ; et les jumelles de tout ça.
func _cascade_armature(a_enlever: Dictionary) -> void:
	if not Armature.a_armature(donnees):
		return
	var g := Armature.graphe(donnees)
	var encore := true
	while encore:
		encore = false
		var avant := a_enlever.size()
		for id in a_enlever.keys():
			if g["connecteurs"].has(id):
				for pid in Armature.poutres_de(g, id):
					a_enlever[pid] = true
				for qid in g["panneaux"]:
					if (g["panneaux"][qid]["noeuds"] as Array).has(id):
						a_enlever[qid] = true
			elif g["poutres"].has(id):
				var n: Array = g["poutres"][id]["noeuds"]
				for qid in g["panneaux"]:
					var c: Array = g["panneaux"][qid]["noeuds"]
					for k in c.size():
						if Armature.cle([c[k], c[(k + 1) % c.size()]]) == Armature.cle(n):
							a_enlever[qid] = true
			var e := element(String(id))
			if Armature.est(e) and e.has("symetrique"):
				a_enlever[String(e["symetrique"])] = true
		encore = a_enlever.size() != avant


func renommer(nouveau: String) -> void:
	nouveau = nouveau.strip_edges()
	if nouveau == "" or nouveau == nom():
		return
	_avant()
	donnees["nom"] = nouveau
	_apres()


# =====================================================================
# FICHIERS
# =====================================================================
## « Chasseur v27 modifié » → « chasseur_v27_modifie » (nom de fichier sans accents ni espaces).
static func nom_fichier(t: String) -> String:
	var s := t.to_lower()
	for paire in [["àâä", "a"], ["éèêë", "e"], ["îï", "i"], ["ôö", "o"], ["ùûü", "u"], ["ç", "c"], ["ÿ", "y"]]:
		for ch in String(paire[0]):
			s = s.replace(ch, paire[1])
	var sortie := ""
	for ch in s:
		sortie += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while sortie.contains("__"):
		sortie = sortie.replace("__", "_")
	sortie = sortie.strip_edges().trim_prefix("_").trim_suffix("_").left(48)
	return sortie if sortie != "" else "vaisseau"


## Texte du fichier : JSON lisible, listes de nombres sur une seule ligne.
func texte() -> String:
	var t := JSON.stringify(donnees, "\t", false)
	var re := RegEx.new()
	re.compile("\\[\\s*(-?[0-9][-0-9.eE+]*(?:,\\s*-?[0-9][-0-9.eE+]*)*)\\s*\\]")
	var sortie := ""
	var debut := 0
	for m in re.search_all(t):
		sortie += t.substr(debut, m.get_start() - debut)
		var nombres := PackedStringArray()
		for x in m.get_string(1).split(","):
			nombres.append(x.strip_edges())
		sortie += "[" + ", ".join(nombres) + "]"
		debut = m.get_end()
	return sortie + t.substr(debut)


## Enregistre une COPIE du vaisseau (« … (copie) ») dans un nouveau fichier ; l'original reste.
func enregistrer_copie(dossier := DOSSIER) -> Error:
	_avant()
	donnees["nom"] = nom() + " (copie)"
	chemin = ""
	_plan = null
	return enregistrer(dossier)


## Enregistre le vaisseau dans user://vaisseaux/<nom>.plan.json. Renommer puis enregistrer renomme le
## fichier ; un autre vaisseau qui a déjà ce nom n'est jamais écrasé (le nouveau prend « _2 », « _3 »…).
func enregistrer(dossier := DOSSIER) -> Error:
	DirAccess.make_dir_recursive_absolute(dossier)
	var base := dossier + nom_fichier(nom())
	var nouveau := base + ".plan.json"
	var k := 2
	while FileAccess.file_exists(nouveau) and nouveau != chemin:
		nouveau = "%s_%d.plan.json" % [base, k]
		k += 1
	donnees["format"] = Plan.FORMAT
	donnees["version"] = Plan.VERSION
	var f := FileAccess.open(nouveau, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(texte() + "\n")
	f.close()
	if chemin != "" and chemin != nouveau and chemin.begins_with(dossier) and FileAccess.file_exists(chemin):
		DirAccess.remove_absolute(chemin)   # le vaisseau a été renommé : l'ancien fichier part
		Plan._textes.erase(chemin)
	chemin = nouveau
	Plan._textes.erase(nouveau)
	modifie = false
	if _plan != null:
		_plan.chemin = chemin
	return OK
