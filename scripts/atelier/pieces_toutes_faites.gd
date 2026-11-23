extends RefCounted
## Atelier, étape 3 : les PIÈCES TOUTES FAITES qu'on pose sur le vaisseau (moteurs, propulseurs, boîtes,
## réservoirs, poutres, plaques, ailes). Chacune a des RÉGLAGES (poussée, dimensions, matière…) ; ses
## pièces pour la physique (masse, poussée, surface d'air) et son dessin sont fabriqués à partir d'eux.
##
## Dans le plan du vaisseau (scripts/atelier/plan.gd), une pièce posée est un « ensemble » :
##   {"id": "moteur_ionique_1", "type": "ensemble", "modele": "moteur_ionique", "nom": "…",
##    "reglages": {"poussee_kn": 200}, "position": […], "rotation_deg": […], "miroir_x": false,
##    "fixe_a": "Aile_bas_gauche", "articulation": "aile_bas_gauche", "symetrique": "moteur_ionique_2",
##    "pieces": [ … fabriquées par pieces() … ]}
## La physique ne lit que les « pieces » (comme pour toute pièce du plan) : elle n'a pas besoin de ce fichier.
##
## Repère d'une pièce toute faite : comme le vaisseau (−Z = avant, +Y = haut, +X = droite), en mètres.
## « attache » dit comment elle se pose sur une surface :
##   - "garde" : elle garde son orientation (un moteur pousse toujours vers l'avant) et vient toucher la
##     surface par le côté ;
##   - "y", "x", "z" : son axe local +Y (+X, +Z) suit la normale de la surface (un propulseur souffle vers
##     l'extérieur, une plaque se couche sur la surface, une aile part de la coque, une poutre en sort).
## Le dessin est PROVISOIRE (formes simples), la physique non. Pas de carburant : la masse ne change pas.
##
## Étape 7 : les PIÈCES MOBILES (charnière, vérin, aile repliable, jambe de train) ont leurs propres
## articulations (articulations()), écrites dans l'ensemble : {"articulations": [{"id": "mouvement", …}]}.
## Leurs morceaux qui bougent disent « articulation » : "mouvement" (le plan en fait « charniere_1/mouvement »,
## portée par la pièce mobile sur laquelle la charnière est posée, s'il y en a une). Une pièce posée SUR une
## pièce mobile va sur sa partie qui bouge (porte()) : une aile posée sur le battant d'une charnière tourne
## avec lui. Les morceaux sont écrits dans la pose 0 de leur articulation (charnière à 0°, vérin rentré,
## aile ouverte, train sorti) : « angle_pose_deg » / « progression_pose ».

const Catalogue = preload("res://scripts/atelier/catalogue.gd")

## Masse par kilonewton de poussée (moteur ionique) : 200 kN → 900 kg (les moteurs du chasseur pèsent
## 400 à 2 000 kg chacun avec leur carénage). Puissance électrique d'un jet ionique à 3 000 m/s :
## P = poussée × vitesse du jet / 2 (pour information : l'électricité viendra plus tard).
const KG_PAR_KN_IONIQUE := 4.5
const VITESSE_JET := 3000.0
const KG_PAR_KN_PROPULSEUR := 2.0
const KG_PAR_KN_LEVAGE := 3.0
const KG_PAR_M2_AILE := 27.0   # ailes du chasseur : 355 kg pour 13 m²

const G0 := 9.80665              # m/s² : la charge d'une jambe de train est un poids sur la Terre
const KG_ROUE_PAR_M3 := 1960.0  # roue + pneu (≈ 25 % d'un disque d'acier plein) : 58 kg pour 50 cm de diamètre
const COMMANDES_MOBILES := ["ailes", "train", "vertical"]

const MATIERES_STRUCTURE := ["aluminium_lithium", "aluminium", "titane", "acier", "composite_carbone"]
const MATIERES_PLAQUE := ["aluminium_lithium", "aluminium", "titane", "acier", "composite_carbone",
	"verre_aluminosilicate", "ceramique"]

