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
##     tourner, retourner en miroir, et sauvegarder seul pour le réutiliser.
## Toute pièce peut aussi avoir une masse (masse_kg + centre) : un moteur du futur atelier pèsera lui-même.
## Dans le plan du chasseur v27, les masses viennent des pièces de Blender, et les moteurs, propulseurs,
## roues et surfaces d'air n'ajoutent rien (leur masse est déjà comptée dans les pièces de Blender).

## Matières : une seule liste pour la masse (densité) et pour le son (comportement de la matière qui craque
## ou qui sonne, scripts/son/pieces_sonores.gd). Densités : valeurs habituelles des fiches techniques.
const MATIERES := {
	"aluminium_lithium": {"nom": "alliage aluminium-lithium", "densite": 2590.0, "son": "aluminium",
		"usage": "coque, trappes"},
	"aluminium": {"nom": "aluminium", "densite": 2700.0, "son": "aluminium", "usage": "habillage du cockpit"},
	"titane": {"nom": "titane (Ti-6Al-4V)", "densite": 4430.0, "son": "titane",
		"usage": "tuyères, moteurs, carters chauds"},
	"acier": {"nom": "acier haute résistance", "densite": 7850.0, "son": "acier", "usage": "trains d'atterrissage"},
	"composite_carbone": {"nom": "composite fibre de carbone", "densite": 1600.0, "son": "composite", "usage": "ailes"},
	"verre_aluminosilicate": {"nom": "verre aluminosilicate feuilleté", "densite": 2460.0, "son": "verre",
		"usage": "verrière, vitres"},
	"ceramique": {"nom": "céramique de bouclier thermique (tuiles de silice)", "densite": 144.0, "son": "verre",
		"usage": "bouclier thermique (pas encore utilisé)"},
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
	"masse": {"nom": "masse ponctuelle", "pese": true,
		"description": "Équipement compté comme une masse en un point (ordinateurs, pilote, réservoir d'air…).",
		"champs": ["masse_kg", "centre"], "facultatifs": ["articulation", "note"]},
	"poutre": {"nom": "poutre", "pese": true,
		"description": "Barre pleine de section rectangulaire, posée le long de son axe Z local.",
		"champs": ["matiere", "position", "longueur_m", "largeur_m", "hauteur_m"],
		"facultatifs": ["rotation_deg", "articulation", "note"]},
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
			"articulation", "nom", "note"]},
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
			var m := dens * a * b * c
			# boîte pleine : I = m/12 · (somme des carrés des deux autres côtés)
			var local := Basis(Vector3(m / 12.0 * (b * b + c * c), 0, 0), Vector3(0, m / 12.0 * (a * a + c * c), 0),
				Vector3(0, 0, m / 12.0 * (a * a + b * b)))
			var r := rotation(p.get("rotation_deg", [0.0, 0.0, 0.0]))
			return {"masse": m, "centre": vecteur(p["position"]), "inertie": de_basis(r * local * r.transposed())}
	if p.has("masse_kg") and p.has("centre"):
		return {"masse": float(p["masse_kg"]), "centre": vecteur(p["centre"]), "inertie": zero}
	return {"masse": 0.0, "centre": Vector3.ZERO, "inertie": zero}


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
