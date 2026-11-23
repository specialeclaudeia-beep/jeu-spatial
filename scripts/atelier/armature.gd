extends RefCounted
## Atelier, étape 6 : l'ARMATURE du vaisseau. On trace des POUTRES de point en point ; à chaque bout, un
## CONNECTEUR se fabrique tout seul (sa forme suit les poutres qui s'y croisent : embout, connecteur
## d'angle, en T, en X, de coin, en étoile). Une zone fermée par 3 ou 4 poutres se REMPLIT d'un PANNEAU
## plat, dans la matière et l'épaisseur choisies : tôle de coque, paroi, vitre, bouclier thermique, ou
## surface d'aile qui porte dans l'air. (Vision Notion 1.1 et 1.2 ; réponse de Gwenaël à la question 16 :
## d'abord des surfaces planes, triangles et quadrilatères.)
##
## Dans le plan du vaisseau (scripts/atelier/plan.gd), chaque élément de l'armature est un « ensemble » de
## premier niveau, comme une pièce toute faite, avec un « modele » :
##   - connecteur : {"id": "connecteur_3", "modele": "connecteur", "position": [x, y, z], "fixe_a": …,
##     "articulation_appui": …} : sa position est LA référence de l'armature (le reste en découle) ;
##     « fixe_a » : la pièce du vaisseau sur laquelle il est posé (vide : il ne tient que par ses poutres) ;
##   - poutre : {"id": "barre_5", "modele": "barre", "noeuds": [connecteur, connecteur], "reglages":
##     {matiere, profil, section_m, paroi_m}} ;
##   - panneau : {"id": "panneau_2", "modele": "panneau", "noeuds": [3 ou 4 connecteurs, dans l'ordre du
##     tour], "reglages": {matiere, epaisseur_m, portant}}.
## refaire() recalcule tout le reste à partir des connecteurs : place et orientation de chaque poutre et de
## chaque panneau, taille et masse des connecteurs, et les pièces pour la physique (« pieces » : poutre en
## tube, panneau, boule, surface d'air). Le jeu ne lit que ces pièces : il n'a pas besoin de ce fichier.
##
## Masses (pas de précision fictive : les formules de la mécanique) :
##   - poutre : tube carré (boîte extérieure moins boîte intérieure), tube rond, ou barre pleine, de la
##     matière choisie, sur sa longueur UTILE (d'un connecteur à l'autre, sans compter deux fois le métal
##     des connecteurs) ;
##   - connecteur : boule creuse (paroi = 2 × celle du tube) ou pleine (barre pleine), de diamètre 1,4 × la
##     plus grosse poutre qui y arrive, dans sa matière (comme les nœuds en boule des charpentes spatiales) ;
##   - panneau : plaque pleine entre ses coins (surface × épaisseur × densité ; inertie d'une plaque mince).
## Pièces mobiles : l'armature suit la pièce sur laquelle elle est posée (posée sur une aile, elle se replie
## avec l'aile). Si elle est posée à la fois sur deux pièces qui bougent l'une par rapport à l'autre, elle
## reste avec le fuselage, et le contrôle avant le vol prévient (elle empêcherait l'aile de bouger).
## Le dessin est PROVISOIRE (formes simples), la physique non. L'air ne voit que les panneaux « portants »
## (surfaces d'aile) ; la traînée d'une coque construite viendra avec l'analyse de l'air.

const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")

const CONNECTEUR := "connecteur"
const POUTRE := "barre"
const PANNEAU := "panneau"
const MODELES_ARMATURE := ["connecteur", "barre", "panneau"]

const SUR_L_AXE := 0.05          # m : un connecteur à moins de 5 cm du milieu est sa propre jumelle
const MEME_POINT := 0.01         # m : deux connecteurs à moins de 1 cm l'un de l'autre sont le même
const LONGUEUR_MIN := 0.05       # m : poutre la plus courte
const LONGUEUR_MAX := 25.0       # m : poutre la plus longue
const DIAMETRE_CONNECTEUR := 1.4 # × la section de la plus grosse poutre
const A_PLAT := 0.01             # quadrilatère : à plat si ses coins sont à moins de 1 % de sa taille du plan

const PROFILS := ["tube_carre", "tube_rond", "plein_carre"]
const MATIERES_POUTRE := ["aluminium_lithium", "aluminium", "titane", "acier", "composite_carbone"]
const MATIERES_PANNEAU := ["aluminium_lithium", "aluminium", "titane", "acier", "composite_carbone",
	"verre_aluminosilicate", "ceramique"]
