extends RefCounted
## Physique du vaisseau — « aucune physique magique ».
##
## Le vaisseau est un corps rigide à 6 degrés de liberté. Tout mouvement vient de forces
## appliquées à un endroit précis du vaisseau :
##   forces  -> changent la vitesse (translation)
##   couples -> changent la vitesse de rotation (couple = position × force)
## La gravité de la planète (et des autres astres) agit en permanence. Pas de carburant.
## La gravité tire un peu plus sur la partie du vaisseau la plus proche d'un astre : cela crée
## un petit couple (« gradient de gravité ») qui fait lentement se balancer le vaisseau.
##
## Repère du vaisseau (comme Godot) : -Z = avant (le nez), +Y = haut, +X = droite.
## La position et la vitesse sont gardées en double précision (px, py, pz...), car les
## Vector3 de Godot sont en simple précision et perdraient des mètres à 700 km du centre.

# =====================================================================
# CONSTANTES
# =====================================================================
const G0 := 9.80665  # pour exprimer les accélérations en « g »
const C := 299792458.0  # m/s, vitesse de la lumière : rien ne peut l'atteindre (relativité restreinte)

# =====================================================================
# CARACTÉRISTIQUES DU VAISSEAU (modifiables)
# =====================================================================
## Masse, centre de gravité et inertie calculés dans Blender à partir des vraies matières de chaque
## pièce (modele3d/v27_roues_arriere/masses_godot.json) : ailes ouvertes, train rentré, droïde à
## bord, sans carburant (le jeu n'en a pas, la masse ne change donc jamais).
var masse := 8534.1                                    # kg
var inertie := Vector3(67901.5, 81291.3, 19295.1)      # kg·m² autour du centre de gravité : tangage (X), lacet (Y), roulis (Z)
## Centre de gravité dans le repère du modèle 3D : 1,43 m derrière son origine (moteurs lourds à l'arrière).
## Le vaisseau tourne autour de ce point : tous les couples (propulseurs, sol) sont calculés par rapport à lui.
## px, py, pz = position du centre de gravité.
const CENTRE_GRAVITE := Vector3(0.0, 0.0147, 1.431)
var reactivite_moteurs := 0.3                          # secondes pour que la poussée suive la consigne
const POUSSEE_MOTEUR := 200000.0   # N, chacun des 5 moteurs arrière (seul, il pousse 2 fois le poids de 10 t)
const POUSSEE_RCS := 6000.0        # N, chacun des 12 propulseurs d'orientation et des 10 buses encastrées

# =====================================================================
# ÉTAT
# =====================================================================
var px := 0.0
var py := 0.0
var pz := 0.0      # position (m), centre de la planète = 0
var vx := 0.0
var vy := 0.0
var vz := 0.0      # vitesse (m/s), mesurée dans le repère de la planète : toujours plus petite que C

# ---------------------------------------------------------------------
# RELATIVITÉ D'EINSTEIN (étape A : relativité restreinte)
# ---------------------------------------------------------------------
## On ne fait pas « vitesse += accélération × temps » (Newton) : à force de pousser, on dépasserait
## la lumière. On suit à la place la « vitesse propre » u = γ·v : la distance parcourue par seconde
## de l'HORLOGE DU PILOTE. Elle, peut grandir sans limite ; la vraie vitesse v = u / γ reste toujours
## sous C, avec γ = √(1 + u²/C²) (facteur de Lorentz). À petite vitesse, γ = 1 : c'est exactement Newton.
## Le moteur pousse toujours avec la même force dans le repère du vaisseau (le pilote sent toujours
## les mêmes G), mais vu de la planète, il accélère de moins en moins près de C.
var ux := 0.0
var uy := 0.0
var uz := 0.0      # vitesse propre (m/s de l'horloge du pilote)
var _v_connue := PackedFloat64Array([0.0, 0.0, 0.0])   # dernière vitesse écrite par la physique
## Deux horloges : celle de l'univers (planète, étoiles) et celle du pilote. Celle du pilote retarde
## quand il va vite (γ) et quand il est au fond d'un puits de gravité (relativité générale, faible ici).
var temps_univers := 0.0   # s
var temps_pilote := 0.0    # s
## Puissance des moteurs principaux (5 moteurs arrière + 2 de levage), modifiable en jeu :
## 1 = la vraie poussée (5 × 200 kN, ≈ 12 g). Les petits propulseurs d'orientation ne changent pas.
var facteur_poussee := 1.0
var orientation := Quaternion.IDENTITY
var omega := Vector3.ZERO                    # vitesse de rotation (rad/s), repère du vaisseau
var acceleration_ressentie := Vector3.ZERO   # ce que sent le pilote (m/s², repère monde) : pas la gravité
var au_sol := false
var ecrase := false
var vitesse_impact := 0.0

# planète
var gm := 0.0              # constante gravitationnelle × masse de la planète (m³/s²)
var rayon_planete := 0.0   # m (0 = pas de sol)
## Relief du sol (étape 8 du système de lumière) : fonction (x, y, z) → hauteur du sol en mètres au-dessus de
## rayon_planete dans cette direction. Vide = sol lisse (sphère). Le jeu y branche le relief de la planète
## dessinée (partie C++), pour que le vaisseau se pose sur le sol qu'on voit.
var relief := Callable()
## Rotation de la planète sur elle-même autour de l'axe Y (rad/s, sens direct : l'est est vers -Z
## vu du pôle nord… peu importe ici) et angle déjà tourné (rad). Le repère de la physique, lui, ne tourne
## pas (pas de force « fictive » à inventer) : c'est le sol qui bouge sous le vaisseau. Le relief
## (fonction ci-dessus) est donné dans le repère de la planète.
var omega_planete := 0.0
var angle_planete := 0.0

# autres astres (lunes, étoiles…) : chacun = { nom, gm, x, y, z } (position en m, double précision).
# Pour l'instant ils restent immobiles : leur propre mouvement viendra plus tard.
var autres_astres: Array = []

# couple dû au gradient de gravité (true = calculé, comme dans la réalité)
var gradient_gravite := true
var couple_gravite_actuel := Vector3.ZERO   # N·m, repère du vaisseau (pour les tests et l'affichage)

# propulseurs : chacun = { nom, position, direction, poussee_max, consigne (0..1), actuel (0..1) }
var moteurs: Array = []
var rcs: Array = []        # petits propulseurs : en plus { axe (0,1,2 ; -1 = buse de déplacement), signe (+1/-1) }

# =====================================================================
# CRÉATION
# =====================================================================
## Les 4 ailes, comme dans le modèle 3D (modele3d/v12, nœuds Charniere_*). Chaque aile tourne autour
## d'une charnière parallèle à l'axe avant-arrière, placée à 0,6 m du centre. L'angle (en degrés,
## autour de l'axe Z du vaisseau) va de « replie » (ailes à plat, l'une sur l'autre) à « ouvert » (en X).
## Les propulseurs posés sur une aile tournent avec elle : leur position est recalculée.
const AILES := {
	"haut_gauche": {"charniere": Vector3(-0.6, 0, 0), "ouvert": -22.249, "replie": 0.0},
	"haut_droit": {"charniere": Vector3(0.6, 0, 0), "ouvert": 22.249, "replie": 0.0},
	"bas_gauche": {"charniere": Vector3(-0.6, 0, 0), "ouvert": -157.751, "replie": -180.0},
	"bas_droit": {"charniere": Vector3(0.6, 0, 0), "ouvert": 157.751, "replie": 180.0},
}
## Buses encastrées : [nom, position, direction de la poussée] lues dans les extras du modèle (poussee_godot).
const BUSES := [
	["freinage gauche", Vector3(-0.10, 0.0, -6.0), Vector3(0.0, 0.0, 1.0)],
	["freinage droit", Vector3(0.10, 0.0, -6.0), Vector3(0.0, 0.0, 1.0)],
	["poussee fine gauche", Vector3(-0.70, 0.0, 4.3), Vector3(0.0, 0.0, -1.0)],
	["poussee fine droit", Vector3(0.70, 0.0, 4.3), Vector3(0.0, 0.0, -1.0)],
	["lateral gauche", Vector3(-0.75, 0.0, 0.0), Vector3(0.997, 0.0, 0.083)],
	["lateral droit", Vector3(0.75, 0.0, 0.0), Vector3(-0.997, 0.0, 0.083)],
	["montee gauche", Vector3(-0.5622, -0.4635, 0.0), Vector3(0.847, 0.529, 0.052)],
	["montee droit", Vector3(0.5622, -0.4635, 0.0), Vector3(-0.833, 0.521, 0.187)],
	["descente gauche", Vector3(-0.5667, 0.6163, 0.0), Vector3(0.842, -0.526, 0.119)],
	["descente droit", Vector3(0.5667, 0.6163, 0.0), Vector3(-0.84, -0.526, 0.135)],
]
const DUREE_AILES := 2.5     # s pour ouvrir ou replier complètement les ailes (vérins)
const DUREE_TRAIN := 3.0     # s pour sortir ou rentrer complètement le train
const HAUTEUR_TRAIN := 1.6   # m entre le centre du vaisseau et le sol, train sorti (modèle 3D)
const HAUTEUR_VENTRE := 1.0  # m entre le centre et le dessous de la coque, train rentré

## Vol vertical (modèle v17) : deux moteurs de levage à l'avant sortent du ventre (trappes puis vérin),
## puis la tuyère du moteur central tourne de 0° (poussée vers l'avant) à 90° (poussée vers le haut).
## En vol vertical, les gaz poussent vers le haut : c'est la poussée réelle des moteurs, répartie entre
## l'avant (moteurs de levage) et l'arrière (tuyère) pour ne pas faire basculer le vaisseau.
const POUSSEE_LEVAGE := 37500.0                      # N, chacun des 2 moteurs de levage
const PIVOT_TUYERE := Vector3(0.0, 0.0, 4.25)        # premier anneau de la tuyère centrale (modèle v18)
const SORTIE_TUYERE := Vector3(0.0, 0.0, 0.8)        # sortie de la tuyère, vue du pivot, à 0°
const ANNEAUX_TUYERE := [0.26, 0.26, 0.28]           # 3 anneaux qui tournent chacun d'un tiers de l'angle
const PIVOT_LEVAGE := 0.27                           # m de part et d'autre de l'axe
const LEVAGE_HAUT := Vector3(0.0, -0.03, -3.0)       # haut du vérin d'un moteur de levage (x = ±0,27)
const LEVAGE_SORTIE := -0.37                         # sortie du moteur sous son vérin (m)
const COURSE_LEVAGE := -0.32                         # descente du vérin (m)
const DUREE_VERTICAL := 4.0                          # s pour passer complètement en vol vertical
const PART_LEVAGE := 0.4                             # part de la séquence : sortie des moteurs de levage
var vertical := 0.0          # 0 = vol normal, 1 = vol vertical complet (levage sorti, tuyère à 90°)
var vertical_consigne := 0.0

var ailes := 1.0             # ouverture des ailes : 0 = repliées, 1 = ouvertes
var ailes_consigne := 1.0
var train := 0.0             # train d'atterrissage : 0 = rentré, 1 = sorti
var train_consigne := 0.0