## Les modèles. Réglage : {cle, nom, unite, min, max, pas, defaut, decimales} ou {cle, nom, choix, defaut}.
const MODELES := {
	"moteur_ionique": {"nom": "Moteur ionique", "attache": "garde",
		"description": "Moteur principal. Plus il pousse, plus il est gros et lourd (4,5 kg par kN).",
		"reglages": [{"cle": "poussee_kn", "nom": "Poussée", "unite": "kN", "min": 50.0, "max": 600.0, "pas": 10.0,
			"defaut": 200.0, "decimales": 0}]},
	"moteur_levage": {"nom": "Moteur de levage", "attache": "garde",
		"description": "Moteur qui pousse vers le haut (vol vertical, décollage sur place).",
		"reglages": [{"cle": "poussee_kn", "nom": "Poussée", "unite": "kN", "min": 10.0, "max": 120.0, "pas": 2.5,
			"defaut": 37.5, "decimales": 1}]},
	"propulseur": {"nom": "Propulseur d'orientation", "attache": "y",
		"description": "Petit propulseur posé sur la coque : il souffle vers l'extérieur. Son rôle (tourner, glisser) est trouvé par le calcul du couple.",
		"reglages": [{"cle": "poussee_kn", "nom": "Poussée", "unite": "kN", "min": 1.0, "max": 20.0, "pas": 0.5,
			"defaut": 6.0, "decimales": 1}]},
	"aile": {"nom": "Aile", "attache": "x",
		"description": "Aile plate en composite carbone : elle porte et freine dans l'air (27 kg par m²).",
		"reglages": [{"cle": "envergure_m", "nom": "Envergure", "unite": "m", "min": 0.5, "max": 8.0, "pas": 0.1,
			"defaut": 2.5, "decimales": 1},
			{"cle": "corde_m", "nom": "Corde (largeur)", "unite": "m", "min": 0.3, "max": 4.0, "pas": 0.1,
			"defaut": 1.4, "decimales": 1}]},
	"poutre": {"nom": "Poutre", "attache": "z",
		"description": "Barre pleine de section carrée : elle sort de la surface où on la pose.",
		"reglages": [{"cle": "matiere", "nom": "Matière", "choix": MATIERES_STRUCTURE, "defaut": "aluminium_lithium"},
			{"cle": "longueur_m", "nom": "Longueur", "unite": "m", "min": 0.2, "max": 15.0, "pas": 0.1, "defaut": 2.0,
			"decimales": 1},
			{"cle": "section_m", "nom": "Section", "unite": "m", "min": 0.04, "max": 0.6, "pas": 0.01, "defaut": 0.12,
			"decimales": 2}]},
	"plaque": {"nom": "Plaque", "attache": "y",
		"description": "Plaque pleine (panneau de coque, cloison, bouclier) couchée sur la surface.",
		"reglages": [{"cle": "matiere", "nom": "Matière", "choix": MATIERES_PLAQUE, "defaut": "aluminium_lithium"},
			{"cle": "longueur_m", "nom": "Longueur", "unite": "m", "min": 0.1, "max": 10.0, "pas": 0.1, "defaut": 1.5,
			"decimales": 1},
			{"cle": "largeur_m", "nom": "Largeur", "unite": "m", "min": 0.1, "max": 10.0, "pas": 0.1, "defaut": 1.0,
			"decimales": 1},
			{"cle": "epaisseur_m", "nom": "Épaisseur", "unite": "m", "min": 0.002, "max": 0.2, "pas": 0.001,
			"defaut": 0.01, "decimales": 3}]},
	"boite": {"nom": "Boîte d'équipement", "attache": "y",
		"description": "Équipement compté comme une boîte pleine de la masse choisie (ordinateur, batterie, lest…).",
		"reglages": [{"cle": "masse_kg", "nom": "Masse", "unite": "kg", "min": 5.0, "max": 3000.0, "pas": 5.0,
			"defaut": 150.0, "decimales": 0},
			{"cle": "largeur_m", "nom": "Largeur", "unite": "m", "min": 0.2, "max": 4.0, "pas": 0.05, "defaut": 0.8,
			"decimales": 2},
			{"cle": "hauteur_m", "nom": "Hauteur", "unite": "m", "min": 0.1, "max": 3.0, "pas": 0.05, "defaut": 0.45,
			"decimales": 2},
			{"cle": "longueur_m", "nom": "Longueur", "unite": "m", "min": 0.2, "max": 6.0, "pas": 0.05, "defaut": 1.0,
			"decimales": 2}]},
	# --- étape 7 : pièces mobiles ---
	"charniere": {"nom": "Charnière motorisée", "attache": "y", "porte": "mouvement",
		"description": "Un battant qui tourne autour d'un axe, mû par une commande (0 et 1 : deux angles). Ce qu'on pose sur le battant tourne avec lui.",
		"reglages": [{"cle": "commande", "nom": "Commande", "choix": COMMANDES_MOBILES, "defaut": "ailes"},
			{"cle": "angle_0_deg", "nom": "Angle à 0", "unite": "°", "min": -180.0, "max": 180.0, "pas": 5.0, "defaut": 0.0, "decimales": 0},
			{"cle": "angle_1_deg", "nom": "Angle à 1", "unite": "°", "min": -180.0, "max": 180.0, "pas": 5.0, "defaut": 90.0, "decimales": 0},
			{"cle": "longueur_m", "nom": "Longueur", "unite": "m", "min": 0.1, "max": 3.0, "pas": 0.05, "defaut": 0.5, "decimales": 2}]},
	"verin": {"nom": "Vérin", "attache": "y", "porte": "tige",
		"description": "Une tige qui sort et rentre tout droit (0 : rentrée, 1 : sortie). Ce qu'on pose sur son plateau monte et descend avec lui.",
		"reglages": [{"cle": "commande", "nom": "Commande", "choix": COMMANDES_MOBILES, "defaut": "vertical"},
			{"cle": "course_m", "nom": "Course", "unite": "m", "min": 0.05, "max": 3.0, "pas": 0.05, "defaut": 0.5, "decimales": 2},
			{"cle": "diametre_m", "nom": "Diamètre", "unite": "m", "min": 0.04, "max": 0.5, "pas": 0.01, "defaut": 0.12, "decimales": 2}]},
	"aile_repliable": {"nom": "Aile repliable", "attache": "x", "porte": "pli",
		"description": "Aile qui se replie à sa base (commande des ailes : 1 = ouverte, 0 = repliée). Dans le hangar, les ailes sont repliées.",
		"reglages": [{"cle": "envergure_m", "nom": "Envergure", "unite": "m", "min": 0.5, "max": 8.0, "pas": 0.1,
			"defaut": 2.5, "decimales": 1},
			{"cle": "corde_m", "nom": "Corde (largeur)", "unite": "m", "min": 0.3, "max": 4.0, "pas": 0.1,
			"defaut": 1.4, "decimales": 1},
			{"cle": "angle_repliee_deg", "nom": "Angle replié", "unite": "°", "min": -150.0, "max": 150.0, "pas": 5.0,
			"defaut": 90.0, "decimales": 0}]},
	"jambe_train": {"nom": "Jambe de train", "attache": "garde", "porte": "pivot",
		"description": "Jambe avec sa roue et son amortisseur, qui rentre en tournant (commande du train : 1 = sortie, 0 = rentrée). L'amortisseur est réglé pour le poids qu'elle porte.",
		"reglages": [{"cle": "hauteur_m", "nom": "Hauteur", "unite": "m", "min": 0.3, "max": 3.0, "pas": 0.05, "defaut": 1.0, "decimales": 2},
			{"cle": "rayon_roue_m", "nom": "Rayon de la roue", "unite": "m", "min": 0.1, "max": 0.6, "pas": 0.01, "defaut": 0.25, "decimales": 2},
			{"cle": "charge_t", "nom": "Poids porté", "unite": "t", "min": 0.2, "max": 30.0, "pas": 0.1, "defaut": 3.0, "decimales": 1},
			{"cle": "rentree", "nom": "Rentre vers", "choix": ["avant", "arriere"], "defaut": "avant"},
			{"cle": "orientable", "nom": "Roue qui tourne", "choix": ["non", "oui"], "defaut": "non"}]},
	"reservoir": {"nom": "Réservoir", "attache": "garde",
		"description": "Réservoir d'eau ou d'air pour la vie à bord (pas de carburant : les moteurs n'en ont pas besoin).",
		"reglages": [{"cle": "volume_l", "nom": "Volume", "unite": "L", "min": 20.0, "max": 5000.0, "pas": 10.0,
			"defaut": 400.0, "decimales": 0},
			{"cle": "contenu", "nom": "Contenu", "choix": ["eau", "air"], "defaut": "eau"}]},
}