## Noms affichés des choix des réglages (les matières ont leur nom dans le catalogue).
const NOMS_CHOIX := {"tube_carre": "tube carré", "tube_rond": "tube rond", "plein_carre": "barre pleine carrée",
	"non": "non (coque, paroi, vitre)", "oui": "oui (surface d'aile)"}

## Réglages (même forme que les pièces toutes faites).
const MODELES := {
	"barre": {"nom": "Poutre",
		"description": "Poutre de l'armature, tracée d'un connecteur à l'autre. Tube carré, tube rond ou barre pleine : sa masse est celle du métal de sa section sur sa longueur utile.",
		"reglages": [
			{"cle": "matiere", "nom": "Matière", "choix": MATIERES_POUTRE, "defaut": "aluminium_lithium"},
			{"cle": "profil", "nom": "Profil", "choix": PROFILS, "defaut": "tube_carre"},
			{"cle": "section_m", "nom": "Section", "unite": "m", "min": 0.02, "max": 0.5, "pas": 0.005, "defaut": 0.08, "decimales": 3},
			{"cle": "paroi_m", "nom": "Paroi du tube", "unite": "m", "min": 0.0005, "max": 0.05, "pas": 0.0005, "defaut": 0.003, "decimales": 4}]},
	"panneau": {"nom": "Panneau",
		"description": "Surface plane qui remplit une zone fermée par 3 ou 4 poutres : tôle de coque, paroi, vitre (en verre), bouclier thermique (céramique) ou surface d'aile (« porte dans l'air »).",
		"reglages": [
			{"cle": "matiere", "nom": "Matière", "choix": MATIERES_PANNEAU, "defaut": "aluminium_lithium"},
			{"cle": "epaisseur_m", "nom": "Épaisseur", "unite": "m", "min": 0.0005, "max": 0.2, "pas": 0.0005, "defaut": 0.002, "decimales": 4},
			{"cle": "portant", "nom": "Porte dans l'air", "choix": ["non", "oui"], "defaut": "non"}]},
	"connecteur": {"nom": "Connecteur",
		"description": "Connecteur de l'armature : il se fabrique tout seul au bout des poutres. Sa forme suit les poutres qui s'y croisent (embout, angle, T, X, coin, étoile) ; c'est une boule creuse de 1,4 fois la plus grosse poutre, dans sa matière.",
		"reglages": []},
}

## Ce que propose le catalogue de l'atelier : [catégorie, nom, modèle, réglages].
const PROPOSITIONS := [
	["Armature : tracer des poutres", "Tube carré d'aluminium-lithium (8 cm)", "barre", {}],
	["Armature : tracer des poutres", "Tube rond de titane (6 cm)", "barre", {"matiere": "titane", "profil": "tube_rond", "section_m": 0.06, "paroi_m": 0.002}],
	["Armature : tracer des poutres", "Tube carré de carbone (10 cm)", "barre", {"matiere": "composite_carbone", "section_m": 0.1, "paroi_m": 0.004}],
	["Armature : tracer des poutres", "Barre pleine d'acier (5 cm)", "barre", {"matiere": "acier", "profil": "plein_carre", "section_m": 0.05}],
	["Armature : remplir une zone", "Tôle d'aluminium-lithium (2 mm)", "panneau", {}],
	["Armature : remplir une zone", "Panneau de carbone (3 mm)", "panneau", {"matiere": "composite_carbone", "epaisseur_m": 0.003}],
	["Armature : remplir une zone", "Vitre (verre feuilleté, 12 mm)", "panneau", {"matiere": "verre_aluminosilicate", "epaisseur_m": 0.012}],
	["Armature : remplir une zone", "Bouclier thermique (céramique, 5 cm)", "panneau", {"matiere": "ceramique", "epaisseur_m": 0.05}],
	["Armature : remplir une zone", "Surface d'aile en carbone (porte dans l'air)", "panneau", {"matiere": "composite_carbone", "epaisseur_m": 0.004, "portant": "oui"}],
]


static func est_modele(modele: String) -> bool:
	return MODELES_ARMATURE.has(modele)


## Vrai si cet élément du plan fait partie de l'armature.
static func est(e) -> bool:
	return e is Dictionary and e.has("modele") and MODELES_ARMATURE.has(String(e["modele"]))


static func nom_modele(modele: String) -> String:
	return String(MODELES[modele]["nom"]) if MODELES.has(modele) else modele


static func definition_reglage(modele: String, cle: String) -> Dictionary:
	for r in MODELES.get(modele, {}).get("reglages", []):
		if r["cle"] == cle:
			return r
	return {}


