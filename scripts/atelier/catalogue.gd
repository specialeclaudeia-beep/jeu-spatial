extends RefCounted
## Catalogue de l'atelier : les MATIÈRES et les TYPES DE PIÈCES qu'un plan de vaisseau peut contenir
## (scripts/atelier/plan.gd). Le jeu et l'atelier lisent ce même catalogue : une pièce pèse et agit pareil
## dans les deux.
##
## Chaque pièce d'un plan a un type. Le type dit quels réglages la pièce doit avoir et ce qu'elle fait :
##   - les pièces qui PÈSENT : structure (forme venue de Blender, inertie déjà calculée), masse (masse
##     ponctuelle : avionique, pilote…), poutre et plaque (formes simples : masse et inertie calculées ici
##     à partir de la matière et des dimensions) ;
##   - les pièces qui AGISSENT : moteur, propulseur, roue, contact_coque (point de la coque qui peut toucher
##     le sol), surface_air (plaque qui porte dans l'air) ;
##   - ensemble : un petit plan dans le plan (une aile avec ses moteurs, par exemple), qu'on peut déplacer,
##     tourner, retourner en miroir, et sauvegarder seul pour le réutiliser. Une PIÈCE TOUTE FAITE posée
##     dans l'atelier (étape 3 : moteur, propulseur, boîte, poutre…) est un ensemble avec un « modele »
##     (scripts/atelier/pieces_toutes_faites.gd) et ses « reglages » ; ses pièces sont fabriquées à partir
##     d'eux ;
##   - bloc : masse donnée, de forme simple (boîte ou cylindre) dont on calcule l'inertie (le corps d'un
##     moteur, une boîte d'équipement…).
## Toute pièce peut aussi avoir un « module » : le morceau du vaisseau dont elle fait partie (une aile avec
## son réacteur et ses plaques d'air…), qu'on choisit ou qu'on enlève d'un seul coup dans l'atelier.
## Toute pièce peut aussi avoir une masse (masse_kg + centre) : un moteur du futur atelier pèsera lui-même.
## Dans le plan du chasseur v27, les masses viennent des pièces de Blender, et les moteurs, propulseurs,
## roues et surfaces d'air n'ajoutent rien (leur masse est déjà comptée dans les pièces de Blender).

## Matières : une seule liste pour la masse (densité) et pour le son (comportement de la matière qui craque
## ou qui sonne, scripts/son/pieces_sonores.gd). Densités : valeurs habituelles des fiches techniques.
const MATIERES := {
	"aluminium_lithium": {"nom": "alliage aluminium-lithium", "densite": 2590.0, "son": "aluminium",
		"usage": "coque, trappes", "couleur": [0.72, 0.74, 0.77], "metal": 0.75},
	"aluminium": {"nom": "aluminium", "densite": 2700.0, "son": "aluminium", "usage": "habillage du cockpit", "couleur": [0.8, 0.81, 0.83], "metal": 0.8},
	"titane": {"nom": "titane (Ti-6Al-4V)", "densite": 4430.0, "son": "titane",
		"usage": "tuyères, moteurs, carters chauds", "couleur": [0.56, 0.57, 0.6], "metal": 0.85},
	"acier": {"nom": "acier haute résistance", "densite": 7850.0, "son": "acier", "usage": "trains d'atterrissage", "couleur": [0.44, 0.45, 0.47], "metal": 0.9},
	"composite_carbone": {"nom": "composite fibre de carbone", "densite": 1600.0, "son": "composite", "usage": "ailes", "couleur": [0.17, 0.18, 0.2], "metal": 0.1},
	"verre_aluminosilicate": {"nom": "verre aluminosilicate feuilleté", "densite": 2460.0, "son": "verre",
		"usage": "verrière, vitres", "couleur": [0.45, 0.6, 0.7], "metal": 0.0},
	"ceramique": {"nom": "céramique de bouclier thermique (tuiles de silice)", "densite": 144.0, "son": "verre",
		"usage": "bouclier thermique", "couleur": [0.9, 0.89, 0.86], "metal": 0.0},
}