## Ce que contient un réservoir : masse volumique (kg/m³) et masse de l'enveloppe (kg par m² de paroi).
const CONTENUS := {
	"eau": {"nom": "eau", "densite": 1000.0, "paroi_kg_m2": 12.0},
	"air": {"nom": "air comprimé à 300 bar", "densite": 357.0, "paroi_kg_m2": 45.0},
}

## Les pièces proposées dans le catalogue de l'atelier : [catégorie, nom, modèle, réglages].
const PROPOSITIONS := [
	["Moteurs", "Moteur ionique petit (100 kN)", "moteur_ionique", {"poussee_kn": 100.0}],
	["Moteurs", "Moteur ionique moyen (200 kN)", "moteur_ionique", {"poussee_kn": 200.0}],
	["Moteurs", "Moteur ionique gros (400 kN)", "moteur_ionique", {"poussee_kn": 400.0}],
	["Moteurs", "Moteur de levage (37,5 kN)", "moteur_levage", {}],
	["Petits propulseurs", "Propulseur d'orientation (6 kN)", "propulseur", {}],
	["Ailes", "Aile (2,5 × 1,4 m)", "aile", {}],
	["Structure", "Poutre", "poutre", {}],
	["Structure", "Plaque de coque", "plaque", {}],
	["Structure", "Bouclier thermique (céramique)", "plaque", {"matiere": "ceramique", "epaisseur_m": 0.05}],
	["Équipements", "Boîte d'équipement", "boite", {}],
	["Équipements", "Réservoir d'eau (400 L)", "reservoir", {}],
	["Équipements", "Réservoir d'air (400 L)", "reservoir", {"contenu": "air"}],
	["Pièces mobiles", "Charnière motorisée (0° → 90°)", "charniere", {}],
	["Pièces mobiles", "Vérin (50 cm)", "verin", {}],
	["Pièces mobiles", "Aile repliable (2,5 × 1,4 m)", "aile_repliable", {}],
	["Pièces mobiles", "Jambe de train (3 t)", "jambe_train", {}],
	["Pièces mobiles", "Jambe de train avant, roue qui tourne", "jambe_train", {"orientable": "oui", "charge_t": 1.5, "hauteur_m": 0.9}],
]

## Noms affichés des choix qui ne sont ni des matières ni des contenus.
const NOMS_CHOIX := {
	"ailes": "ailes (1 = ouvertes)", "train": "train (1 = sorti)", "vertical": "vol vertical (1 = vertical)",
	"avant": "vers l'avant", "arriere": "vers l'arrière", "oui": "oui", "non": "non",
}


static func existe(modele: String) -> bool:
	return MODELES.has(modele)


static func nom(modele: String) -> String:
	return String(MODELES[modele]["nom"]) if MODELES.has(modele) else modele


static func attache(modele: String) -> String:
	return String(MODELES[modele]["attache"]) if MODELES.has(modele) else "garde"


## Étape 7 : la partie mobile d'une pièce mobile qui porte ce qu'on pose dessus ("" : pièce fixe).
static func porte(modele: String) -> String:
	return String(MODELES[modele].get("porte", "")) if MODELES.has(modele) else ""


## Vrai pour une pièce mobile (elle a ses propres articulations).
static func mobile(modele: String) -> bool:
	return porte(modele) != ""


## Remplit un ensemble du plan d'après son modèle et ses réglages : ses pièces, et ses articulations s'il en a.
static func remplir(e: Dictionary, modele: String, r: Dictionary) -> void:
	e["pieces"] = pieces(modele, r, String(e.get("id", "")))
	var arts := articulations(modele, r)
	if arts.is_empty():
		e.erase("articulations")
	else:
		e["articulations"] = arts


static func definition_reglage(modele: String, cle: String) -> Dictionary:
	if not MODELES.has(modele):
		return {}
	for r in MODELES[modele]["reglages"]:
		if r["cle"] == cle:
			return r
	return {}


## Réglages complets : ceux qui manquent prennent leur valeur par défaut ; les nombres restent dans leurs
## bornes, les choix parmi ceux permis.
static func reglages_complets(modele: String, r := {}) -> Dictionary:
	var sortie := {}
	if not MODELES.has(modele):
		return r.duplicate()
	for d in MODELES[modele]["reglages"]:
		var cle: String = d["cle"]
		var v = r.get(cle, d["defaut"])
		if d.has("choix"):
			sortie[cle] = String(v) if (d["choix"] as Array).has(String(v)) else String(d["defaut"])
		else:
			sortie[cle] = clampf(float(v), float(d["min"]), float(d["max"]))
	return sortie


static func _f(r: Dictionary, cle: String) -> float:
	return float(r[cle])


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


# =====================================================================
# DIMENSIONS (communes au dessin et à la physique)
# =====================================================================
## Diamètre et longueur d'un moteur ionique : la poussée suit la surface de sortie (√), la longueur un peu
## moins vite.
static func dimensions_ionique(poussee_kn: float) -> Vector2:
	return Vector2(1.0 * sqrt(poussee_kn / 200.0), 2.6 * pow(poussee_kn / 200.0, 1.0 / 3.0))


static func dimensions_levage(poussee_kn: float) -> Vector2:
	var s := sqrt(poussee_kn / 37.5)
	return Vector2(0.62 * s, 0.42 * sqrt(s))


## Diamètre et longueur d'un réservoir en forme de gélule (longueur = 2,2 × diamètre).
static func dimensions_reservoir(volume_l: float) -> Vector2:
	var v := volume_l / 1000.0
	var d := pow(v / (PI * (1.2 / 4.0 + 1.0 / 6.0)), 1.0 / 3.0)
	return Vector2(d, 2.2 * d)


## Charnière : longueur L → [largeur d'un battant, épaisseur, rayon de l'axe] (m).
static func dimensions_charniere(l: float) -> Vector3:
	return Vector3(0.12 + 0.2 * l, 0.02 + 0.01 * l, 0.03 + 0.03 * l)


## Vérin : longueur du corps (tige rentrée dedans) pour sa course.
static func longueur_verin(course: float) -> float:
	return course + 0.12


## Jambe de train : [diamètre de la jambe, course de l'amortisseur] (m) pour la hauteur et le poids porté.
static func dimensions_jambe(r: Dictionary) -> Vector2:
	return Vector2(0.06 + 0.04 * sqrt(_f(r, "charge_t")), clampf(0.1 * _f(r, "hauteur_m") + 0.05, 0.08, 0.35))