## Réglages complets (valeurs par défaut, bornes, choix permis).
static func reglages_complets(modele: String, r := {}) -> Dictionary:
	var sortie := {}
	for d in MODELES.get(modele, {}).get("reglages", []):
		var cle: String = d["cle"]
		var v = r.get(cle, d["defaut"])
		if d.has("choix"):
			sortie[cle] = String(v) if (d["choix"] as Array).has(String(v)) else String(d["defaut"])
		else:
			sortie[cle] = clampf(float(v), float(d["min"]), float(d["max"]))
	return sortie


static func a_armature(donnees: Dictionary) -> bool:
	for e in donnees.get("pieces", []):
		if est(e):
			return true
	return false


static func position(e: Dictionary) -> Vector3:
	return Catalogue.vecteur(e.get("position", [0.0, 0.0, 0.0]))


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


## Clé d'un ensemble de connecteurs (le même panneau, quel que soit l'ordre de ses coins).
static func cle(ids: Array) -> String:
	var s := []
	for i in ids:
		s.append(String(i))
	s.sort()
	return "|".join(s)


# =====================================================================
# LE GRAPHE : connecteurs reliés par des poutres
# =====================================================================
## {"connecteurs": {id: e}, "poutres": {id: e}, "panneaux": {id: e}, "voisins": {connecteur: [[autre,
## poutre]…]}, "entre": {cle(a, b): poutre}, "remplis": {cle(coins): panneau}}.
static func graphe(donnees: Dictionary) -> Dictionary:
	var g := {"connecteurs": {}, "poutres": {}, "panneaux": {}, "voisins": {}, "entre": {}, "remplis": {}}
	for e in donnees.get("pieces", []):
		if not est(e):
			continue
		var id := String(e["id"])
		match String(e["modele"]):
			CONNECTEUR:
				g["connecteurs"][id] = e
				g["voisins"][id] = []
			POUTRE:
				g["poutres"][id] = e
			PANNEAU:
				g["panneaux"][id] = e
	for id in g["poutres"]:
		var n: Array = g["poutres"][id].get("noeuds", [])
		if n.size() != 2 or not g["connecteurs"].has(String(n[0])) or not g["connecteurs"].has(String(n[1])):
			continue
		var a := String(n[0])
		var b := String(n[1])
		(g["voisins"][a] as Array).append([b, id])
		(g["voisins"][b] as Array).append([a, id])
		g["entre"][cle([a, b])] = id
	for id in g["panneaux"]:
		g["remplis"][cle(g["panneaux"][id].get("noeuds", []))] = id
	return g


## La poutre entre deux connecteurs ("" : aucune).
static func poutre_entre(g: Dictionary, a: String, b: String) -> String:
	return String(g["entre"].get(cle([a, b]), ""))


## Les poutres qui arrivent à un connecteur.
static func poutres_de(g: Dictionary, id: String) -> Array:
	return (g["voisins"].get(id, []) as Array).map(func(x): return String(x[1]))


## Forme d'un connecteur, d'après les poutres qui s'y croisent : {"nom", "branches"}.
static func genre_connecteur(g: Dictionary, id: String) -> Dictionary:
	var e: Dictionary = g["connecteurs"].get(id, {})
	if e.is_empty():
		return {"nom": "connecteur", "branches": 0}
	var p := position(e)
	var dirs := []
	for x in g["voisins"].get(id, []):
		var q := position(g["connecteurs"][String(x[0])])
		if (q - p).length() > 1e-6:
			dirs.append((q - p).normalized())
	var n := dirs.size()
	var opposes := 0
	var utilises := {}
	for i in n:
		for j in range(i + 1, n):
			if not utilises.has(i) and not utilises.has(j) and (dirs[i] as Vector3).dot(dirs[j]) < -0.985:
				opposes += 1
				utilises[i] = true
				utilises[j] = true
	var nom := ""
	match n:
		0:
			nom = "connecteur seul"
		1:
			nom = "embout"
		2:
			var angle := rad_to_deg(acos(clampf((dirs[0] as Vector3).dot(dirs[1]), -1.0, 1.0)))
			nom = "manchon (raccord droit)" if opposes == 1 else "connecteur d'angle (%d°)" % roundi(angle)
		3:
			if opposes == 1:
				nom = "connecteur en T"
			else:
				var plat := absf((dirs[0] as Vector3).cross(dirs[1]).normalized().dot(dirs[2])) < 0.1
				nom = "connecteur à 3 branches à plat" if plat else "connecteur de coin (3 branches)"
		4:
			nom = "connecteur en X (croix)" if opposes == 2 else "connecteur à 4 branches"
		_:
			nom = "connecteur en étoile (%d branches)" % n
	return {"nom": nom, "branches": n}