## Types de pièces. « champs » : réglages obligatoires ; « facultatifs » : réglages possibles (toute pièce
## peut aussi avoir un « nom » lisible et une « note »).
## Toutes les positions sont en mètres dans le repère du vaisseau (−Z = avant, +Y = haut, +X = droite),
## dans la POSE DE RÉFÉRENCE du plan (pour le chasseur : ailes ouvertes, train rentré, tuyère droite).
## Les directions sont des vecteurs (normalisés au chargement).
const TYPES := {
	"structure": {"nom": "pièce de structure", "pese": true,
		"description": "Pièce modélisée (dans Blender) : sa masse, son centre et son inertie propre sont donnés.",
		"champs": ["masse_kg", "centre", "inertie_propre"], "facultatifs": ["matiere", "surface_m2", "articulation", "note"]},
	"bloc": {"nom": "bloc", "pese": true,
		"description": "Masse donnée, de forme simple (boîte, cylindre le long de son axe Z local, ou boule) : son inertie est calculée.",
		"champs": ["masse_kg", "position", "forme", "dimensions_m"],
		"facultatifs": ["rotation_deg", "matiere", "articulation", "note"]},
	"masse": {"nom": "masse ponctuelle", "pese": true,
		"description": "Équipement compté comme une masse en un point (ordinateurs, pilote, réservoir d'air…).",
		"champs": ["masse_kg", "centre"], "facultatifs": ["articulation", "note"]},
	"poutre": {"nom": "poutre", "pese": true,
		"description": "Barre de section rectangulaire (pleine, ou tube si « paroi_m ») ou tube rond (« profil » : rond), posée le long de son axe Z local.",
		"champs": ["matiere", "position", "longueur_m", "largeur_m", "hauteur_m"],
		"facultatifs": ["rotation_deg", "profil", "paroi_m", "articulation", "note"]},
	"panneau": {"nom": "panneau", "pese": true,
		"description": "Surface plane remplie entre 3 ou 4 coins (« sommets ») d'une armature, de l'épaisseur et de la matière choisies. 4 coins qui ne sont pas à plat : deux triangles plats.",
		"champs": ["matiere", "sommets", "epaisseur_m"],
		"facultatifs": ["articulation", "note"]},
	"plaque": {"nom": "plaque", "pese": true,
		"description": "Plaque pleine (panneau de coque, cloison), à plat dans son plan XZ local.",
		"champs": ["matiere", "position", "longueur_m", "largeur_m", "epaisseur_m"],
		"facultatifs": ["rotation_deg", "articulation", "note"]},
	"moteur": {"nom": "moteur", "pese": false,
		"description": "Moteur principal : pousse fort vers sa direction, réglé par les gaz.",
		"champs": ["point", "direction", "poussee_n"],
		"facultatifs": ["role", "seulement_sorti", "articulation", "masse_kg", "centre", "note"]},
	"propulseur": {"nom": "petit propulseur", "pese": false,
		"description": "Petit propulseur : son rôle (tourner, glisser) est trouvé par le calcul du couple.",
		"champs": ["point", "direction", "poussee_n"],
		"facultatifs": ["encastre", "articulation", "masse_kg", "centre", "note"]},
	"roue": {"nom": "roue du train", "pese": false,
		"description": "Bas d'une roue, train sorti, avec son amortisseur.",
		"champs": ["point", "course_m", "raideur_n_m", "amorti_n_s_m"],
		"facultatifs": ["rayon_m", "orientable_deg", "vitesse_braquage_deg_s", "freinee", "choc_max_m_s", "masse_kg",
			"centre", "note"]},
	"contact_coque": {"nom": "point de coque", "pese": false,
		"description": "Point de la coque qui peut toucher le sol (ventre, nez, queue).",
		"champs": ["point"], "facultatifs": ["note"]},
	"surface_air": {"nom": "surface d'air", "pese": false,
		"description": "Plaque mince qui porte et freine dans l'air (bande d'aile, dérive).",
		"champs": ["point", "normale", "surface_m2", "allongement"],
		"facultatifs": ["corde_m", "biplan", "groupe", "articulation", "note"]},
	"ensemble": {"nom": "ensemble", "pese": true,
		"description": "Un petit plan dans le plan : ses pièces bougent ensemble.",
		"champs": [], "facultatifs": ["pieces", "plan", "articulations", "position", "rotation_deg", "miroir_x",
			"articulation", "nom", "note", "modele", "reglages", "fixe_a", "symetrique",
			"noeuds", "longueur_m", "surface_m2", "articulation_appui"]},
}