static func _densite(matiere: String) -> float:
	return float(Catalogue.MATIERES[matiere]["densite"])


## Étape 7 : les articulations d'une pièce mobile (repère de la pièce ; le plan les place et les nomme
## « id de l'ensemble/id »). Vide pour une pièce fixe.
static func articulations(modele: String, reglages: Dictionary) -> Array:
	var r := reglages_complets(modele, reglages)
	match modele:
		"charniere":
			var dc := dimensions_charniere(_f(r, "longueur_m"))
			return [{"id": "mouvement", "type": "charniere", "nom": "battant", "commande": String(r["commande"]),
				"point": [0.0, snappedf(dc.z, 0.0001), 0.0], "axe": [1.0, 0.0, 0.0],
				"angle_0_deg": _f(r, "angle_0_deg"), "angle_1_deg": _f(r, "angle_1_deg"), "angle_pose_deg": 0.0}]
		"verin":
			return [{"id": "tige", "type": "verin", "nom": "tige", "commande": String(r["commande"]),
				"course": [0.0, _f(r, "course_m"), 0.0], "progression_pose": 0.0}]
		"aile_repliable":
			# ouverte (1) : à plat ; repliée (0) : bout de l'aile relevé de l'angle choisi, autour de l'axe avant-arrière
			return [{"id": "pli", "type": "charniere", "nom": "pli de l'aile", "commande": "ailes",
				"point": [0.0, 0.0, 0.0], "axe": [0.0, 0.0, 1.0],
				"angle_0_deg": _f(r, "angle_repliee_deg"), "angle_1_deg": 0.0, "angle_pose_deg": 0.0}]
		"jambe_train":
			# sortie (1) : droite vers le bas ; rentrée (0) : couchée vers l'avant (ou l'arrière), autour de l'axe gauche-droite
			var a0 := 90.0 if String(r["rentree"]) == "avant" else -90.0
			return [{"id": "pivot", "type": "charniere", "nom": "pivot de la jambe", "commande": "train",
				"point": [0.0, 0.0, 0.0], "axe": [1.0, 0.0, 0.0],
				"angle_0_deg": a0, "angle_1_deg": 0.0, "angle_pose_deg": 0.0}]
	return []