## Les morceaux d'armature qui tiennent ensemble (reliés par des poutres) : [{connecteurs, poutres,
## panneaux, appuis: [connecteurs posés sur le vaisseau], articulations: {articulation: vrai}}].
static func morceaux(g: Dictionary) -> Array:
	var vus := {}
	var sortie := []
	for depart in g["connecteurs"]:
		if vus.has(depart):
			continue
		var m := {"connecteurs": [], "poutres": [], "panneaux": [], "appuis": [], "articulations": {}}
		var pile := [depart]
		vus[depart] = true
		var poutres := {}
		while not pile.is_empty():
			var id := String(pile.pop_back())
			(m["connecteurs"] as Array).append(id)
			var e: Dictionary = g["connecteurs"][id]
			if String(e.get("fixe_a", "")) != "":
				(m["appuis"] as Array).append(id)
				m["articulations"][String(e.get("articulation_appui", ""))] = true
			for x in g["voisins"][id]:
				poutres[String(x[1])] = true
				if not vus.has(String(x[0])):
					vus[String(x[0])] = true
					pile.append(String(x[0]))
		m["poutres"] = poutres.keys()
		sortie.append(m)
	var de := {}
	for k in sortie.size():
		for c in sortie[k]["connecteurs"]:
			de[c] = k
	for id in g["panneaux"]:
		var n: Array = g["panneaux"][id].get("noeuds", [])
		if not n.is_empty() and de.has(String(n[0])):
			(sortie[de[String(n[0])]]["panneaux"] as Array).append(id)
	return sortie


# =====================================================================
# LES ZONES À REMPLIR
# =====================================================================
## Les zones fermées de l'armature : triangles de poutres, et quadrilatères de poutres sans diagonale (une
## diagonale en fait deux triangles). [{"noeuds": [ids dans l'ordre du tour], "cle", "a_plat": bool,
## "rempli": id du panneau ("" : libre)}].
static func zones(donnees: Dictionary, g := {}) -> Array:
	if g.is_empty():
		g = graphe(donnees)
	var adj := {}
	for id in g["connecteurs"]:
		adj[id] = {}
		for x in g["voisins"][id]:
			adj[id][String(x[0])] = true
	var ids: Array = g["connecteurs"].keys()
	ids.sort()
	var sortie := []
	# triangles a < b < c
	for a in ids:
		for b in adj[a]:
			if String(b) <= String(a):
				continue
			for c in adj[b]:
				if String(c) <= String(b) or not adj[a].has(c):
					continue
				_ajouter_zone(sortie, g, [a, b, c], true)
	# quadrilatères a-b-c-d (a : le plus petit des quatre ; diagonales a-c et b-d sans poutre)
	for a in ids:
		var deux := {}
		for b in adj[a]:
			for c in adj[b]:
				if String(c) == String(a) or adj[a].has(c) or String(c) <= String(a):
					continue
				if not deux.has(c):
					deux[c] = []
				(deux[c] as Array).append(b)
		for c in deux:
			var communs: Array = deux[c]
			for i in communs.size():
				for j in range(i + 1, communs.size()):
					var b := String(communs[i])
					var d := String(communs[j])
					if b <= String(a) or d <= String(a) or adj[b].has(d):
						continue
					var q := _quadrilatere(g, [a, b, c, d])
					if not q.is_empty():
						_ajouter_zone(sortie, g, [a, b, c, d], bool(q["a_plat"]))
	return sortie


static func _ajouter_zone(sortie: Array, g: Dictionary, n: Array, a_plat: bool) -> void:
	var pts := n.map(func(i): return position(g["connecteurs"][String(i)]))
	if normale(pts).length() < 1e-6:
		return   # coins alignés
	var k := cle(n)
	sortie.append({"noeuds": n.map(func(i): return String(i)), "cle": k, "a_plat": a_plat,
		"rempli": String(g["remplis"].get(k, ""))})


