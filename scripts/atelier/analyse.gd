extends RefCounted
## Atelier, étape 2 : ce que l'atelier AFFICHE sur le vaisseau, calculé par le MÊME code que le jeu.
##   - le tableau ingénieur (en haut de l'écran) : masse, poussée, poussée / poids, décollage vertical,
##     couple des moteurs, rotation des petits propulseurs, centre de gravité ;
##   - le classement des pièces du plan en catégories (catalogue à gauche) et la recherche ;
##   - la fiche de chaque pièce, de chaque type de pièce et de chaque matière (panneau de droite).
## Rien n'est recopié : tout vient du plan (scripts/atelier/plan.gd) et de la physique du vaisseau
## (scripts/physique/vaisseau_physique.gd), construite à partir de ce plan exactement comme dans le jeu.
## Pas de carburant : la masse ne change jamais.
## Étape 3 : les pièces toutes faites posées dans l'atelier (catégorie « Pièces ajoutées ») et les modules
## du chasseur ont aussi leur fiche.

const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")
const Plan = preload("res://scripts/atelier/plan.gd")
const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")

const G_SOL := 9.81   # m/s², gravité au sol de la planète du jeu (jeu.gd : GRAVITE_SURFACE)

## Catégories du catalogue, dans l'ordre d'affichage : [clé, titre].
const CATEGORIES := [
	["coque", "Coque et structure"],
	["ailes", "Ailes"],
	["cockpit", "Cockpit"],
	["moteurs", "Moteurs"],
	["propulseurs", "Petits propulseurs"],
	["train", "Train d'atterrissage"],
	["equipements", "Équipements (masses)"],
	["air", "Surfaces d'air"],
	["contact", "Points de contact de la coque"],
	["ajouts", "Pièces ajoutées"],
]

## Pièces de structure (venues de Blender) : catégorie d'après le début de leur nom.
const PREFIXES := [
	["Aile", "ailes"],
	["Cockpit", "cockpit"], ["Ecran", "cockpit"], ["Levier", "cockpit"], ["Manche", "cockpit"],
	["Pedale", "cockpit"], ["Poignee", "cockpit"], ["Verriere", "cockpit"],
	["Roue", "train"], ["Jambe", "train"], ["Pied", "train"], ["Pivot_train", "train"], ["Ressort", "train"],
	["Fourche", "train"], ["Puits_train", "train"], ["Trappe_arriere", "train"], ["Trappe_avant", "train"],
	["Amortisseur", "train"],
	["Moteur", "moteurs"], ["Tuyere", "moteurs"], ["Puits_moteur_levage", "moteurs"], ["Trappe_levage", "moteurs"],
	["RCS", "propulseurs"],
]

## Mots du plan (sans accents) → mots affichés.
const MOTS := {
	"tuyere": "tuyère", "ecran": "écran", "verriere": "verrière", "pedale": "pédale", "poignee": "poignée",
	"arriere": "arrière", "droide": "droïde", "lateral": "latéral", "montee": "montée", "poussee": "poussée",
	"integres": "intégrés", "systeme": "système", "rcs": "RCS", "d": "droit", "g": "gauche",
}

## Morceaux d'une pièce toute faite (scripts/atelier/pieces_toutes_faites.gd) → mots affichés.
const MORCEAUX := {"corps": "corps", "poussee": "poussée", "air": "surface d'air", "poutre": "poutre",
	"plaque": "plaque", "boite": "boîte", "reservoir": "réservoir"}

var plan
var v               # physique du vaisseau (comme dans le jeu, sans planète : pose de référence)
var masse_totale := 0.0
var _par_id := {}   # id → pièce du plan (mise à plat)
var _rcs_par_id := {}
var _moteur_par_id := {}
var ajouts := {}    # id d'une pièce posée dans l'atelier → son ensemble dans le plan (modèle, réglages…)