# =====================================================================
# PIÈCES POUR LA PHYSIQUE (repère de la pièce toute faite)
# =====================================================================
## Les pièces du plan d'une pièce toute faite. id_ensemble sert à nommer ses surfaces d'air (chaque aile
## a son groupe).
static func pieces(modele: String, reglages: Dictionary, id_ensemble := "") -> Array:
	var r := reglages_complets(modele, reglages)
	match modele:
		"moteur_ionique":
			var p := _f(r, "poussee_kn")
			var dl := dimensions_ionique(p)
			return [
				{"id": "corps", "type": "bloc", "forme": "cylindre", "dimensions_m": [snappedf(dl.x, 0.0001), snappedf(dl.y, 0.0001)],
					"position": [0.0, 0.0, 0.0], "masse_kg": snappedf(KG_PAR_KN_IONIQUE * p, 0.01), "matiere": "titane"},
				{"id": "poussee", "type": "moteur", "point": _arr(Vector3(0, 0, dl.y * 0.5)), "direction": [0.0, 0.0, -1.0],
					"poussee_n": p * 1000.0, "role": "principal", "nom": id_ensemble if id_ensemble != "" else "moteur ionique"},
			]
		"moteur_levage":
			var p2 := _f(r, "poussee_kn")
			var dh := dimensions_levage(p2)
			return [
				{"id": "corps", "type": "bloc", "forme": "cylindre", "dimensions_m": [snappedf(dh.x, 0.0001), snappedf(dh.y, 0.0001)],
					"position": [0.0, 0.0, 0.0], "rotation_deg": [90.0, 0.0, 0.0],
					"masse_kg": snappedf(KG_PAR_KN_LEVAGE * p2, 0.01), "matiere": "titane"},
				{"id": "poussee", "type": "moteur", "point": _arr(Vector3(0, -dh.y * 0.5, 0)), "direction": [0.0, 1.0, 0.0],
					"poussee_n": p2 * 1000.0, "role": "levage", "nom": "levage " + (id_ensemble if id_ensemble != "" else "posé")},
			]
		"propulseur":
			var p3 := _f(r, "poussee_kn")
			var s := sqrt(p3 / 6.0)
			return [
				{"id": "corps", "type": "bloc", "forme": "boite", "dimensions_m": _arr(Vector3(0.24, 0.1, 0.24) * s),
					"position": _arr(Vector3(0, 0.05 * s, 0)), "masse_kg": snappedf(KG_PAR_KN_PROPULSEUR * p3, 0.01),
					"matiere": "titane"},
				{"id": "poussee", "type": "propulseur", "point": _arr(Vector3(0, 0.24 * s, 0)), "direction": [0.0, -1.0, 0.0],
					"poussee_n": p3 * 1000.0, "nom": id_ensemble if id_ensemble != "" else "propulseur"},
			]
		"aile":
			var b := _f(r, "envergure_m")
			var c := _f(r, "corde_m")
			return [
				{"id": "corps", "type": "bloc", "forme": "boite", "dimensions_m": _arr(Vector3(b, 0.09 * c, c)),
					"position": _arr(Vector3(b * 0.5, 0, 0)), "masse_kg": snappedf(KG_PAR_M2_AILE * b * c, 0.01),
					"matiere": "composite_carbone"},
				{"id": "air", "type": "surface_air", "point": _arr(Vector3(b * 0.5, 0, -c * 0.25)), "normale": [0.0, 1.0, 0.0],
					"surface_m2": snappedf(b * c, 0.0001), "allongement": snappedf(2.0 * b / c, 0.001), "corde_m": c,
					"groupe": id_ensemble if id_ensemble != "" else "aile"},
			]
		"poutre":
			return [{"id": "poutre", "type": "poutre", "matiere": r["matiere"], "position": [0.0, 0.0, 0.0],
				"longueur_m": _f(r, "longueur_m"), "largeur_m": _f(r, "section_m"), "hauteur_m": _f(r, "section_m")}]
		"plaque":
			return [{"id": "plaque", "type": "plaque", "matiere": r["matiere"], "position": [0.0, 0.0, 0.0],
				"longueur_m": _f(r, "longueur_m"), "largeur_m": _f(r, "largeur_m"), "epaisseur_m": _f(r, "epaisseur_m")}]
		"boite":
			return [{"id": "boite", "type": "bloc", "forme": "boite",
				"dimensions_m": _arr(Vector3(_f(r, "largeur_m"), _f(r, "hauteur_m"), _f(r, "longueur_m"))),
				"position": [0.0, 0.0, 0.0], "masse_kg": _f(r, "masse_kg")}]
		"charniere":
			# deux battants d'acier de part et d'autre d'un axe (l'axe : 1,5 × sa masse pleine, avec son moteur)
			var l := _f(r, "longueur_m")
			var dc := dimensions_charniere(l)
			var ac := _densite("acier")
			return [
				{"id": "base", "type": "bloc", "forme": "boite", "dimensions_m": _arr(Vector3(l, dc.y, dc.x)),
					"position": _arr(Vector3(0, dc.y * 0.5, dc.x * 0.5)), "masse_kg": snappedf(ac * l * dc.y * dc.x, 0.01), "matiere": "acier"},
				{"id": "axe", "type": "bloc", "forme": "cylindre", "dimensions_m": [snappedf(2.0 * dc.z, 0.0001), l],
					"position": _arr(Vector3(0, dc.z, 0)), "rotation_deg": [0.0, 90.0, 0.0],
					"masse_kg": snappedf(1.5 * ac * PI * dc.z * dc.z * l, 0.01), "matiere": "acier"},
				{"id": "battant", "type": "bloc", "forme": "boite", "dimensions_m": _arr(Vector3(l, dc.y, dc.x)),
					"position": _arr(Vector3(0, dc.z, -dc.x * 0.5)), "masse_kg": snappedf(ac * l * dc.y * dc.x, 0.01),
					"matiere": "acier", "articulation": "mouvement"},
			]
		"verin":
			# corps creux (moitié de sa masse pleine), tige pleine et plateau d'acier
			var d := _f(r, "diametre_m")
			var lc := longueur_verin(_f(r, "course_m"))
			var ac2 := _densite("acier")
			var rt := d * 0.22
			return [
				{"id": "corps", "type": "bloc", "forme": "cylindre", "dimensions_m": [d, snappedf(lc, 0.0001)],
					"position": _arr(Vector3(0, lc * 0.5, 0)), "rotation_deg": [90.0, 0.0, 0.0],
					"masse_kg": snappedf(0.5 * ac2 * PI * d * d * 0.25 * lc, 0.01), "matiere": "acier"},
				{"id": "tige", "type": "bloc", "forme": "cylindre", "dimensions_m": [snappedf(2.0 * rt, 0.0001), snappedf(lc, 0.0001)],
					"position": _arr(Vector3(0, lc * 0.5 + 0.04, 0)), "rotation_deg": [90.0, 0.0, 0.0],
					"masse_kg": snappedf(ac2 * PI * rt * rt * lc, 0.01), "matiere": "acier", "articulation": "tige"},
				{"id": "plateau", "type": "bloc", "forme": "boite", "dimensions_m": _arr(Vector3(1.6 * d, 0.02, 1.6 * d)),
					"position": _arr(Vector3(0, lc + 0.05, 0)), "masse_kg": snappedf(ac2 * 2.56 * d * d * 0.02, 0.01),
					"matiere": "acier", "articulation": "tige"},
			]
		"aile_repliable":
			# la même aile, posée sur son pli, plus la ferrure du pli (acier, fixe)
			var morceaux := pieces("aile", {"envergure_m": r["envergure_m"], "corde_m": r["corde_m"]}, id_ensemble)
			for m in morceaux:
				m["articulation"] = "pli"
			var c2 := _f(r, "corde_m")
			var rf := 0.02 + 0.045 * c2
			morceaux.append({"id": "ferrure", "type": "bloc", "forme": "cylindre",
				"dimensions_m": [snappedf(2.0 * rf, 0.0001), snappedf(0.6 * c2, 0.0001)], "position": [0.0, 0.0, 0.0],
				"masse_kg": snappedf(_densite("acier") * PI * rf * rf * 0.6 * c2, 0.01), "matiere": "acier"})
			return morceaux
		"jambe_train":
			# jambe (tube d'acier : 60 % de sa masse pleine), roue, et l'amortisseur réglé pour le poids porté :
			# écrasé de 40 % de sa course sous ce poids, amorti à 80 % du critique (pas de rebond)
			var h := _f(r, "hauteur_m")
			var rr := _f(r, "rayon_roue_m")
			var dj := dimensions_jambe(r)
			var charge := _f(r, "charge_t") * 1000.0
			var ac3 := _densite("acier")
			var raideur := charge * G0 / (0.4 * dj.y)
			var roue := {"id": "roue", "type": "roue", "point": _arr(Vector3(0, -h - rr, 0)), "course_m": snappedf(dj.y, 0.0001),
				"raideur_n_m": snappedf(raideur, 1.0), "amorti_n_s_m": snappedf(1.6 * sqrt(raideur * charge), 1.0),
				"rayon_m": rr, "freinee": String(r["orientable"]) != "oui", "choc_max_m_s": 2.0, "articulation": "pivot"}
			if String(r["orientable"]) == "oui":
				roue["orientable_deg"] = 35.0
			return [
				{"id": "fixation", "type": "bloc", "forme": "boite", "dimensions_m": _arr(Vector3(2.2 * dj.x, 0.06, 2.2 * dj.x)),
					"position": [0.0, -0.03, 0.0], "masse_kg": snappedf(ac3 * 4.84 * dj.x * dj.x * 0.06, 0.01), "matiere": "acier"},
				{"id": "jambe", "type": "bloc", "forme": "cylindre", "dimensions_m": [snappedf(dj.x, 0.0001), h],
					"position": _arr(Vector3(0, -h * 0.5, 0)), "rotation_deg": [90.0, 0.0, 0.0],
					"masse_kg": snappedf(0.6 * ac3 * PI * dj.x * dj.x * 0.25 * h, 0.01), "matiere": "acier", "articulation": "pivot"},
				{"id": "masse_roue", "type": "bloc", "forme": "cylindre", "dimensions_m": [snappedf(2.0 * rr, 0.0001), snappedf(0.6 * rr, 0.0001)],
					"position": _arr(Vector3(0, -h, 0)), "rotation_deg": [0.0, 90.0, 0.0],
					"masse_kg": snappedf(KG_ROUE_PAR_M3 * PI * rr * rr * 0.6 * rr, 0.01), "articulation": "pivot"},
				roue,
			]
		"reservoir":
			var dr := dimensions_reservoir(_f(r, "volume_l"))
			return [{"id": "reservoir", "type": "bloc", "forme": "cylindre", "dimensions_m": [snappedf(dr.x, 0.0001), snappedf(dr.y, 0.0001)],
				"position": [0.0, 0.0, 0.0], "masse_kg": snappedf(masse_reservoir(r), 0.01), "matiere": "aluminium",
				"note": "%s, %s L" % [CONTENUS[r["contenu"]]["nom"], _f(r, "volume_l")]}]
	return []