func _init() -> void:
	# 5 moteurs arrière : 4 sur les ailes + 1 central. Ils poussent tous vers l'avant (-Z).
	# Positions prises sur le modèle 3D (points Point_moteur_*), mesurées dans le repère de la charnière.
	var avant := Vector3(0, 0, -1)
	_ajouter_moteur("haut gauche", Vector3(-1.12, 0, 4.0), avant, POUSSEE_MOTEUR, "haut_gauche")
	_ajouter_moteur("haut droit", Vector3(1.12, 0, 4.0), avant, POUSSEE_MOTEUR, "haut_droit")
	_ajouter_moteur("bas gauche", Vector3(1.12, 0, 4.0), avant, POUSSEE_MOTEUR, "bas_gauche")
	_ajouter_moteur("bas droit", Vector3(-1.12, 0, 4.0), avant, POUSSEE_MOTEUR, "bas_droit")
	_ajouter_moteur("central", PIVOT_TUYERE + SORTIE_TUYERE, avant, POUSSEE_MOTEUR, "")
	# moteurs de levage : ils poussent vers le haut, seulement une fois complètement sortis
	_ajouter_moteur("levage gauche", Vector3.ZERO, Vector3.UP, 0.0, "")
	_ajouter_moteur("levage droit", Vector3.ZERO, Vector3.UP, 0.0, "")

	# Propulseurs d'orientation (points Point_rcs_* du modèle), par paires opposées : ils font tourner
	# sans faire avancer. Un propulseur placé en haut du nez souffle vers le haut, donc il pousse
	# le nez vers le BAS (action-réaction).
	var p := POUSSEE_RCS
	var nez_haut := Vector3(0, 0.2, -5.2)
	var nez_bas := Vector3(0, -0.26, -5.2)
	var nez_gauche := Vector3(-0.29, 0, -5.2)
	var nez_droit := Vector3(0.29, 0, -5.2)
	var queue_haut := Vector3(0, 1.01, 4.0)
	var queue_bas := Vector3(0, -1.01, 4.0)
	var queue_gauche := Vector3(-0.91, 0, 4.0)
	var queue_droit := Vector3(0.91, 0, 4.0)
	# tangage + = nez vers le haut
	_ajouter_rcs("nez bas", nez_bas, Vector3.UP, p, 0, 1)
	_ajouter_rcs("queue haut", queue_haut, Vector3.DOWN, p, 0, 1)
	_ajouter_rcs("nez haut", nez_haut, Vector3.DOWN, p, 0, -1)
	_ajouter_rcs("queue bas", queue_bas, Vector3.UP, p, 0, -1)
	# lacet + = nez vers la gauche
	_ajouter_rcs("nez droit", nez_droit, Vector3.LEFT, p, 1, 1)
	_ajouter_rcs("queue gauche", queue_gauche, Vector3.RIGHT, p, 1, 1)
	_ajouter_rcs("nez gauche", nez_gauche, Vector3.RIGHT, p, 1, -1)
	_ajouter_rcs("queue droit", queue_droit, Vector3.LEFT, p, 1, -1)
	# roulis + = vers la gauche : un propulseur au bout de chaque aile, qui pousse perpendiculairement
	# à l'aile. Les deux ailes opposées (haut droit + bas gauche) forment une paire.
	var bout := Vector3(5.35, 0.24, 1.475)
	var bout_m := Vector3(-5.35, 0.24, 1.475)
	_ajouter_rcs("bout aile haut droit", bout, Vector3.UP, p, 2, 1, "haut_droit")
	_ajouter_rcs("bout aile bas gauche", bout, Vector3.UP, p, 2, 1, "bas_gauche")
	_ajouter_rcs("bout aile haut gauche", bout_m, Vector3.UP, p, 2, -1, "haut_gauche")
	_ajouter_rcs("bout aile bas droit", bout_m, Vector3.UP, p, 2, -1, "bas_droit")
	# Buses encastrées dans la coque (modèle v21, points Point_rcs_<nom>) : chacune souffle
	# perpendiculairement à la coque, la force est l'opposé du souffle. Par paires gauche/droite, elles
	# déplacent le vaisseau sans le faire tourner (freiner, avancer doucement, glisser, monter, descendre).
	for b in BUSES:
		_ajouter_rcs(b[0], b[1], (b[2] as Vector3).normalized(), p, -1, 0)
	_placer_propulseurs_ailes()
	_calculer_poussees()


## Poussée vers le haut possible en vol vertical complet (sert au pilote automatique pour savoir s'il
## peut s'arrêter à plat), puis poussée maximale dans la configuration actuelle.
func _calculer_poussees() -> void:
	var garde := vertical
	vertical = 1.0
	_placer_propulseurs_vertical()
	_preparer_repartition()
	_calculer_poussee_max()
	var verticale := _poussee_avant_vraie
	vertical = garde
	_placer_propulseurs_vertical()
	_preparer_repartition()
	_calculer_poussee_max()
	poussee_verticale_max = verticale * facteur_poussee


## Change la puissance des moteurs principaux (1 = vraie poussée de 200 kN par moteur).
## Le calcul des poussées (quel moteur, quel propulseur) se fait toujours avec les vrais moteurs ;
## la poussée en plus des « moteurs imaginaires » passe par le centre de gravité, comme si leurs
## tuyères s'orientaient pour ne pas faire tourner le vaisseau (sinon 2 cm d'écart × des milliards
## de newtons donneraient un couple que les petits propulseurs ne pourraient jamais rattraper).
func regler_poussee(facteur: float) -> void:
	facteur_poussee = maxf(facteur, 0.0)
	_calculer_poussees()


## Poussée maximale d'un moteur arrière (N), avec le réglage de puissance.
func poussee_moteur() -> float:
	return POUSSEE_MOTEUR * facteur_poussee


## Pour un propulseur posé sur une aile, pos et dir sont donnés dans le repère de la charnière.
func _ajouter_moteur(nom: String, pos: Vector3, dir: Vector3, poussee: float, aile: String) -> void:
	moteurs.append({"nom": nom, "position": pos, "direction": dir, "poussee_max": poussee, "consigne": 0.0, "actuel": 0.0,
		"aile": aile, "pos_aile": pos, "dir_aile": dir})


func _ajouter_rcs(nom: String, pos: Vector3, dir: Vector3, poussee: float, axe: int, signe: int, aile := "") -> void:
	rcs.append({"nom": nom, "position": pos, "direction": dir, "poussee_max": poussee, "axe": axe, "signe": signe, "actuel": 0.0,
		"aile": aile, "pos_aile": pos, "dir_aile": dir})


## Angle de la charnière d'une aile (degrés, autour de l'axe Z du vaisseau) pour l'ouverture actuelle.
## Sert aussi à l'affichage : le modèle 3D et la physique tournent exactement pareil.
func angle_aile(nom: String) -> float:
	var a: Dictionary = AILES[nom]
	return lerpf(float(a["replie"]), float(a["ouvert"]), ailes)


## Recalcule la position et la direction des propulseurs posés sur les ailes.
func _placer_propulseurs_ailes() -> void:
	for t in moteurs + rcs:
		var nom: String = t["aile"]
		if nom == "":
			continue
		var rot := Basis(Vector3.BACK, deg_to_rad(angle_aile(nom)))
		t["position"] = (AILES[nom]["charniere"] as Vector3) + rot * (t["pos_aile"] as Vector3)
		t["direction"] = rot * (t["dir_aile"] as Vector3)


## Sortie des moteurs de levage (0 = rentrés, 1 = sortis) et angle de la tuyère (degrés).
func sortie_levage() -> float:
	return clampf(vertical / PART_LEVAGE, 0.0, 1.0)


func angle_tuyere() -> float:
	return 90.0 * clampf((vertical - PART_LEVAGE) / (1.0 - PART_LEVAGE), 0.0, 1.0)


## Place la sortie de la tuyère centrale et les moteurs de levage selon la séquence de vol vertical.
func _placer_propulseurs_vertical() -> void:
	var rot := Basis(Vector3.RIGHT, deg_to_rad(angle_tuyere()))
	var central: Dictionary = moteurs[4]
	# chaque anneau tourne d'un tiers de l'angle par rapport au précédent (3 x 30° = 90°)
	var pos := PIVOT_TUYERE
	var tiers := deg_to_rad(angle_tuyere()) / 3.0
	for k in 3:
		pos += Basis(Vector3.RIGHT, tiers * (k + 1)) * Vector3(0, 0, float(ANNEAUX_TUYERE[k]))
	central["position"] = pos
	central["direction"] = rot * Vector3(0, 0, -1)
	var s := sortie_levage()
	for k in 2:
		var m: Dictionary = moteurs[5 + k]
		var x := -PIVOT_LEVAGE if k == 0 else PIVOT_LEVAGE
		m["position"] = Vector3(x, LEVAGE_HAUT.y + COURSE_LEVAGE * s + LEVAGE_SORTIE, LEVAGE_HAUT.z)
		# un moteur de levage à moitié sorti ne peut pas fonctionner (il soufflerait dans la coque)
		m["poussee_max"] = POUSSEE_LEVAGE if s >= 1.0 else 0.0


func passer_vol_vertical(oui: bool) -> void:
	vertical_consigne = 1.0 if oui else 0.0


## Direction de la poussée commandée par les gaz (repère du vaisseau) : vers l'avant, puis vers le
## haut à mesure que la tuyère tourne.
func direction_poussee() -> Vector3:
	var a := deg_to_rad(angle_tuyere())
	return Vector3(0.0, sin(a), -cos(a))


func ouvrir_ailes(ouvrir: bool) -> void:
	ailes_consigne = 1.0 if ouvrir else 0.0


func sortir_train(sortir: bool) -> void:
	train_consigne = 1.0 if sortir else 0.0


## Distance entre le centre du vaisseau et ce qui touche le sol : les roues si le train est
## complètement sorti, sinon le ventre de la coque.
func hauteur_contact() -> float:
	return HAUTEUR_TRAIN if train >= 1.0 else HAUTEUR_VENTRE

# =====================================================================
# COMMANDES
# =====================================================================
## Calcul automatique des poussées (idée reprise du module thrForceMapping de Basilisk, licence ISC,
## réécrite et simplifiée). On donne ce qu'on veut obtenir :
##   - une poussée vers l'avant (gaz, de 0 à 1),
##   - une rotation sur chaque axe (tangage, lacet, roulis, de -1 à 1),
## et le calcul cherche combien chaque propulseur (moteurs + propulseurs d'orientation) doit pousser
## pour s'en approcher le plus possible, à partir de sa VRAIE position et de sa direction.
## Chaque propulseur ne peut que pousser (jamais tirer) et jamais plus que sa puissance maximale.
## Le vaisseau n'est jamais tourné directement : la rotation vient ensuite des forces (couple = position × force).
var _tous: Array = []            # tous les propulseurs (moteurs puis propulseurs d'orientation)
var _colonnes: Array = []        # effet de chacun à pleine puissance : [Fx, Fy, Fz, Cx, Cy, Cz], mis à l'échelle
var _niveaux: PackedFloat64Array = PackedFloat64Array()   # niveaux calculés (0..1)
var poussee_avant_max := 0.0     # N, plus grande poussée possible dans la direction commandée, sans tourner
var _poussee_avant_vraie := 0.0  # N, la même avec les vrais moteurs (sert au calcul des poussées)
## Petite rotation que le calcul des poussées n'a pas pu annuler au dernier ordre (en part de la
## rotation maximale) : un léger déséquilibre des gros moteurs, que le stabilisateur compense.
var _reste_rotation := Vector3.ZERO
var poussee_verticale_max := 0.0  # N, vers le haut en vol vertical complet (calculée au départ)
var _poussee_borne := 0.0        # N, somme de tous les moteurs dans cette direction (borne haute)
var _recalcul_poussee := false
var _appels_depuis_calcul := 0
var couple_max := Vector3.ZERO   # N·m, rotation maximale demandée pour un ordre de 1 sur chaque axe
var _echelle_force := 1.0
const POIDS_ROTATION := 2.0      # la rotation compte plus que la poussée quand les deux ne sont pas possibles
const SOBRIETE := 0.001          # à résultat égal : moteurs proches des gaz, petits propulseurs coupés
const TOURS_CALCUL := 10         # nombre de passes du calcul (léger : environ 2 000 opérations)


