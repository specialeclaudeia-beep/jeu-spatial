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
## Étape 4 : l'ANALYSE INGÉNIEUR complète : analyse de n'importe quelle sélection (masse, part, centre,
## inertie propre, ce que devient le vaisseau sans elle), répartition des masses, poussées et couple moteur
## par moteur et par axe, défauts de symétrie gauche-droite, et les chiffres de la salle à part.
## Étape 6 : l'ARMATURE (poutres, connecteurs, panneaux) a sa catégorie, ses fiches (forme d'un connecteur,
## longueur d'une poutre, surface d'un panneau…) et sa part dans la tuile MASSE.
## Étape 8 : la CABINE (tuile CABINE et sa page) : pression, air, réserves, recycleur, solidité de chaque
## paroi sous pression, volumes fermés de l'armature, fuites (scripts/physique/vie_a_bord.gd).

const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")
const Armature = preload("res://scripts/atelier/armature.gd")
const Plan = preload("res://scripts/atelier/plan.gd")
const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const VieABord = preload("res://scripts/physique/vie_a_bord.gd")

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
	["armature", "Armature (poutres, panneaux)"],
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
	"plaque": "plaque", "boite": "boîte", "reservoir": "réservoir", "connecteur": "connecteur", "panneau": "panneau"}

var plan
var v               # physique du vaisseau (comme dans le jeu, sans planète : pose de référence)
var masse_totale := 0.0
var _par_id := {}   # id → pièce du plan (mise à plat)
var _rcs_par_id := {}
var _moteur_par_id := {}
var ajouts := {}    # id d'une pièce posée dans l'atelier → son ensemble dans le plan (modèle, réglages…)
var armature := {}  # les éléments de l'armature parmi eux (connecteurs, poutres, panneaux)
var _symetrie = null # défauts de symétrie (calculés une fois, à la demande)
var _vie := {}       # la cabine (étape 8), calculée une fois


func _init(p_plan = null) -> void:
	plan = p_plan if p_plan != null else Plan.par_defaut()
	v = VaisseauPhysique.new(plan)
	masse_totale = v.masse
	for p in plan.pieces:
		_par_id[p["id"]] = p
	for e in plan.donnees.get("pieces", []):
		if e is Dictionary and e.has("modele"):
			ajouts[String(e["id"])] = e
			if Armature.est(e):
				armature[String(e["id"])] = e
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
	var a_fond := 0.0
	for m in v.moteurs:
		if m["role"] == "levage":
			continue
		principaux += 1
		a_fond += float(m["poussee_n"])
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
		"poussee_avant": v.poussee_avant_max, "moteurs_principaux": principaux, "poussee_moteurs": a_fond,
		"poussee_poids": v.poussee_avant_max / poids,
		"poussee_verticale": v.poussee_verticale_max, "rapport_vertical": v.poussee_verticale_max / poids,
		"peut_decoller": v.poussee_verticale_max > poids,
		"poids": poids,
		"couple_moteurs": couple, "force_moteurs": force, "decalage_poussee": decalage, "couple_compense": compense,
		"couple_max": v.couple_max, "acceleration_rotation": acc_rot,
		"centre_gravite": v.centre_gravite, "inertie": v.inertie,
		"masse_armature": float(_masse_de(pieces_par_categorie()["armature"])[0]),
	}


## Les tuiles du tableau ingénieur : [titre, valeur, détail].
func tuiles() -> Array:
	var t := tableau()
	var c: Vector3 = t["couple_moteurs"]
	var cm: Vector3 = t["couple_max"]
	var ar: Vector3 = t["acceleration_rotation"]
	var cg: Vector3 = t["centre_gravite"]
	return [
		["MASSE", "%s kg" % nombre(t["masse"], 1), ("%d pièces · dont armature %s kg · masse constante" % [t["pieces"], nombre(t["masse_armature"], 1)])
			if t["masse_armature"] > 0.0 else "%d pièces · masse constante (pas de carburant)" % t["pieces"]],
		["POUSSÉE VERS L'AVANT", "%s kN" % nombre(t["poussee_avant"] / 1000.0), _texte_poussee_avant(t)],
		["POUSSÉE / POIDS", nombre(t["poussee_poids"], 1), "accélère à %s g au sol" % nombre(t["poussee_poids"], 1)],
		["DÉCOLLAGE VERTICAL", "%s kN" % nombre(t["poussee_verticale"] / 1000.0),
			("× %s le poids : il décolle" if t["peut_decoller"] else "× %s le poids : trop faible") % nombre(t["rapport_vertical"], 2)],
		["COUPLE DES MOTEURS", "%s N·m" % nombre(c.length()), _texte_couple(t)],
		["ROTATION (PROPULSEURS)", "%s / %s / %s kN·m" % [nombre(cm.x / 1000.0), nombre(cm.y / 1000.0), nombre(cm.z / 1000.0)],
			"tangage / lacet / roulis : %s / %s / %s °/s²" % [nombre(ar.x, 1), nombre(ar.y, 1), nombre(ar.z, 1)]],
		["CENTRE DE GRAVITÉ", "%s m" % nombre(cg.z, 2), "derrière l'origine du modèle (hauteur %s m)" % nombre(cg.y, 2)
			+ _texte_cg_mobiles()],
		_tuile_symetrie(),
	]


## Étape 7 : ce que les pièces mobiles font au centre de gravité (dans la tuile), "" sans pièce mobile.
func _texte_cg_mobiles() -> String:
	if plan.articulations.is_empty():
		return ""
	var m := mobiles()
	var dmax := 0.0
	for c in m["commandes"]:
		dmax = maxf(dmax, float(c["deplacement"]))
	return " · pièces mobiles : il bouge de %s au plus" % longueur_txt(dmax)


## Ce que montre un clic sur chaque tuile du tableau (même ordre que tuiles()) : la page d'analyse détaillée.
const DETAIL_TUILES := ["masses", "poussees", "poussees", "poussees", "poussees", "poussees", "masses", "symetrie"]


## Les mêmes, pour ce vaisseau : avec des pièces mobiles (étape 7), la tuile du centre de gravité ouvre leur page.
func details_tuiles() -> Array:
	var d := DETAIL_TUILES.duplicate()
	if not plan.articulations.is_empty():
		d[6] = "mobiles"
	return d


func _tuile_symetrie() -> Array:
	var s := symetrie()
	var x := float(s["cg_x"])
	var n: int = (s["elements"] as Array).size()
	return ["SYMÉTRIE", ("%s %s" % [longueur_txt(absf(x)), "à droite" if x > 0.0 else "à gauche"]) if absf(x) >= 0.0005 else "centrée",
		"centre de gravité sur le côté · %s" % ("aucune pièce sans jumelle" if n == 0 else "%d pièce%s sans jumelle" % [n, "s" if n > 1 else ""])]


## Les moteurs à fond, ou réduits par le pilotage pour ne pas faire tourner le vaisseau (poussée décalée).
static func _texte_poussee_avant(t: Dictionary) -> String:
	var a_fond := float(t["poussee_moteurs"])
	if float(t["poussee_avant"]) < 0.99 * a_fond:
		return "réduite pour ne pas tourner (%s kN à fond, %d moteurs)" % [nombre(a_fond / 1000.0), t["moteurs_principaux"]]
	return "%d moteur%s principa%s à fond" % [t["moteurs_principaux"], "s" if int(t["moteurs_principaux"]) > 1 else "",
		"ux" if int(t["moteurs_principaux"]) > 1 else "l"]


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
		return "armature" if Armature.est_modele(String(p.get("modele_ajout", ""))) else "ajouts"
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


## Fiche d'une pièce posée dans l'atelier (pièce toute faite, ou élément de l'armature).
func fiche_ajout(id: String) -> Dictionary:
	var e: Dictionary = ajouts.get(id, {})
	if e.is_empty():
		return {"titre": id, "sous_titre": "pièce inconnue", "lignes": [], "note": ""}
	if Armature.est(e):
		return fiche_armature(id)
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