func _init(p_plan = null) -> void:
	plan = p_plan if p_plan != null else Plan.par_defaut()
	v = VaisseauPhysique.new(plan)
	masse_totale = v.masse
	for p in plan.pieces:
		_par_id[p["id"]] = p
	for e in plan.donnees.get("pieces", []):
		if e is Dictionary and e.has("modele"):
			ajouts[String(e["id"])] = e
	for t in v.rcs:
		_rcs_par_id[t["id"]] = t
	for m in v.moteurs:
		_moteur_par_id[m["id"]] = m


func piece(id: String) -> Dictionary:
	return _par_id.get(id, {})


func a_piece(id: String) -> bool:
	return _par_id.has(id)


# =====================================================================
# TABLEAU INGÉNIEUR
# =====================================================================
## Les chiffres du tableau (nombres bruts, en unités SI) : voir tuiles() pour le texte affiché.
func tableau() -> Dictionary:
	var poids: float = v.masse * G_SOL
	var principaux := 0
	var couple := Vector3.ZERO
	var force := Vector3.ZERO
	for m in v.moteurs:
		if m["role"] == "levage":
			continue
		principaux += 1
		var f: Vector3 = (m["dir_ref"] as Vector3) * float(m["poussee_n"])
		force += f
		couple += ((m["pos_ref"] as Vector3) - v.centre_gravite).cross(f)
	# la poussée des moteurs passe-t-elle par le centre de gravité ? sinon, à quelle distance, et les petits
	# propulseurs peuvent-ils compenser ce couple (sur chaque axe) ?
	var decalage := couple.length() / maxf(force.length(), 1.0)
	var cm: Vector3 = v.couple_max
	var compense := absf(couple.x) <= cm.x and absf(couple.y) <= cm.y and absf(couple.z) <= cm.z
	var acc_rot := Vector3(rad_to_deg(v.couple_max.x / v.inertie.x), rad_to_deg(v.couple_max.y / v.inertie.y),
		rad_to_deg(v.couple_max.z / v.inertie.z))
	return {
		"masse": v.masse, "pieces": plan.pieces.size(), "pieces_pesantes": int(plan.proprietes_masse()["pieces_pesantes"]),
		"poussee_avant": v.poussee_avant_max, "moteurs_principaux": principaux,
		"poussee_poids": v.poussee_avant_max / poids,
		"poussee_verticale": v.poussee_verticale_max, "rapport_vertical": v.poussee_verticale_max / poids,
		"peut_decoller": v.poussee_verticale_max > poids,
		"poids": poids,
		"couple_moteurs": couple, "force_moteurs": force, "decalage_poussee": decalage, "couple_compense": compense,
		"couple_max": v.couple_max, "acceleration_rotation": acc_rot,
		"centre_gravite": v.centre_gravite, "inertie": v.inertie,
	}


## Les tuiles du tableau ingénieur : [titre, valeur, détail].
func tuiles() -> Array:
	var t := tableau()
	var c: Vector3 = t["couple_moteurs"]
	var cm: Vector3 = t["couple_max"]
	var ar: Vector3 = t["acceleration_rotation"]
	var cg: Vector3 = t["centre_gravite"]
	return [
		["MASSE", "%s kg" % nombre(t["masse"], 1), "%d pièces · masse constante (pas de carburant)" % t["pieces"]],
		["POUSSÉE VERS L'AVANT", "%s kN" % nombre(t["poussee_avant"] / 1000.0), "%d moteurs principaux à fond" % t["moteurs_principaux"]],
		["POUSSÉE / POIDS", nombre(t["poussee_poids"], 1), "accélère à %s g au sol" % nombre(t["poussee_poids"], 1)],
		["DÉCOLLAGE VERTICAL", "%s kN" % nombre(t["poussee_verticale"] / 1000.0),
			("× %s le poids : il décolle" if t["peut_decoller"] else "× %s le poids : trop faible") % nombre(t["rapport_vertical"], 2)],
		["COUPLE DES MOTEURS", "%s N·m" % nombre(c.length()), _texte_couple(t)],
		["ROTATION (PROPULSEURS)", "%s / %s / %s kN·m" % [nombre(cm.x / 1000.0), nombre(cm.y / 1000.0), nombre(cm.z / 1000.0)],
			"tangage / lacet / roulis : %s / %s / %s °/s²" % [nombre(ar.x, 1), nombre(ar.y, 1), nombre(ar.z, 1)]],
		["CENTRE DE GRAVITÉ", "%s m" % nombre(cg.z, 2), "derrière l'origine du modèle (hauteur %s m)" % nombre(cg.y, 2)],
	]