func _preparer_repartition() -> void:
	_tous = moteurs + rcs
	_poussee_borne = 0.0
	var dir_p := direction_poussee()
	for m in moteurs:
		_poussee_borne += float(m["poussee_max"]) * maxf(0.0, (m["direction"] as Vector3).dot(dir_p))
	# rotation maximale sur chaque axe : ce que donnent les paires de propulseurs prévues pour cet axe,
	# dans les deux sens. Chaque paire tourne sans pousser de côté : cette rotation est toujours possible.
	var plus := Vector3.ZERO
	var moins := Vector3.ZERO
	for t in rcs:
		var k: int = t["axe"]
		if k < 0:
			continue
		var c: float = (t["position"] as Vector3 - CENTRE_GRAVITE).cross(t["direction"])[k] * float(t["poussee_max"])
		if int(t["signe"]) > 0:
			plus[k] += maxf(0.0, c)
		else:
			moins[k] += maxf(0.0, -c)
	couple_max = Vector3(minf(plus.x, moins.x), minf(plus.y, moins.y), minf(plus.z, moins.z))
	# échelle des forces : la plus petite poussée qui peut pousser de côté. Ainsi une erreur de force
	# de quelques kN compte autant qu'une erreur de rotation : pas de déplacement parasite.
	var f_cote := INF
	for t in _tous:
		var d0: Vector3 = t["direction"]
		if (absf(d0.x) > 1e-6 or absf(d0.y) > 1e-6) and float(t["poussee_max"]) > 0.0:
			f_cote = minf(f_cote, float(t["poussee_max"]))
	if f_cote == INF:
		f_cote = _poussee_borne
	_echelle_force = f_cote
	_colonnes.clear()
	_niveaux.resize(_tous.size())
	for i in _tous.size():
		var t = _tous[i]
		var f: Vector3 = (t["direction"] as Vector3) * float(t["poussee_max"])
		var c2: Vector3 = (t["position"] as Vector3 - CENTRE_GRAVITE).cross(f)
		_colonnes.append(PackedFloat64Array([
			f.x / f_cote, f.y / f_cote, f.z / f_cote,
			POIDS_ROTATION * c2.x / couple_max.x, POIDS_ROTATION * c2.y / couple_max.y, POIDS_ROTATION * c2.z / couple_max.z]))
		_niveaux[i] = 0.0


## force_cote : force voulue en plus (newtons, repère du vaisseau), par exemple pour pousser de côté.
## Les petits propulseurs la donnent, sans faire tourner le vaisseau. Sert au pilote automatique.
## Si elle dépasse ce que les propulseurs peuvent, on fait au mieux.
func commander(gaz: float, tangage: float, lacet: float, roulis: float, force_cote := Vector3.ZERO) -> void:
	gaz = clampf(gaz, 0.0, 1.0)
	gaz_demande = gaz
	# la configuration a changé (ailes, tuyère, moteurs de levage) : poussée maximale à recalculer,
	# au plus 20 fois par seconde pour rester léger
	_appels_depuis_calcul += 1
	if _recalcul_poussee and _appels_depuis_calcul >= 6:
		_calculer_poussee_max()
	var e := _repartir(gaz * _poussee_avant_vraie, gaz, tangage, lacet, roulis, force_cote)
	_reste_rotation = Vector3(e[3], e[4], e[5]) / POIDS_ROTATION
	# les moteurs reçoivent une consigne (ils mettent un peu de temps à la suivre),
	# les propulseurs d'orientation réagissent tout de suite
	for i in _tous.size():
		var niveau := _niveaux[i]
		if niveau < 1e-6:
			niveau = 0.0
		if i < moteurs.size():
			_tous[i]["consigne"] = niveau
		else:
			_tous[i]["actuel"] = niveau


## Cherche les niveaux (0..1) de tous les propulseurs pour obtenir une poussée « force » (N) dans la
## direction commandée et la rotation demandée. Renvoie l'écart restant (même échelle que les colonnes).
func _repartir(force: float, gaz: float, tangage: float, lacet: float, roulis: float, force_cote := Vector3.ZERO) -> PackedFloat64Array:
	var dir_p := direction_poussee() * (force / _echelle_force) + force_cote / _echelle_force
	# objectif, dans la même échelle que les colonnes
	var but := PackedFloat64Array([dir_p.x, dir_p.y, dir_p.z,
		POIDS_ROTATION * clampf(tangage, -1.0, 1.0),
		POIDS_ROTATION * clampf(lacet, -1.0, 1.0),
		POIDS_ROTATION * clampf(roulis, -1.0, 1.0)])
	# point de départ (et solution préférée) : moteurs qui poussent dans la bonne direction au niveau
	# des gaz, les autres et les petits propulseurs coupés
	var n := _tous.size()
	var prefere := PackedFloat64Array()
	prefere.resize(n)
	var dir_u := direction_poussee()
	for i in n:
		var utile: bool = i < moteurs.size() and (_tous[i]["direction"] as Vector3).dot(dir_u) > 0.5
		prefere[i] = gaz if utile else 0.0
		_niveaux[i] = prefere[i]
	# écart actuel = effet des niveaux actuels − objectif
	var ecart := PackedFloat64Array([-but[0], -but[1], -but[2], -but[3], -but[4], -but[5]])
	for i in n:
		var col: PackedFloat64Array = _colonnes[i]
		for k in 6:
			ecart[k] += col[k] * _niveaux[i]
	# on ajuste chaque propulseur à tour de rôle (« descente par coordonnées »), dans les limites 0..1
	for passe in TOURS_CALCUL:
		for i in n:
			var col: PackedFloat64Array = _colonnes[i]
			var h := SOBRIETE
			var g := SOBRIETE * (_niveaux[i] - prefere[i])
			for k in 6:
				h += col[k] * col[k]
				g += col[k] * ecart[k]
			var nouveau := clampf(_niveaux[i] - g / h, 0.0, 1.0)
			var d := nouveau - _niveaux[i]
			if d != 0.0:
				for k in 6:
					ecart[k] += col[k] * d
				_niveaux[i] = nouveau
	return ecart


## Plus grande poussée possible dans la direction commandée SANS faire tourner le vaisseau.
## Vers l'avant, c'est la somme des 5 moteurs. En vol vertical, l'avant (moteurs de levage) ne peut
## pas porter autant que l'arrière (tuyère) : on cherche par dichotomie la poussée la plus forte
## pour laquelle le calcul des poussées trouve une solution équilibrée.
func _calculer_poussee_max() -> void:
	_recalcul_poussee = false
	_appels_depuis_calcul = 0
	_poussee_avant_vraie = _chercher_poussee_max()
	poussee_avant_max = _poussee_avant_vraie * facteur_poussee


func _chercher_poussee_max() -> float:
	if _poussee_borne <= 0.0:
		return 0.0
	if _equilibre_possible(_poussee_borne):
		return _poussee_borne
	var bas := 0.0
	var haut := _poussee_borne
	for i in 14:
		var milieu := (bas + haut) * 0.5
		if _equilibre_possible(milieu):
			bas = milieu
		else:
			haut = milieu
	return bas


func _equilibre_possible(force: float) -> bool:
	var e := _repartir(force, force / _poussee_borne, 0.0, 0.0, 0.0)
	var erreur_force := sqrt(e[0] * e[0] + e[1] * e[1] + e[2] * e[2]) * _echelle_force
	var erreur_rotation := sqrt(e[3] * e[3] + e[4] * e[4] + e[5] * e[5])
	return erreur_force < 0.002 * force + 50.0 and erreur_rotation < 0.01


func ajouter_astre(nom: String, gm_astre: float, x: float, y: float, z: float) -> void:
	autres_astres.append({"nom": nom, "gm": gm_astre, "x": x, "y": y, "z": z})


## Un astre qui bouge (une lune) : position(t) → PackedFloat64Array [x, y, z] (m, repère de la physique,
## centré sur la planète), t = temps_univers. Le repère suit la planète, qui est elle aussi attirée par
## la lune : on retire donc cette attraction de la planète (« terme indirect ») ; il ne reste que ce
## qui change vraiment le mouvement du vaisseau par rapport à la planète (la marée de la lune).
func ajouter_astre_mobile(nom: String, gm_astre: float, position: Callable, rayon := 0.0) -> void:
	var p: PackedFloat64Array = position.call(temps_univers)
	autres_astres.append({"nom": nom, "gm": gm_astre, "x": p[0], "y": p[1], "z": p[2], "position": position,
		"indirect": true, "rayon": rayon})


## Repère qui accélère autrement que « tiré par les astres » (repère de la lune, qui suit son orbite autour
## de la planète) : acceleration_repere(t) → [ax, ay, az], retirée de la gravité (force d'inertie exacte).
var acceleration_repere := Callable()
var _a_repere := [0.0, 0.0, 0.0]


func _placer_astres(t := NAN) -> void:
	if is_nan(t):
		t = temps_univers
	if acceleration_repere.is_valid():
		_a_repere = acceleration_repere.call(t)
	for a in autres_astres:
		if a.has("position"):
			var p: PackedFloat64Array = (a["position"] as Callable).call(t)
			a["x"] = p[0]
			a["y"] = p[1]
			a["z"] = p[2]

# =====================================================================
# SIMULATION
# =====================================================================
## Accélération due à la gravité au point (x, y, z) : somme des attractions de tous les astres
## (loi de Newton : a = G·M / r², dirigée vers l'astre).
func gravite(x: float, y: float, z: float) -> Array:
	var ax := 0.0
	var ay := 0.0
	var az := 0.0
	if gm != 0.0:
		var r2 := x * x + y * y + z * z
		var k := -gm / (r2 * sqrt(r2))
		ax += k * x
		ay += k * y
		az += k * z
	for a in autres_astres:
		var dx: float = x - float(a["x"])
		var dy: float = y - float(a["y"])
		var dz: float = z - float(a["z"])
		var d2 := dx * dx + dy * dy + dz * dz
		var k2 := -float(a["gm"]) / (d2 * sqrt(d2))
		ax += k2 * dx
		ay += k2 * dy
		az += k2 * dz
		if a.get("indirect", false):
			var r2a: float = float(a["x"]) ** 2 + float(a["y"]) ** 2 + float(a["z"]) ** 2
			var k3 := float(a["gm"]) / (r2a * sqrt(r2a))
			ax -= k3 * float(a["x"])
			ay -= k3 * float(a["y"])
			az -= k3 * float(a["z"])
	if acceleration_repere.is_valid():
		ax -= float(_a_repere[0])
		ay -= float(_a_repere[1])
		az -= float(_a_repere[2])
	return [ax, ay, az]