## Fiche d'un élément de l'armature : connecteur (sa forme, ses poutres), poutre (longueur, profil),
## panneau (surface, coins, s'il porte dans l'air).
func fiche_armature(id: String) -> Dictionary:
	var e: Dictionary = armature.get(id, {})
	if e.is_empty():
		return {"titre": id, "sous_titre": "élément inconnu", "lignes": [], "note": ""}
	var modele := String(e["modele"])
	var g := Armature.graphe(plan.donnees)
	var mc := _masse_de(pieces_ajout(id))
	var lignes := []
	var r: Dictionary = Armature.reglages_complets(modele, e.get("reglages", {}))
	match modele:
		Armature.CONNECTEUR:
			var genre := Armature.genre_connecteur(g, id)
			lignes.append(["Forme", _majuscule(String(genre["nom"]))])
			var poutres := Armature.poutres_de(g, id)
			lignes.append(["Poutres qui y arrivent", ", ".join(PackedStringArray(poutres.map(func(i): return nom_element(i)))) if not poutres.is_empty() else "aucune"])
			var q: Dictionary = (e.get("pieces", [{}]) as Array)[0] if not (e.get("pieces", []) as Array).is_empty() else {}
			if not q.is_empty():
				var dims: Array = q["dimensions_m"]
				lignes.append(["Boule", ("creuse de %s, paroi %s" % [longueur_txt(float(dims[0])), longueur_txt(float(dims[1]))]) if dims.size() > 1
					else "pleine de %s" % longueur_txt(float(dims[0]))])
				lignes.append(["Matière", _majuscule(String(Catalogue.MATIERES[String(q["matiere"])]["nom"]))])
			lignes.append(["Place", vecteur_txt(e.get("position", [0, 0, 0])) + " m"])
			var support := String(e.get("fixe_a", ""))
			lignes.append(["Posé sur", nom_element(support) if nom_element(support) != "" else "rien (il tient par ses poutres)"])
		Armature.POUTRE:
			var n: Array = e.get("noeuds", [])
			var l := float(e.get("longueur_m", 0.0))
			var q2: Dictionary = (e.get("pieces", [{}]) as Array)[0] if not (e.get("pieces", []) as Array).is_empty() else {}
			lignes.append(["Longueur", "%s (entre les centres des connecteurs ; %s de métal)" % [longueur_txt(l), longueur_txt(float(q2.get("longueur_m", l)))]])
			lignes.append(["Profil", "%s de %s%s" % [Armature.NOMS_CHOIX[String(r["profil"])], longueur_txt(float(r["section_m"])),
				", paroi %s" % longueur_txt(float(r["paroi_m"])) if String(r["profil"]) != "plein_carre" else ""]])
			lignes.append(["Matière", _majuscule(String(Catalogue.MATIERES[String(r["matiere"])]["nom"]))])
			lignes.append(["Entre", " et ".join(PackedStringArray(n.map(func(i): return nom_element(String(i)))))])
		Armature.PANNEAU:
			var n2: Array = e.get("noeuds", [])
			lignes.append(["Surface", "%s m² (%d coins)" % [nombre(float(e.get("surface_m2", 0.0)), 2), n2.size()]])
			lignes.append(["Épaisseur", longueur_txt(float(r["epaisseur_m"]))])
			lignes.append(["Matière", _majuscule(String(Catalogue.MATIERES[String(r["matiere"])]["nom"]))])
			lignes.append(["Coins", ", ".join(PackedStringArray(n2.map(func(i): return nom_element(String(i)))))])
			for i in pieces_ajout(id):
				var p := piece(i)
				if String(p["type"]) == "surface_air":
					lignes.append(["Porte dans l'air", "%s m², allongement %s" % [nombre(float(p["surface_m2"]), 2), nombre(float(p["allongement"]), 1)]])
	lignes.append(["Masse", "%s kg (%s %% du vaisseau)" % [nombre(mc[0], 2), nombre(100.0 * float(mc[0]) / masse_totale, 2)]])
	var art := String(e.get("articulation", ""))
	if art != "" and plan.articulations.has(art):
		lignes.append(["Pièce mobile", _texte_articulation(plan.articulations[art])])
	var sym := String(e.get("symetrique", ""))
	if sym != "" and ajouts.has(sym):
		lignes.append(["Jumeau (symétrie)", nom_element(sym)])
	return {"titre": String(e.get("nom", id)), "sous_titre": "armature · " + id, "lignes": lignes,
		"note": String(Armature.MODELES[modele]["description"])}


## Boîte (repère de l'élément) qui contient le dessin d'une pièce posée (toute faite ou de l'armature).
static func boite_ajout(e: Dictionary) -> AABB:
	if Armature.est(e):
		return Armature.boite(e)
	return Pieces.boite(String(e["modele"]), e.get("reglages", {}))


## Résumé d'une ligne d'une pièce posée (toute faite ou de l'armature).
static func resume_ajout(e: Dictionary) -> String:
	if Armature.est(e):
		return Armature.resume(e)
	return Pieces.resume(String(e["modele"]), e.get("reglages", {}))


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


# =====================================================================
# ÉTAPE 7 : LES PIÈCES MOBILES
# =====================================================================
var _mobiles := {}


## Les pièces mobiles du vaisseau, calculées par la physique du jeu :
##   commandes : [{commande, nom, a_0, a_1, duree, articulations (ids), masse (kg emmenés), cg_0, cg_1,
##                 deplacement (m)}] : centre de gravité quand la commande vaut 0, puis 1 (les autres comme au
##                 départ du jeu) ;
##   articulations : [{id, nom, type, commande, masse (kg emmenés, celles qu'elle porte comprises), pieces (ids),
##                     porte_par, element ({genre, id} : ce qu'on choisit dans le vaisseau)}].
func mobiles() -> Dictionary:
	if not _mobiles.is_empty():
		return _mobiles
	var arts: Dictionary = plan.articulations
	var par_art := {}   # articulation → ids des pièces qu'elle emmène (elle et celles qu'elle porte)
	for id in arts:
		par_art[id] = []
	for p in plan.pieces:
		for id in Plan.chaine(arts, String(p.get("articulation", ""))):
			(par_art[id] as Array).append(String(p["id"]))
	var liste := []
	for id in arts:
		var a: Dictionary = arts[id]
		var ids: Array = par_art[id]
		var el := {}
		var k := String(id).rfind("/")
		if k > 0 and ajouts.has(String(id).substr(0, k)):
			el = {"genre": "ajout", "id": String(id).substr(0, k)}   # partie mobile d'une pièce posée
		elif not ids.is_empty():
			el = element_de(piece(String(ids[0])))
		liste.append({"id": id, "nom": nom_articulation(id), "type": String(a.get("type", "")), "commande": String(a.get("commande", "")),
			"masse": float(_masse_de(ids)[0]), "pieces": ids, "porte_par": String(a.get("porte_par", "")), "element": el})
	var commandes := []
	for c in Catalogue.COMMANDES:
		var les := []
		var masse := 0.0
		for x in liste:
			if x["commande"] == c:
				les.append(x["id"])
				if String(x["porte_par"]) == "" or String((arts[x["porte_par"]] as Dictionary).get("commande", "")) != c:
					masse += float(x["masse"])   # (une articulation portée par une autre de la même commande : déjà comptée)
		if les.is_empty():
			continue
		var avant: float = v.valeur_commande(c)
		var cgs := []
		for x in [0.0, 1.0]:
			v.regler_commande(c, x)
			v.placer_pieces_mobiles()
			cgs.append(v.centre_gravite)
		v.regler_commande(c, avant)
		v.placer_pieces_mobiles()
		var d: Dictionary = Catalogue.COMMANDES[c]
		commandes.append({"commande": c, "nom": String(d["nom"]), "a_0": String(d["a_0"]), "a_1": String(d["a_1"]),
			"duree": plan.duree_commande(c), "articulations": les, "masse": masse, "cg_0": cgs[0], "cg_1": cgs[1],
			"deplacement": ((cgs[1] as Vector3) - (cgs[0] as Vector3)).length()})
	_mobiles = {"commandes": commandes, "articulations": liste}
	return _mobiles