## Types d'articulations (pièces mobiles) : ce qui fait bouger une pièce par rapport au vaisseau.
## Chacune suit une commande (ailes, train, vertical : de 0 à 1) pendant une phase de cette commande
## (« phase » : [début, fin], [0, 1] si absente). Facultatifs : « nom », « modele_3d » (nœud du modèle 3D).
##   - charnière : tourne autour de son axe (passant par « point ») de angle_0_deg (commande 0) à angle_1_deg ;
##   - tuyère à anneaux : anneaux_m = longueur de chaque anneau depuis le pivot ; chaque anneau tourne d'une
##     part égale de l'angle (3 anneaux pour 90° : 30° chacun) ; droite dans la pose de référence ;
##   - vérin : glisse de « course » (m, vecteur) entre le début et la fin de sa phase.
const ARTICULATIONS := {
	"charniere": {"nom": "charnière", "champs": ["commande", "point", "axe", "angle_0_deg", "angle_1_deg"]},
	"tuyere_anneaux": {"nom": "tuyère à anneaux", "champs": ["commande", "pivot", "axe", "anneaux_m", "angle_1_deg"]},
	"verin": {"nom": "vérin", "champs": ["commande", "course"]},
}


## Masse, centre et inertie d'une pièce, dans le repère du plan où elle est écrite :
## {"masse": kg, "centre": Vector3, "inertie": [Ixx, Iyy, Izz, Ixy, Ixz, Iyz] autour de son propre centre}.
## Une pièce qui ne pèse pas renvoie une masse nulle.
static func masse_piece(p: Dictionary) -> Dictionary:
	var t: String = p.get("type", "")
	var zero := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	match t:
		"structure":
			return {"masse": float(p["masse_kg"]), "centre": vecteur(p["centre"]), "inertie": (p["inertie_propre"] as Array).duplicate()}
		"poutre", "plaque":
			var dens: float = float(MATIERES[p["matiere"]]["densite"])
			# dimensions locales : x = largeur, y = hauteur (poutre) ou épaisseur (plaque), z = longueur
			var a: float = float(p["largeur_m"])
			var b: float = float(p["hauteur_m"]) if t == "poutre" else float(p["epaisseur_m"])
			var c: float = float(p["longueur_m"])
			var mi := _boite_pleine(dens, a, b, c)
			if t == "poutre" and String(p.get("profil", "")) == "rond":
				# tube rond (diamètre extérieur = largeur) : cylindre extérieur moins cylindre intérieur
				var ro := a * 0.5
				var ri := maxf(ro - float(p.get("paroi_m", ro)), 0.0)
				mi = _cylindre_plein(dens, ro, c)
				if ri > 0.0:
					var creux := _cylindre_plein(dens, ri, c)
					mi = [float(mi[0]) - float(creux[0]), _moins(mi[1], creux[1])]
			elif t == "poutre" and p.has("paroi_m"):
				# tube rectangulaire : boîte extérieure moins boîte intérieure (même longueur)
				var e := float(p["paroi_m"])
				if 2.0 * e < minf(a, b):
					var creux2 := _boite_pleine(dens, a - 2.0 * e, b - 2.0 * e, c)
					mi = [float(mi[0]) - float(creux2[0]), _moins(mi[1], creux2[1])]
			var r := rotation(p.get("rotation_deg", [0.0, 0.0, 0.0]))
			var local: Basis = mi[1]
			return {"masse": float(mi[0]), "centre": vecteur(p["position"]), "inertie": de_basis(r * local * r.transposed())}
		"panneau":
			return masse_panneau(MATIERES[p["matiere"]]["densite"], p["sommets"], float(p["epaisseur_m"]))
		"bloc":
			var m := float(p["masse_kg"])
			var dim: Array = p["dimensions_m"]
			var local: Basis
			if String(p["forme"]) == "cylindre":
				# cylindre plein : diamètre, longueur (le long de Z local)
				var r := float(dim[0]) * 0.5
				var l := float(dim[1])
				var ix := m * (3.0 * r * r + l * l) / 12.0
				local = Basis(Vector3(ix, 0, 0), Vector3(0, ix, 0), Vector3(0, 0, m * r * r * 0.5))
			elif String(p["forme"]) == "boule":
				# boule : diamètre (et épaisseur de paroi si elle est creuse). Pleine : I = 2/5 · m · R² ;
				# creuse (R dehors, r dedans) : I = 2/5 · m · (R⁵ − r⁵) / (R³ − r³)
				var rb2 := float(dim[0]) * 0.5
				var ri2 := maxf(rb2 - float(dim[1]), 0.0) if dim.size() > 1 else 0.0
				var ib := 0.4 * m * (pow(rb2, 5) - pow(ri2, 5)) / maxf(pow(rb2, 3) - pow(ri2, 3), 1e-12)
				local = Basis(Vector3(ib, 0, 0), Vector3(0, ib, 0), Vector3(0, 0, ib))
			else:
				# boîte pleine : x, y, z
				var a := float(dim[0])
				var b := float(dim[1])
				var c := float(dim[2])
				local = Basis(Vector3(m / 12.0 * (b * b + c * c), 0, 0), Vector3(0, m / 12.0 * (a * a + c * c), 0),
					Vector3(0, 0, m / 12.0 * (a * a + b * b)))
			var rb := rotation(p.get("rotation_deg", [0.0, 0.0, 0.0]))
			return {"masse": m, "centre": vecteur(p["position"]), "inertie": de_basis(rb * local * rb.transposed())}
	if p.has("masse_kg") and p.has("centre"):
		return {"masse": float(p["masse_kg"]), "centre": vecteur(p["centre"]), "inertie": zero}
	return {"masse": 0.0, "centre": Vector3.ZERO, "inertie": zero}