## Couple du gradient de gravité (repère du vaisseau), pour un astre situé à (dx, dy, dz) du
## vaisseau. Formule classique (Orbiter, Basilisk) : couple = 3·GM/r³ · (n × (I·n)),
## n = direction de l'astre vue depuis le vaisseau. Il est nul quand un axe principal pointe
## vers l'astre, et il tend à tourner l'axe le plus long du vaisseau (nez-queue) vers l'astre.
func _couple_un_astre(gm_astre: float, dx: float, dy: float, dz: float, vers_corps: Basis) -> Vector3:
	var r := sqrt(dx * dx + dy * dy + dz * dz)
	if r <= 0.0:
		return Vector3.ZERO
	var n: Vector3 = vers_corps * Vector3(dx / r, dy / r, dz / r)
	var i_n := Vector3(inertie.x * n.x, inertie.y * n.y, inertie.z * n.z)
	return n.cross(i_n) * (3.0 * gm_astre / (r * r * r))


func couple_gravite() -> Vector3:
	if not gradient_gravite:
		return Vector3.ZERO
	var vers_corps := Basis(orientation).inverse()
	var c := Vector3.ZERO
	if gm != 0.0:
		c += _couple_un_astre(gm, -px, -py, -pz, vers_corps)
	for a in autres_astres:
		c += _couple_un_astre(float(a["gm"]), float(a["x"]) - px, float(a["y"]) - py, float(a["z"]) - pz, vers_corps)
	return c


## Force totale et couple total donnés par les propulseurs (repère du vaisseau) : [force, couple].
func effet_propulseurs() -> Array:
	var f_corps := Vector3.ZERO
	var couple := Vector3.ZERO
	var n_moteurs := moteurs.size()
	for i in _tous.size():
		var t: Dictionary = _tous[i]
		var niveau := float(t["actuel"])
		if niveau > 0.0:
			var f: Vector3 = t["direction"] * (float(t["poussee_max"]) * niveau)
			# moteurs principaux : poussée x facteur_poussee, mais la part en plus passe par le centre de gravité
			f_corps += f * facteur_poussee if i < n_moteurs else f
			couple += (t["position"] as Vector3 - CENTRE_GRAVITE).cross(f)
	return [f_corps, couple]


## Avance la simulation de dt secondes. Près du sol, le pas est découpé en petits morceaux :
## les ressorts du train sont raides, un grand pas (temps accéléré) les ferait vibrer de plus en plus.
const PAS_SOL := 1.0 / 240.0     # s, pas le plus long quand le vaisseau est près du sol
const HAUTEUR_DECOUPE := 30.0    # m : en dessous de cette altitude, on découpe


## Atmosphère : l'air de la planète (scripts/physique/atmosphere.gd), ou null (pas d'air : espace, lune,
## autre système d'étoile, et la plupart des tests). L'air tourne avec la planète (omega_planete).
const Aerodynamique = preload("res://scripts/physique/aerodynamique.gd")
var atmosphere = null
var aero = Aerodynamique.new()
var densite_air := 0.0            # kg/m³ autour du vaisseau
var temperature_air := 0.0        # K
var vitesse_air := 0.0            # m/s : vitesse par rapport à l'air
var force_air := Vector3.ZERO     # N, repère du vaisseau (dernier pas)
## Échauffement : nez du vaisseau (le point le plus chaud, au contact de l'air comprimé devant lui).
## Flux de chaleur au point d'arrêt : loi de Sutton-Graves (q = k·√(ρ/r)·v³, utilisée pour les capsules
## et la navette), corrigée pour une paroi chaude. La coque rayonne sa chaleur (loi de Stefan-Boltzmann)
## et a une capacité thermique : elle chauffe et refroidit en quelques dizaines de secondes.
const RAYON_NEZ := 0.3            # m (nez effilé du modèle : plus il est pointu, plus il chauffe)
const SUTTON_GRAVES := 1.7415e-4  # kg^0,5/m (air)
const CAPACITE_COQUE := 25000.0   # J/(m²·K) : environ 1 cm d'acier ou de céramique
const EMISSIVITE := 0.85
const SIGMA := 5.670374e-8        # W/(m²·K⁴)
const T_ESPACE := 250.0           # K : équilibre moyen d'une coque à l'ombre et au soleil, loin de l'air
const T_LIMITE_COQUE := 1900.0    # K (~1 630 °C) : au-delà, une vraie coque fondrait (seulement affiché)
var temperature_nez := 290.0      # K
var flux_nez := 0.0               # W/m², chaleur reçue de l'air


## Einstein C : le trou de ver (scripts/physique/trou_de_ver.gd), ou null. Près de sa gorge, c'est lui
## qui fait avancer le vaisseau (l'espace y est courbé autrement qu'autour d'un astre).
var trou_de_ver = null


func pas(dt: float) -> void:
	# Einstein C : à grande vitesse, découper le pas pour ne pas sauter par-dessus la gorge
	if trou_de_ver != null:
		var n_t: int = trou_de_ver.morceaux(self, dt)
		if n_t > 1:
			for i in n_t:
				_pas_un(dt / n_t)
				if ecrase:
					return
			return
	# Einstein B : près d'un astre très dense (trou noir), tout va très vite : pas découpé pour que
	# chaque morceau fasse au plus 1/200 du temps qu'il faut pour tomber ou passer.
	var n_dense := _morceaux_dense(dt)
	if n_dense > 1:
		for i in n_dense:
			_pas_un(dt / n_dense)
			if ecrase:
				return
		return
	if dt > PAS_SOL and pres_du_sol(dt):
		var n := mini(int(ceil(dt / PAS_SOL)), 2000)
		for i in n:
			_pas_un(dt / n)
	else:
		_pas_un(dt)


## Vrai si, pendant un pas de dt secondes, le vaisseau peut arriver près du sol : le pas y est alors
## découpé en morceaux de PAS_SOL (le jeu s'en sert aussi pour limiter l'accélération du temps).
func pres_du_sol(dt: float) -> bool:
	return rayon_planete > 0.0 and altitude() < HAUTEUR_DECOUPE + vitesse() * dt


const DENSE_U := 1.0e-6        # au-delà de G·M/(r·c²) = 10⁻⁶ (bord du Soleil : 2·10⁻⁶), on découpe
const MORCEAUX_DENSE_MAX := 400


func _morceaux_dense(dt: float) -> int:
	if gm == 0.0 or rayon_planete > 0.0:
		return 1
	var r := distance_centre()
	if gm / (r * C * C) < DENSE_U:
		return 1
	var t_car := r / (vitesse() + sqrt(gm / r))
	return clampi(int(ceil(dt / (0.005 * t_car))), 1, MORCEAUX_DENSE_MAX)


func _pas_un(dt: float) -> void:
	angle_planete = fposmod(angle_planete + omega_planete * dt, TAU)
	_placer_astres()
	# 1. Les moteurs suivent leur consigne avec un petit temps de réponse
	var k := clampf(dt / maxf(reactivite_moteurs, 1e-9), 0.0, 1.0)
	for m in moteurs:
		m["actuel"] = float(m["actuel"]) + (float(m["consigne"]) - float(m["actuel"])) * k

	# 1 bis. Les ailes et le train bougent à vitesse constante vers leur consigne. Les propulseurs
	# des ailes tournent avec elles : le calcul des poussées est refait avec leurs nouvelles positions.
	if ailes != ailes_consigne:
		ailes = move_toward(ailes, ailes_consigne, dt / DUREE_AILES)
		_placer_propulseurs_ailes()
		_preparer_repartition()
		_recalcul_poussee = true
	# posé sur le ventre, le train ne peut pas sortir : le sol bloque les jambes (il peut rentrer)
	if vertical != vertical_consigne:
		vertical = move_toward(vertical, vertical_consigne, dt / DUREE_VERTICAL)
		_placer_propulseurs_vertical()
		_preparer_repartition()
		_recalcul_poussee = true
	if train != train_consigne and not (au_sol and train_consigne > train):
		train = move_toward(train, train_consigne, dt / DUREE_TRAIN)
	# étape 6 (sol) : la roue avant tourne vers sa consigne à vitesse limitée (vérin de direction)
	braquage = move_toward(braquage, clampf(braquage_consigne, -1.0, 1.0) * braquage_permis(), dt * VITESSE_BRAQUAGE)

	# 2. Somme des forces et des couples, dans le repère du vaisseau
	var effet := effet_propulseurs()
	var f_corps: Vector3 = effet[0]
	var couple: Vector3 = effet[1]
	# le gradient de gravité ajoute son propre petit couple
	couple_gravite_actuel = couple_gravite()
	couple += couple_gravite_actuel
	var base := Basis(orientation)
	var a_p: Vector3 = (base * f_corps) / masse   # accélération due à la poussée (repère monde)
	# contact avec le sol : forces des ressorts du train (ou de la coque), à l'endroit où ils touchent
	au_sol = false
	if rayon_planete > 0.0:
		var sol := _forces_sol(base)
		a_p += (sol[0] as Vector3) / masse
		couple += sol[1]
	# l'air : traînée, portance (forces sur les ailes, les dérives et la coque) et échauffement
	if atmosphere != null and rayon_planete > 0.0:
		var f_air := _forces_air(base, dt)
		a_p += (base * (f_air[0] as Vector3)) / masse
		couple += f_air[1]
	else:
		densite_air = 0.0
		vitesse_air = 0.0
		force_air = Vector3.ZERO
		aero.forces(Vector3.ZERO, omega, 0.0, 1.0, ailes, train)
		_chauffer(dt, 340.0)   # loin de l'air, la coque rayonne et revient vers l'équilibre de l'espace

	# 3. Translation : méthode de Verlet (stable pour les orbites), appliquée à la vitesse propre u
	#    (relativité restreinte). À petite vitesse, c'est exactement l'ancien calcul de Newton.
	#    Einstein B : la gravité n'est plus une force, c'est la courbure de l'espace-temps (voir _pousser_u).
	if trou_de_ver != null and trou_de_ver.translater(self, a_p, dt):
		_tourner(couple, dt)   # près de la gorge du trou de ver : c'est lui qui a fait avancer le vaisseau
		return
	_lire_vitesse()
	var m0 := metrique(px, py, pz)
	var rythme0 := float(m0[0]) / gamma()
	var h := dt * 0.5
	_pousser_u(gravite(px, py, pz), a_p, h, m0)
	# vitesse « de coordonnées » : ce que les règles et les horloges lointaines mesurent. Près d'un
	# astre, l'espace est étiré (A) et le temps ralenti (N) : on y avance de u·N/(A·Γ) par seconde.
	var kx := float(m0[0]) / (float(m0[1]) * gamma())
	px += ux * kx * dt
	py += uy * kx * dt
	pz += uz * kx * dt
	var m1 := metrique(px, py, pz)
	if float(m1[0]) <= HORIZON_N:
		_tomber_dans_trou_noir()
		return
	# pendant ce trajet, c'est la quantité de mouvement p = A·u qui reste la même (géodésique)
	var ka := float(m0[1]) / float(m1[1])
	ux *= ka
	uy *= ka
	uz *= ka
	# les astres qui bougent (lune, Soleil vu de la planète) sont replacés à la fin du pas : sans ça,
	# la seconde moitié de la gravité serait comptée avec leur position du début (erreur qui grandit
	# avec la durée du pas, gênante en temps très accéléré)
	_placer_astres(temps_univers + dt)
	_pousser_u(gravite(px, py, pz), a_p, h, m1)
	_ecrire_vitesse()
	# horloges : celle du pilote avance de dt × N / Γ (N = ralentissement du temps par la gravité,
	# Γ = par la vitesse). Formule exacte d'Einstein (métrique de Schwarzschild), même près d'un trou noir.
	var rythme1 := float(m1[0]) / gamma()
	temps_univers += dt
	temps_pilote += dt * 0.5 * (rythme0 + rythme1)

	# ce que sent le pilote : poussée et sol (la gravité ne se sent pas). Posé, le sol pousse ≈ 1 g.
	acceleration_ressentie = a_p

	# 4. Rotation du corps rigide
	_tourner(couple, dt)