## Nom lisible d'une articulation : celle d'une pièce posée prend le nom de la pièce (« Charnière motorisée 1 »).
func nom_articulation(id: String) -> String:
	var a: Dictionary = plan.articulations.get(id, {})
	var k := id.rfind("/")
	if k > 0 and ajouts.has(id.substr(0, k)):
		return "%s (%s)" % [String(ajouts[id.substr(0, k)].get("nom", id.substr(0, k))), String(a.get("nom", id.substr(k + 1)))]
	return _majuscule(String(a.get("nom", _mots(id))))


## Page « Pièces mobiles » : chaque commande (ce qu'elle emmène, de combien le centre de gravité bouge),
## puis chaque articulation (cliquable : ses pièces en orange).
func fiche_mobiles() -> Dictionary:
	var m := mobiles()
	var lignes := []
	lignes.append(["Pièces mobiles", "%d articulation%s" % [(m["articulations"] as Array).size(), "s" if (m["articulations"] as Array).size() > 1 else ""]])
	for c in m["commandes"]:
		var dcg: Vector3 = (c["cg_1"] as Vector3) - (c["cg_0"] as Vector3)
		lignes.append([_majuscule(String(c["nom"])) + " (0 → 1)", "%s emmenés · centre de gravité %s · %s s" % [
			masse_txt(float(c["masse"])), ("bouge de " + longueur_txt(dcg.length()) + " " + sens_txt(dcg)) if dcg.length() >= 0.0005 else "ne bouge pas",
			nombre(float(c["duree"]), 1)]])
	var sections := []
	for c in m["commandes"]:
		var liste := []
		for x in m["articulations"]:
			if x["commande"] != c["commande"]:
				continue
			var porte := ""
			if String(x["porte_par"]) != "":
				porte = " · portée par " + nom_articulation(String(x["porte_par"]))
			liste.append(ligne_liste(String(x["nom"]), masse_txt(float(x["masse"])) + porte, float(x["masse"]) / maxf(masse_totale, 1e-9),
				x["element"]))
		sections.append({"titre": "%s : 0 = %s, 1 = %s" % [String(c["nom"]).to_upper(), String(c["a_0"]), String(c["a_1"])], "liste": liste})
	return {"titre": "Pièces mobiles", "sous_titre": "analyse ingénieur · même calcul que le jeu", "lignes": lignes, "sections": sections,
		"note": "Tout ce qui est posé sur une pièce mobile la suit : moteurs, roues, ailes, et leur masse. Quand une pièce bouge, le centre de gravité se déplace et le vaisseau tourne un peu dans l'autre sens (comme un chat qui se retourne en tombant), puis s'arrête avec elle. « Mouvements » (en haut) les essaie dans le hangar."}


static func masse_txt(m: float) -> String:
	return "%s kg" % nombre(m, 1 if m < 100.0 else 0)


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
# ÉTAPE 4 : ANALYSE D'UNE SÉLECTION
# =====================================================================
## Analyse d'un groupe de pièces (ids du plan mis à plat), dans la pose de référence du plan (ailes
## ouvertes, train rentré). Mêmes calculs que pour le vaisseau entier (plan.gd : Huygens, inertie 3×3).
## Renvoie masse (kg), part (0 à 1), centre, inertie (Basis, autour de SON centre), poussées (N), surface
## d'air (m²), et le vaisseau SANS le groupe : masse_sans, centre_sans, deplacement (de son centre de gravité).
func analyse_groupe(ids: Array) -> Dictionary:
	var dans := {}
	var liste := []
	for i in ids:
		var id := String(i)
		if _par_id.has(id) and not dans.has(id):
			dans[id] = true
			liste.append(_par_id[id])
	var tout: Dictionary = plan.proprietes_masse()
	var mp: Dictionary = _masse_liste(liste)
	var reste := []
	for p in plan.pieces:
		if not dans.has(String(p["id"])):
			reste.append(p)
	var ms: Dictionary = _masse_liste(reste)
	var r := {"pieces": liste.size(), "masse": float(mp["masse"]), "centre": mp["centre"], "inertie": mp["inertie"],
		"part": float(mp["masse"]) / maxf(float(tout["masse"]), 1e-9), "masse_sans": float(ms["masse"]),
		"centre_sans": ms["centre"], "deplacement": (ms["centre"] as Vector3) - (tout["centre"] as Vector3),
		"poussee_principale": 0.0, "poussee_levage": 0.0, "poussee_propulseurs": 0.0, "moteurs": 0, "propulseurs": 0,
		"surface_air": 0.0, "roues": 0}
	for p in liste:
		match String(p["type"]):
			"moteur":
				r["moteurs"] += 1
				if String(p.get("role", "")) == "levage":
					r["poussee_levage"] += float(p["poussee_n"])
				else:
					r["poussee_principale"] += float(p["poussee_n"])
			"propulseur":
				r["propulseurs"] += 1
				r["poussee_propulseurs"] += float(p["poussee_n"])
			"surface_air":
				r["surface_air"] += float(p["surface_m2"])
			"roue":
				r["roues"] += 1
	return r


## Propriétés de masse d'une liste de pièces (une liste vide pèse 0 : plan.proprietes_masse([]) donnerait
## le vaisseau entier).
func _masse_liste(liste: Array) -> Dictionary:
	if liste.is_empty():
		return {"masse": 0.0, "centre": Vector3.ZERO, "inertie": Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)}
	return plan.proprietes_masse(liste)


## Les lignes d'analyse d'une sélection, pour sa fiche.
func lignes_groupe(ids: Array) -> Array:
	var g := analyse_groupe(ids)
	var lignes := []
	if float(g["masse"]) <= 0.0:
		lignes.append(["Masse", "aucune (pièces sans masse à elles : comptée dans la structure)"])
	else:
		lignes.append(["Masse", "%s kg (%s %% du vaisseau)" % [nombre(g["masse"], 1), nombre(100.0 * float(g["part"]), 1 if float(g["part"]) >= 0.01 else 2)]])
		lignes.append(["Centre de la sélection", vecteur_txt(g["centre"]) + " m"])
		lignes.append(["Écart au centre de gravité", longueur_txt(((g["centre"] as Vector3) - v.centre_gravite).length())])
		var ib: Basis = g["inertie"]
		lignes.append(["Inertie propre (tangage / lacet / roulis)", "%s / %s / %s kg·m²" % [chiffres(ib.x.x), chiffres(ib.y.y), chiffres(ib.z.z)]])
	var pousse := []
	if float(g["poussee_principale"]) > 0.0:
		pousse.append("%s kN vers l'avant" % nombre(float(g["poussee_principale"]) / 1000.0, 1))
	if float(g["poussee_levage"]) > 0.0:
		pousse.append("%s kN de levage" % nombre(float(g["poussee_levage"]) / 1000.0, 1))
	if float(g["poussee_propulseurs"]) > 0.0:
		pousse.append("%d propulseur%s (%s kN)" % [g["propulseurs"], "s" if int(g["propulseurs"]) > 1 else "", nombre(float(g["poussee_propulseurs"]) / 1000.0, 1)])
	if not pousse.is_empty():
		lignes.append(["Poussée", ", ".join(PackedStringArray(pousse))])
	if float(g["surface_air"]) > 0.0:
		lignes.append(["Surface d'air", "%s m²" % nombre(float(g["surface_air"]), 2)])
	if int(g["roues"]) > 0:
		lignes.append(["Roues", str(g["roues"])])
	if float(g["masse"]) > 0.0 and float(g["masse_sans"]) > 0.0:
		lignes.append(["Sans elle", "le vaisseau pèserait %s kg ; son centre de gravité %s" % [nombre(g["masse_sans"], 1),
			deplacement_txt(g["deplacement"])]])
	return lignes