## Boîte pleine (côtés a, b, c le long de X, Y, Z) : [masse, inertie autour de son centre].
static func _boite_pleine(dens: float, a: float, b: float, c: float) -> Array:
	var m := dens * a * b * c
	return [m, Basis(Vector3(m / 12.0 * (b * b + c * c), 0, 0), Vector3(0, m / 12.0 * (a * a + c * c), 0),
		Vector3(0, 0, m / 12.0 * (a * a + b * b)))]


## Cylindre plein de rayon r et de longueur l le long de Z : [masse, inertie autour de son centre].
static func _cylindre_plein(dens: float, r: float, l: float) -> Array:
	var m := dens * PI * r * r * l
	var ix := m * (3.0 * r * r + l * l) / 12.0
	return [m, Basis(Vector3(ix, 0, 0), Vector3(0, ix, 0), Vector3(0, 0, 0.5 * m * r * r))]


static func _moins(a: Basis, b: Basis) -> Basis:
	return Basis(a.x - b.x, a.y - b.y, a.z - b.z)


## Les triangles d'un panneau (indices des coins) : un triangle, ou un quadrilatère coupé en deux par sa
## plus courte diagonale (à plat, les deux façons donnent la même surface ; pas à plat, c'est le pli le plus
## court, celui d'une tôle pliée).
static func triangles_panneau(s: Array) -> Array:
	if s.size() == 3:
		return [[0, 1, 2]]
	if s.size() != 4:
		return []
	if (vecteur(s[0]) - vecteur(s[2])).length() <= (vecteur(s[1]) - vecteur(s[3])).length():
		return [[0, 1, 2], [0, 2, 3]]
	return [[0, 1, 3], [1, 2, 3]]