## Rotation : on suit le moment cinétique L (repère monde). Seul un couple le change :
## L += couple × dt (loi exacte). La vitesse de rotation s'en déduit : ω = I⁻¹·L (repère du vaisseau).
## L'ancienne méthode (on ajoutait directement dω à ω) prenait un peu d'énergie à chaque pas :
## en tournant vite ou en temps accéléré, la rotation s'emballait jusqu'à des nombres infinis,
## et la position du vaisseau devenait invalide. Ici, L ne peut grandir que si un couple agit vraiment.
## Quand le vaisseau tourne vite, le pas est découpé en petits morceaux (au plus ANGLE_SOUS_PAS
## radian chacun) pour que l'effet gyroscopique (ω × I·ω) reste précis.
const ANGLE_SOUS_PAS := 0.05     # rad parcourus au plus par sous-pas de rotation
const SOUS_PAS_MAX := 16         # limite pour rester léger, même en tournant très vite


func _tourner(couple_corps: Vector3, dt: float) -> void:
	var l_monde: Vector3 = Basis(orientation) * (inertie * omega)
	# vitesse de rotation la plus grande atteinte pendant ce pas (pour choisir le découpage)
	var w_max := omega.length() + (couple_corps / inertie).length() * dt
	var n := clampi(int(ceil(w_max * dt / ANGLE_SOUS_PAS)), 1, SOUS_PAS_MAX)
	var h := dt / n
	for i in n:
		# le couple est attaché au vaisseau : il tourne avec lui
		l_monde += Basis(orientation) * (couple_corps * h)
		# méthode du point milieu : rotation calculée avec la vitesse du milieu du sous-pas
		var w1: Vector3 = (Basis(orientation.inverse()) * l_monde) / inertie
		var q_milieu := _tourner_quaternion(orientation, w1, h * 0.5)
		var w2: Vector3 = (Basis(q_milieu.inverse()) * l_monde) / inertie
		orientation = _tourner_quaternion(orientation, w2, h)
	omega = (Basis(orientation.inverse()) * l_monde) / inertie


static func _tourner_quaternion(q: Quaternion, w: Vector3, t: float) -> Quaternion:
	var vitesse_rot := w.length()
	var angle := vitesse_rot * t
	if angle < 1e-12:
		return q
	return (q * Quaternion(w / vitesse_rot, angle)).normalized()


## Ordres du stabilisateur de rotation (de -1 à 1 sur chaque axe) pour freiner la rotation.
## Il n'agit que par les propulseurs. Son ordre reste le même pendant duree_s secondes (une image) :
## en temps accéléré, une image dure jusqu'à 8 s, et un ordre trop fort ferait tourner le vaisseau
## dans l'autre sens, de plus en plus fort. On limite donc l'ordre pour, au plus, réduire la
## rotation de moitié en une image.
const GAIN_STABILISATEUR := 6.0


func ordres_stabilisateur(duree_s: float) -> Vector3:
	var o := Vector3.ZERO
	for k in 3:
		var gain := GAIN_STABILISATEUR
		if couple_max[k] > 0.0 and duree_s > 0.0:
			gain = minf(gain, 0.5 * inertie[k] / (couple_max[k] * duree_s))
		o[k] = -omega[k] * gain
		# Ordre long (temps très accéléré) : le stabilisateur compense aussi le petit déséquilibre des
		# gros moteurs (sinon, en 14 minutes d'un seul ordre à x100 000, il ferait tourner le vaisseau).
		if duree_s > 1.0:
			o[k] -= _reste_rotation[k]
		o[k] = clampf(o[k], -1.0, 1.0)
	return o


## Contact avec le sol (idée des « points de contact » d'Orbiter, licence MIT, réécrite) :
## chaque roue est au bout d'une jambe à ressort-amortisseur. Quand la roue passe sous le sol, la
## jambe s'écrase et pousse sur le vaisseau : force = raideur × écrasement + amortissement × vitesse.
## Cette force agit à l'endroit de la roue, donc elle fait aussi tourner le vaisseau (couple).
## Le sol frotte (il freine le glissement, sans dépasser frottement × poussée du sol).
## Si la jambe arrive en bout de course trop vite, ou si la coque tape le sol trop fort : écrasé.
## Rien n'est déplacé ou arrêté directement : le sol ne fait que pousser.
## Train du modèle v27 : bas de la roue avant et des roues arrière, train sorti, amortisseurs détendus.
## Les jambes arrière partent en biais vers l'extérieur (40° de la verticale, elles passent sous les
## réacteurs d'aile, modèle v26). Depuis la v27, les patins sont remplacés par des roues freinées de
## 18 cm de rayon, montées sur une fusée 14 cm à l'extérieur du bout de la jambe : elles sont à 2,37 m
## l'une de l'autre (patins v26 : 2,09 m ; v25 : 84 cm, le vaisseau se couchait dès 3,5° de pente de
## côté). Le ressort de chaque jambe est compté ici comme un ressort vertical équivalent sous la roue.
const ROUES := [Vector3(0.0, -1.6, -4.4), Vector3(-1.184, -1.6, 2.4), Vector3(1.184, -1.6, 2.4)]   # avant, arrière gauche, arrière droit
const COURSE_TRAIN := [0.15, 0.12, 0.12]           # m : course des amortisseurs du modèle
## Amortisseurs dimensionnés pour le poids que porte chaque jambe : le centre de gravité réel est
## à 1,43 m derrière l'origine, tout près des jambes arrière, qui portent donc 86 % du vaisseau.
const RAIDEUR_TRAIN := [250000.0, 700000.0, 700000.0]  # N/m (posé : environ 5 cm à l'avant, 5 cm à l'arrière)
const AMORTI_TRAIN := [30000.0, 80000.0, 80000.0]  # N·s/m (amortisseur un peu sous le critique : pas de rebond)
const COQUE := [Vector3(-0.9, -1.0, -2.5), Vector3(0.9, -1.0, -2.5), Vector3(-0.9, -1.0, 2.5),
	Vector3(0.9, -1.0, 2.5), Vector3(0.0, -0.2, -5.6), Vector3(0.0, 0.0, 5.4)]   # ventre, nez, queue
const RAIDEUR_COQUE := 1500000.0 # N/m : la coque est dure
const AMORTI_COQUE := 60000.0
const FROTTEMENT := 0.5          # le sol freine au plus de 0,5 × la force qui appuie
const VISCOSITE_SOL := 40000.0   # N·s/m : force de freinage d'un point qui glisse
const CHOC_MAX_COQUE := 3.0      # m/s : la coque qui tape le sol plus vite que ça = écrasé
const CHOC_MAX_TRAIN := 2.0      # m/s : jambe en bout de course encore plus vite que ça = train cassé
var _touchait := {}              # points qui touchaient déjà le sol au pas précédent
## Son, phase 3 : « prise » du sol, en LECTURE SEULE. _forces_sol y note ce qui se passe sous chaque point
## (choc au contact, roulement, glissement, freins). Le son (scripts/son/capteurs.gd) la lit puis la vide.
## Rien de ce qui est écrit ici ne sert à la physique : aucun résultat ne change (test « La physique ne
## change pas » du son, et les tests de la physique). Index : roues 0 à 2, puis points de la coque 3 à 8.
const PRISE_POINTS := 9
var prise_n := 0                                               # morceaux de pas de physique notés
var prise_choc := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0])       # m/s : plus forte vitesse d'arrivée sur le sol
var prise_choc_cote := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0])  # m/s : vitesse le long du sol à ce moment
var prise_butee := PackedFloat64Array([0, 0, 0])               # m/s : amortisseur qui arrive en bout de course
var prise_fn := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0])         # N (somme) : force qui appuie sur le sol
var prise_roule := PackedFloat64Array([0, 0, 0])               # m/s (somme) : vitesse de roulement des roues
var prise_glisse := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0])     # m/s (somme) : vitesse de glissement (dérapage, raclage)
var prise_frein := PackedFloat64Array([0, 0, 0])               # (somme) serrage des freins d'une roue qui roule
var _prise_butee := PackedByteArray([0, 0, 0])                 # amortisseur déjà en bout de course (pour la prise)


## Le son lit la prise puis la vide (aucun effet sur la physique).
func vider_prise_sol() -> void:
	prise_n = 0
	for a in [prise_choc, prise_choc_cote, prise_fn, prise_glisse]:
		a.fill(0.0)
	for a in [prise_butee, prise_roule, prise_frein]:
		a.fill(0.0)
var compression_roues := PackedFloat64Array([0.0, 0.0, 0.0])   # m, écrasement de chaque amortisseur (pour le dessin)