## « bougerait de 3,2 cm vers l'avant et 4 mm vers le bas » (repère du plan : −Z avant, +Y haut, +X droite).
static func deplacement_txt(d: Vector3) -> String:
	var morceaux := []
	var m := maxf(absf(d.x), maxf(absf(d.y), absf(d.z)))
	if m < 0.0005:
		return "ne bougerait presque pas (moins de 0,5 mm)"
	var axes := [[absf(d.z), "l'arrière" if d.z > 0.0 else "l'avant"], [absf(d.y), "le haut" if d.y > 0.0 else "le bas"],
		[absf(d.x), "la droite" if d.x > 0.0 else "la gauche"]]
	axes.sort_custom(func(a, b): return a[0] > b[0])
	for a in axes:
		if float(a[0]) >= 0.0005 and float(a[0]) >= 0.15 * m:
			morceaux.append("%s vers %s" % [longueur_txt(a[0]), a[1]])
	return "bougerait de " + " et ".join(PackedStringArray(morceaux))


## 0,0042 → « 4,2 mm » ; 0,032 → « 3,2 cm » ; 1,8 → « 1,80 m ».
static func longueur_txt(x: float) -> String:
	x = absf(x)
	if x < 0.01:
		return "%s mm" % nombre(x * 1000.0, 1)
	if x < 1.0:
		return "%s cm" % nombre(x * 100.0, 1)
	return "%s m" % nombre(x, 2)


# =====================================================================
# ÉTAPE 4 : LES PAGES D'ANALYSE (clic sur une tuile du tableau)
# =====================================================================
## Une ligne d'une liste d'analyse : texte, valeur, part (0 à 1, barre ; < 0 : pas de barre), et ce qu'un
## clic choisit ({genre, id} ou {genre: "groupe", elements: […]} ; vide : rien).
static func ligne_liste(texte: String, valeur: String, part := -1.0, choix := {}) -> Dictionary:
	return {"texte": texte, "valeur": valeur, "part": part, "choix": choix}


## L'élément de premier niveau d'une pièce mise à plat : sa pièce posée, ou elle-même.
static func element_de(p: Dictionary) -> Dictionary:
	if p.has("ajout"):
		return {"genre": "ajout", "id": String(p["ajout"])}
	return {"genre": "piece", "id": String(p["id"])}


## Répartition des masses : par catégorie, par matière, et les pièces les plus lourdes (une pièce posée
## compte pour une, avec tous ses morceaux).
func repartition_masses(n_lourdes := 15) -> Dictionary:
	var total := maxf(masse_totale, 1e-9)
	var par_cat := []
	var pc := pieces_par_categorie()
	for c in CATEGORIES:
		var m := float(_masse_de(pc[c[0]])[0])
		if m > 0.0:
			par_cat.append({"cle": c[0], "titre": c[1], "masse": m, "part": m / total})
	par_cat.sort_custom(func(a, b): return float(a["masse"]) > float(b["masse"]))
	var par_mat := []
	var pm: Dictionary = plan.proprietes_masse()["masse_par_matiere"]
	for k in pm:
		var nom := "Équipements (masses données)"
		if Catalogue.MATIERES.has(String(k)):
			nom = _majuscule(String(Catalogue.MATIERES[String(k)]["nom"]))
		par_mat.append({"cle": String(k), "titre": nom, "masse": float(pm[k]), "part": float(pm[k]) / total,
			"choisir": Catalogue.MATIERES.has(String(k))})
	par_mat.sort_custom(func(a, b): return float(a["masse"]) > float(b["masse"]))
	var elements := {}
	for p in plan.pieces:
		var m := float(p["masse_calculee"]["masse"])
		if m <= 0.0:
			continue
		var e := element_de(p)
		var cle := String(e["genre"]) + ":" + String(e["id"])
		if not elements.has(cle):
			elements[cle] = {"genre": e["genre"], "id": e["id"], "masse": 0.0,
				"nom": nom_element(String(e["id"])) if e["genre"] == "ajout" else nom_lisible(p)}
		elements[cle]["masse"] += m
	var lourdes: Array = elements.values()
	lourdes.sort_custom(func(a, b): return float(a["masse"]) > float(b["masse"]))
	var n_pesantes := lourdes.size()
	if lourdes.size() > n_lourdes:
		lourdes = lourdes.slice(0, n_lourdes)
	for e in lourdes:
		e["part"] = float(e["masse"]) / total
	return {"masse": masse_totale, "par_categorie": par_cat, "par_matiere": par_mat, "lourdes": lourdes, "elements_pesants": n_pesantes}


func fiche_masses() -> Dictionary:
	var r := repartition_masses()
	var cg: Vector3 = v.centre_gravite
	var lignes := [["Masse totale", "%s kg (masse constante : pas de carburant)" % nombre(masse_totale, 1)],
		["Pièces qui pèsent", "%d (%d pièces en tout)" % [r["elements_pesants"], plan.pieces.size()]],
		["Centre de gravité", vecteur_txt(cg) + " m"],
		["Inertie (tangage / lacet / roulis)", "%s / %s / %s kg·m²" % [nombre(v.inertie.x), nombre(v.inertie.y), nombre(v.inertie.z)]]]
	var cats := []
	for c in r["par_categorie"]:
		cats.append(ligne_liste(String(c["titre"]), _kg_part(c), float(c["part"]), {"genre": "categorie", "id": c["cle"]}))
	var mats := []
	for c in r["par_matiere"]:
		mats.append(ligne_liste(String(c["titre"]), _kg_part(c), float(c["part"]),
			{"genre": "matiere", "id": c["cle"]} if bool(c["choisir"]) else {}))
	var lourdes := []
	for e in r["lourdes"]:
		lourdes.append(ligne_liste(String(e["nom"]), _kg_part(e), float(e["part"]), {"genre": e["genre"], "id": e["id"]}))
	return {"titre": "Répartition des masses", "sous_titre": "analyse ingénieur · pose de référence (ailes ouvertes)",
		"lignes": lignes, "sections": [
			{"titre": "PAR CATÉGORIE", "liste": cats},
			{"titre": "PAR MATIÈRE", "liste": mats},
			{"titre": "LES %d PIÈCES LES PLUS LOURDES" % lourdes.size(), "liste": lourdes}],
		"note": "Clique sur une ligne pour voir ces pièces dans le vaisseau. Une pièce posée compte pour une, avec tous ses morceaux."}


static func _kg_part(c: Dictionary) -> String:
	var part := float(c["part"]) * 100.0
	return "%s kg · %s %%" % [nombre(float(c["masse"]), 0 if float(c["masse"]) >= 100.0 else 1), nombre(part, 1 if part >= 1.0 else 2)]