static func _texte_couple(t: Dictionary) -> String:
	var d := float(t["decalage_poussee"])
	if d < 0.001:
		return "la poussée passe par le centre de gravité"
	return "poussée à %s du centre de gravité · %s" % [
		("%s cm" % nombre(d * 100.0, 1)) if d < 1.0 else ("%s m" % nombre(d, 2)),
		"les propulseurs compensent" if bool(t["couple_compense"]) else "TROP pour les propulseurs"]


# =====================================================================
# CATALOGUE : CATÉGORIES, NOMS, RECHERCHE
# =====================================================================
static func categorie(p: Dictionary) -> String:
	if p.has("ajout"):
		return "ajouts"
	match String(p.get("type", "")):
		"moteur":
			return "moteurs"
		"propulseur":
			return "propulseurs"
		"roue":
			return "train"
		"contact_coque":
			return "contact"
		"surface_air":
			return "air"
		"masse":
			return "equipements"
		"poutre", "plaque":
			return "coque"
	var id := String(p.get("id", "")).get_file()
	for pr in PREFIXES:
		if id.begins_with(pr[0]):
			return pr[1]
	return "coque"


static func titre_categorie(cle: String) -> String:
	for c in CATEGORIES:
		if c[0] == cle:
			return c[1]
	return cle


## Pièces du plan rangées par catégorie : {clé: [ids]} (dans l'ordre du plan).
func pieces_par_categorie() -> Dictionary:
	var d := {}
	for c in CATEGORIES:
		d[c[0]] = []
	for p in plan.pieces:
		(d[categorie(p)] as Array).append(p["id"])
	return d


## « Aile_haut_gauche » → « Aile haut gauche » ; moteurs et propulseurs : leur nom du plan.
static func nom_lisible(p: Dictionary) -> String:
	if p.has("ajout"):
		var morceau := String(p.get("id", "")).get_file()
		return "%s : %s" % [String(p.get("nom_ajout", p["ajout"])), String(MORCEAUX.get(morceau, _mots(morceau)))]
	var t := String(p.get("type", ""))
	var id := String(p.get("id", "")).get_file()
	var nom := String(p.get("nom", ""))
	match t:
		"moteur":
			# « Poussée du moteur central » : la force elle-même ; le moteur (sa masse, son dessin) est une
			# pièce de structure à part, qui s'appelle « Moteur central »
			return "Poussée du moteur " + _mots(nom if nom != "" else id).trim_prefix("moteur ")
		"propulseur":
			return ("Buse " if bool(p.get("encastre", false)) else "Propulseur ") + _mots(nom if nom != "" else id.trim_prefix("rcs_"))
		"roue":
			return _majuscule(_mots(nom if nom != "" else id))
		"contact_coque":
			return "Point de coque : " + _mots(id.trim_prefix("coque_"))
		"surface_air":
			return "Surface d'air : " + _mots(id.trim_prefix("air_"))
		"masse":
			return _majuscule(_mots(id.trim_prefix("Masse_")))
	return _majuscule(_mots(id.trim_suffix("_piece")))


