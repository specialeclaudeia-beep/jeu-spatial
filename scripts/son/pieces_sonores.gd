extends RefCounted
## Les 16 « pièces sonores » du vaisseau (moteur audio, phase 4) : les grandes pièces dont on calcule la tension.
##
## Chacune est un groupe de masses du modèle 3D (modeles/vaisseau/masses_godot.json, calculé dans Blender), tenu au
## reste du vaisseau par une ATTACHE (emplanture d'aile, support de moteur, pied de dérive, pivot de jambe de
## train, cadre de la verrière, coupe entre le nez et le cockpit). Ce que l'attache doit transmettre se calcule
## dans charges.gd (principe de d'Alembert). Ici : quelles masses, où, quelle matière, et ce qui pousse
## directement sur la pièce (son moteur, l'air sur elle, le sol sur sa roue, la pression de la cabine).
##
##   - 4 ailes (composite) : l'aile, coupée en 3 bandes (de l'emplanture au bout, comme aerodynamique.gd), et son
##     réacteur, qui est posé dessus ; elles tournent avec leur charnière quand les ailes s'ouvrent ou se replient ;
##   - 4 supports de réacteur d'aile (titane) ;
##   - le moteur central et sa tuyère (titane) ;
##   - 2 dérives (composite) ;
##   - 3 jambes de train (acier) : elles bougent entre « rentré » et « sorti » ;
##   - la verrière (verre feuilleté) : poussée vers le dehors par l'air de la cabine quand il n'y en a plus dehors ;
##   - le nez (aluminium-lithium) : tout ce qui est devant le cockpit (avionique, canons, moteurs de levage, train
##     avant, petits propulseurs du nez) et 30 % de la peau du fuselage.
## Le reste (cockpit, fuselage central) sert d'appui : il n'est pas une pièce sonore.
##
## Les masses et leurs centres viennent du modèle ; les points d'attache et la position « train sorti » des
## pièces du train sont lus sur le modèle 3D (à 10 cm près). Rien ici ne touche la physique.

const FICHIER := "res://modeles/vaisseau/masses_godot.json"
const Z_NEZ := -1.5                  # m : coupe entre le nez et le cockpit (repère du modèle)
const PART_FUSELAGE_NEZ := 0.3       # part de la peau du fuselage qui est devant cette coupe
const CENTRE_FUSELAGE_NEZ := Vector3(0.0, 0.036, -3.5)
const P_CABINE := 101325.0           # Pa : le cockpit est plein d'air à la pression du niveau de la mer
const VERRIERE_SURFACE := 1.6        # m² : la verrière vue de dessus (ce que la pression pousse)
const VERRIERE_NORMALE := Vector3(0.0, 0.95, -0.31)   # vers le dehors (haut et un peu vers l'avant)
const VERRIERE_CENTRE := Vector3(0.0, 0.85, -0.32)
## Bandes d'une aile (comme aerodynamique.gd : distance à la charnière) et part de la masse de l'aile
## (choisies pour retomber sur le centre de masse du modèle, à 2,27 m de la charnière).
const BANDES_AILE := [[1.0, 0.5], [2.85, 0.3], [4.55, 0.2]]
const NOMS_AILES := ["haut_gauche", "haut_droit", "bas_gauche", "bas_droit"]
const ATTENUATION := 1.0             # dB par mètre de structure (comme moteurs_son.gd et sol_son.gd)
const JONCTION_AILE_DB := 6.0        # dB perdus au passage d'une emplanture d'aile
## Matières : craquements (comportement « Kaiser-Felicity », voir tension_son.gd) et sons (chocs.gd).
## felicite : part de la plus forte charge déjà vue à partir de laquelle la matière recommence à craquer
## (métal : seulement au-delà de l'ancien record ; composite : un peu avant).
const MATIERES := {
	"composite": {"felicite": 0.92, "l_j": 70.0},
	"titane": {"felicite": 1.0, "l_j": 74.0},
	"acier": {"felicite": 1.0, "l_j": 74.0},
	"verre": {"felicite": 0.97, "l_j": 72.0},
	"aluminium": {"felicite": 1.0, "l_j": 74.0},
}

## Types de points : fixe, sur une aile (repère de sa charnière), tuyère (tourne autour de son pivot), train.
enum { FIXE, AILE, TUYERE, TRAIN }