## Poussées et couple, moteur par moteur et axe par axe (tangage, lacet, roulis), comparés à ce que les
## petits propulseurs peuvent compenser.
func poussees() -> Dictionary:
	var t := tableau()
	var cg: Vector3 = v.centre_gravite
	var principaux := []
	var levage := []
	var total := 0.0
	for p in plan.pieces:
		if String(p["type"]) != "moteur":
			continue
		var f: Vector3 = (p["direction"] as Vector3) * float(p["poussee_n"])
		var e := element_de(p)
		var d := {"id": String(p["id"]), "genre": e["genre"], "id_choix": e["id"], "poussee": float(p["poussee_n"]),
			"couple": ((p["point"] as Vector3) - cg).cross(f), "direction": p["direction"],
			"nom": String(p.get("nom_ajout", "")) if p.has("ajout") else _majuscule(nom_lisible(p).trim_prefix("Poussée du "))}
		if String(p.get("role", "")) == "levage":
			levage.append(d)
		else:
			principaux.append(d)
			total += float(p["poussee_n"])
	principaux.sort_custom(func(a, b): return float(a["poussee"]) > float(b["poussee"]))
	var c: Vector3 = t["couple_moteurs"]
	var cm: Vector3 = t["couple_max"]
	var axes := []
	for k in 3:
		axes.append({"nom": ["tangage", "lacet", "roulis"][k], "couple": c[k], "max": cm[k],
			"part": absf(c[k]) / cm[k] if cm[k] > 0.0 else (INF if absf(c[k]) > 1.0 else 0.0)})
	# les petits propulseurs, rangés par rôle (trouvé par le calcul du couple)
	var roles := {}
	for r in v.rcs:
		var cle := "%d:%d" % [int(r.get("axe", -1)), int(r.get("signe", 0))]
		if not roles.has(cle):
			roles[cle] = {"axe": int(r.get("axe", -1)), "signe": int(r.get("signe", 0)), "ids": [], "poussee": 0.0}
		(roles[cle]["ids"] as Array).append(String(r["id"]))
		roles[cle]["poussee"] += float(r["poussee_max"])
	var liste_roles: Array = roles.values()
	liste_roles.sort_custom(func(a, b): return _rang_role(a) < _rang_role(b))
	return {"principaux": principaux, "levage": levage, "total": total, "force": t["force_moteurs"], "couple": c,
		"axes": axes, "decalage": t["decalage_poussee"], "compense": t["couple_compense"], "roles": liste_roles}


## Ordre des rôles : tangage, lacet, roulis (chaque fois un sens puis l'autre), puis glisser.
static func _rang_role(g: Dictionary) -> int:
	return 100 if int(g["axe"]) < 0 else int(g["axe"]) * 10 + (0 if int(g["signe"]) > 0 else 1)


func fiche_poussees() -> Dictionary:
	var r := poussees()
	var t := tableau()
	var f: Vector3 = r["force"]
	var lignes := []
	lignes.append(["Poussée des moteurs", "%s kN (%d moteur%s principa%s à fond)" % [nombre(float(r["total"]) / 1000.0, 1), (r["principaux"] as Array).size(),
		"s" if (r["principaux"] as Array).size() > 1 else "", "ux" if (r["principaux"] as Array).size() > 1 else "l"]])
	if float(t["poussee_avant"]) < 0.99 * float(r["total"]):
		lignes.append(["Vers l'avant, sans tourner", "%s kN seulement : le pilotage réduit les moteurs pour que le vaisseau ne tourne pas" % nombre(float(t["poussee_avant"]) / 1000.0, 1)])
	if f.length() > 0.0:
		var ecart := rad_to_deg(f.normalized().angle_to(Vector3.FORWARD))
		lignes.append(["Résultante", "%s kN, %s" % [nombre(f.length() / 1000.0, 1), "dans l'axe du vaisseau" if ecart < 0.05 else "à %s° de l'axe du vaisseau" % nombre(ecart, 1)]])
	lignes.append(["Poussée / poids au sol", "%s : à fond, il accélère de %s g" % [nombre(t["poussee_poids"], 2), nombre(t["poussee_poids"], 2)]])
	lignes.append(["Décollage vertical", "%s kN, × %s le poids : %s" % [nombre(float(t["poussee_verticale"]) / 1000.0, 1), nombre(t["rapport_vertical"], 2),
		"il peut décoller ici" if bool(t["peut_decoller"]) else "trop faible pour décoller ici"]])
	var c: Vector3 = r["couple"]
	lignes.append(["Couple des moteurs", "%s kN·m · %s" % [nombre(c.length() / 1000.0, 2), _texte_couple(t)]])
	var axes := []
	for a in r["axes"]:
		var part := float(a["part"])
		var kn := "%s kN·m" % nombre(absf(float(a["couple"])) / 1000.0, 2)
		var etat := "rien à compenser" if absf(float(a["couple"])) < 1.0 else (
			"%s · %s %%" % [kn, nombre(part * 100.0, 0)] if is_finite(part) else "%s · aucun propulseur" % kn)
		var l := ligne_liste(_majuscule(String(a["nom"])), etat, clampf(part, 0.0, 1.0) if is_finite(part) else 1.0)
		l["alerte"] = not is_finite(part) or part >= 1.0   # les propulseurs ne suffisent plus : barre rouge
		axes.append(l)
	var moteurs := []
	for m in r["principaux"]:
		moteurs.append(ligne_liste(String(m["nom"]), "%s kN · couple %s kN·m" % [nombre(float(m["poussee"]) / 1000.0, 1),
			nombre((m["couple"] as Vector3).length() / 1000.0, 1)], float(m["poussee"]) / maxf(float(r["total"]), 1.0),
			{"genre": m["genre"], "id": m["id_choix"]}))
	var lev := []
	for m in r["levage"]:
		lev.append(ligne_liste(String(m["nom"]), "%s kN vers %s" % [nombre(float(m["poussee"]) / 1000.0, 1), _direction_txt(m["direction"])], -1.0,
			{"genre": m["genre"], "id": m["id_choix"]}))
	var roles := []
	for g in r["roles"]:
		var elements := []
		for i in g["ids"]:
			elements.append(element_de(piece(String(i))))
		var nom := role_propulseur({"axe": g["axe"], "signe": g["signe"], "effet_rotation": 0.0}).get_slice(" (", 0)
		roles.append(ligne_liste(_majuscule(nom), "%d · %s kN" % [(g["ids"] as Array).size(), nombre(float(g["poussee"]) / 1000.0, 1)], -1.0,
			{"genre": "groupe", "elements": elements}))
	var sections := [{"titre": "COUPLE PAR AXE (la barre : part de ce que les propulseurs compensent)", "liste": axes},
		{"titre": "MOTEURS PRINCIPAUX", "liste": moteurs}]
	if not lev.is_empty():
		sections.append({"titre": "MOTEURS DE LEVAGE (vol vertical)", "liste": lev})
	if not roles.is_empty():
		sections.append({"titre": "PETITS PROPULSEURS, PAR RÔLE", "liste": roles})
	return {"titre": "Poussées et couple", "sous_titre": "analyse ingénieur · moteurs à fond, pose de référence",
		"lignes": lignes, "sections": sections,
		"note": "Une poussée qui ne passe pas par le centre de gravité fait tourner le vaisseau : c'est le couple (flèche violette autour du centre de gravité, case « Poussées »). Au-delà de 100 % sur un axe, les petits propulseurs ne peuvent plus le compenser (barre rouge). Chaque moteur seul ferait tourner le vaisseau (son couple) ; celui d'en face annule le sien."}


# =====================================================================
# ÉTAPE 4 : SYMÉTRIE GAUCHE-DROITE
# =====================================================================
const MILIEU := 0.05          # m : une pièce à moins de 5 cm du plan du milieu n'a pas besoin de jumelle
const ECART_JUMELLE := 0.03   # m : la jumelle est à moins de 3 cm de l'image en miroir


## Point qui situe une pièce (son point d'action s'il en a un, sinon le centre de sa masse).
static func _point_de(p: Dictionary) -> Vector3:
	if p.has("point"):
		return p["point"]
	return p["masse_calculee"]["centre"]