## Frottement « accroché » : un point posé reste accroché au sol par un petit ressort de côté
## (raideur RAIDEUR_COTE) tant que la force demandée ne dépasse pas frottement × poussée du sol.
## Au-delà, il glisse (l'accroche suit). Sans cela, un vaisseau posé sur une pente glissait tout
## doucement, sans jamais s'arrêter. Les roues roulent librement dans leur direction (avec une petite
## résistance au roulement) ; de côté, le pneu accroche le sol jusqu'à ADHERENCE_PNEU × la force qui
## appuie, puis il dérape. La coque, elle, frotte dans tous les sens (FROTTEMENT).
const RAIDEUR_COTE := 100000.0   # N/m (assez souple pour rester stable avec des pas de 1/240 s)
const RESISTANCE_ROULEMENT := 0.02
## Modèle v27 : un pneu accroche mieux le sol qu'un patin ou une coque qui frotte (0,8 : pneu sur sol
## sec et dur). C'est la limite du « cercle d'adhérence » : freiner + tourner ensemble ne peut pas
## dépasser 0,8 × la force qui appuie sur la roue.
const ADHERENCE_PNEU := 0.8
## Étape 6 (sol) : rouler au sol. La roue avant est orientable (comme celle d'un avion : les palonniers
## du lacet la font tourner, jusqu'à 35°, par un vérin qui met 0,6 s pour aller au bout) et freinée
## (touche Maj). Le frein ne fait que serrer la roue : c'est le frottement du sol sur la roue qui ralentit
## le vaisseau, sans jamais dépasser ADHERENCE_PNEU × la force qui appuie sur la roue.
## Modèle v27 : les roues arrière (86 % du poids) roulent dans l'axe du vaisseau et sont freinées elles
## aussi (Maj serre les trois freins) : le vaisseau freine beaucoup mieux, et il roule droit tout seul
## (train tricycle : les roues arrière, derrière le centre de gravité, le ramènent dans l'axe).
## Frein de parc automatique (comme le « auto hold » d'une voiture) : vaisseau au sol presque arrêté
## (moins de 0,3 m/s par rapport au sol) et gaz à zéro, les freins se serrent tout seuls ; ils se
## desserrent dès qu'on remet les gaz. Sans lui, posé sur une pente, le vaisseau partirait en roue libre.
const BRAQUAGE_MAX := deg_to_rad(35.0)   # rad
## v27 : avec les roues arrière qui accrochent, un virage serré trop vite ferait basculer le vaisseau
## (centre de gravité haut, 1,6 m au-dessus du sol, pour 2,37 m entre les roues arrière). Comme sur un
## vrai avion (palonniers : beaucoup de braquage à l'arrêt, quelques degrés en vitesse), le vérin de
## direction braque de moins en moins vite qu'on roule : virage à au plus ACCEL_VIRAGE (0,3 g).
const ACCEL_VIRAGE := 3.0                # m/s²
const EMPATTEMENT := 6.8                 # m, entre la roue avant et les roues arrière


## Braquage le plus grand que le vérin donne à cette vitesse (rad).
func braquage_permis() -> float:
	var v2 := vitesse_par_rapport_au_sol().length_squared()
	return minf(BRAQUAGE_MAX, atan(EMPATTEMENT * ACCEL_VIRAGE / maxf(v2, 1e-6)))
const VITESSE_BRAQUAGE := deg_to_rad(60.0)   # rad/s
var braquage_consigne := 0.0     # -1 (droite) à 1 (gauche), donné par le lacet quand on est au sol
var braquage := 0.0              # rad, angle réel de la roue avant (positif = vers la gauche)
var frein := 0.0                 # 0 à 1 : serrage des freins des roues (Maj)
var frein_parc := false          # frein de parc automatique serré (voir plus haut)
var gaz_demande := 0.0           # dernier ordre de gaz (0 à 1), pour le frein de parc
const VITESSE_PARC := 0.3        # m/s : en dessous, gaz à zéro, le frein de parc se serre
const PAS_PENTE := 0.25          # m : écart pour mesurer la pente du sol sous un point
var _accroches := {}             # point → position de son accroche au sol (repère de la planète)


## Renvoie [force (repère monde), couple (repère du vaisseau)].
## Chaque point qui touche prend le sol sous LUI (pas au centre du vaisseau) et sa vraie pente :
## sur un sol en pente, le sol pousse perpendiculairement à la pente.
func _forces_sol(base: Basis) -> Array:
	var f_monde := Vector3.ZERO
	var couple := Vector3.ZERO
	var r_c := sqrt(px * px + py * py + pz * pz)
	# relief du sol sous le vaisseau : s'il est loin, rien à calculer
	var r_sol := rayon_planete + hauteur_sol(px, py, pz)
	if r_c - r_sol > 15.0:
		_touchait.clear()
		_accroches.clear()
		_sol_connu.clear()
		return [f_monde, couple]
	var vit := Vector3(vx, vy, vz)
	# frein de parc : il se serre posé, presque arrêté, gaz à zéro ; il se desserre dès qu'on remet les gaz
	if gaz_demande > 0.01 or _touchait.is_empty():
		frein_parc = false
	elif not frein_parc:
		# vitesse horizontale par rapport au sol (celle de la chute au moment du posé ne compte pas)
		var v_rel := vit - Vector3(omega_planete * pz, 0.0, -omega_planete * px)
		var haut := Vector3(px, py, pz) / r_c
		frein_parc = (v_rel - haut * v_rel.dot(haut)).length() < VITESSE_PARC
	var serrage := 1.0 if frein_parc else clampf(frein, 0.0, 1.0)
	var points := []
	compression_roues.fill(0.0)
	if train >= 1.0:
		for k in ROUES.size():
			points.append([ROUES[k], k, k])
	for i in COQUE.size():
		points.append([COQUE[i], -1, 10 + i])
	var deja := _touchait
	_touchait = {}
	var accroches := _accroches
	_accroches = {}
	var avant: Vector3 = base * Vector3(0.0, 0.0, -1.0)
	prise_n += 1   # prise du son (lecture seule)
	for pt in points:
		var r_corps: Vector3 = (pt[0] as Vector3) - CENTRE_GRAVITE   # vu du centre de gravité
		var k_roue: int = pt[1]
		var roue := k_roue >= 0
		var r_monde: Vector3 = base * r_corps
		# position du point (double précision) et sol juste sous lui
		var qx := px + r_monde.x
		var qy := py + r_monde.y
		var qz := pz + r_monde.z
		var dq := sqrt(qx * qx + qy * qy + qz * qz)
		var cle: int = pt[2]   # numéro du point (roue 0-2, coque 10-15)
		var ici := _vers_planete_64(qx, qy, qz)   # 64 bits : un Vector3 (32 bits) à 600 km ne voit pas 6 cm
		var sol_ici := _sol_sous(cle, ici, qx, qy, qz, false)
		var h := dq - rayon_planete - float(sol_ici[0])
		if h >= 0.0:
			if roue:
				_prise_butee[k_roue] = 0   # prise du son : roue en l'air
			continue
		var up := Vector3(qx / dq, qy / dq, qz / dq)
		var n: Vector3 = _sol_sous(cle, ici, qx, qy, qz, true)[1]
		# enfoncement mesuré perpendiculairement à la pente
		var c := -h * up.dot(n)
		# vitesse du point par rapport au sol (le sol tourne avec la planète)
		var v_sol := Vector3(omega_planete * qz, 0.0, -omega_planete * qx)
		var v_point: Vector3 = vit + base * omega.cross(r_corps) - v_sol
		var vn := v_point.dot(n)
		if not deja.has(cle) and vn < 0.0:
			if deja.is_empty() and _touchait.is_empty():
				vitesse_impact = 0.0   # premier point qui touche : nouveau posé
			vitesse_impact = maxf(vitesse_impact, -vn)
			# prise du son : choc au contact (vitesse d'arrivée, et le long du sol pour le crissement du pneu)
			var ip := k_roue if roue else cle - 7
			if -vn > prise_choc[ip]:
				prise_choc[ip] = -vn
				prise_choc_cote[ip] = (v_point - n * vn).length()
			if not roue and -vn > CHOC_MAX_COQUE:
				ecrase = true
		_touchait[cle] = true
		var fn := 0.0
		if roue:
			var course: float = COURSE_TRAIN[k_roue]
			compression_roues[k_roue] = minf(c, course)
			fn = float(RAIDEUR_TRAIN[k_roue]) * minf(c, course) - float(AMORTI_TRAIN[k_roue]) * vn
			if c > course:
				# amortisseur en bout de course : la jambe devient dure
				fn += RAIDEUR_COQUE * (c - course) - AMORTI_COQUE * vn
				if -vn > CHOC_MAX_TRAIN:
					ecrase = true
				if _prise_butee[k_roue] == 0:
					prise_butee[k_roue] = maxf(prise_butee[k_roue], -vn)   # prise du son
				_prise_butee[k_roue] = 1
			else:
				_prise_butee[k_roue] = 0
		else:
			fn = RAIDEUR_COQUE * c - AMORTI_COQUE * vn
		fn = maxf(fn, 0.0)
		if fn <= 0.0:
			continue
		au_sol = true
		# frottement : ressort d'accroche + amortisseur, limité à frottement × fn
		var accroche: PackedFloat64Array = accroches.get(cle, ici)
		var ecart := _depuis_planete(Vector3(ici[0] - accroche[0], ici[1] - accroche[1], ici[2] - accroche[2]))
		ecart -= n * ecart.dot(n)
		var vt := v_point - n * vn
		var axe_roule := Vector3.ZERO
		if roue and not frein_parc:
			# chaque roue roule dans sa direction : la roue avant selon son braquage, les roues arrière
			# (v27) dans l'axe du vaisseau ; direction projetée sur le sol
			var dir_roue: Vector3 = base * Vector3(-sin(braquage), 0.0, -cos(braquage)) if k_roue == 0 and braquage != 0.0 else avant
			axe_roule = dir_roue - n * dir_roue.dot(n)
			if axe_roule.length() > 1e-6:
				axe_roule = axe_roule.normalized()
				ecart -= axe_roule * ecart.dot(axe_roule)
				vt -= axe_roule * vt.dot(axe_roule)
		var ft := -ecart * RAIDEUR_COTE - vt * VISCOSITE_SOL
		# frein de parc serré : la roue bloquée est accrochée au sol dans tous les sens (comme un patin),
		# jusqu'à l'adhérence du pneu
		var ft_max := (ADHERENCE_PNEU if roue else FROTTEMENT) * fn
		if ft.length() > ft_max:
			prise_glisse[k_roue if roue else cle - 7] += vt.length()   # prise du son : ça dérape ou ça racle
			# ça glisse : la force est limitée et l'accroche suit le point
			ft = ft.normalized() * ft_max
			var e_ok := ecart.normalized() * minf(ecart.length(), ft_max / RAIDEUR_COTE)
			var e_p := _vers_planete_dir(e_ok)
			accroche = PackedFloat64Array([ici[0] - e_p.x, ici[1] - e_p.y, ici[2] - e_p.z])
		elif axe_roule != Vector3.ZERO:
			# la roue qui roule n'est accrochée au sol que de côté : l'accroche avance avec elle
			var e_cote := _vers_planete_dir(ecart)
			accroche = PackedFloat64Array([ici[0] - e_cote.x, ici[1] - e_cote.y, ici[2] - e_cote.z])
		_accroches[cle] = accroche
		if axe_roule != Vector3.ZERO:
			# le long de la roue : résistance au roulement + frein, comme un frottement « visqueux » qui
			# ne dépasse pas (résistance + frein × adhérence) × la force qui appuie (pas de rebond à l'arrêt)
			var v_roule := v_point.dot(axe_roule)
			var mu_roule := RESISTANCE_ROULEMENT + serrage * ADHERENCE_PNEU
			ft += axe_roule * clampf(-v_roule * VISCOSITE_SOL, -mu_roule * fn, mu_roule * fn)
			# la roue ne peut pas accrocher le sol plus fort que le pneu (déraper de côté + freiner)
			var ft_roue := (ADHERENCE_PNEU + RESISTANCE_ROULEMENT) * fn
			if ft.length() > ft_roue:
				ft = ft.normalized() * ft_roue
				if serrage > 0.95:
					prise_glisse[k_roue] += absf(v_roule)   # prise du son : roue bloquée par le frein, qui glisse
			prise_roule[k_roue] += absf(v_roule)   # prise du son (lecture seule)
			prise_frein[k_roue] += serrage
		prise_fn[k_roue if roue else cle - 7] += fn   # prise du son (lecture seule)
		var f: Vector3 = n * fn + ft
		f_monde += f
		couple += r_corps.cross(base.inverse() * f)
	return [f_monde, couple]


