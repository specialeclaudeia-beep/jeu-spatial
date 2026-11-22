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

const Catalogue = preload("res://scripts/atelier/catalogue.gd")

## Masse par kilonewton de poussée (moteur ionique) : 200 kN → 900 kg (les moteurs du chasseur pèsent
## 400 à 2 000 kg chacun avec leur carénage). Puissance électrique d'un jet ionique à 3 000 m/s :
## P = poussée × vitesse du jet / 2 (pour information : l'électricité viendra plus tard).
const KG_PAR_KN_IONIQUE := 4.5
const VITESSE_JET := 3000.0
const KG_PAR_KN_PROPULSEUR := 2.0
const KG_PAR_KN_LEVAGE := 3.0
const KG_PAR_M2_AILE := 27.0   # ailes du chasseur : 355 kg pour 13 m²

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
]


static func existe(modele: String) -> bool:
	return MODELES.has(modele)


static func nom(modele: String) -> String:
	return String(MODELES[modele]["nom"]) if MODELES.has(modele) else modele


static func attache(modele: String) -> String:
	return String(MODELES[modele]["attache"]) if MODELES.has(modele) else "garde"


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
	return AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))


## Résumé d'une ligne : « 200 kN · 900 kg ».
static func resume(modele: String, reglages: Dictionary) -> String:
	var r := reglages_complets(modele, reglages)
	var m := masse(modele, r)
	var kg := "%s kg" % _nombre(m, 0 if m >= 10.0 else 1)
	match modele:
		"moteur_ionique", "moteur_levage", "propulseur":
			return "%s kN · %s" % [_nombre(_f(r, "poussee_kn"), 1 if fmod(_f(r, "poussee_kn"), 1.0) != 0.0 else 0), kg]
		"aile":
			return "%s m² · %s" % [_nombre(_f(r, "envergure_m") * _f(r, "corde_m"), 1), kg]
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