## Défauts de symétrie gauche-droite (plan x = 0), dans la pose de référence : centre de gravité sur le
## côté, masses de chaque côté, poussées de chaque côté, et les pièces qui n'ont pas de jumelle en miroir
## (même type, même masse à 2 % près, même poussée, direction en miroir, à moins de 3 cm de l'image).
func symetrie() -> Dictionary:
	if _symetrie != null:
		return _symetrie
	var gauche := 0.0
	var droite := 0.0
	var milieu := 0.0
	for p in plan.pieces:
		var m := float(p["masse_calculee"]["masse"])
		var x := float((p["masse_calculee"]["centre"] as Vector3).x)
		if x < -MILIEU:
			gauche += m
		elif x > MILIEU:
			droite += m
		else:
			milieu += m
	var pg := 0.0
	var pd := 0.0
	for mt in v.moteurs:
		if mt["role"] == "levage":
			continue
		var x := float((mt["pos_ref"] as Vector3).x)
		if x < -MILIEU:
			pg += float(mt["poussee_n"])
		elif x > MILIEU:
			pd += float(mt["poussee_n"])
	# jumelles : on range les pièces par type et par case de 10 cm (hauteur, longueur), pour ne comparer
	# que les voisines (un vaisseau de 500 pièces reste rapide)
	var cases := {}
	for p in plan.pieces:
		var q := _point_de(p)
		var cle := "%s|%d|%d" % [p["type"], roundi(q.y * 10.0), roundi(q.z * 10.0)]
		if not cases.has(cle):
			cases[cle] = []
		(cases[cle] as Array).append(p)
	var sans := []
	for p in plan.pieces:
		var q := _point_de(p)
		if absf(q.x) < MILIEU:
			continue
		var image := Vector3(-q.x, q.y, q.z)
		var trouve := false
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for b in cases.get("%s|%d|%d" % [p["type"], roundi(q.y * 10.0) + dy, roundi(q.z * 10.0) + dz], []):
					if b != p and _jumelles(p, b, image):
						trouve = true
						break
				if trouve:
					break
			if trouve:
				break
		if not trouve:
			sans.append(String(p["id"]))
	# les défauts, par élément (une pièce posée compte pour une)
	var elements := []
	var vus := {}
	for i in sans:
		var p := piece(i)
		var e := element_de(p)
		var cle := String(e["genre"]) + ":" + String(e["id"])
		if vus.has(cle):
			continue
		vus[cle] = true
		var x := float(_point_de(p).x)
		if e["genre"] == "ajout":
			x = float(_masse_de(pieces_ajout(String(e["id"])))[1].x)
		elements.append({"genre": e["genre"], "id": e["id"], "x": x,
			"nom": nom_element(String(e["id"])) if e["genre"] == "ajout" else nom_lisible(p)})
	_symetrie = {"cg_x": float(plan.proprietes_masse()["centre"].x), "masse_gauche": gauche, "masse_droite": droite,
		"masse_milieu": milieu, "poussee_gauche": pg, "poussee_droite": pd, "sans_jumelle": sans, "elements": elements}
	return _symetrie


static func _jumelles(a: Dictionary, b: Dictionary, image: Vector3) -> bool:
	if (_point_de(b) - image).length() > ECART_JUMELLE:
		return false
	var ma := float(a["masse_calculee"]["masse"])
	var mb := float(b["masse_calculee"]["masse"])
	if absf(ma - mb) > 0.02 * maxf(ma, mb) + 1e-6:
		return false
	for k in ["direction", "normale"]:
		if a.has(k) and b.has(k):
			var da: Vector3 = a[k]
			var db: Vector3 = b[k]
			var d := Vector3(-da.x, da.y, da.z).dot(db)
			if k == "normale":
				d = absf(d)   # une surface d'air n'a pas de sens : sa normale peut être retournée
			if d < 0.995:   # 5,7° d'écart au plus
				return false
	for k in ["poussee_n", "surface_m2"]:
		if a.has(k) and b.has(k) and absf(float(a[k]) - float(b[k])) > 0.01 * maxf(absf(float(a[k])), 1e-6):
			return false
	return true


func fiche_symetrie() -> Dictionary:
	var s := symetrie()
	var t := tableau()
	var c: Vector3 = t["couple_moteurs"]
	var x := float(s["cg_x"])
	var lignes := [["Centre de gravité sur le côté", ("%s %s" % [longueur_txt(x), "à droite" if x > 0.0 else "à gauche"]) if absf(x) >= 0.0005 else "centré (moins de 0,5 mm)"],
		["Masse à gauche", "%s kg" % nombre(s["masse_gauche"], 1)],
		["Masse à droite", "%s kg" % nombre(s["masse_droite"], 1)],
		["Masse au milieu", "%s kg (à moins de 5 cm du plan du milieu)" % nombre(s["masse_milieu"], 1)],
		["Poussée à gauche / à droite", "%s / %s kN (moteurs principaux)" % [nombre(float(s["poussee_gauche"]) / 1000.0, 1), nombre(float(s["poussee_droite"]) / 1000.0, 1)]],
		["Couple de côté des moteurs", "lacet %s kN·m · roulis %s kN·m" % [nombre(c.y / 1000.0, 2), nombre(c.z / 1000.0, 2)]]]
	var liste := []
	for e in s["elements"]:
		var ex := float(e["x"])
		liste.append(ligne_liste(String(e["nom"]), "%s %s" % [longueur_txt(ex), "à droite" if ex > 0.0 else "à gauche"], -1.0,
			{"genre": e["genre"], "id": e["id"]}))
	var sections := []
	if not liste.is_empty():
		sections.append({"titre": "PIÈCES SANS JUMELLE DE L'AUTRE CÔTÉ (en orange)", "liste": liste})
	return {"titre": "Symétrie gauche-droite", "sous_titre": "analyse ingénieur · pose de référence (ailes ouvertes)",
		"lignes": lignes, "sections": sections,
		"note": "Une pièce a une jumelle quand la même pièce (même type, même masse, même poussée) se trouve à la même place de l'autre côté, en miroir. Les pièces sans jumelle sont en orange. Un défaut n'est pas forcément une erreur (le chasseur a le levier des gaz à gauche et le manche à droite), mais il décale le centre de gravité et fait tourner le vaisseau."}


# =====================================================================
# ÉTAPE 4 : LA SALLE À PART (une pièce ou un morceau isolé, analysé seul)
# =====================================================================
## Les tuiles du tableau ingénieur dans la salle à part : les chiffres du morceau seul.
func tuiles_groupe(ids: Array) -> Array:
	var g := analyse_groupe(ids)
	var ib: Basis = g["inertie"]
	var c: Vector3 = g["centre"]
	var tuiles := [
		["MASSE DU MORCEAU", "%s kg" % nombre(g["masse"], 1), "%s %% du vaisseau · %d pièce%s" % [nombre(100.0 * float(g["part"]), 1), g["pieces"], "s" if int(g["pieces"]) > 1 else ""]],
		["SON CENTRE DE GRAVITÉ", "%s m" % nombre(c.z, 2), "à %s du centre du vaisseau" % longueur_txt((c - v.centre_gravite).length())],
		["INERTIE PROPRE", "%s kg·m²" % nombre(maxf(ib.x.x, maxf(ib.y.y, ib.z.z))), "tangage / lacet / roulis : %s / %s / %s" % [nombre(ib.x.x), nombre(ib.y.y), nombre(ib.z.z)]],
	]
	var p := float(g["poussee_principale"]) + float(g["poussee_levage"]) + float(g["poussee_propulseurs"])
	if p > 0.0:
		tuiles.append(["POUSSÉE DU MORCEAU", "%s kN" % nombre(p / 1000.0, 1), "%d moteur%s, %d propulseur%s" % [g["moteurs"], "s" if int(g["moteurs"]) > 1 else "", g["propulseurs"], "s" if int(g["propulseurs"]) > 1 else ""]])
	if float(g["surface_air"]) > 0.0:
		tuiles.append(["SURFACE D'AIR", "%s m²" % nombre(float(g["surface_air"]), 2), "portance dans l'atmosphère"])
	if float(g["masse_sans"]) > 0.0:
		tuiles.append(["LE VAISSEAU SANS LUI", "%s kg" % nombre(g["masse_sans"], 1), "centre de gravité qui " + deplacement_txt(g["deplacement"])])
	return tuiles