## Sol sous un point du vaisseau : [hauteur du relief, normale (repère de la physique)].
## Chaque question au relief coûte cher (partie C++ de la planète, 5 questions pour la normale) et
## _forces_sol en pose une vingtaine à chaque morceau de 1/240 s. Quand le point n'a presque pas bougé
## sur le sol (moins de 1 mm, par exemple vaisseau posé), on reprend la réponse précédente : l'erreur
## reste sous le millimètre, bien moins que l'écrasement des amortisseurs (5 cm).
const BOUGE_SOL := 0.001          # m
var _sol_connu := {}              # point → [position (repère de la planète), hauteur, normale (repère de la planète) ou null]
var _sol_relief := Callable()
var _sol_rayon := 0.0


func _sol_sous(cle: int, ici: PackedFloat64Array, x: float, y: float, z: float, avec_normale: bool) -> Array:
	if relief != _sol_relief or rayon_planete != _sol_rayon:   # autre astre (lune) ou autre sol : on oublie tout
		_sol_connu.clear()
		_sol_relief = relief
		_sol_rayon = rayon_planete
	var c: Array = _sol_connu.get(cle, [])
	if c.is_empty() or _ecart2(c[0], ici) > BOUGE_SOL * BOUGE_SOL:
		c = [ici, hauteur_sol(x, y, z), null]
		_sol_connu[cle] = c
	if avec_normale and c[2] == null:
		c[2] = _vers_planete_dir(normale_sol(x, y, z))
	return [c[1], _depuis_planete(c[2]) if c[2] != null else Vector3.ZERO]


## L'air autour du vaisseau : renvoie [force (repère du vaisseau), couple] et fait chauffer le nez.
func _forces_air(base: Basis, dt: float) -> Array:
	var z := distance_centre() - rayon_planete
	var et: Array = atmosphere.etat(z)
	densite_air = et[0]
	temperature_air = et[1]
	var v_rel := Vector3(vx, vy, vz) - vitesse_sol(px, py, pz)   # l'air tourne avec la planète
	vitesse_air = v_rel.length()
	var res: Array = [Vector3.ZERO, Vector3.ZERO]
	if densite_air > 0.0:
		res = aero.forces(base.inverse() * (-v_rel), omega, densite_air, float(et[3]), ailes, train)
	else:
		aero.forces(Vector3.ZERO, omega, 0.0, 1.0, ailes, train)
	force_air = res[0]
	_chauffer(dt, float(et[3]))
	return res


func _chauffer(dt: float, son: float) -> void:
	var t := temperature_nez
	var v := vitesse_air
	var rho := densite_air
	var q := 0.0
	if rho > 0.0:
		var m := v / maxf(son, 1.0)
		var t_r := temperature_air * (1.0 + 0.18 * m * m)   # température de l'air arrêté contre le nez
		var froid := SUTTON_GRAVES * sqrt(rho / RAYON_NEZ) * v * v * v
		# paroi chaude : elle reçoit moins (rien quand elle est à la température de l'air arrêté)
		q = froid * (t_r - t) / maxf(t_r - 300.0, 50.0)
		# à petite vitesse, l'air échange aussi sa chaleur par simple contact (nombre de Stanton ≈ 0,001)
		var contact := 0.001 * rho * v * 1005.0 * (t_r - t)
		if absf(contact) > absf(q):
			q = contact
	flux_nez = q
	# rayonnement : vers l'air ambiant en bas, vers l'espace (équilibre moyen) en haut
	var part_air := clampf(rho / 0.01, 0.0, 1.0)
	var t_env := lerpf(T_ESPACE, temperature_air, part_air) if rho > 0.0 else T_ESPACE
	var n := maxi(1, ceili(dt / 2.0))   # pas de 2 s au plus (temps accéléré)
	var h := dt / n
	for i in n:
		var ray := EMISSIVITE * SIGMA * (t_env ** 4 - t ** 4)
		t = maxf(t + (q + ray) * h / CAPACITE_COQUE, 3.0)
	temperature_nez = t


## Plus long pas de calcul (s) qui reste précis dans l'air : la traînée et l'amortissement de la rotation
## par les ailes agissent vite près du sol ; avec des pas trop longs (temps accéléré), le calcul
## « rebondirait » (il deviendrait faux). INF hors de l'air.
func pas_max_air() -> float:
	if atmosphere == null or rayon_planete <= 0.0:
		return INF
	var rho: float = atmosphere.densite(distance_centre() - rayon_planete)
	if rho <= 0.0:
		return INF
	var v := maxf((Vector3(vx, vy, vz) - vitesse_sol(px, py, pz)).length(), 1.0)
	# translation : masse / (ρ·v·surface) ; rotation (roulis, le plus vif) : inertie / (½ρ·v·pente·surface·bras²)
	var t_lin := masse / (rho * v * 60.0)
	var t_rot := minf(inertie.z, minf(inertie.x, inertie.y)) / (0.5 * rho * v * 4.2 * 52.0 * 9.0)
	return 0.3 * minf(t_lin, t_rot)


## Direction perpendiculaire au sol (pente comprise) au point (x, y, z), repère monde.
func normale_sol(x: float, y: float, z: float) -> Vector3:
	var d := sqrt(x * x + y * y + z * z)
	var up := Vector3(x / d, y / d, z / d)
	if not relief.is_valid():
		return up
	var t1 := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := up.cross(t1)
	var e := PAS_PENTE
	var g1 := (hauteur_sol(x + t1.x * e, y + t1.y * e, z + t1.z * e) - hauteur_sol(x - t1.x * e, y - t1.y * e, z - t1.z * e)) / (2.0 * e)
	var g2 := (hauteur_sol(x + t2.x * e, y + t2.y * e, z + t2.z * e) - hauteur_sol(x - t2.x * e, y - t2.y * e, z - t2.z * e)) / (2.0 * e)
	return (up - t1 * g1 - t2 * g2).normalized()


## Repère de la planète (qui tourne de angle_planete autour de Y) ↔ repère de la physique (fixe).
func _vers_planete(x: float, y: float, z: float) -> Vector3:
	var c := cos(angle_planete)
	var s := sin(angle_planete)
	return Vector3(c * x - s * z, y, s * x + c * z)


## La même chose en 64 bits (positions : à 600 km du centre, un Vector3 ne voit que des pas de 6 cm).
func _vers_planete_64(x: float, y: float, z: float) -> PackedFloat64Array:
	var c := cos(angle_planete)
	var s := sin(angle_planete)
	return PackedFloat64Array([c * x - s * z, y, s * x + c * z])


static func _ecart2(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var dx := a[0] - b[0]
	var dy := a[1] - b[1]
	var dz := a[2] - b[2]
	return dx * dx + dy * dy + dz * dz


func _vers_planete_dir(v: Vector3) -> Vector3:
	return _vers_planete(v.x, v.y, v.z)


func _depuis_planete(v: Vector3) -> Vector3:
	var c := cos(angle_planete)
	var s := sin(angle_planete)
	return Vector3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z)


# =====================================================================
# MESURES (pour les instruments)
# =====================================================================
# =====================================================================
# RELATIVITÉ
# =====================================================================
## Einstein B : LA GRAVITÉ D'EINSTEIN. Chaque astre courbe l'espace-temps autour de lui (solution exacte
## de Schwarzschild, 1916, écrite en coordonnées « isotropes ») :
##     ds² = −N² c² dt² + A² (dx² + dy² + dz²),   N = (1 − U/2) / (1 + U/2),   A = (1 + U/2)²,
## avec U = Σ G·M / (r·c²) (somme sur les astres ; exact pour un astre seul, très précis pour plusieurs
## tant que U est petit). N < 1 : le temps passe moins vite près d'un astre. A > 1 : l'espace y est étiré.
## Le vaisseau suit une « géodésique » de cet espace-temps (le chemin le plus droit possible) : plus de
## force de gravité. On suit p = A·u (u = vitesse propre mesurée sur place), qui change de :
##   gravité : dp/dt = g · [Γ / (1 + U/2)² + N·u² / (c²·(1 + U/2)·Γ)]    (g = gravité de Newton)
##             À petite vitesse et loin des trous noirs, c'est exactement Newton (dp/dt = g). Le second
##             terme double la déviation de la lumière (Einstein, 1915) ; les deux ensemble font tourner
##             lentement les orbites (avance du périhélie, comme celle de Mercure).
##   poussée : a_p = poussée / masse, ce que sent le pilote. Vue sur place, elle est « transformée de
##             Lorentz » : du/dτ = a_p + (Γ − 1)(a_p·n)n, n = direction du mouvement, puis × N/Γ (dτ/dt).
## m = metrique(x, y, z) au point où l'on est (évite de la recalculer).
func _pousser_u(g: Array, a_p: Vector3, h: float, m: Array) -> void:
	var gam := gamma()
	var n_lapse := float(m[0])
	var a_esp := float(m[1])
	var q := float(m[2])     # 1 + U/2
	var axp := a_p.x
	var ayp := a_p.y
	var azp := a_p.z
	var u2 := ux * ux + uy * uy + uz * uz
	if u2 > 0.0 and gam > 1.0:
		var u_l := sqrt(u2)
		var nx := ux / u_l
		var ny := uy / u_l
		var nz := uz / u_l
		var k := (gam - 1.0) * (axp * nx + ayp * ny + azp * nz)
		axp += k * nx
		ayp += k * ny
		azp += k * nz
	# du/dt = (dp/dt) / A ; u2/C² écrit à part pour rester précis à petite vitesse
	var kg := (gam / (q * q) + n_lapse * u2 / (C * C * q * gam)) / a_esp
	var kp := n_lapse / gam
	ux += (kg * float(g[0]) + axp * kp) * h
	uy += (kg * float(g[1]) + ayp * kp) * h
	uz += (kg * float(g[2]) + azp * kp) * h


## Métrique au point (x, y, z) : [N (rythme du temps), A (étirement de l'espace), 1 + U/2, U].
## U = G·M / (r·c²) : 7·10⁻¹⁰ au sol de la Terre, 2·10⁻⁶ au bord du Soleil, 2 à l'horizon d'un trou noir.
func metrique(x: float, y: float, z: float) -> Array:
	var u_pot := -potentiel(x, y, z) / (C * C)
	var q := 1.0 + 0.5 * u_pot
	return [(1.0 - 0.5 * u_pot) / q, q * q, q, u_pot]


## Rythme du temps ici (sans la vitesse) : secondes d'une horloge immobile ici pour une seconde loin de
## tout astre. 1 − 7·10⁻¹⁰ sur la Terre (le GPS doit en tenir compte), 0 à l'horizon d'un trou noir.
func rythme_gravite() -> float:
	return float(metrique(px, py, pz)[0])


## Rythme de l'horloge du pilote : secondes du pilote par seconde de l'univers (gravité ET vitesse).
func rythme_pilote() -> float:
	return rythme_gravite() / gamma()