## Chaque pièce : {nom, matiere, attache, points: [[type, masse, a, b, k]], aile (n° ou −1), air: [surfaces],
## pression (bool), jonction_db}. a = position (ou position rentrée, ou position dans le repère de la charnière),
## b = position sortie (train), k = n° de l'aile, ou part de l'angle de la tuyère.
var pieces: Array = []
var masse_totale := 0.0
var tous: Array = []        # toutes les masses du modèle [masse, position] (contrôle de d'Alembert)


func _init() -> void:
	var f := FileAccess.open(FICHIER, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	if not (d is Dictionary):
		push_warning("Son : %s illisible" % FICHIER)
		return
	var masses := {}            # nom → [masse, position]
	for nom in d["equipements"]:
		var e: Dictionary = d["equipements"][nom]
		masses[nom] = [float(e["masse_kg"]), _v(e["position_godot"])]
	for nom in d["pieces"]:
		var p: Dictionary = d["pieces"][nom]
		masses[nom] = [float(p["masse_kg"]), _v(p["centre_godot"])]
	for nom in masses:
		masse_totale += float(masses[nom][0])
		tous.append(masses[nom])
	_construire(masses)


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _construire(m: Dictionary) -> void:
	var ouvert := [-22.249, 22.249, -157.751, 157.751]   # degrés, comme vaisseau_physique.gd (AILES)
	var charnieres := [Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0)]
	# --- les 4 ailes et leurs réacteurs ---
	for k in 4:
		var nom: String = NOMS_AILES[k]
		var vers_charniere := Basis(Vector3.BACK, -deg_to_rad(ouvert[k]))
		var aile: Array = m["Aile_" + nom]
		var c_aile: Vector3 = vers_charniere * ((aile[1] as Vector3) - charnieres[k])
		var points := []
		for b in BANDES_AILE:
			var q := Vector3(c_aile.x * float(b[0]) / 2.27, c_aile.y, c_aile.z)
			points.append([AILE, float(aile[0]) * float(b[1]), q, Vector3.ZERO, k])
		var reac: Array = m["Masse_reacteur_aile_" + nom]
		var c_reac: Vector3 = vers_charniere * ((reac[1] as Vector3) - charnieres[k])
		var p_reac := [AILE, float(reac[0]), c_reac, Vector3.ZERO, k]
		points.append(p_reac)
		pieces.append({"nom": "aile " + nom.replace("_", " "), "matiere": "composite", "points": points, "aile": k,
			"attache_aile": Vector3(0.0, 0.0, c_aile.z), "air": [k], "jonction_db": JONCTION_AILE_DB})
		pieces.append({"nom": "réacteur " + nom.replace("_", " "), "matiere": "titane", "points": [p_reac], "aile": k,
			"attache_aile": c_reac, "air": [], "jonction_db": JONCTION_AILE_DB, "reacteur": true})
	# --- moteur central et tuyère (les 3 anneaux tournent chacun d'un tiers de l'angle en vol vertical) ---
	var pts := [[FIXE, m["Masse_moteur_central"][0], m["Masse_moteur_central"][1], Vector3.ZERO, 0.0],
		[FIXE, m["Moteur_central"][0], m["Moteur_central"][1], Vector3.ZERO, 0.0]]
	for s in 3:
		var t: Array = m["Tuyere_segment_%d" % (s + 1)]
		pts.append([TUYERE, t[0], t[1], Vector3.ZERO, (s + 1) / 3.0])
	pieces.append({"nom": "moteur central", "matiere": "titane", "points": pts, "attache": Vector3(0.0, 0.0, 3.0), "air": [],
		"central": true})
	# --- dérives (surfaces 4 et 5 de l'air : gauche, droite) ---
	for k in 2:
		var dv: Array = m["Aileron_g" if k == 0 else "Aileron_d"]
		pieces.append({"nom": "dérive " + ("gauche" if k == 0 else "droite"), "matiere": "composite",
			"points": [[FIXE, dv[0], dv[1], Vector3.ZERO, 0.0]], "attache": Vector3(-0.62 if k == 0 else 0.62, 0.78, 3.8),
			"air": [4 + k]})
	# --- train : [pièce, position sortie] ; roue n° (comme les points du sol : 0 avant, 1 arrière gauche, 2 droit) ---
	var avant := [["Jambe_avant", Vector3(0.0, -0.6, -4.0)], ["Fourche_avant", Vector3(0.0, -1.0, -4.3)],
		["Roue_avant", Vector3(0.0, -1.32, -4.4)]]
	pieces.append({"nom": "jambe avant", "matiere": "acier", "points": _train(m, avant), "attache": Vector3(0.0, -0.05, -3.65),
		"air": [], "roue": 0})
	for k in 2:
		var cote := "gauche" if k == 0 else "droit"
		var sx := -1.0 if k == 0 else 1.0
		var arr := [["Jambe_arriere_" + cote, Vector3(0.8 * sx, -1.05, 2.4)], ["Ressort_arriere_" + cote, Vector3(0.9 * sx, -1.1, 2.4)],
			["Pied_arriere_" + cote, Vector3(1.1 * sx, -1.35, 2.4)], ["Roue_arriere_" + cote, Vector3(1.184 * sx, -1.35, 2.4)],
			["Pivot_train_arriere_" + cote, (m["Pivot_train_arriere_" + cote][1] as Vector3)]]
		pieces.append({"nom": "jambe arrière " + cote, "matiere": "acier", "points": _train(m, arr),
			"attache": m["Pivot_train_arriere_" + cote][1], "air": [], "roue": 1 + k})
	# --- verrière ---
	var vpts := []
	for nom in ["Cockpit_verriere", "Verriere", "Verriere_cadre"]:
		vpts.append([FIXE, m[nom][0], m[nom][1], Vector3.ZERO, 0.0])
	pieces.append({"nom": "verrière", "matiere": "verre", "points": vpts, "attache": Vector3(0.0, 0.55, -0.32), "air": [],
		"pression": true})
	# --- nez : tout ce qui est devant la coupe (le train avant compris), et une part de la peau du fuselage ---
	var npts := [[FIXE, float(m["Fuselage"][0]) * PART_FUSELAGE_NEZ, CENTRE_FUSELAGE_NEZ, Vector3.ZERO, 0.0]]
	var sorti := {}
	for a in avant:
		sorti[a[0]] = a[1]
	for nom in m:
		var p: Vector3 = m[nom][1]
		if nom == "Fuselage" or p.z >= Z_NEZ or float(m[nom][0]) <= 0.0:
			continue
		if sorti.has(nom):
			npts.append([TRAIN, m[nom][0], p, sorti[nom], 0.0])
		else:
			npts.append([FIXE, m[nom][0], p, Vector3.ZERO, 0.0])
	pieces.append({"nom": "nez", "matiere": "aluminium", "points": npts, "attache": Vector3(0.0, 0.0, Z_NEZ), "air": [7],
		"nez": true})