# =====================================================================
# NOMBRES EN FRANÇAIS
# =====================================================================
## 8534.6 → « 8 534,6 » (espace fine entre les milliers, virgule).
## Un nombre avec 3 chiffres utiles (une petite pièce n'a pas une inertie de « 0 ») : 12 345, 1,23, 0,000 512.
static func chiffres(x: float) -> String:
	if absf(x) < 1e-12 or absf(x) >= 100.0:
		return nombre(x)
	return nombre(x, clampi(2 - int(floor(log(absf(x)) / log(10.0))), 0, 9))


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
## Sens d'un déplacement en mots : « vers le bas », « vers le bas et l'avant » (les parts de plus d'un quart).
static func sens_txt(d: Vector3) -> String:
	var u := d.normalized()
	var parts := []
	for k in 3:
		if absf(u[k]) > 0.25:
			parts.append([absf(u[k]), [["la droite", "la gauche"], ["le haut", "le bas"], ["l'arrière", "l'avant"]][k][0 if u[k] > 0.0 else 1]])
	parts.sort_custom(func(a, b): return a[0] > b[0])
	return "vers " + " et ".join(parts.map(func(p): return p[1]))


static func _direction_txt(a) -> String:
	var d := Catalogue.vecteur(a).normalized()
	var noms := [[Vector3(0, 0, -1), "l'avant"], [Vector3(0, 0, 1), "l'arrière"], [Vector3(0, 1, 0), "le haut"],
		[Vector3(0, -1, 0), "le bas"], [Vector3(1, 0, 0), "la droite"], [Vector3(-1, 0, 0), "la gauche"]]
	for n in noms:
		if d.dot(n[0]) > 0.999:
			return n[1]
	return vecteur_txt(d)


# =====================================================================
# ÉTAPE 8 : LA CABINE (parois sous pression, air, oxygène, fuites)
# =====================================================================
const VERT_MARGE := Color(0.3, 0.85, 0.5)
const ORANGE_MARGE := Color(1.0, 0.7, 0.25)
const ROUGE_MARGE := Color(1.0, 0.36, 0.32)


## L'analyse de la vie à bord (même calcul que le jeu : scripts/physique/vie_a_bord.gd).
func vie() -> Dictionary:
	if _vie.is_empty():
		_vie = v.vie.analyse if v.vie != null else VieABord.analyser(plan)
	return _vie


## Couleur d'une marge (pression qui casse / pression de la cabine) : vert ≥ ×2, orange de ×1 à ×2, rouge < ×1.
static func couleur_marge(m: float) -> Color:
	return VERT_MARGE if m >= VieABord.MARGE_SURE else (ORANGE_MARGE if m >= 1.0 else ROUGE_MARGE)


static func marge_txt(m: float) -> String:
	if m == INF:
		return "—"
	return "×%s" % (nombre(m, 1) if m < 100.0 else nombre(m))


static func duree_txt(s: float) -> String:
	if s == INF:
		return "toujours"
	if s < 1.0:
		return "%s s" % nombre(s, 2 if s < 0.1 else 1)
	if s < 90.0:
		return "%s s" % nombre(s)
	if s < 5400.0:
		return "%s min" % nombre(s / 60.0)
	if s < 172800.0:
		return "%s h" % nombre(s / 3600.0, 1 if s < 36000.0 else 0)
	return "%s jours" % nombre(s / 86400.0)


static func kpa_txt(p: float) -> String:
	return "%s kPa" % nombre(p / 1000.0, 1 if p < 1.0e6 else 0)


static func surface_trou_txt(s: float) -> String:
	return ("%s cm²" % nombre(s * 1.0e4, 1 if s < 1.0e-3 else 0)) if s < 0.1 else ("%s m²" % nombre(s, 2))


## Les chiffres de la cabine : {a_cabine, consigne, volume, masse_air, masse_o2, reserve_o2, reserve_n2,
## remplissages, recycleur, jours_o2, jours_o2_sans, pire_marge, pire_paroi, surface_trous, trous,
## fuite (texte), compense, temps_vide, temps_armstrong, temps_reserve, survie}
func bilan_cabine() -> Dictionary:
	var a := vie()
	var b := {"a_cabine": bool(a["a_cabine"]), "consigne": float(a["consigne"]), "pire_marge": float(a["pire_marge"]),
		"pire_paroi": int(a["pire_paroi"]), "survie": bool(a["survie"]["present"]), "recycleur": bool(a["survie"]["recycleur"]),
		"reserve_o2": float(a["survie"]["oxygene_kg"]), "reserve_n2": float(a["survie"]["azote_kg"]), "trous": [], "surface_trous": 0.0}
	if not b["a_cabine"]:
		return b
	var cab: Dictionary = a["compartiments"][0]
	var vol := float(cab["volume_m3"])
	var p := float(b["consigne"])
	var m: Array = VieABord.masses_air(p, vol)
	b["volume"] = vol
	b["masse_o2"] = float(m[0])
	b["masse_air"] = float(m[0]) + float(m[1])
	b["remplissages"] = (float(b["reserve_o2"]) + float(b["reserve_n2"])) / maxf(float(b["masse_air"]), 1e-9)
	var conso := VieABord.CONSOMMATION_O2
	b["jours_o2"] = float(b["reserve_o2"]) / (conso * ((1.0 - VieABord.PART_RECYCLEE) if b["recycleur"] else 1.0)) / 86400.0
	b["jours_o2_sans"] = float(b["reserve_o2"]) / conso / 86400.0
	var s_trous := 0.0
	for t in cab["trous"]:
		s_trous += float(t["surface"])
		b["trous"].append(t)
	b["surface_trous"] = s_trous
	b["compense"] = false
	b["temps_vide"] = INF
	b["temps_armstrong"] = INF
	b["temps_reserve"] = INF
	if s_trous > 0.0:
		# débit à la pression de la cabine, dans le vide (jet à la vitesse du son : débit proportionnel à la pression)
		var x_o2 := float(m[0]) / maxf(float(b["masse_air"]), 1e-9)
		var m_mol := 1.0 / (x_o2 / VieABord.M_O2 + (1.0 - x_o2) / VieABord.M_N2)
		var debit: float = VieABord.ecoulement(VieABord.CD * s_trous, p, VieABord.T_CABINE, m_mol, 0.0).x
		var apport := VieABord.DEBIT_REGULATEUR if b["survie"] else 0.0
		var reserve := float(b["reserve_o2"]) + float(b["reserve_n2"])
		if apport >= debit and reserve > 0.0:
			b["compense"] = true
			b["temps_reserve"] = reserve / debit
		else:
			var tau := float(b["masse_air"]) / debit
			b["temps_vide"] = tau * log(p / 100.0)               # jusqu'à 0,1 kPa
			b["temps_armstrong"] = tau * log(p / VieABord.LIMITE_ARMSTRONG) if p > VieABord.LIMITE_ARMSTRONG else 0.0
		b["debit_fuite"] = debit
	return b


## La tuile CABINE du tableau ingénieur : [titre, valeur, détail, couleur].
func tuile_cabine() -> Array:
	var b := bilan_cabine()
	if not b["a_cabine"]:
		return ["CABINE", "aucune", "pas de cabine sous pression : le pilote respire l'air du dehors", Color.WHITE]
	var pm := float(b["pire_marge"])
	var couleur := couleur_marge(pm) if pm < VieABord.MARGE_SURE else Color.WHITE
	var detail := "%s m³ d'air · parois %s · oxygène %s" % [nombre(float(b["volume"]), 1), marge_txt(pm),
		duree_txt(float(b["jours_o2"]) * 86400.0) if b["survie"] else "pas renouvelé"]
	if float(b["surface_trous"]) > 0.0:
		detail = "FUITE : %s ouverts · %s" % [surface_trou_txt(float(b["surface_trous"])),
			"le régulateur compense" if b["compense"] else "vide en " + duree_txt(float(b["temps_vide"]))]
		couleur = ORANGE_MARGE if b["compense"] else ROUGE_MARGE
	return ["CABINE", kpa_txt(float(b["consigne"])), detail, couleur]