## Le temps « s'arrête » à l'horizon d'un trou noir (N = 0) : en dessous de ce rythme, le vaisseau est
## considéré comme passé de l'autre côté (vu de loin, il ne finit jamais d'y tomber ; pour le pilote,
## il le traverse en un instant, et plus rien ne peut en ressortir, pas même la lumière).
const HORIZON_N := 1.0e-3
var avale := false   # tombé dans un trou noir


func _tomber_dans_trou_noir() -> void:
	avale = true
	ecrase = true
	vitesse_impact = C
	ux = 0.0
	uy = 0.0
	uz = 0.0
	_ecrire_vitesse()


## Marée (m/s² par mètre) : différence de gravité entre le nez et la queue du vaisseau, par mètre.
## 2·G·M/r³ pour l'astre le plus proche (Newton suffit : c'est elle qui étire le vaisseau).
func maree() -> float:
	var m := 0.0
	if gm != 0.0:
		var r := distance_centre()
		m = 2.0 * gm / (r * r * r)
	for a in autres_astres:
		var d := sqrt((px - float(a["x"])) ** 2 + (py - float(a["y"])) ** 2 + (pz - float(a["z"])) ** 2)
		m = maxf(m, 2.0 * float(a["gm"]) / (d * d * d))
	return m


## Si quelqu'un a changé la vitesse v de l'extérieur (placer en orbite, tests, pilote auto…),
## on recalcule la vitesse propre à partir d'elle. Sinon on garde u, plus précise près de C.
func _lire_vitesse() -> void:
	if vx == _v_connue[0] and vy == _v_connue[1] and vz == _v_connue[2]:
		return
	var v2 := vx * vx + vy * vy + vz * vz
	var b2 := minf(v2 / (C * C), 1.0 - 1e-15)   # une vitesse écrite à la main ne peut pas atteindre C
	var gam := 1.0 / sqrt(1.0 - b2)
	var k := gam
	if v2 / (C * C) > b2:
		k *= sqrt(b2 * C * C / v2)
	ux = vx * k
	uy = vy * k
	uz = vz * k
	_ecrire_vitesse()


func _ecrire_vitesse() -> void:
	var ig := 1.0 / _gamma_u()
	vx = ux * ig
	vy = uy * ig
	vz = uz * ig
	_v_connue[0] = vx
	_v_connue[1] = vy
	_v_connue[2] = vz


## Facteur de Lorentz γ (1 au repos, 2,29 à 0,9 c, 7,09 à 0,99 c) : de combien l'horloge du pilote
## retarde, et de combien l'énergie de mouvement dépasse celle de Newton.
func gamma() -> float:
	_lire_vitesse()
	return _gamma_u()


func _gamma_u() -> float:
	return sqrt(1.0 + (ux * ux + uy * uy + uz * uz) / (C * C))


## Vitesse en fraction de celle de la lumière (0 à 1, jamais 1).
func beta() -> float:
	return vitesse() / C


## Rapidité (sans unité) : elle, s'additionne simplement à chaque poussée. Vitesse = C × tanh(rapidité).
func rapidite() -> float:
	_lire_vitesse()
	var u := sqrt(ux * ux + uy * uy + uz * uz)
	return log(u / C + sqrt(1.0 + u * u / (C * C)))   # asinh(u / C)


## Énergie de mouvement (J) : (γ − 1)·m·C², qui devient ½·m·v² à petite vitesse.
func energie_mouvement() -> float:
	var gam := gamma()
	var u2 := ux * ux + uy * uy + uz * uz
	# (γ − 1) écrit sans soustraction, pour rester précis à petite vitesse
	return masse * u2 / (gam + 1.0)


## Potentiel de gravité Φ (m²/s², négatif) : sert à l'horloge (au fond d'un puits, le temps passe moins vite).
func potentiel(x: float, y: float, z: float) -> float:
	var phi := 0.0
	if gm != 0.0:
		phi -= gm / sqrt(x * x + y * y + z * z)
	for a in autres_astres:
		var dx: float = x - float(a["x"])
		var dy: float = y - float(a["y"])
		var dz: float = z - float(a["z"])
		phi -= float(a["gm"]) / sqrt(dx * dx + dy * dy + dz * dz)
	return phi


func distance_centre() -> float:
	return sqrt(px * px + py * py + pz * pz)


func altitude() -> float:
	return distance_centre() - rayon_planete - hauteur_sol(px, py, pz)


## Hauteur du sol (m au-dessus de rayon_planete) sous la direction (x, y, z) ; 0 sans relief.
func hauteur_sol(x: float, y: float, z: float) -> float:
	if relief.is_valid():
		if angle_planete == 0.0:
			return float(relief.call(x, y, z))
		var c := cos(angle_planete)
		var s := sin(angle_planete)
		return float(relief.call(c * x - s * z, y, s * x + c * z))
	return 0.0


func vitesse() -> float:
	return sqrt(vx * vx + vy * vy + vz * vz)


## Vitesse du sol qui tourne sous le point (x, y, z) (m/s, repère de la physique).
func vitesse_sol(x: float, y: float, z: float) -> Vector3:
	return Vector3(omega_planete * z, 0.0, -omega_planete * x)


## Vitesse du vaisseau par rapport au sol qui tourne sous lui (c'est elle qui compte pour se poser).
func vitesse_par_rapport_au_sol() -> Vector3:
	return Vector3(vx, vy, vz) - vitesse_sol(px, py, pz)


func vitesse_verticale() -> float:
	var r := distance_centre()
	return (vx * px + vy * py + vz * pz) / r if r > 0.0 else 0.0


func vitesse_horizontale() -> float:
	var v := vitesse()
	var vv := vitesse_verticale()
	return sqrt(maxf(0.0, v * v - vv * vv))


## Vitesse horizontale par rapport au sol (qui tourne avec la planète).
func vitesse_horizontale_sol() -> float:
	var v := vitesse_par_rapport_au_sol().length()
	var vv := vitesse_verticale()
	return sqrt(maxf(0.0, v * v - vv * vv))


func energie_specifique() -> float:
	return vitesse() * vitesse() * 0.5 - gm / distance_centre()


func moment_cinetique_monde() -> Vector3:
	return Basis(orientation) * Vector3(inertie.x * omega.x, inertie.y * omega.y, inertie.z * omega.z)


## Orbite actuelle : périapside et apoapside (altitudes, en m). apo = INF si on s'échappe.
func orbite() -> Dictionary:
	var r := distance_centre()
	var e_spec := energie_specifique()
	# moment cinétique orbital h = r × v (double précision)
	var hx := py * vz - pz * vy
	var hy := pz * vx - px * vz
	var hz := px * vy - py * vx
	var h2 := hx * hx + hy * hy + hz * hz
	var ecc := sqrt(maxf(0.0, 1.0 + 2.0 * e_spec * h2 / (gm * gm)))
	if e_spec >= 0.0:
		return {"peri": h2 / (gm * (1.0 + ecc)) - rayon_planete, "apo": INF, "excentricite": ecc}
	var a := -gm / (2.0 * e_spec)
	return {"peri": a * (1.0 - ecc) - rayon_planete, "apo": a * (1.0 + ecc) - rayon_planete, "excentricite": ecc}


## Grandes distances : durée (s de l'univers) qu'une image peut couvrir pour que le vaisseau ne fasse pas
## plus de « part » du chemin qui le sépare de l'astre le plus proche (en temps) : distance au sol de
## l'astre ÷ (vitesse par rapport à lui + vitesse de chute √(2·G·M/r)). Sert à limiter le temps accéléré
## au-delà de x100 000. astre_limitant = nom de l'astre qui limite.
var astre_limitant := ""


func limite_temps(part: float) -> float:
	var v := vitesse()
	var meilleur := INF
	astre_limitant = ""
	if gm > 0.0:
		var r := distance_centre()
		var t := maxf(r - rayon_planete, 1e-3 * r) / (v + sqrt(2.0 * gm / r))
		if t < meilleur:
			meilleur = t
			astre_limitant = "planète" if rayon_planete > 0.0 else "étoile"
	for a in autres_astres:
		var dx := px - float(a["x"])
		var dy := py - float(a["y"])
		var dz := pz - float(a["z"])
		var r := sqrt(dx * dx + dy * dy + dz * dz)
		var w := Vector3(vx, vy, vz)
		if a.has("position"):   # astre qui bouge : sa vitesse, mesurée sur une minute
			var f: Callable = a["position"]
			var p0: PackedFloat64Array = f.call(temps_univers - 30.0)
			var p1: PackedFloat64Array = f.call(temps_univers + 30.0)
			w -= Vector3(p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]) / 60.0
		var t := maxf(r - float(a.get("rayon", 0.0)), 1e-3 * r) / (w.length() + sqrt(2.0 * float(a["gm"]) / r))
		if t < meilleur:
			meilleur = t
			astre_limitant = String(a["nom"])
	if trou_de_ver != null:
		var d: float = trou_de_ver.distance_gorge(self)
		var t2 := d / maxf(v, 1.0)
		if t2 < meilleur:
			meilleur = t2
			astre_limitant = "trou de ver"
	return part * meilleur


## Vitesse d'une orbite circulaire à la distance r (coordonnées isotropes), mesurée sur place, selon
## Einstein : v² = G·M / (R·(1 − 2·G·M/(R·c²))), R = r·(1 + G·M/(2·r·c²))² (rayon « de Schwarzschild »).
## Loin des trous noirs, c'est √(G·M/r), comme Newton. Plus d'orbite possible sous 3 fois le rayon de
## l'horizon (R < 6·G·M/c²) : la vitesse dépasserait la moitié de celle de la lumière et l'orbite tomberait.
func vitesse_circulaire(r: float) -> float:
	var m := gm / (C * C)
	var r_s := r * (1.0 + 0.5 * m / r) ** 2
	return sqrt(gm / (r_s * maxf(1.0 - 2.0 * m / r_s, 1e-9)))


## Place le vaisseau en orbite circulaire, nez dans le sens du déplacement.
func placer_en_orbite(altitude_m: float) -> void:
	var r := rayon_planete + altitude_m
	px = r
	py = 0.0
	pz = 0.0
	vx = 0.0
	vy = 0.0
	vz = -vitesse_circulaire(r)
	_lire_vitesse()
	avale = false
	temps_univers = 0.0
	temps_pilote = 0.0
	orientation = Quaternion.IDENTITY   # l'avant (-Z) est déjà dans le sens de la vitesse
	omega = Vector3.ZERO
	au_sol = false
	ecrase = false
	vitesse_impact = 0.0
	temperature_nez = 290.0
	_touchait.clear()
	_accroches.clear()
	for m in moteurs:
		m["consigne"] = 0.0
		m["actuel"] = 0.0
	# ailes ouvertes, train rentré
	ailes = 1.0
	ailes_consigne = 1.0
	train = 0.0
	train_consigne = 0.0
	braquage = 0.0
	braquage_consigne = 0.0
	frein = 0.0
	vertical = 0.0
	vertical_consigne = 0.0
	_placer_propulseurs_ailes()
	_placer_propulseurs_vertical()
	_preparer_repartition()
	_calculer_poussee_max()
