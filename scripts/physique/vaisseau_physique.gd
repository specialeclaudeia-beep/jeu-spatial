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
## pièce (modele3d/v25_cockpit_detaille/masses_godot.json) : ailes ouvertes, train rentré, droïde à
## bord, sans carburant (le jeu n'en a pas, la masse ne change donc jamais).
var masse := 8458.5                                    # kg
var inertie := Vector3(68054.9, 81433.9, 19250.2)      # kg·m² autour du centre de gravité : tangage (X), lacet (Y), roulis (Z)
## Centre de gravité dans le repère du modèle 3D : 1,45 m derrière son origine (moteurs lourds à l'arrière).
## Le vaisseau tourne autour de ce point : tous les couples (propulseurs, sol) sont calculés par rapport à lui.
## px, py, pz = position du centre de gravité.
const CENTRE_GRAVITE := Vector3(0.0, 0.02, 1.448)
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
func ajouter_astre_mobile(nom: String, gm_astre: float, position: Callable) -> void:
	var p: PackedFloat64Array = position.call(temps_univers)
	autres_astres.append({"nom": nom, "gm": gm_astre, "x": p[0], "y": p[1], "z": p[2], "position": position,
		"indirect": true})


func _placer_astres() -> void:
	for a in autres_astres:
		if a.has("position"):
			var p: PackedFloat64Array = (a["position"] as Callable).call(temps_univers)
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


func pas(dt: float) -> void:
	if rayon_planete > 0.0 and dt > PAS_SOL and altitude() < HAUTEUR_DECOUPE + vitesse() * dt:
		var n := mini(int(ceil(dt / PAS_SOL)), 2000)
		for i in n:
			_pas_un(dt / n)
	else:
		_pas_un(dt)


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

	# 3. Translation : méthode de Verlet (stable pour les orbites), appliquée à la vitesse propre u
	#    (relativité restreinte). À petite vitesse, c'est exactement l'ancien calcul de Newton.
	_lire_vitesse()
	var inv_g0 := 1.0 / gamma()
	var phi0 := potentiel(px, py, pz)
	var h := dt * 0.5
	_pousser_u(gravite(px, py, pz), a_p, h)
	var ig := 1.0 / gamma()
	px += ux * ig * dt
	py += uy * ig * dt
	pz += uz * ig * dt
	_pousser_u(gravite(px, py, pz), a_p, h)
	_ecrire_vitesse()
	# horloges : celle du pilote avance de dt / γ (vitesse) × √(1 + 2Φ/C²) (gravité)
	var inv_g1 := 1.0 / gamma()
	var phi := 0.5 * (phi0 + potentiel(px, py, pz))
	temps_univers += dt
	temps_pilote += dt * 0.5 * (inv_g0 + inv_g1) * sqrt(maxf(0.0, 1.0 + 2.0 * phi / (C * C)))

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
## Train du modèle v20 : bas de la roue avant et des patins arrière, train sorti, amortisseurs détendus.
const ROUES := [Vector3(0.0, -1.6, -4.4), Vector3(-0.42, -1.6, 2.4), Vector3(0.42, -1.6, 2.4)]   # avant, arrière gauche, arrière droit
const COURSE_TRAIN := [0.15, 0.12, 0.12]           # m : course des amortisseurs du modèle
## Amortisseurs dimensionnés pour le poids que porte chaque jambe : le centre de gravité réel est
## à 1,45 m derrière l'origine, tout près des jambes arrière, qui portent donc 86 % du vaisseau.
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
var compression_roues := PackedFloat64Array([0.0, 0.0, 0.0])   # m, écrasement de chaque amortisseur (pour le dessin)