static func masse_reservoir(r: Dictionary) -> float:
	var c: Dictionary = CONTENUS[String(r["contenu"])]
	var dr := dimensions_reservoir(float(r["volume_l"]))
	var paroi := 2.2 * PI * dr.x * dr.x   # surface d'une gélule de longueur 2,2 × diamètre
	return float(r["volume_l"]) / 1000.0 * float(c["densite"]) + paroi * float(c["paroi_kg_m2"])


## Masse totale (kg) d'une pièce toute faite.
static func masse(modele: String, reglages: Dictionary) -> float:
	var m := 0.0
	for p in pieces(modele, reglages):
		m += float(Catalogue.masse_piece(p)["masse"])
	return m


## Boîte (repère de la pièce) qui contient tout son dessin : sert à la poser contre une surface.
static func boite(modele: String, reglages: Dictionary) -> AABB:
	var r := reglages_complets(modele, reglages)
	match modele:
		"moteur_ionique":
			var dl := dimensions_ionique(_f(r, "poussee_kn"))
			return AABB(Vector3(-dl.x * 0.5, -dl.x * 0.5, -dl.y * 0.5), Vector3(dl.x, dl.x, dl.y))
		"moteur_levage":
			var dh := dimensions_levage(_f(r, "poussee_kn"))
			return AABB(Vector3(-dh.x * 0.5, -dh.y * 0.5 - 0.03, -dh.x * 0.5), Vector3(dh.x, dh.y + 0.03, dh.x))
		"propulseur":
			var s := sqrt(_f(r, "poussee_kn") / 6.0)
			return AABB(Vector3(-0.12, 0.0, -0.12) * s, Vector3(0.24, 0.24, 0.24) * s)
		"aile":
			var b := _f(r, "envergure_m")
			var c := _f(r, "corde_m")
			return AABB(Vector3(0.0, -0.045 * c, -c * 0.5), Vector3(b, 0.09 * c, c))
		"poutre":
			var sc := _f(r, "section_m")
			var l := _f(r, "longueur_m")
			return AABB(Vector3(-sc * 0.5, -sc * 0.5, -l * 0.5), Vector3(sc, sc, l))
		"plaque":
			var t := Vector3(_f(r, "largeur_m"), _f(r, "epaisseur_m"), _f(r, "longueur_m"))
			return AABB(-t * 0.5, t)
		"boite":
			var t2 := Vector3(_f(r, "largeur_m"), _f(r, "hauteur_m"), _f(r, "longueur_m"))
			return AABB(-t2 * 0.5, t2)
		"reservoir":
			var dr := dimensions_reservoir(_f(r, "volume_l"))
			return AABB(Vector3(-dr.x * 0.5, -dr.x * 0.5, -dr.y * 0.5), Vector3(dr.x, dr.x, dr.y))
		"charniere":
			var lh := _f(r, "longueur_m")
			var dc := dimensions_charniere(lh)
			return AABB(Vector3(-lh * 0.5, 0.0, -dc.x), Vector3(lh, 2.0 * dc.z, 2.0 * dc.x))
		"verin":
			var dv := _f(r, "diametre_m")
			var lc := longueur_verin(_f(r, "course_m"))
			return AABB(Vector3(-0.8 * dv, 0.0, -0.8 * dv), Vector3(1.6 * dv, lc + 0.06, 1.6 * dv))
		"aile_repliable":
			var b2 := _f(r, "envergure_m")
			var c3 := _f(r, "corde_m")
			var rf := 0.02 + 0.045 * c3
			return AABB(Vector3(-rf, -maxf(0.045 * c3, rf), -c3 * 0.5), Vector3(b2 + rf, 2.0 * maxf(0.045 * c3, rf), c3))
		"jambe_train":
			var hj := _f(r, "hauteur_m")
			var rj := _f(r, "rayon_roue_m")
			var dj := dimensions_jambe(r)
			var lx := maxf(1.1 * dj.x, 0.3 * rj)
			var lz := maxf(1.1 * dj.x, rj)
			return AABB(Vector3(-lx, -hj - rj, -lz), Vector3(2.0 * lx, hj + rj, 2.0 * lz))
	return AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))


## Résumé d'une ligne : « 200 kN · 900 kg ».
static func resume(modele: String, reglages: Dictionary) -> String:
	var r := reglages_complets(modele, reglages)
	var m := masse(modele, r)
	var kg := "%s kg" % _nombre(m, 0 if m >= 10.0 else 1)
	match modele:
		"moteur_ionique", "moteur_levage", "propulseur":
			return "%s kN · %s" % [_nombre(_f(r, "poussee_kn"), 1 if fmod(_f(r, "poussee_kn"), 1.0) != 0.0 else 0), kg]
		"aile", "aile_repliable":
			return "%s m² · %s" % [_nombre(_f(r, "envergure_m") * _f(r, "corde_m"), 1), kg]
		"charniere":
			return "%s° → %s° · %s" % [_nombre(_f(r, "angle_0_deg")), _nombre(_f(r, "angle_1_deg")), kg]
		"verin":
			return "course %s m · %s" % [_nombre(_f(r, "course_m"), 2), kg]
		"jambe_train":
			return "porte %s t · %s" % [_nombre(_f(r, "charge_t"), 1), kg]
		"reservoir":
			return "%s L · %s" % [_nombre(_f(r, "volume_l"), 0), kg]
	return kg


static func _nombre(x: float, decimales := 0) -> String:
	var t := ("%." + str(decimales) + "f") % x
	return t.replace(".", ",")