static func _train(m: Dictionary, liste: Array) -> Array:
	var pts := []
	for e in liste:
		pts.append([TRAIN, m[e[0]][0], m[e[0]][1], e[1], 0.0])
	return pts


## Position (repère du modèle) d'un point d'une pièce, pour la géométrie actuelle.
static func position(pt: Array, charnieres: PackedVector3Array, angles: PackedFloat64Array, angle_tuyere: float,
		pivot: Vector3, train: float) -> Vector3:
	match int(pt[0]):
		AILE:
			var k: int = pt[4]
			return charnieres[k] + Basis(Vector3.BACK, deg_to_rad(angles[k])) * (pt[2] as Vector3)
		TUYERE:
			var a := deg_to_rad(angle_tuyere) * float(pt[4])
			return pivot + Basis(Vector3.RIGHT, a) * ((pt[2] as Vector3) - pivot)
		TRAIN:
			return (pt[2] as Vector3).lerp(pt[3], clampf(train, 0.0, 1.0))
	return pt[2]


## Point d'attache d'une pièce (repère du modèle).
static func attache(p: Dictionary, charnieres: PackedVector3Array, angles: PackedFloat64Array) -> Vector3:
	if p.has("attache_aile"):
		var k: int = p["aile"]
		return charnieres[k] + Basis(Vector3.BACK, deg_to_rad(angles[k])) * (p["attache_aile"] as Vector3)
	return p["attache"]