## Un quadrilatère est une vraie zone s'il ne se croise pas lui-même (ses deux moitiés regardent du même
## côté). {"a_plat": bool}, ou vide s'il se croise.
static func _quadrilatere(g: Dictionary, n: Array) -> Dictionary:
	var p := n.map(func(i): return position(g["connecteurs"][String(i)]))
	var n1 := ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3))
	var n2 := ((p[2] as Vector3) - (p[0] as Vector3)).cross((p[3] as Vector3) - (p[0] as Vector3))
	var n3 := ((p[2] as Vector3) - (p[1] as Vector3)).cross((p[3] as Vector3) - (p[1] as Vector3))
	var n4 := ((p[3] as Vector3) - (p[1] as Vector3)).cross((p[0] as Vector3) - (p[1] as Vector3))
	if n1.length() < 1e-9 or n2.length() < 1e-9 or n1.normalized().dot(n2.normalized()) < 0.2 \
			or n3.length() < 1e-9 or n4.length() < 1e-9 or n3.normalized().dot(n4.normalized()) < 0.2:
		return {}
	var nn := normale(p).normalized()
	var c := ((p[0] as Vector3) + (p[1] as Vector3) + (p[2] as Vector3) + (p[3] as Vector3)) * 0.25
	var taille := 0.0
	var ecart := 0.0
	for q in p:
		taille = maxf(taille, ((q as Vector3) - c).length())
		ecart = maxf(ecart, absf(((q as Vector3) - c).dot(nn)))
	return {"a_plat": ecart <= A_PLAT * taille + 0.002}


## Normale (non normalisée, longueur = 2 × surface pour un polygone plan) d'un tour de points (Newell).
static func normale(pts: Array) -> Vector3:
	var n := Vector3.ZERO
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	return n


# =====================================================================
# TOUT REFAIRE À PARTIR DES CONNECTEURS
# =====================================================================
## Recalcule toute l'armature du plan (en place) : enlève ce qui ne tient plus (poutre ou panneau dont un
## connecteur a disparu, connecteur qui n'a plus de poutre), puis la taille et la masse des connecteurs, la
## place des poutres et des panneaux, les pièces mobiles suivies, et les pièces pour la physique.
static func refaire(donnees: Dictionary) -> void:
	var liste: Array = donnees.get("pieces", [])
	# 1. ce qui ne tient plus
	var encore := true
	while encore:
		encore = false
		var g := graphe(donnees)
		var a_enlever := {}
		var vues := {}
		for id in g["poutres"]:
			var n: Array = g["poutres"][id].get("noeuds", [])
			var k := cle(n)
			if n.size() != 2 or String(n[0]) == String(n[1]) or not g["connecteurs"].has(String(n[0])) \
					or not g["connecteurs"].has(String(n[1])) or vues.has(k):
				a_enlever[id] = true
			vues[k] = true
		var vus_p := {}
		for id in g["panneaux"]:
			var n: Array = g["panneaux"][id].get("noeuds", [])
			var k := cle(n)
			if not (n.size() in [3, 4]) or vus_p.has(k) or n.any(func(i): return not g["connecteurs"].has(String(i))):
				a_enlever[id] = true
			vus_p[k] = true
		var dans_panneau := {}
		for id in g["panneaux"]:
			if not a_enlever.has(id):
				for i in g["panneaux"][id].get("noeuds", []):
					dans_panneau[String(i)] = true
		for id in g["connecteurs"]:
			var garde := false
			for x in g["voisins"][id]:
				if not a_enlever.has(String(x[1])):
					garde = true
			if not garde and not dans_panneau.has(id):
				a_enlever[id] = true
		if not a_enlever.is_empty():
			encore = true
			liste = liste.filter(func(e): return not (e is Dictionary and a_enlever.has(String(e.get("id", "")))))
			donnees["pieces"] = liste
	var gr := graphe(donnees)
	# une jumelle disparue : plus de lien
	for e in liste:
		if est(e) and e.has("symetrique") and not _existe(liste, String(e["symetrique"])):
			e.erase("symetrique")
	# 2. connecteurs : la plus grosse poutre qui y arrive donne leur taille et leur matière
	var taille := {}
	for id in gr["connecteurs"]:
		var s := 0.0
		var r := reglages_complets(POUTRE, {})
		for pid in poutres_de(gr, id):
			var rp := reglages_complets(POUTRE, gr["poutres"][pid].get("reglages", {}))
			if float(rp["section_m"]) > s:
				s = float(rp["section_m"])
				r = rp
		if s <= 0.0:
			s = float(r["section_m"])
		var d := snappedf(maxf(DIAMETRE_CONNECTEUR * s, 0.03), 0.005)
		var paroi := 0.0 if String(r["profil"]) == "plein_carre" else minf(2.0 * float(r["paroi_m"]), d * 0.5)
		taille[id] = {"d": d, "paroi": paroi, "matiere": String(r["matiere"])}
	# 3. pièces mobiles : chaque morceau suit la pièce mobile de ses appuis (s'ils sont d'accord)
	var art_de := {}
	for m in morceaux(gr):
		var arts: Array = (m["articulations"] as Dictionary).keys()
		var art := String(arts[0]) if arts.size() == 1 else ""
		for c in m["connecteurs"]:
			art_de[c] = art
	# 4. place, orientation et pièces de chaque élément
	for e in liste:
		if not est(e):
			continue
		var id := String(e["id"])
		var art := ""
		match String(e["modele"]):
			CONNECTEUR:
				art = String(art_de.get(id, ""))
				_refaire_connecteur(e, taille[id])
			POUTRE:
				var n: Array = e["noeuds"]
				art = String(art_de.get(String(n[0]), ""))
				_refaire_poutre(e, gr["connecteurs"][String(n[0])], gr["connecteurs"][String(n[1])], taille[String(n[0])], taille[String(n[1])])
			PANNEAU:
				var n2: Array = e["noeuds"]
				art = String(art_de.get(String(n2[0]), ""))
				var pts := n2.map(func(i): return position(gr["connecteurs"][String(i)]))
				_refaire_panneau(e, pts)
		if art != "":
			e["articulation"] = art
		else:
			e.erase("articulation")


