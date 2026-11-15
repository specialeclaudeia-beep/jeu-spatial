extends RefCounted
## Ordinateur de bord : pilote automatique (étape 1 : garder le cap, s'arrêter).
##
## Aucune physique magique : le pilote ne touche jamais à la position, à la vitesse ou à la
## rotation du vaisseau. Il calcule seulement les mêmes ordres qu'un pilote humain (gaz, tangage,
## lacet, roulis) et une force de côté, puis le calcul automatique des poussées les répartit
## entre les vrais moteurs et propulseurs.
##
## Modes :
##   AUCUN  : le joueur pilote.
##   CAP    : garde le nez pointé dans la direction qu'il avait à l'activation (roulis compris).
##   ARRET  : annule la vitesse par rapport à la planète. Près d'une planète, il compense aussi la
##            gravité : le vaisseau finit en vol stationnaire, nez vers le haut, sur ses moteurs.

enum { AUCUN, CAP, ARRET }

const ACC_MAX := 3.0 * 9.80665   # m/s² : le pilote ne pousse pas plus fort que 3 g (confort)
const TEMPS_ARRET := 3.0         # s : sans limite, la vitesse serait divisée par e toutes les 3 s
const VITESSE_ARRETE := 0.05     # m/s : en dessous, dans le vide, on considère le vaisseau arrêté
const GAIN_ANGLE := 1.5          # rad/s de rotation voulus par radian d'écart (près du but)
const MARGE_FREIN := 0.6         # on ne compte que sur 60 % de la rotation maximale pour freiner
const TEMPS_REPONSE := 0.25      # s : temps pour corriger la vitesse de rotation
const FORCE_COTE_MAX := 10000.0  # N : ce que les petits propulseurs donnent de côté sans peiner
const ANGLE_POUSSEE := 0.5       # rad (~30°) : au-delà de cet écart, les moteurs restent coupés

var mode := AUCUN
var cible := Quaternion.IDENTITY   # orientation à garder (mode CAP)
var gaz := 0.0
var ordres := Vector3.ZERO         # tangage, lacet, roulis (-1..1)
var force_cote := Vector3.ZERO     # N, repère du vaisseau
var arrete := false                # mode ARRET : vitesse annulée


func activer(m: int, v) -> void:
	mode = m
	cible = v.orientation
	arrete = false
	gaz = 0.0
	ordres = Vector3.ZERO
	force_cote = Vector3.ZERO


func nom_mode() -> String:
	match mode:
		CAP: return "garder le cap"
		ARRET: return "vaisseau arrêté" if arrete else "s'arrêter"
	return "désactivé"


## Calcule les ordres pour la prochaine image. duree_s = durée pendant laquelle l'ordre restera
## le même (une image, plus longue en temps accéléré).
func calculer(v, duree_s: float) -> void:
	gaz = 0.0
	force_cote = Vector3.ZERO
	match mode:
		CAP:
			ordres = _ordres_orientation(v, cible, duree_s)
		ARRET:
			_calculer_arret(v, duree_s)
		_:
			ordres = Vector3.ZERO


func _calculer_arret(v, duree_s: float) -> void:
	var vit := Vector3(v.vx, v.vy, v.vz)
	var g_arr: Array = v.gravite(v.px, v.py, v.pz) if v.gm > 0.0 else [0.0, 0.0, 0.0]
	var g := Vector3(g_arr[0], g_arr[1], g_arr[2])
	if v.au_sol:
		arrete = true
		ordres = v.ordres_stabilisateur(duree_s)
		return
	if g.length() < 1e-6 and vit.length() < VITESSE_ARRETE:
		# dans le vide : arrêté. On garde l'orientation actuelle sans pousser.
		if not arrete:
			cible = v.orientation
		arrete = true
		ordres = _ordres_orientation(v, cible, duree_s)
		return
	arrete = vit.length() < VITESSE_ARRETE
	# accélération voulue : freiner la vitesse, et compenser la gravité
	var a := -vit / TEMPS_ARRET - g
	if a.length() > ACC_MAX:
		a = a.normalized() * ACC_MAX
	# les moteurs poussent vers le nez (-Z) : on tourne le nez dans la direction de « a »,
	# par le plus court chemin (le roulis n'est pas imposé)
	var base := Basis(v.orientation)
	var nez: Vector3 = -base.z
	if a.length() > 1e-6:
		var dir := a.normalized()
		var axe := nez.cross(dir)
		var angle := nez.angle_to(dir)
		if axe.length() > 1e-9 and angle > 1e-9:
			cible = (Quaternion(axe.normalized(), angle) * v.orientation).normalized()
		elif angle > PI - 1e-3:   # exactement à l'opposé : on bascule par le tangage
			cible = (Quaternion(base.x, PI) * v.orientation).normalized()
		else:
			cible = v.orientation
		ordres = _ordres_orientation(v, cible, duree_s)
		# poussée : seulement quand le nez est à peu près dans la bonne direction
		var ecart := nez.angle_to(dir)
		var alignement := clampf(1.0 - ecart / ANGLE_POUSSEE, 0.0, 1.0)
		var a_nez := a.dot(nez)
		gaz = clampf(a_nez * v.masse / v.poussee_avant_max, 0.0, 1.0) * alignement
		# ce que les moteurs ne donnent pas de côté, les petits propulseurs le complètent
		var reste: Vector3 = base.inverse() * (a * v.masse)
		force_cote = Vector3(reste.x, reste.y, 0.0).limit_length(FORCE_COTE_MAX)
	else:
		ordres = _ordres_orientation(v, v.orientation, duree_s)


## Ordres de rotation pour amener le vaisseau sur l'orientation « but ».
## On choisit une vitesse de rotation voulue sur chaque axe : assez lente pour pouvoir freiner
## à temps avec les propulseurs, puis on demande la rotation qui y mène.
func _ordres_orientation(v, but: Quaternion, duree_s: float) -> Vector3:
	var q: Quaternion = v.orientation.inverse() * but
	if q.w < 0.0:
		q = -q
	var e := Vector3.ZERO   # écart d'angle (rad), repère du vaisseau
	var s := sqrt(maxf(0.0, 1.0 - q.w * q.w))
	if s > 1e-9:
		e = Vector3(q.x, q.y, q.z) / s * (2.0 * acos(clampf(q.w, -1.0, 1.0)))
	var o := Vector3.ZERO
	for k in 3:
		var acc_max: float = v.couple_max[k] / v.inertie[k]   # rad/s² avec l'ordre 1
		if acc_max <= 0.0:
			continue
		var w_voulu := signf(e[k]) * minf(GAIN_ANGLE * absf(e[k]), sqrt(2.0 * MARGE_FREIN * acc_max * absf(e[k])))
		var t := maxf(TEMPS_REPONSE, 2.0 * duree_s)
		o[k] = clampf((w_voulu - v.omega[k]) / (acc_max * t), -1.0, 1.0)
	return o