static func _mots(t: String) -> String:
	var morceaux := t.replace("_", " ").split(" ", false)
	var sortie := PackedStringArray()
	for m in morceaux:
		var bas := m.to_lower()
		sortie.append(String(MOTS[bas]) if MOTS.has(bas) else bas)
	return " ".join(sortie)


static func _majuscule(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else t


## Texte sans accents ni majuscules, pour chercher « tuyere » et trouver « Tuyère ».
static func sans_accents(t: String) -> String:
	var s := t.to_lower()
	for paire in [["àâä", "a"], ["éèêë", "e"], ["îï", "i"], ["ôö", "o"], ["ùûü", "u"], ["ç", "c"], ["ÿ", "y"]]:
		for ch in String(paire[0]):
			s = s.replace(ch, paire[1])
	return s.replace("œ", "oe").replace("æ", "ae").replace("’", "'")


## Vrai si la pièce correspond à la recherche (tous les mots doivent être trouvés quelque part : nom,
## id, catégorie, type, matière).
func correspond(id: String, recherche: String) -> bool:
	var r := sans_accents(recherche.strip_edges())
	if r == "":
		return true
	var p := piece(id)
	var texte := " ".join([nom_lisible(p), id, titre_categorie(categorie(p)), _nom_type(p), _nom_matiere(p),
		String(p.get("note", ""))])
	texte = sans_accents(texte)
	for mot in r.split(" ", false):
		if not texte.contains(mot):
			return false
	return true


static func correspond_texte(texte: String, recherche: String) -> bool:
	var r := sans_accents(recherche.strip_edges())
	if r == "":
		return true
	var t := sans_accents(texte)
	for mot in r.split(" ", false):
		if not t.contains(mot):
			return false
	return true


static func _nom_type(p: Dictionary) -> String:
	var t := String(p.get("type", ""))
	return String(Catalogue.TYPES[t]["nom"]) if Catalogue.TYPES.has(t) else t


static func _nom_matiere(p: Dictionary) -> String:
	var m = p.get("matiere", null)
	if m == null or not Catalogue.MATIERES.has(String(m)):
		return ""
	return String(Catalogue.MATIERES[String(m)]["nom"])


# =====================================================================
# FICHES
# =====================================================================
## Fiche d'une pièce du vaisseau : {titre, sous_titre, lignes: [[intitulé, valeur]], note}.
func fiche_piece(id: String) -> Dictionary:
	var p := piece(id)
	if p.is_empty():
		return {"titre": id, "sous_titre": "pièce inconnue", "lignes": [], "note": ""}
	var t := String(p["type"])
	var lignes := []
	lignes.append(["Type", _nom_type(p)])
	lignes.append(["Catégorie", titre_categorie(categorie(p))])
	var mat := _nom_matiere(p)
	if mat != "":
		lignes.append(["Matière", "%s (%s kg/m³)" % [mat, nombre(Catalogue.MATIERES[String(p["matiere"])]["densite"])]])
	var mp: Dictionary = p["masse_calculee"]
	var m := float(mp["masse"])
	if m > 0.0:
		lignes.append(["Masse", "%s kg (%s %% du vaisseau)" % [nombre(m, 1), nombre(100.0 * m / masse_totale, 2)]])
		var c: Vector3 = mp["centre"]
		lignes.append(["Centre de la pièce", vecteur_txt(c) + " m"])
		lignes.append(["Distance au centre de gravité", "%s m" % nombre((c - v.centre_gravite).length(), 2)])
	elif t in ["moteur", "propulseur", "roue", "surface_air", "contact_coque"]:
		lignes.append(["Masse", "comptée dans les pièces de structure"])
	if p.has("surface_m2") and t == "structure":
		lignes.append(["Surface de coque", "%s m²" % nombre(float(p["surface_m2"]), 2)])
	var art := String(p.get("articulation", ""))
	if art != "" and plan.articulations.has(art):
		lignes.append(["Pièce mobile", _texte_articulation(plan.articulations[art])])
	if p.has("module"):
		lignes.append(["Module", nom_module(String(p["module"]))])
	if p.has("ajout"):
		lignes.append(["Fait partie de", String(p.get("nom_ajout", p["ajout"]))])
	match t:
		"moteur":
			var e: Dictionary = _moteur_par_id.get(id, {})
			var f: Vector3 = (p["direction"] as Vector3) * float(p["poussee_n"])
			var couple: Vector3 = ((p["point"] as Vector3) - v.centre_gravite).cross(f)
			lignes.append(["Poussée maximale", "%s kN" % nombre(float(p["poussee_n"]) / 1000.0, 1)])
			lignes.append(["Pousse vers", _direction_txt(p["direction"])])
			lignes.append(["Rôle", "moteur de levage (vol vertical)" if String(p.get("role", "")) == "levage" else "moteur principal"])
			lignes.append(["Couple à pleine poussée", "%s kN·m autour du centre de gravité" % nombre(couple.length() / 1000.0, 1)])
			if bool(p.get("seulement_sorti", false)):
				lignes.append(["Fonctionne", "seulement sorti (vol vertical)"])
			if not e.is_empty():
				lignes.append(["Sortie de la poussée", vecteur_txt(p["point"]) + " m"])
		"propulseur":
			var e2: Dictionary = _rcs_par_id.get(id, {})
			var f2: Vector3 = (p["direction"] as Vector3) * float(p["poussee_n"])
			var couple2: Vector3 = ((p["point"] as Vector3) - v.centre_gravite).cross(f2)
			lignes.append(["Poussée maximale", "%s kN" % nombre(float(p["poussee_n"]) / 1000.0, 1)])
			lignes.append(["Pousse vers", _direction_txt(p["direction"])])
			lignes.append(["Rôle (trouvé par le calcul)", role_propulseur(e2)])
			lignes.append(["Couple à pleine poussée", "%s N·m" % nombre(couple2.length())])
			lignes.append(["Encastré dans la coque", "oui" if bool(p.get("encastre", false)) else "non"])
		"roue":
			lignes.append(["Rayon", "%s m" % nombre(float(p.get("rayon_m", 0.18)), 2)])
			lignes.append(["Course de l'amortisseur", "%s cm" % nombre(float(p["course_m"]) * 100.0)])
			lignes.append(["Raideur du ressort", "%s kN/m" % nombre(float(p["raideur_n_m"]) / 1000.0)])
			lignes.append(["Amortissement", "%s kN·s/m" % nombre(float(p["amorti_n_s_m"]) / 1000.0)])
			if p.has("orientable_deg"):
				lignes.append(["Orientable", "± %s° (roue avant : elle dirige au sol)" % nombre(float(p["orientable_deg"]))])
			lignes.append(["Freinée", "oui" if bool(p.get("freinee", false)) else "non"])
			if p.has("choc_max_m_s"):
				lignes.append(["Choc supporté", "%s m/s à l'arrivée au sol" % nombre(float(p["choc_max_m_s"]), 1)])
			lignes.append(["Bas de la roue (train sorti)", vecteur_txt(p["point"]) + " m"])
		"surface_air":
			lignes.append(["Surface", "%s m²" % nombre(float(p["surface_m2"]), 2)])
			lignes.append(["Allongement", nombre(float(p["allongement"]), 1)])
			if p.has("corde_m"):
				lignes.append(["Corde (largeur)", "%s m" % nombre(float(p["corde_m"]), 1)])
			lignes.append(["Normale", _direction_txt(p["normale"])])
			if bool(p.get("biplan", false)):
				lignes.append(["Ailes en X", "oui (gêne entre ailes proches comptée)"])
		"contact_coque":
			lignes.append(["Point", vecteur_txt(p["point"]) + " m"])
			lignes.append(["Rôle", "endroit de la coque qui peut toucher le sol (sans le train)"])
	return {"titre": nom_lisible(p), "sous_titre": id, "lignes": lignes, "note": String(p.get("note", ""))}


## Masse (kg) et centre (repère du plan) d'une liste de pièces mises à plat.
func _masse_de(ids: Array) -> Array:
	var m := 0.0
	var c := Vector3.ZERO
	for i in ids:
		var mp: Dictionary = piece(i).get("masse_calculee", {})
		if mp.is_empty():
			continue
		m += float(mp["masse"])
		c += (mp["centre"] as Vector3) * float(mp["masse"])
	return [m, c / m if m > 0.0 else c]


## Les morceaux (pièces mises à plat) d'une pièce posée dans l'atelier.
func pieces_ajout(id: String) -> Array:
	var ids := []
	for p in plan.pieces:
		if String(p.get("ajout", "")) == id:
			ids.append(p["id"])
	return ids


## Les pièces d'un module du chasseur (ailes, train, cockpit…).
func pieces_module(cle: String) -> Array:
	var ids := []
	for p in plan.pieces:
		if not p.has("ajout") and String(p.get("module", "")) == cle:
			ids.append(p["id"])
	return ids


func nom_module(cle: String) -> String:
	return String((plan.donnees.get("modules", {}) as Dictionary).get(cle, _majuscule(_mots(cle))))


## Nom d'une pièce de premier niveau du plan (pièce posée ou pièce du chasseur).
func nom_element(id: String) -> String:
	if ajouts.has(id):
		return String(ajouts[id].get("nom", id))
	if _par_id.has(id):
		return nom_lisible(_par_id[id])
	return ""


## Masse d'une pièce posée (kg).
func masse_ajout(id: String) -> float:
	return float(_masse_de(pieces_ajout(id))[0])


## Fiche d'une pièce posée dans l'atelier (pièce toute faite).
func fiche_ajout(id: String) -> Dictionary:
	var e: Dictionary = ajouts.get(id, {})
	if e.is_empty():
		return {"titre": id, "sous_titre": "pièce inconnue", "lignes": [], "note": ""}
	var modele := String(e["modele"])
	var r: Dictionary = Pieces.reglages_complets(modele, e.get("reglages", {}))
	var ids := pieces_ajout(id)
	var mc := _masse_de(ids)
	var lignes := []
	lignes.append(["Pièce toute faite", Pieces.nom(modele)])
	lignes.append(["Masse", "%s kg (%s %% du vaisseau)" % [nombre(mc[0], 1), nombre(100.0 * float(mc[0]) / masse_totale, 2)]])
	lignes.append(["Centre de la pièce", vecteur_txt(mc[1]) + " m"])
	for i in ids:
		var p := piece(i)
		match String(p["type"]):
			"moteur", "propulseur":
				var f: Vector3 = (p["direction"] as Vector3) * float(p["poussee_n"])
				var couple: Vector3 = ((p["point"] as Vector3) - v.centre_gravite).cross(f)
				lignes.append(["Poussée maximale", "%s kN" % nombre(float(p["poussee_n"]) / 1000.0, 1)])
				lignes.append(["Pousse vers", _direction_txt(p["direction"])])
				if p["type"] == "moteur":
					lignes.append(["Rôle", "moteur de levage (vol vertical)" if String(p.get("role", "")) == "levage" else "moteur principal"])
					lignes.append(["Puissance du jet", "%s MW (électricité : plus tard)" % nombre(float(p["poussee_n"]) * Pieces.VITESSE_JET * 0.5 / 1.0e6)])
				else:
					lignes.append(["Rôle (trouvé par le calcul)", role_propulseur(_rcs_par_id.get(i, {}))])
				lignes.append(["Couple à pleine poussée", "%s kN·m autour du centre de gravité" % nombre(couple.length() / 1000.0, 1)])
			"surface_air":
				lignes.append(["Surface d'air", "%s m² (allongement %s)" % [nombre(float(p["surface_m2"]), 2), nombre(float(p["allongement"]), 1)]])
	if modele == "reservoir":
		lignes.append(["Contenu", "%s (%s kg)" % [String(Pieces.CONTENUS[String(r["contenu"])]["nom"]),
			nombre(float(r["volume_l"]) / 1000.0 * float(Pieces.CONTENUS[String(r["contenu"])]["densite"]))]])
	var support := String(e.get("fixe_a", ""))
	var nom_support := nom_element(support)
	lignes.append(["Posée sur", nom_support if nom_support != "" else "rien (elle flotte)"])
	var art := String(e.get("articulation", ""))
	if art != "" and plan.articulations.has(art):
		lignes.append(["Pièce mobile", _texte_articulation(plan.articulations[art])])
	var sym := String(e.get("symetrique", ""))
	if sym != "" and ajouts.has(sym):
		lignes.append(["Jumelle (symétrie)", nom_element(sym)])
	return {"titre": String(e.get("nom", id)), "sous_titre": "pièce posée · " + id, "lignes": lignes,
		"note": String(Pieces.MODELES[modele]["description"]) if Pieces.existe(modele) else ""}


## Fiche d'un module du chasseur.
func fiche_module(cle: String, peut_enlever := true) -> Dictionary:
	var ids := pieces_module(cle)
	var mc := _masse_de(ids)
	var poussee := 0.0
	var n_propulseurs := 0
	for i in ids:
		var p := piece(i)
		if p["type"] == "moteur" or p["type"] == "propulseur":
			poussee += float(p["poussee_n"])
			n_propulseurs += 1
	var lignes := [["Pièces", str(ids.size())],
		["Masse", "%s kg (%s %% du vaisseau)" % [nombre(mc[0], 1), nombre(100.0 * float(mc[0]) / masse_totale, 1)]],
		["Centre du module", vecteur_txt(mc[1]) + " m"]]
	if n_propulseurs > 0:
		lignes.append(["Moteurs et propulseurs", "%d (%s kN en tout)" % [n_propulseurs, nombre(poussee / 1000.0, 1)]])
	lignes.append(["Enlever", "oui : touche Suppr" if peut_enlever else "non : le pilote est dedans"])
	return {"titre": nom_module(cle), "sous_titre": "module du chasseur", "lignes": lignes,
		"note": "Un module est un morceau du chasseur qu'on enlève d'un bloc (ses pièces sont en orange). Les pièces posées dessus restent, mais ne touchent plus rien. Déplacer un module du chasseur viendra plus tard."}


## Rôle d'un petit propulseur, tel que la physique l'a trouvé (par le calcul du couple).
static func role_propulseur(e: Dictionary) -> String:
	if e.is_empty():
		return "?"
	var axe := int(e.get("axe", -1))
	var signe := int(e.get("signe", 0))
	var effet := float(e.get("effet_rotation", 0.0))
	match axe:
		0:
			return "tourner en tangage, nez vers le %s (effet %s)" % ["haut" if signe > 0 else "bas", nombre(effet, 2)]
		1:
			return "tourner en lacet, nez vers la %s (effet %s)" % ["gauche" if signe > 0 else "droite", nombre(effet, 2)]
		2:
			return "tourner en roulis, pencher à %s (effet %s)" % ["gauche" if signe > 0 else "droite", nombre(effet, 2)]
	return "glisser (déplacement), effet de rotation %s seulement" % nombre(effet, 2)


func _texte_articulation(a: Dictionary) -> String:
	var t := String(a.get("type", ""))
	var nom := String(Catalogue.ARTICULATIONS[t]["nom"]) if Catalogue.ARTICULATIONS.has(t) else t
	var commande := String(a.get("commande", ""))
	var suit := {"ailes": "suit l'ouverture des ailes", "train": "suit le train", "vertical": "suit le vol vertical"}
	return "%s « %s », %s" % [nom, _mots(String(a.get("id", ""))), suit.get(commande, commande)]


## Fiche d'un type de pièce du catalogue.
func fiche_type(t: String) -> Dictionary:
	if not Catalogue.TYPES.has(t):
		return {"titre": t, "sous_titre": "", "lignes": [], "note": ""}
	var d: Dictionary = Catalogue.TYPES[t]
	var n := 0
	for p in plan.pieces:
		if p["type"] == t:
			n += 1
	var lignes := [["Réglages obligatoires", ", ".join(PackedStringArray(d["champs"])) if (d["champs"] as Array).size() > 0 else "aucun"],
		["Réglages possibles", ", ".join(PackedStringArray(d["facultatifs"]))],
		["Pèse elle-même", "oui (matière × volume, ou masse donnée)" if bool(d["pese"]) else "seulement si on lui donne une masse"],
		["Dans ton vaisseau", "%d pièce%s" % [n, "s" if n > 1 else ""]]]
	return {"titre": _majuscule(String(d["nom"])), "sous_titre": "type de pièce : " + t, "lignes": lignes,
		"note": String(d["description"])}


## Fiche d'une matière.
func fiche_matiere(cle: String) -> Dictionary:
	if not Catalogue.MATIERES.has(cle):
		return {"titre": cle, "sous_titre": "", "lignes": [], "note": ""}
	var d: Dictionary = Catalogue.MATIERES[cle]
	var par_matiere: Dictionary = plan.proprietes_masse()["masse_par_matiere"]
	var m := float(par_matiere.get(cle, 0.0))
	var n := 0
	for p in plan.pieces:
		if p.get("matiere", null) != null and String(p["matiere"]) == cle:
			n += 1
	var lignes := [["Masse volumique", "%s kg/m³" % nombre(float(d["densite"]))],
		["Usage", String(d["usage"])],
		["Son (quand elle vibre)", String(d["son"])],
		["Dans ton vaisseau", "%s kg (%s %%), %d pièce%s" % [nombre(m, 1), nombre(100.0 * m / masse_totale, 1), n, "s" if n > 1 else ""]]]
	return {"titre": _majuscule(String(d["nom"])), "sous_titre": "matière : " + cle, "lignes": lignes, "note": ""}


# =====================================================================
# NOMBRES EN FRANÇAIS
# =====================================================================
## 8534.6 → « 8 534,6 » (espace fine entre les milliers, virgule).
static func nombre(x: float, decimales := 0) -> String:
	var negatif := x < 0.0
	var t := ("%." + str(decimales) + "f") % absf(x)
	var entier := t
	var reste := ""
	if decimales > 0:
		entier = t.get_slice(".", 0)
		reste = "," + t.get_slice(".", 1)
	var groupes := PackedStringArray()
	while entier.length() > 3:
		groupes.insert(0, entier.substr(entier.length() - 3))
		entier = entier.substr(0, entier.length() - 3)
	groupes.insert(0, entier)
	var s := " ".join(groupes) + reste
	if negatif and s.strip_edges().replace("0", "").replace(",", "").replace(" ", "") != "":
		s = "−" + s
	return s


static func vecteur_txt(a) -> String:
	var p := Catalogue.vecteur(a)
	return "(%s ; %s ; %s)" % [nombre(p.x, 2), nombre(p.y, 2), nombre(p.z, 2)]


## Direction lisible : « l'avant », « le haut », ou les trois nombres.
static func _direction_txt(a) -> String:
	var d := Catalogue.vecteur(a).normalized()
	var noms := [[Vector3(0, 0, -1), "l'avant"], [Vector3(0, 0, 1), "l'arrière"], [Vector3(0, 1, 0), "le haut"],
		[Vector3(0, -1, 0), "le bas"], [Vector3(1, 0, 0), "la droite"], [Vector3(-1, 0, 0), "la gauche"]]
	for n in noms:
		if d.dot(n[0]) > 0.999:
			return n[1]
	return vecteur_txt(d)