static func _existe(liste: Array, id: String) -> bool:
	for e in liste:
		if e is Dictionary and String(e.get("id", "")) == id:
			return true
	return false


static func _refaire_connecteur(e: Dictionary, t: Dictionary) -> void:
	var d := float(t["d"])
	var paroi := float(t["paroi"])
	var dens := float(Catalogue.MATIERES[String(t["matiere"])]["densite"])
	var rr := d * 0.5
	var ri := maxf(rr - paroi, 0.0) if paroi > 0.0 else 0.0
	var m := dens * 4.0 / 3.0 * PI * (rr * rr * rr - ri * ri * ri)
	e["reglages"] = {}
	e["rotation_deg"] = [0.0, 0.0, 0.0]
	e.erase("miroir_x")
	var dims := [snappedf(d, 0.0001)]
	if paroi > 0.0:
		dims.append(snappedf(paroi, 0.00001))
	e["pieces"] = [{"id": "connecteur", "type": "bloc", "forme": "boule", "dimensions_m": dims, "position": [0.0, 0.0, 0.0],
		"masse_kg": snappedf(m, 0.0001), "matiere": String(t["matiere"])}]


## Base dont l'axe Z va dans la direction z ; X reste à l'horizontale (une face du tube regarde vers le haut).
static func base_z(z: Vector3) -> Basis:
	var zz := z.normalized()
	var x := Vector3.UP.cross(zz)
	if x.length() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, zz.cross(x).normalized(), zz)


static func _refaire_poutre(e: Dictionary, a: Dictionary, b: Dictionary, ta: Dictionary, tb: Dictionary) -> void:
	var r := reglages_complets(POUTRE, e.get("reglages", {}))
	e["reglages"] = r
	var pa := position(a)
	var pb := position(b)
	var l := (pb - pa).length()
	var base := base_z(pb - pa if l > 1e-6 else Vector3.BACK)
	_ecrire_xf(e, Transform3D(base, (pa + pb) * 0.5))
	e["longueur_m"] = snappedf(l, 0.0001)
	var ra := float(ta["d"]) * 0.5
	var rb := float(tb["d"]) * 0.5
	var utile := maxf(l - ra - rb, 0.002)
	var s := float(r["section_m"])
	var morceau := {"id": "poutre", "type": "poutre", "matiere": String(r["matiere"]),
		"position": [0.0, 0.0, snappedf((ra - rb) * 0.5, 0.0001)], "longueur_m": snappedf(utile, 0.0001),
		"largeur_m": s, "hauteur_m": s}
	match String(r["profil"]):
		"tube_rond":
			morceau["profil"] = "rond"
			morceau["paroi_m"] = minf(float(r["paroi_m"]), s * 0.5)
		"tube_carre":
			morceau["paroi_m"] = minf(float(r["paroi_m"]), s * 0.5)
	e["pieces"] = [morceau]