## La page CABINE (clic sur la tuile).
func fiche_cabine() -> Dictionary:
	var a := vie()
	var b := bilan_cabine()
	if not b["a_cabine"]:
		return {"titre": "Cabine et vie à bord", "sous_titre": "analyse ingénieur · même calcul que le jeu", "lignes": [
			["Cabine", "aucune : ce vaisseau n'a pas de cabine sous pression"]], "sections": [],
			"note": "La cabine du chasseur est son cockpit. Un volume fermé construit avec les panneaux de l'armature peut aussi être pressurisé."}
	var p := float(b["consigne"])
	var lignes := []
	lignes.append(["Pression de la cabine", "%s, dont %s d'oxygène (comme au niveau de la mer : 101,3 kPa)" % [kpa_txt(p),
		kpa_txt(minf(VieABord.PPO2_CIBLE, p))]])
	lignes.append(["Air de la cabine", "%s m³ · %s (dont %s d'oxygène)" % [nombre(float(b["volume"]), 1), masse_txt(float(b["masse_air"])),
		masse_txt(float(b["masse_o2"]))]])
	var pire := int(b["pire_paroi"])
	if pire >= 0:
		var w: Dictionary = a["parois"][pire]
		lignes.append(["Paroi la plus faible", "%s : casse à %s, marge %s (sûr à partir de ×2)" % [String(w["nom"]),
			kpa_txt(float(w["p_rupture_pa"])), marge_txt(float(w["marge"]))]])
	if b["survie"]:
		lignes.append(["Réserves", "%s d'oxygène, %s d'azote : de quoi remplir la cabine %s fois" % [masse_txt(float(b["reserve_o2"])),
			masse_txt(float(b["reserve_n2"])), nombre(float(b["remplissages"]))]])
		lignes.append(["Recycleur", ("en marche : l'oxygène dure %s (%s sans lui)" if b["recycleur"] else "arrêté : l'oxygène dure %s (%s avec lui)") % [
			duree_txt(float(b["jours_o2"]) * 86400.0), duree_txt((float(b["jours_o2_sans"]) if b["recycleur"] else float(b["reserve_o2"]) / (VieABord.CONSOMMATION_O2 * (1.0 - VieABord.PART_RECYCLEE)) / 86400.0) * 86400.0)]])
	else:
		lignes.append(["Système de survie", "enlevé : pas de régulateur ni de réserves, l'air de la cabine n'est pas renouvelé"])
	if float(b["surface_trous"]) > 0.0:
		lignes.append(["Fuites", ("%s ouverts : le régulateur compense (%s par seconde), réserves vides en %s" % [surface_trou_txt(float(b["surface_trous"])),
			masse_txt(float(b["debit_fuite"])), duree_txt(float(b["temps_reserve"]))]) if b["compense"] else
			("%s ouverts : la cabine se vide en %s (le pilote sous la limite d'Armstrong en %s)" % [surface_trou_txt(float(b["surface_trous"])),
			duree_txt(float(b["temps_vide"])), duree_txt(float(b["temps_armstrong"]))])])
	else:
		lignes.append(["Fuites", "aucune : la cabine est fermée"])
	var sections := []
	for c in a["compartiments"]:
		var liste := []
		for i in c["parois"]:
			var w2: Dictionary = a["parois"][i]
			var l := {}
			if not bool(w2["presente"]):
				l = ligne_liste(_majuscule(String(w2["nom"])), "ENLEVÉE : trou de %s" % surface_trou_txt(float(w2["surface_m2"])), 1.0, {})
				l["alerte"] = true
				l["couleur"] = ROUGE_MARGE
			elif not bool(w2["etanche"]):
				l = ligne_liste(_majuscule(String(w2["nom"])), "laisse passer l'air (%s)" % _nom_matiere_cle(String(w2["matiere"])), 1.0, w2["element"])
				l["alerte"] = true
				l["couleur"] = ROUGE_MARGE
			elif bool(c["pressurise"]):
				var mg := float(w2["marge"])
				l = ligne_liste(_majuscule(String(w2["nom"])), marge_txt(mg), clampf(1.0 / maxf(mg, 1e-9), 0.0, 1.0), w2["element"])
				l["detail"] = "casse à %s · %s" % [kpa_txt(float(w2["p_rupture_pa"])), _forme_paroi(w2)]
				l["alerte"] = mg < VieABord.MARGE_SURE
				if mg < VieABord.MARGE_SURE:
					l["couleur"] = couleur_marge(mg)
			else:
				l = ligne_liste(_majuscule(String(w2["nom"])), "pas sous pression", -1.0, w2["element"])
				l["detail"] = _forme_paroi(w2)
			liste.append(l)
		var titre := "%s : %s m³ · %s" % [String(c["nom"]).to_upper(), nombre(float(c["volume_m3"]), 2),
			("pressurisé" if bool(c["pressurise"]) else "pas pressurisé") if not bool(c["cabine"]) else "parois qui tiennent la pression (part de leur force utilisée)"]
		sections.append({"titre": titre, "liste": liste})
	if not (a["ouverts"] as Array).is_empty():
		var liste2 := []
		for o in a["ouverts"]:
			var elts: Array = (o["panneaux"] as Array).map(func(id): return {"genre": "ajout", "id": String(id)})
			var l2 := ligne_liste("%d panneau%s" % [(o["panneaux"] as Array).size(), "x" if (o["panneaux"] as Array).size() > 1 else ""],
				"%d bord%s sans voisin" % [int(o["bords_ouverts"]), "s" if int(o["bords_ouverts"]) > 1 else ""], -1.0,
				{"genre": "groupe", "elements": elts} if elts.size() > 1 else elts[0])
			if bool(o["pressurise"]):
				l2["couleur"] = ROUGE_MARGE
			liste2.append(l2)
		sections.append({"titre": "SURFACES DE L'ARMATURE PAS FERMÉES (pas de volume, pas de pression)", "liste": liste2})
	return {"titre": "Cabine et vie à bord", "sous_titre": "analyse ingénieur · même calcul que le jeu", "lignes": lignes, "sections": sections,
		"note": "Dans le vide, l'air de la cabine pousse chaque paroi vers le dehors (101 kPa : 10 tonnes par mètre carré). Une paroi courbe tient jusqu'à résistance × épaisseur ÷ rayon ; un panneau plat de l'armature se bombe entre ses poutres (formulaire de Roark). Marge = pression qui la casse ÷ pression de la cabine : au moins ×2 pour une cabine habitée (vert), orange de ×1 à ×2, rouge en dessous (elle casse dans le vide). « Parois » (en haut) les colore sur le vaisseau. Un volume fermé de l'armature (chaque bord de panneau touche un autre panneau) peut être pressurisé (rempli au départ à la pression de la cabine, puis fermé : le régulateur ne sert que la cabine) ; la céramique du bouclier thermique laisse passer l'air."}


## « verre aluminosilicate feuilleté, 1,2 cm, courbe (rayon 73 cm) » ; « …, plat (comme un disque de 41 cm) ».
static func _forme_paroi(w: Dictionary) -> String:
	return "%s, %s, %s" % [_nom_matiere_cle(String(w["matiere"])), longueur_txt(float(w["epaisseur_m"])),
		("courbe (rayon %s)" if String(w["genre"]) == "coque" else "plat (comme un disque de %s de rayon)") % longueur_txt(float(w["rayon_m"]))]


static func _nom_matiere_cle(m: String) -> String:
	return String(Catalogue.MATIERES[m]["nom"]) if Catalogue.MATIERES.has(m) else m


## Couleur de chaque paroi sous pression (pour l'atelier) : {id de pièce ou de pièce posée: Color}.
func couleurs_parois() -> Dictionary:
	var a := vie()
	var res := {}
	for c in a["compartiments"]:
		for i in c["parois"]:
			var w: Dictionary = a["parois"][i]
			if not bool(w["presente"]):
				continue
			var couleur := Color(0.6, 0.65, 0.72)
			if not bool(w["etanche"]):
				couleur = ROUGE_MARGE
			elif bool(c["pressurise"]):
				couleur = couleur_marge(float(w["marge"]))
			res[String(w["element"]["id"])] = couleur
			for d in w.get("dessins", []):
				res[String(d)] = couleur
	return res