## Masse, centre et inertie d'un panneau plein (plaque mince d'épaisseur e entre ses coins, coins au milieu
## de l'épaisseur). Pour chaque triangle de coins a, b, c (masse m) : ∫ r·rᵀ dm = m/12 · (a·aᵀ + b·bᵀ + c·cᵀ
## + s·sᵀ) avec s = a + b + c ; ramené au centre de gravité (Huygens), plus l'épaisseur (m·e²/12 le long de
## la normale) ; inertie = trace · 1 − ce tableau.
static func masse_panneau(densite, sommets: Array, e: float) -> Dictionary:
	var dens := float(densite)
	var pts := []
	for q in sommets:
		pts.append(vecteur(q))
	var m := 0.0
	var premier := Vector3.ZERO
	var c := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # ∫ x², y², z², xy, xz, yz
	var normale := Vector3.ZERO
	for t in triangles_panneau(pts):
		var a: Vector3 = pts[t[0]]
		var b: Vector3 = pts[t[1]]
		var d: Vector3 = pts[t[2]]
		var n := (b - a).cross(d - a)
		var mi := dens * 0.5 * n.length() * e
		if mi <= 0.0:
			continue
		normale += n if n.dot(normale) >= 0.0 else -n
		var s := a + b + d
		m += mi
		premier += s * (mi / 3.0)
		var k := mi / 12.0
		for v in [a, b, d, s]:
			c[0] += k * v.x * v.x
			c[1] += k * v.y * v.y
			c[2] += k * v.z * v.z
			c[3] += k * v.x * v.y
			c[4] += k * v.x * v.z
			c[5] += k * v.y * v.z
	if m <= 0.0:
		return {"masse": 0.0, "centre": Vector3.ZERO, "inertie": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]}
	var g := premier / m
	c[0] -= m * g.x * g.x
	c[1] -= m * g.y * g.y
	c[2] -= m * g.z * g.z
	c[3] -= m * g.x * g.y
	c[4] -= m * g.x * g.z
	c[5] -= m * g.y * g.z
	var nn := normale.normalized()
	var ke := m * e * e / 12.0
	c[0] += ke * nn.x * nn.x
	c[1] += ke * nn.y * nn.y
	c[2] += ke * nn.z * nn.z
	c[3] += ke * nn.x * nn.y
	c[4] += ke * nn.x * nn.z
	c[5] += ke * nn.y * nn.z
	var tr: float = c[0] + c[1] + c[2]
	return {"masse": m, "centre": g, "inertie": [tr - c[0], tr - c[1], tr - c[2], -c[3], -c[4], -c[5]]}


## Surface (m²) d'un panneau.
static func surface_panneau(sommets: Array) -> float:
	var pts := []
	for q in sommets:
		pts.append(vecteur(q))
	var a := 0.0
	for t in triangles_panneau(pts):
		a += 0.5 * ((pts[t[1]] as Vector3) - (pts[t[0]] as Vector3)).cross((pts[t[2]] as Vector3) - (pts[t[0]] as Vector3)).length()
	return a


## [x, y, z] → Vector3.
static func vecteur(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Orientation d'une pièce : angles en degrés autour de X, Y, Z (ordre de Godot : Y, puis X, puis Z).
static func rotation(deg) -> Basis:
	var v := vecteur(deg)
	return Basis.from_euler(Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z)))


## Tenseur d'inertie [Ixx, Iyy, Izz, Ixy, Ixz, Iyz] ↔ Basis symétrique.
static func vers_basis(i: Array) -> Basis:
	var xx := float(i[0])
	var yy := float(i[1])
	var zz := float(i[2])
	var xy := float(i[3])
	var xz := float(i[4])
	var yz := float(i[5])
	return Basis(Vector3(xx, xy, xz), Vector3(xy, yy, yz), Vector3(xz, yz, zz))


static func de_basis(b: Basis) -> Array:
	return [b.x.x, b.y.y, b.z.z, b.x.y, b.x.z, b.y.z]