static func _refaire_panneau(e: Dictionary, pts: Array) -> void:
	var r := reglages_complets(PANNEAU, e.get("reglages", {}))
	e["reglages"] = r
	var n := normale(pts)
	var y := n.normalized() if n.length() > 1e-9 else Vector3.UP
	var x := ((pts[1] as Vector3) - (pts[0] as Vector3))
	x = (x - y * x.dot(y))
	x = x.normalized() if x.length() > 1e-9 else (Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.BACK)
	var base := Basis(x, y, x.cross(y))
	var o := Vector3.ZERO
	for p in pts:
		o += p
	o /= float(pts.size())
	var locaux := pts.map(func(p): return base.transposed() * ((p as Vector3) - o))
	var bb := AABB(locaux[0], Vector3.ZERO)
	for q in locaux:
		bb = bb.expand(q)
	var c := bb.get_center()
	o += base * c
	locaux = locaux.map(func(q): return (q as Vector3) - c)
	_ecrire_xf(e, Transform3D(base, o))
	var t := float(r["epaisseur_m"])
	var surface := Catalogue.surface_panneau(locaux)
	e["surface_m2"] = snappedf(surface, 0.0001)
	var morceaux_p := [{"id": "panneau", "type": "panneau", "matiere": String(r["matiere"]),
		"sommets": locaux.map(func(q): return _arr(q)), "epaisseur_m": t}]
	if String(r["portant"]) == "oui" and surface > 1e-4:
		# surface d'aile : plaque mince qui porte, comme une aile toute faite (point au quart de la corde)
		var bt: Basis = Catalogue.rotation(e["rotation_deg"])
		var avant := bt.transposed() * Vector3.FORWARD
		avant.y = 0.0
		avant = avant.normalized() if avant.length() > 0.2 else Vector3.FORWARD
		var cote := Vector3.UP.cross(avant).normalized()
		var mn := INF
		var mx := -INF
		var sn := INF
		var sx := -INF
		for q in locaux:
			mn = minf(mn, (q as Vector3).dot(avant))
			mx = maxf(mx, (q as Vector3).dot(avant))
			sn = minf(sn, (q as Vector3).dot(cote))
			sx = maxf(sx, (q as Vector3).dot(cote))
		var envergure := maxf(sx - sn, 0.01)
		var corde := surface / envergure
		var g: Vector3 = Catalogue.masse_panneau(1.0, locaux, t)["centre"]
		morceaux_p.append({"id": "air", "type": "surface_air", "point": _arr(g + avant * corde * 0.25), "normale": [0.0, 1.0, 0.0],
			"surface_m2": snappedf(surface, 0.0001), "allongement": snappedf(clampf(envergure * envergure / surface, 0.1, 30.0), 0.001),
			"corde_m": snappedf(corde, 0.0001), "groupe": String(e["id"])})
	e["pieces"] = morceaux_p


## Place et orientation (sans miroir : chaque élément de l'armature a la sienne, calculée de ses coins).
static func _ecrire_xf(e: Dictionary, xf: Transform3D) -> void:
	var eu := xf.basis.orthonormalized().get_euler()
	e["position"] = _arr(xf.origin)
	var rot := [snappedf(rad_to_deg(eu.x), 0.0001), snappedf(rad_to_deg(eu.y), 0.0001), snappedf(rad_to_deg(eu.z), 0.0001)]
	for i in 3:
		if absf(float(rot[i])) < 0.00005:
			rot[i] = 0.0
	e["rotation_deg"] = rot
	e.erase("miroir_x")


# =====================================================================
# CHIFFRES, DESSIN, BOÎTE
# =====================================================================
static func masse(e: Dictionary) -> float:
	var m := 0.0
	for p in e.get("pieces", []):
		m += float(Catalogue.masse_piece(p)["masse"])
	return m


## Masse par mètre d'une poutre, ou par m² d'un panneau, avec ces réglages : [kg, "kg/m" ou "kg/m²"].
static func masse_unite(modele: String, r := {}) -> Array:
	var rr := reglages_complets(modele, r)
	if modele == PANNEAU:
		return [float(Catalogue.MATIERES[String(rr["matiere"])]["densite"]) * float(rr["epaisseur_m"]), "kg/m²"]
	if modele == POUTRE:
		var e := {"modele": POUTRE, "reglages": rr}
		_refaire_poutre(e, {"position": [0.0, 0.0, 0.0]}, {"position": [0.0, 0.0, -1.0]}, {"d": 0.0}, {"d": 0.0})
		return [masse(e), "kg/m"]
	return [0.0, "kg"]


static func _nombre(x: float, decimales := 0) -> String:
	return (("%." + str(decimales) + "f") % x).replace(".", ",")


static func _taille_txt(x: float) -> String:
	if x < 0.01:
		return "%s mm" % _nombre(x * 1000.0, 1 if fmod(x * 10000.0 + 0.001, 10.0) > 0.01 else 0)
	if x < 1.0:
		return "%s cm" % _nombre(x * 100.0, 1 if fmod(x * 1000.0, 10.0) > 0.01 else 0)
	return "%s m" % _nombre(x, 2)


static func nom_matiere(m: String) -> String:
	return String(Catalogue.MATIERES.get(m, {}).get("nom", m))