## Frottement « accroché » : un point posé reste accroché au sol par un petit ressort de côté
## (raideur RAIDEUR_COTE) tant que la force demandée ne dépasse pas frottement × poussée du sol.
## Au-delà, il glisse (l'accroche suit). Sans cela, un vaisseau posé sur une pente glissait tout
## doucement, sans jamais s'arrêter. La roue avant roule librement dans l'axe du vaisseau (avec une
## petite résistance au roulement) ; les patins arrière frottent dans tous les sens.
const RAIDEUR_COTE := 100000.0   # N/m (assez souple pour rester stable avec des pas de 1/240 s)
const RESISTANCE_ROULEMENT := 0.02
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
		return [f_monde, couple]
	var vit := Vector3(vx, vy, vz)
	var points := []
	compression_roues.fill(0.0)
	if train >= 1.0:
		for k in ROUES.size():
			points.append([ROUES[k], k])
	for r in COQUE:
		points.append([r, -1])
	var deja := _touchait
	_touchait = {}
	var accroches := _accroches
	_accroches = {}
	var avant: Vector3 = base * Vector3(0.0, 0.0, -1.0)
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
		var h := dq - rayon_planete - hauteur_sol(qx, qy, qz)
		if h >= 0.0:
			continue
		var up := Vector3(qx / dq, qy / dq, qz / dq)
		var n := normale_sol(qx, qy, qz)
		# enfoncement mesuré perpendiculairement à la pente
		var c := -h * up.dot(n)
		# vitesse du point par rapport au sol (le sol tourne avec la planète)
		var v_sol := Vector3(omega_planete * qz, 0.0, -omega_planete * qx)
		var v_point: Vector3 = vit + base * omega.cross(r_corps) - v_sol
		var vn := v_point.dot(n)
		var cle := str(pt[0])
		if not deja.has(cle) and vn < 0.0:
			if deja.is_empty() and _touchait.is_empty():
				vitesse_impact = 0.0   # premier point qui touche : nouveau posé
			vitesse_impact = maxf(vitesse_impact, -vn)
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
		else:
			fn = RAIDEUR_COQUE * c - AMORTI_COQUE * vn
		fn = maxf(fn, 0.0)
		if fn <= 0.0:
			continue
		au_sol = true
		# frottement : ressort d'accroche + amortisseur, limité à frottement × fn
		var ici := _vers_planete(qx, qy, qz)
		var accroche: Vector3 = accroches.get(cle, ici)
		var ecart := _depuis_planete(ici - accroche)
		ecart -= n * ecart.dot(n)
		var vt := v_point - n * vn
		var axe_roule := Vector3.ZERO
		if k_roue == 0:
			# la roue avant roule dans l'axe du vaisseau (projeté sur le sol)
			axe_roule = avant - n * avant.dot(n)
			if axe_roule.length() > 1e-6:
				axe_roule = axe_roule.normalized()
				ecart -= axe_roule * ecart.dot(axe_roule)
				vt -= axe_roule * vt.dot(axe_roule)
		var ft := -ecart * RAIDEUR_COTE - vt * VISCOSITE_SOL
		var ft_max := FROTTEMENT * fn
		if ft.length() > ft_max:
			# ça glisse : la force est limitée et l'accroche suit le point
			ft = ft.normalized() * ft_max
			var e_ok := ecart.normalized() * minf(ecart.length(), ft_max / RAIDEUR_COTE)
			accroche = ici - _vers_planete_dir(e_ok)
		_accroches[cle] = accroche
		if axe_roule != Vector3.ZERO:
			var v_roule := v_point.dot(axe_roule)
			if absf(v_roule) > 1e-4:
				ft -= axe_roule * signf(v_roule) * RESISTANCE_ROULEMENT * fn
		var f: Vector3 = n * fn + ft
		f_monde += f
		couple += r_corps.cross(base.inverse() * f)
	return [f_monde, couple]


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
## Change la vitesse propre pendant h secondes (temps de l'univers) :
##   gravité : du/dt = γ·g (vu de la planète, la gravité tire comme Newton, sans jamais faire dépasser C ;
##             l'étape B la remplacera par la vraie courbure de l'espace-temps d'Einstein) ;
##   poussée : a_p = poussée / masse, ce que sent le pilote dans son vaisseau. Vue de la planète, elle est
##             « transformée de Lorentz » : du/dτ = a_p + (γ − 1)(a_p·n)n, n = direction du mouvement,
##             et du/dt = du/dτ / γ. Dans l'axe du mouvement, la vitesse propre gagne a_p par seconde
##             du PILOTE ; de côté, a_p/γ.
func _pousser_u(g: Array, a_p: Vector3, h: float) -> void:
	var gam := gamma()
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
	ux += (gam * float(g[0]) + axp / gam) * h
	uy += (gam * float(g[1]) + ayp / gam) * h
	uz += (gam * float(g[2]) + azp / gam) * h


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


## Place le vaisseau en orbite circulaire, nez dans le sens du déplacement.
func placer_en_orbite(altitude_m: float) -> void:
	var r := rayon_planete + altitude_m
	px = r
	py = 0.0
	pz = 0.0
	vx = 0.0
	vy = 0.0
	vz = -sqrt(gm / r)
	_lire_vitesse()
	temps_univers = 0.0
	temps_pilote = 0.0
	orientation = Quaternion.IDENTITY   # l'avant (-Z) est déjà dans le sens de la vitesse
	omega = Vector3.ZERO
	au_sol = false
	ecrase = false
	vitesse_impact = 0.0
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
	vertical = 0.0
	vertical_consigne = 0.0
	_placer_propulseurs_ailes()
	_placer_propulseurs_vertical()
	_preparer_repartition()
	_calculer_poussee_max()