# =====================================================================
# DESSIN (PROVISOIRE)
# =====================================================================
## Les formes simples du dessin, repère de la pièce : [{forme, taille, xf, couleur, metal, rugosite, role}].
##   forme : "boite" (taille = côtés), "cylindre" (taille = rayon en haut, rayon en bas, hauteur ; axe Y de
##   xf), "gelule" (rayon, hauteur ; axe Y de xf) ;
##   role : "" (pièce), "lueur" (sortie qui s'allume dans le jeu), "panache" (jet ; taille = rayon au départ,
##   rayon au bout, longueur, le long de l'axe +Y de xf, en partant de son origine) ;
##   vitre : vrai pour une plaque en verre (dessinée transparente ; dans le jeu, une vraie vitre).
static func dessin(modele: String, reglages: Dictionary) -> Array:
	var r := reglages_complets(modele, reglages)
	var titane := Color(0.56, 0.57, 0.6)
	var sombre := Color(0.2, 0.205, 0.22)   # (albédo 3 % : métal noirci ; plus sombre n'existe pas, étape 5)
	var vers_z := Basis(Vector3.RIGHT, PI * 0.5)    # axe Y du cylindre → axe +Z de la pièce
	var vers_bas := Basis(Vector3.RIGHT, PI)        # axe Y → −Y
	match modele:
		"moteur_ionique":
			var dl := dimensions_ionique(_f(r, "poussee_kn"))
			var d := dl.x
			var l := dl.y
			return [
				_forme("cylindre", Vector3(d * 0.5, d * 0.5, l * 0.72), Transform3D(vers_z, Vector3(0, 0, -l * 0.14)), titane, 0.85, 0.35),
				_forme("cylindre", Vector3(d * 0.47, d * 0.47, l * 0.05), Transform3D(vers_z, Vector3(0, 0, -l * 0.5 + l * 0.025)), sombre, 0.6, 0.5),
				_forme("cylindre", Vector3(d * 0.46, d * 0.36, l * 0.28), Transform3D(vers_z, Vector3(0, 0, l * 0.36)), Color(0.3, 0.3, 0.33), 0.9, 0.3),
				_forme("cylindre", Vector3(d * 0.42, d * 0.42, 0.02), Transform3D(vers_z, Vector3(0, 0, l * 0.5 - 0.03)), Color.BLACK, 0.0, 1.0, "lueur"),
				_forme("panache", Vector3(d * 0.42, d * 0.08, d * 2.5), Transform3D(vers_z, Vector3(0, 0, l * 0.5)), Color(0.0, 0.25, 1.0), 0.0, 1.0, "panache"),
			]
		"moteur_levage":
			var dh := dimensions_levage(_f(r, "poussee_kn"))
			return [
				_forme("cylindre", Vector3(dh.x * 0.5, dh.x * 0.5, dh.y), Transform3D.IDENTITY, titane, 0.85, 0.35),
				_forme("cylindre", Vector3(dh.x * 0.44, dh.x * 0.44, 0.03), Transform3D(Basis.IDENTITY, Vector3(0, -dh.y * 0.5 - 0.015, 0)), sombre, 0.6, 0.6),
				_forme("cylindre", Vector3(dh.x * 0.4, dh.x * 0.4, 0.01), Transform3D(Basis.IDENTITY, Vector3(0, -dh.y * 0.5 - 0.035, 0)), Color.BLACK, 0.0, 1.0, "lueur"),
				_forme("panache", Vector3(dh.x * 0.4, dh.x * 0.1, dh.x * 2.0), Transform3D(vers_bas, Vector3(0, -dh.y * 0.5 - 0.03, 0)), Color(0.0, 0.25, 1.0), 0.0, 1.0, "panache"),
			]
		"propulseur":
			var s := sqrt(_f(r, "poussee_kn") / 6.0)
			return [
				_forme("boite", Vector3(0.24, 0.1, 0.24) * s, Transform3D(Basis.IDENTITY, Vector3(0, 0.05 * s, 0)), Color(0.5, 0.51, 0.54), 0.7, 0.45),
				_forme("cylindre", Vector3(0.07, 0.035, 0.14) * s, Transform3D(Basis.IDENTITY, Vector3(0, 0.17 * s, 0)), Color(0.3, 0.3, 0.33), 0.9, 0.3),
				_forme("cylindre", Vector3(0.06 * s, 0.06 * s, 0.005), Transform3D(Basis.IDENTITY, Vector3(0, 0.235 * s, 0)), Color.BLACK, 0.0, 1.0, "lueur"),
				_forme("panache", Vector3(0.06, 0.012, 0.6) * s, Transform3D(Basis.IDENTITY, Vector3(0, 0.24 * s, 0)), Color(0.0, 0.25, 1.0), 0.0, 1.0, "panache"),
			]
		"aile":
			var b := _f(r, "envergure_m")
			var c := _f(r, "corde_m")
			var t := 0.09 * c
			return [
				_forme("boite", Vector3(b, t, c * 0.82), Transform3D(Basis.IDENTITY, Vector3(b * 0.5, 0, c * 0.09)), _couleur("composite_carbone"), 0.1, 0.55),
				# bord d'attaque arrondi, volet du bord de fuite
				_forme("cylindre", Vector3(t * 0.5, t * 0.5, b), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(b * 0.5, 0, -c * 0.41)), _couleur("composite_carbone").lightened(0.08), 0.1, 0.5),
				_forme("boite", Vector3(b * 0.96, t * 0.55, c * 0.16), Transform3D(Basis.IDENTITY, Vector3(b * 0.5, 0, c * 0.42)), Color(0.24, 0.25, 0.28), 0.2, 0.6),
			]
		"poutre":
			var sc := _f(r, "section_m")
			return [_forme("boite", Vector3(sc, sc, _f(r, "longueur_m")), Transform3D.IDENTITY, _couleur(String(r["matiere"])), _metal(String(r["matiere"])), 0.45)]
		"plaque":
			# une plaque en verre est une vitre (transparente ; le jeu en fait une vraie vitre, étape 5)
			var vitre := _forme("boite", Vector3(_f(r, "largeur_m"), _f(r, "epaisseur_m"), _f(r, "longueur_m")), Transform3D.IDENTITY,
				_couleur(String(r["matiere"])), _metal(String(r["matiere"])), 0.5)
			vitre["vitre"] = String(r["matiere"]) == "verre_aluminosilicate"
			return [vitre]
		"boite":
			var t2 := Vector3(_f(r, "largeur_m"), _f(r, "hauteur_m"), _f(r, "longueur_m"))
			return [
				_forme("boite", t2, Transform3D.IDENTITY, Color(0.34, 0.4, 0.48), 0.4, 0.55),
				_forme("boite", Vector3(t2.x + 0.01, 0.02, t2.z + 0.01), Transform3D(Basis.IDENTITY, Vector3(0, t2.y * 0.5 - 0.05, 0)), Color(0.85, 0.62, 0.1), 0.2, 0.6),
			]
		"charniere":
			var lh := _f(r, "longueur_m")
			var dc := dimensions_charniere(lh)
			var acier := _couleur("acier")
			var battant := _forme("boite", Vector3(lh, dc.y, dc.x), Transform3D(Basis.IDENTITY, Vector3(0, dc.z, -dc.x * 0.5)), acier.lightened(0.12), 0.85, 0.4)
			battant["articulation"] = "mouvement"
			return [
				_forme("boite", Vector3(lh, dc.y, dc.x), Transform3D(Basis.IDENTITY, Vector3(0, dc.y * 0.5, dc.x * 0.5)), acier, 0.9, 0.45),
				_forme("cylindre", Vector3(dc.z, dc.z, lh), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, dc.z, 0)), Color(0.85, 0.62, 0.1), 0.6, 0.45),
				battant,
			]
		"verin":
			var dv := _f(r, "diametre_m")
			var lc := longueur_verin(_f(r, "course_m"))
			var tige := _forme("cylindre", Vector3(dv * 0.22, dv * 0.22, lc), Transform3D(Basis.IDENTITY, Vector3(0, lc * 0.5 + 0.04, 0)), Color(0.82, 0.83, 0.85), 0.95, 0.2)
			tige["articulation"] = "tige"
			var plateau := _forme("boite", Vector3(1.6 * dv, 0.02, 1.6 * dv), Transform3D(Basis.IDENTITY, Vector3(0, lc + 0.05, 0)), _couleur("acier"), 0.9, 0.45)
			plateau["articulation"] = "tige"
			return [
				_forme("cylindre", Vector3(dv * 0.5, dv * 0.5, lc), Transform3D(Basis.IDENTITY, Vector3(0, lc * 0.5, 0)), Color(0.85, 0.62, 0.1), 0.5, 0.5),
				tige,
				plateau,
			]
		"aile_repliable":
			var formes := dessin("aile", {"envergure_m": r["envergure_m"], "corde_m": r["corde_m"]})
			for f in formes:
				f["articulation"] = "pli"
			var c4 := _f(r, "corde_m")
			var rf := 0.02 + 0.045 * c4
			formes.append(_forme("cylindre", Vector3(rf, rf, 0.6 * c4), Transform3D(vers_z, Vector3.ZERO), Color(0.85, 0.62, 0.1), 0.6, 0.45))
			return formes
		"jambe_train":
			var hj := _f(r, "hauteur_m")
			var rj := _f(r, "rayon_roue_m")
			var dj := dimensions_jambe(r)
			var sur_x := Basis(Vector3.BACK, PI * 0.5)   # axe Y du cylindre → axe X (essieu)
			var morceaux := [
				_forme("cylindre", Vector3(dj.x * 0.5, dj.x * 0.5, hj - dj.y), Transform3D(Basis.IDENTITY, Vector3(0, -(hj - dj.y) * 0.5, 0)), _couleur("acier"), 0.9, 0.4),
				_forme("cylindre", Vector3(dj.x * 0.32, dj.x * 0.32, dj.y), Transform3D(Basis.IDENTITY, Vector3(0, -hj + dj.y * 0.5, 0)), Color(0.82, 0.83, 0.85), 0.95, 0.2),
				_forme("cylindre", Vector3(rj, rj, rj * 0.6), Transform3D(sur_x, Vector3(0, -hj, 0)), sombre, 0.0, 0.9),   # pneu
				_forme("cylindre", Vector3(rj * 0.55, rj * 0.55, rj * 0.62), Transform3D(sur_x, Vector3(0, -hj, 0)), _couleur("acier"), 0.9, 0.4),
			]
			for f in morceaux:
				f["articulation"] = "pivot"
			morceaux.append(_forme("boite", Vector3(2.2 * dj.x, 0.06, 2.2 * dj.x), Transform3D(Basis.IDENTITY, Vector3(0, -0.03, 0)), Color(0.85, 0.62, 0.1), 0.6, 0.45))
			return morceaux
		"reservoir":
			var dr := dimensions_reservoir(_f(r, "volume_l"))
			var blanc := Color(0.84, 0.84, 0.82) if String(r["contenu"]) == "eau" else Color(0.32, 0.5, 0.72)
			return [
				_forme("gelule", Vector3(dr.x * 0.5, dr.y, 0.0), Transform3D(vers_z, Vector3.ZERO), blanc, 0.3, 0.45),
				_forme("cylindre", Vector3(dr.x * 0.51, dr.x * 0.51, 0.05), Transform3D(vers_z, Vector3(0, 0, -dr.y * 0.22)), sombre, 0.6, 0.5),
				_forme("cylindre", Vector3(dr.x * 0.51, dr.x * 0.51, 0.05), Transform3D(vers_z, Vector3(0, 0, dr.y * 0.22)), sombre, 0.6, 0.5),
			]
	return [_forme("boite", Vector3(0.5, 0.5, 0.5), Transform3D.IDENTITY, Color(0.8, 0.3, 0.8), 0.0, 0.8)]


static func _forme(forme: String, taille: Vector3, xf: Transform3D, couleur: Color, metal: float, rugosite: float, role := "") -> Dictionary:
	return {"forme": forme, "taille": taille, "xf": xf, "couleur": couleur, "metal": metal, "rugosite": rugosite, "role": role, "vitre": false}


static func _couleur(matiere: String) -> Color:
	var c = Catalogue.MATIERES.get(matiere, {}).get("couleur", [0.6, 0.6, 0.6])
	return Color(float(c[0]), float(c[1]), float(c[2]))


static func _metal(matiere: String) -> float:
	return float(Catalogue.MATIERES.get(matiere, {}).get("metal", 0.5))