## Les réglages en clair : « tube carré de 8 cm en titane (paroi 3 mm), 2,0 kg/m ».
static func texte_reglages(modele: String, reglages := {}) -> String:
	var r := reglages_complets(modele, reglages)
	var mu := masse_unite(modele, r)
	if modele == PANNEAU:
		return "%s de %s, %s %s%s" % [nom_matiere(String(r["matiere"])), _taille_txt(float(r["epaisseur_m"])), _nombre(float(mu[0]), 1),
			mu[1], ", porte dans l'air" if String(r["portant"]) == "oui" else ""]
	return "%s de %s en %s%s, %s %s" % [String(NOMS_CHOIX[String(r["profil"])]), _taille_txt(float(r["section_m"])),
		nom_matiere(String(r["matiere"])), " (paroi %s)" % _taille_txt(float(r["paroi_m"])) if String(r["profil"]) != "plein_carre" else "",
		_nombre(float(mu[0]), 1), mu[1]]


## Résumé d'une ligne : « 2,40 m · tube carré 8 cm · 5,7 kg ».
static func resume(e: Dictionary) -> String:
	var r: Dictionary = e.get("reglages", {})
	var kg := "%s kg" % _nombre(masse(e), 1)
	match String(e.get("modele", "")):
		POUTRE:
			r = reglages_complets(POUTRE, r)
			return "%s · %s %s · %s" % [_taille_txt(float(e.get("longueur_m", 0.0))), String(NOMS_CHOIX[String(r["profil"])]),
				_taille_txt(float(r["section_m"])), kg]
		PANNEAU:
			r = reglages_complets(PANNEAU, r)
			return "%s m² · %s %s · %s" % [_nombre(float(e.get("surface_m2", 0.0)), 2), nom_matiere(String(r["matiere"])),
				_taille_txt(float(r["epaisseur_m"])), kg]
		CONNECTEUR:
			var p: Array = e.get("pieces", [])
			var d := float(p[0]["dimensions_m"][0]) if not p.is_empty() else 0.0
			return "boule de %s · %s" % [_taille_txt(d), kg]
	return kg


## Les formes simples du dessin (repère de l'élément), comme Pieces.dessin(). Un panneau est une forme
## « panneau » (ses coins « sommets » et son « epaisseur ») ; un panneau en verre est une vitre.
static func dessin(e: Dictionary) -> Array:
	var p: Array = e.get("pieces", [])
	if p.is_empty():
		return []
	var q: Dictionary = p[0]
	var mat := String(q.get("matiere", "aluminium_lithium"))
	var couleur := Pieces._couleur(mat)
	var metal := Pieces._metal(mat)
	match String(e.get("modele", "")):
		CONNECTEUR:
			var d := float(q["dimensions_m"][0])
			return [Pieces._forme("boule", Vector3(d, d, d) * 0.5, Transform3D.IDENTITY, couleur.darkened(0.12), metal, 0.4)]
		POUTRE:
			var s := float(q["largeur_m"])
			var l := float(q["longueur_m"])
			var o := Catalogue.vecteur(q["position"])
			if String(q.get("profil", "")) == "rond":
				return [Pieces._forme("cylindre", Vector3(s * 0.5, s * 0.5, l), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), o), couleur, metal, 0.42)]
			return [Pieces._forme("boite", Vector3(s, s, l), Transform3D(Basis.IDENTITY, o), couleur, metal, 0.42)]
		PANNEAU:
			var sommets := (q["sommets"] as Array).map(func(x): return Catalogue.vecteur(x))
			var t := float(q["epaisseur_m"])
			var bb := _boite_points(sommets)
			var f := Pieces._forme("panneau", bb.size + Vector3(0.0, t, 0.0), Transform3D.IDENTITY, couleur, metal, 0.5)
			f["sommets"] = sommets
			f["epaisseur"] = t
			f["vitre"] = mat == "verre_aluminosilicate"
			return [f]
	return []


static func _boite_points(pts: Array) -> AABB:
	var b := AABB(pts[0], Vector3.ZERO)
	for q in pts:
		b = b.expand(q)
	return b


## Boîte (repère de l'élément) qui contient son dessin.
static func boite(e: Dictionary) -> AABB:
	var b := AABB()
	var premier := true
	for f in dessin(e):
		var fb: AABB
		var t: Vector3 = f["taille"]
		match String(f["forme"]):
			"cylindre":
				fb = AABB(Vector3(-t.x, -t.z * 0.5, -t.x), Vector3(2.0 * t.x, t.z, 2.0 * t.x))
			"boule":
				fb = AABB(-t, 2.0 * t)
			_:
				fb = AABB(-t * 0.5, t)
		fb = (f["xf"] as Transform3D) * fb
		b = fb if premier else b.merge(fb)
		premier = false
	return b
