extends RefCounted
## Ordinateur de bord : pilote automatique (garder le cap, s'arrêter, atterrir).
##
## Aucune physique magique : le pilote ne touche jamais à la position, à la vitesse ou à la
## rotation du vaisseau. Il calcule seulement les mêmes ordres qu'un pilote humain (gaz, tangage,
## lacet, roulis) et une force de côté, puis le calcul automatique des poussées les répartit
## entre les vrais moteurs et propulseurs.
##
## Modes :
##   AUCUN    : le joueur pilote.
##   CAP      : garde le nez pointé dans la direction qu'il avait à l'activation (roulis compris).
##   ARRET    : annule la vitesse par rapport à la planète : le vaisseau finit en vol stationnaire, à plat.
##   ATTERRIR : comme ARRET, mais il descend ensuite et se pose doucement (train sorti, moins de 2 m/s).
##
## Comment il freine (tout est calculé à partir de la vraie poussée du vaisseau) :
##  - Il passe en vol vertical (la tuyère tourne vers le haut) : le vaisseau n'a PAS besoin de se
##    retourner, il se penche seulement, nez en haut, pour pousser contre sa vitesse.
##  - La verticale passe avant tout (ne jamais toucher le sol) ; toute la poussée qui reste sert à
##    freiner la vitesse horizontale. Plus le vaisseau est haut, plus il peut se pencher.
##  - La gravité travaille pour lui : si le vaisseau monte, il laisse la gravité freiner la montée et
##    garde toute la poussée pour la vitesse horizontale. Pour atterrir, il tombe d'abord (chute libre)
##    puis freine au dernier moment à la poussée voulue, de façon à arriver à 1 m/s.
##  - Seulement en cas d'urgence (trop bas ou descente trop rapide pour le vol vertical) : il utilise
##    les gros moteurs, nez en haut, jusqu'à ce que le vol vertical suffise de nouveau.
##  - Il calcule ses ordres au plus toutes les 0,04 s de temps de jeu (periode_controle) : même en
##    temps accéléré, le pilote auto garde le contrôle. Il limite lui-même l'accélération du temps
##    quand c'est dangereux (limite_temps).

enum { AUCUN, CAP, ARRET, ATTERRIR }

const VaisseauPhysiqueH = preload("res://scripts/physique/vaisseau_physique.gd")
const PAS_JEU := 1.0 / 120.0     # s : durée d'une image du jeu à vitesse normale

# --- orientation ---
const GAIN_ANGLE := 1.5          # rad/s de rotation voulus par radian d'écart (près du but)
const MARGE_FREIN := 0.6         # on ne compte que sur 60 % de la rotation maximale pour freiner
const TEMPS_REPONSE := 0.25      # s : temps pour corriger la vitesse de rotation
const VITESSE_ARRETE := 0.1      # m/s : en dessous, on considère le vaisseau arrêté

# --- freinage ---
const ACC_MAX := 3.0 * 9.80665   # m/s² : dans le vide, le pilote ne pousse pas plus fort que 3 g (confort)
const TEMPS_FREIN := 1.5         # s : freinage dans le vide (à fond, puis en douceur sur les derniers m/s)
const ANGLE_POUSSEE := 0.5       # rad (~30°) : dans le vide, au-delà de cet écart les moteurs restent coupés
const TAU_V := 1.0               # s : temps pour annuler la vitesse verticale
const TAU_H := 1.0               # s : temps pour annuler la vitesse horizontale (fin du freinage)
const T_AVANCE := 1.0            # s : avance prise sur la vitesse horizontale (le vaisseau met du temps à se redresser)
const T_AVANCE_V := 0.5          # s : avance prise sur la vitesse verticale
const VITESSE_FIN := 1.0         # m/s : sous cette vitesse horizontale, le freinage devient plus vigoureux
const GAIN_FIN := 2.0            # gain supplémentaire quand la vitesse horizontale tend vers zéro
const MARGE_SOL := 40.0          # m : « s'arrêter » reste au moins à cette hauteur
const UTILISATION_V := 0.94      # part de la poussée du vol vertical dont on se sert (le reste = marge)
const FORCE_COTE_MAX := 10000.0  # N : ce que les petits propulseurs donnent de côté sans peiner
const A_REPOS := 2.0             # m/s² : quand rien ne presse, le dessus du vaisseau vise le haut

# --- atterrissage ---
const V_TOUCHE := 1.0            # m/s : vitesse de descente voulue au contact du sol
const D_FIN := 6.0               # m : sur les derniers mètres, le freinage s'adoucit jusqu'à zéro
const UTILISATION_FREIN := 0.7   # part de la capacité de freinage vertical que le profil de descente utilise
const K_DESCENTE := 2.0          # 1/s : gain de suivi de la vitesse de descente voulue
const H_ARRET_LATERAL := 60.0    # m : tant que le vaisseau glisse, il ne descend pas sous cette hauteur
const GAIN_INTEGRALE := 0.25     # 1/s² : correction lente de la vitesse verticale restante (vol stationnaire)

# --- urgence ---
const T_PIVOT := 0.9              # s par radian : temps pour se redresser avant de pouvoir pousser vers le haut
const T_REPONSE_MOTEURS := 0.3   # s : les moteurs mettent ce temps à suivre l'ordre
const UTILISATION_URGENCE := 0.95
const H_URGENCE := 10.0          # m : hauteur sous laquelle on ne veut jamais descendre
const H_PLANCHER_URGENCE := 70.0 # m : en urgence, le vaisseau remonte au moins jusqu'à cette hauteur avant de revenir au vol vertical

var mode := AUCUN
var cible := Quaternion.IDENTITY   # orientation visée
var gaz := 0.0
var ordres := Vector3.ZERO         # tangage, lacet, roulis (-1..1)
var force_cote := Vector3.ZERO     # N, repère du vaisseau
var arrete := false                # ARRET : vitesse annulée   ATTERRIR : posé
var urgence := false               # freinage d'urgence aux gros moteurs
var passage_a_plat := true         # passage en vol vertical : rester à plat (sinon suivre la tuyère)
var phase := ""                    # texte : ce que fait le pilote (affichage)
var _integrale_vv := 0.0           # m : somme de la vitesse verticale restante (correction lente)
var _calme := false                # CAP : le vaisseau tient son cap, presque rien à corriger
var _chrono := 0.0                 # s : temps écoulé depuis l'activation
var _chrono_sortie := -100.0       # s : moment où le pilote a quitté l'urgence


## Ce que le pilote sait de la situation (calculé une fois par pas).
class Etat:
	var pos := Vector3.ZERO
	var r := 1.0
	var haut := Vector3.UP        # direction « en haut » (loin de la planète)
	var h := 0.0                  # altitude du centre de gravité
	var hs := 0.0                 # hauteur du bas des roues au-dessus du sol
	var vit := Vector3.ZERO
	var vv := 0.0                 # vitesse verticale (+ = monte)
	var vv_av := 0.0              # vitesse verticale prévue dans un instant (avec l'accélération actuelle)
	var vh_v := Vector3.ZERO      # vitesse horizontale (vecteur)
	var vh := 0.0
	var u_h := Vector3.ZERO       # direction de la vitesse horizontale (nulle si le vaisseau ne glisse pas)
	var g := 0.0                  # pesanteur ici
	var g_eff := 0.0              # pesanteur apparente : la force centrifuge allège le vaisseau qui va vite
	var g_sol := 0.0              # pesanteur à la surface (la plus forte : sert aux freinages prudents)


func activer(m: int, v) -> void:
	mode = m
	cible = v.orientation
	arrete = false
	urgence = false
	passage_a_plat = true
	phase = ""
	_integrale_vv = 0.0
	_chrono = 0.0
	_calme = false
	_chrono_sortie = -100.0
	gaz = 0.0
	ordres = Vector3.ZERO
	force_cote = Vector3.ZERO


func nom_mode() -> String:
	match mode:
		CAP: return "garder le cap"
		ARRET: return "vaisseau arrêté" if arrete else "s'arrêter"
		ATTERRIR:
			if arrete: return "posé"
			return "atterrissage : " + (phase if phase != "" else "en route")
	return "désactivé"


## Calcule les ordres pour la prochaine période. duree_s = durée pendant laquelle l'ordre restera
## le même (au plus periode_controle()).
func calculer(v, duree_s: float) -> void:
	gaz = 0.0
	force_cote = Vector3.ZERO
	match mode:
		CAP:
			ordres = _ordres_orientation(v, cible, duree_s)
			_calme = ordres.length() < 0.02 and v.omega.length() < 0.0005
		ARRET, ATTERRIR:
			_calculer_arret(v, duree_s)
		_:
			ordres = Vector3.ZERO


## Temps de jeu entre deux calculs du pilote (s). Le jeu découpe chaque image en morceaux de cette
## durée : le pilote garde le contrôle même en temps accéléré.
func periode_controle(_v) -> float:
	if mode == CAP and _calme:
		return 0.5                        # le cap est tenu, rien ne bouge : un calcul de temps en temps suffit
	if arrete:
		return 0.1
	return 0.04


## Plus grande accélération du temps (1, 10, 100 ou 1000) que le pilote auto accepte pour l'instant :
## près du sol, une image ne doit jamais sauter une grande part de la hauteur qui reste.
func limite_temps(v) -> int:
	if mode == AUCUN or mode == CAP:
		return 1000
	if v.au_sol or v.rayon_planete <= 0.0:
		return 1000 if v.au_sol else 100
	var e := _etat(v)
	var cap := 100
	if e.hs < 30.0:
		cap = 1
	elif e.hs < 150.0:
		cap = 10
	elif arrete and e.hs > 1000.0:
		cap = 1000
	var rythme := maxf(absf(e.vv), 1.0) * PAS_JEU
	var acc_h := 0.25 * maxf(e.hs, 1.0) / rythme
	var palier := 1
	for p in [10, 100, 1000]:
		if acc_h >= p:
			palier = p
	return mini(cap, palier)


func _etat(v) -> Etat:
	var e := Etat.new()
	e.pos = Vector3(v.px, v.py, v.pz)
	e.r = v.distance_centre()
	e.h = v.altitude()
	e.hs = e.h - VaisseauPhysiqueH.HAUTEUR_TRAIN
	e.vit = Vector3(v.vx, v.vy, v.vz)
	if v.gm > 0.0 and e.r > 1.0:
		var g_arr: Array = v.gravite(v.px, v.py, v.pz)
		var g_v := Vector3(g_arr[0], g_arr[1], g_arr[2])
		e.g = g_v.length()
		e.haut = e.pos / e.r
		e.g_sol = v.gm / maxf(v.rayon_planete * v.rayon_planete, 1.0) if v.rayon_planete > 0.0 else e.g
	e.vv = e.vit.dot(e.haut)
	e.vh_v = e.vit - e.haut * e.vv
	e.vh = e.vh_v.length()
	if e.vh > 1e-3:
		e.u_h = e.vh_v / e.vh
	e.g_eff = e.g - e.vh * e.vh / maxf(e.r, 1.0)
	var a_felt: Vector3 = v.acceleration_ressentie
	e.vv_av = e.vv + (a_felt.dot(e.haut) - e.g_eff) * T_AVANCE_V
	return e


# =====================================================================
# S'ARRÊTER, ATTERRIR
# =====================================================================
func _calculer_arret(v, duree_s: float) -> void:
	var e := _etat(v)
	if v.au_sol:
		# posé : plus de poussée, les propulseurs freinent seulement la rotation
		arrete = true
		phase = "posé"
		ordres = v.ordres_stabilisateur(duree_s)
		_integrale_vv = 0.0
		return
	if e.g < 1e-6:
		_arret_dans_le_vide(v, e, duree_s)
		return
	arrete = mode == ARRET and e.vit.length() < VITESSE_ARRETE
	_chrono += duree_s
	_choisir_configuration(v, e)
	var atterrit := mode == ATTERRIR
	if atterrit and v.train_consigne < 0.5 and e.hs < 1500.0 + 10.0 * absf(e.vv):
		v.sortir_train(true)

	var base := Basis(v.orientation)
	var d_corps: Vector3 = v.direction_poussee()
	var t_hat: Vector3 = base * d_corps            # direction réelle de la poussée des gaz
	# poussée que le pilote peut demander (pour décider) : vol vertical ou gros moteurs
	var a_t: float
	if urgence:
		a_t = float(v.POUSSEE_MOTEUR) * 5.0 / v.masse
	else:
		a_t = UTILISATION_V * v.poussee_verticale_max / v.masse

	# 1. accélération voulue
	# vitesse horizontale « prévue » : la poussée qui freine déjà va encore agir pendant que le
	# vaisseau se redresse. Sans cette avance, il dépasse l'arrêt et oscille.
	var a_ress: Vector3 = v.acceleration_ressentie
	var v_prev := e.vh_v + (a_ress - e.haut * a_ress.dot(e.haut)) * T_AVANCE
	var gain_h := 1.0 / TAU_H
	if v_prev.length() < VITESSE_FIN:
		gain_h *= 1.0 + GAIN_FIN * (1.0 - v_prev.length() / VITESSE_FIN)    # sur les derniers m/s, il freine plus vite
	var a_v: float
	var a_hv: Vector3
	if mode == ARRET and not urgence:
		# s'arrêter : la vitesse verticale et la vitesse horizontale s'annulent en même temps
		var r := _acceleration_commune(v, e, a_t, v_prev, gain_h, duree_s)
		a_v = r[0]
		a_hv = r[1]
	else:
		# atterrir (ou urgence) : la verticale d'abord, le reste de la poussée freine le glissement
		a_v = clampf(_acceleration_verticale(v, e, a_t, duree_s), 0.0, a_t)
		var a_h_dispo := sqrt(maxf(a_t * a_t - a_v * a_v, 0.0))
		a_hv = (-v_prev * gain_h).limit_length(a_h_dispo)
	# près du sol, le vaisseau ne se penche pas beaucoup (il doit se poser à plat)
	var penche_max := clampf(10.0 + (e.hs - 20.0) * (80.0 / 130.0), 3.0, 90.0)
	if penche_max < 89.0:
		a_hv = a_hv.limit_length(a_v * tan(deg_to_rad(penche_max)) + 0.8)
	var a_des := e.haut * a_v + a_hv               # accélération voulue (repère monde)

	# 2. orientation : le dessus du vaisseau (ou la tuyère) vise la direction voulue
	var dir := (e.haut * maxf(a_v, A_REPOS) + a_hv).normalized()
	var ref := d_corps
	if not urgence and v.vertical < 1.0 and passage_a_plat:
		ref = Vector3.UP                           # il reste à plat au lieu de se cabrer puis revenir
	cible = _orientation_vers(v, base * ref, dir)
	ordres = _ordres_orientation(v, cible, duree_s)

	# 3. gaz : assez pour donner l'accélération verticale voulue (la verticale passe avant tout) ou, si
	# le vaisseau freine surtout de côté, l'accélération horizontale. Seulement quand la poussée vise
	# à peu près la bonne direction (pleine poussée à moins de 50°, coupée au-delà de 80°).
	var t_v := t_hat.dot(e.haut)
	var t_hp := t_hat - e.haut * t_v
	var a_star := 0.0
	if t_v > 0.3:
		a_star = a_v / t_v
	if a_hv.length() > 0.01 and t_hp.length_squared() > 0.01:
		a_star = maxf(a_star, maxf(a_hv.dot(t_hp), 0.0) / t_hp.length_squared())
	var cos_err := t_hat.dot(dir)
	var alignement := clampf((cos_err - 0.5) / 0.37, 0.0, 1.0)
	if urgence:
		alignement = clampf((cos_err + 0.2) / 0.6, 0.0, 1.0)
	if v.poussee_avant_max > 0.0:
		gaz = clampf(a_star * alignement * v.masse / v.poussee_avant_max, 0.0, 1.0)
	# ce que les gaz ne donnent pas, les petits propulseurs le complètent (un peu)
	var reste: Vector3 = base.inverse() * ((a_des - t_hat * (gaz * v.poussee_avant_max / v.masse)) * v.masse)
	reste -= d_corps * reste.dot(d_corps)
	force_cote = reste.limit_length(FORCE_COTE_MAX)


## Accélération verticale voulue (m/s², vers le haut, poids compris) : ce que la poussée doit donner
## dans la direction « haut ».
func _acceleration_verticale(v, e: Etat, a_t: float, duree_s: float) -> float:
	var cap_net := maxf(UTILISATION_V * a_t - e.g_sol, 0.5)   # freinage vertical net possible
	var a_net := 0.0                                            # accélération voulue en plus du poids
	if mode == ATTERRIR and not urgence and (v.vertical >= 0.99 or passage_a_plat):
		# profil de descente : vitesse de descente la plus grande qui permet encore de freiner pour
		# arriver à V_TOUCHE au sol, avec un freinage constant A qui s'adoucit sur les derniers mètres
		var h_fin := 0.0
		if e.vh > 1.0:
			h_fin = H_ARRET_LATERAL * clampf((e.vh - 1.0) / 3.0, 0.0, 1.0)
		var s := -e.vv
		# le vaisseau met du temps à pousser vers le haut (moteurs, et surtout se redresser s'il est
		# penché pour freiner de côté) : pendant ce temps il continue de tomber, on le compte
		var poussee: Vector3 = Basis(v.orientation) * v.direction_poussee()
		var inclinaison := poussee.angle_to(e.haut) if v.vertical >= 0.99 else 1.2
		var retard := T_REPONSE_MOTEURS + T_PIVOT * inclinaison
		var d_brut := e.hs - h_fin
		var perte := maxf(s, 0.0) * retard + 0.5 * maxf(e.g_eff, 0.0) * retard * retard
		# le retard ne compte plus sur les derniers mètres (le vaisseau est droit et descend doucement)
		var d := d_brut - perte * clampf((d_brut - D_FIN) / D_FIN, 0.0, 1.0)
		var a_frein := UTILISATION_FREIN * cap_net
		var vt := 0.0
		var a_ff := 0.0
		if d > 0.0:
			if d >= D_FIN:
				vt = sqrt(V_TOUCHE * V_TOUCHE + a_frein * (2.0 * d - D_FIN))
				a_ff = a_frein
			else:
				vt = sqrt(V_TOUCHE * V_TOUCHE + a_frein * d * d / D_FIN)
				a_ff = a_frein * d / D_FIN
			phase = "chute libre" if s < vt - (a_ff + e.g_eff) / K_DESCENTE else ("freinage" if d > D_FIN else "approche finale")
		else:
			phase = "freinage horizontal" if h_fin > 0.0 else "approche finale"
			vt = 0.0 if h_fin > 0.0 else V_TOUCHE
		a_net = a_ff + K_DESCENTE * (s - vt)
	else:
		# s'arrêter : annuler la vitesse verticale. Si le vaisseau monte, a_net est négatif : on laisse
		# la gravité freiner la montée. S'il descend, on freine à temps pour rester au-dessus de MARGE_SOL.
		var h_plancher := H_PLANCHER_URGENCE if urgence else MARGE_SOL
		a_net = -e.vv_av / TAU_V
		if e.vv < 0.0:
			a_net = maxf(a_net, 1.3 * e.vv * e.vv / (2.0 * maxf(e.hs - h_plancher, 1.0)))
		if e.hs < h_plancher:
			var vv_voulu := clampf((h_plancher - e.hs) * 0.3, 0.0, 2.5)
			a_net = maxf(a_net, (vv_voulu - e.vv) / TAU_V)
		phase = "vol stationnaire" if arrete else "freinage"
	# vol stationnaire : correction lente de ce qui reste de vitesse verticale
	var cible_vv := 0.0
	if absf(e.vv - cible_vv) < 0.5 and e.vh < 0.3 and (mode == ARRET or e.hs < 3.0 * D_FIN):
		_integrale_vv = clampf(_integrale_vv + (e.vv - cible_vv) * duree_s, -2.0, 2.0)
	a_net -= GAIN_INTEGRALE * _integrale_vv
	return e.g_eff + a_net


## S'arrêter : la vitesse verticale et la vitesse horizontale doivent s'annuler en même temps, le plus
## vite possible. On cherche le taux d'arrêt x = 1/T le plus grand pour lequel la poussée suffit
## (pesanteur comprise) : (g + s·x)² + (vh·x)² = a_max². Tout s'arrête au même moment, donc la poussée
## garde la même direction du début à la fin : c'est le freinage le plus court. Si le vaisseau monte,
## la gravité freine la montée et toute la poussée va à la vitesse horizontale.
## Renvoie [accélération verticale (poids compris), accélération horizontale (vecteur monde)].
func _acceleration_commune(_v, e: Etat, a_t: float, v_prev: Vector3, gain_h: float, duree_s: float) -> Array:
	var s := -e.vv_av                      # vitesse de descente
	var g := e.g_eff
	var x_v := 1.0 / TAU_V                 # taux d'arrêt en fin de freinage (doux)
	var x_h := gain_h
	var surface := s * s + v_prev.length_squared()
	var x_max := 1e9
	if surface > 1e-6:
		var b := g * s
		var c := g * g - a_t * a_t
		x_max = (-b + sqrt(maxf(b * b - surface * c, 0.0))) / surface
	var a_v := g + s * minf(x_max, x_v)
	var a_hv := -v_prev * minf(x_max, x_h)
	if a_v < 0.0:
		# le vaisseau monte vite : la gravité freine la montée, toute la poussée va à l'horizontale
		a_v = 0.0
		var vit_h := v_prev.length()
		if vit_h > 1e-3:
			a_hv = -v_prev / vit_h * minf(a_t, vit_h * x_h)
	# ne jamais toucher le sol : freiner la descente à temps pour rester au-dessus du plancher
	var plancher := H_PLANCHER_URGENCE if urgence else MARGE_SOL
	var a_net := a_v - g
	if e.vv < 0.0:
		a_net = maxf(a_net, 1.3 * e.vv * e.vv / (2.0 * maxf(e.hs - plancher, 1.0)))
	if e.hs < plancher:
		var vv_voulu := clampf((plancher - e.hs) * 0.3, 0.0, 2.5)
		a_net = maxf(a_net, (vv_voulu - e.vv) / TAU_V)
	# vol stationnaire : correction lente de ce qui reste de vitesse verticale
	if absf(e.vv) < 0.5 and e.vh < 0.3:
		_integrale_vv = clampf(_integrale_vv + e.vv * duree_s, -2.0, 2.0)
	a_net -= GAIN_INTEGRALE * _integrale_vv
	phase = "vol stationnaire" if arrete else "freinage"
	a_v = clampf(g + a_net, 0.0, a_t)
	return [a_v, a_hv.limit_length(sqrt(maxf(a_t * a_t - a_v * a_v, 0.0)))]


## Vol vertical (la tuyère tourne vers le haut, le vaisseau ne se retourne jamais) ou, en urgence
## seulement, gros moteurs : on compare ce que chacun peut encore faire avant le sol.
func _choisir_configuration(v, e: Etat) -> void:
	if urgence:
		# on revient au vol vertical dès qu'il suffit largement
		if e.hs > 0.7 * H_PLANCHER_URGENCE and e.vit.length() < 6.0 and _vitesse_impact_prevue(v, e, false, 1.3) < 0.5:
			urgence = false
			_chrono_sortie = _chrono
			# arrêté nez en haut sur les gros moteurs : la tuyère tourne et le nez suit ; sinon il reste à plat
			var poussee: Vector3 = Basis(v.orientation) * v.direction_poussee()
			passage_a_plat = poussee.angle_to(e.haut) > 0.8
	else:
		var imp_v := _vitesse_impact_prevue(v, e, false, 1.0)
		var en_transition: bool = v.vertical_consigne >= 0.5 and v.vertical < 0.99
		var seuil := 3.0 if en_transition else 0.5
		if _chrono - _chrono_sortie < 6.0:
			seuil = 8.0                       # il vient de quitter l'urgence : pas de va-et-vient
		if imp_v > seuil and _vitesse_impact_prevue(v, e, true, 1.0) < imp_v - 3.0:
			urgence = true
	var veut_vertical := not urgence
	if veut_vertical != (v.vertical_consigne >= 0.5):
		v.passer_vol_vertical(veut_vertical)
		if veut_vertical and v.vertical < 0.1:
			var poussee2: Vector3 = Basis(v.orientation) * v.direction_poussee()
			passage_a_plat = poussee2.angle_to(e.haut) > 0.8


## Vitesse à laquelle le vaisseau arriverait à H_URGENCE au-dessus du sol, en freinant au mieux
## (0 = il s'arrête avant). On compte la chute pendant que la tuyère tourne ou que le vaisseau se
## redresse, puis le freinage à la poussée du vol vertical (ou des gros moteurs).
func _vitesse_impact_prevue(v, e: Etat, gros_moteurs: bool, marge: float) -> float:
	var t: float
	var cap: float
	var poussee: Vector3 = Basis(v.orientation) * v.direction_poussee()
	if gros_moteurs:
		# le nez doit monter jusqu'à la verticale, tuyère à plat
		var a_m: float = float(v.POUSSEE_MOTEUR) * 5.0 / v.masse
		cap = UTILISATION_URGENCE * (a_m - e.g_sol)
		var nez: Vector3 = Basis(v.orientation) * Vector3(0.0, 0.0, -1.0)
		t = T_REPONSE_MOTEURS + T_PIVOT * nez.angle_to(e.haut)
		if v.vertical > 0.01:
			t += VaisseauPhysiqueH.DUREE_VERTICAL * v.vertical * 0.5   # la tuyère revient en arrière
	else:
		var a_vol: float = UTILISATION_V * v.poussee_verticale_max / v.masse
		cap = UTILISATION_URGENCE / marge * (a_vol - e.g_sol)
		var inclinaison := poussee.angle_to(e.haut) if v.vertical >= 0.99 else 0.0
		t = maxf(VaisseauPhysiqueH.DUREE_VERTICAL * (1.0 - v.vertical), T_REPONSE_MOTEURS + T_PIVOT * inclinaison)
		if v.vertical < 0.99 and poussee.angle_to(e.haut) < 0.8:
			t = T_REPONSE_MOTEURS + 1.0        # déjà porté nez en haut : la tuyère tourne sans lâcher la poussée
	if cap < 0.5:
		return 1e9
	var vv1 := e.vv - e.g * t
	var h1 := e.hs + e.vv * t - 0.5 * e.g * t * t - H_URGENCE
	if vv1 >= 0.0:
		return 0.0
	if h1 <= 0.0:
		return sqrt(vv1 * vv1 + 2.0 * cap * 0.0) + 1.0      # déjà trop bas
	return sqrt(maxf(vv1 * vv1 - 2.0 * h1 * cap, 0.0))


## Loin de toute planète : on annule la vitesse avec les gros moteurs (le nez vise contre la vitesse).
func _arret_dans_le_vide(v, e: Etat, duree_s: float) -> void:
	if e.vit.length() < VITESSE_ARRETE:
		if not arrete:
			cible = v.orientation
		arrete = true
		ordres = _ordres_orientation(v, cible, duree_s)
		return
	arrete = false
	var base := Basis(v.orientation)
	var d_corps: Vector3 = v.direction_poussee()
	var a_max := ACC_MAX
	if v.poussee_avant_max > 0.0:
		a_max = minf(ACC_MAX, v.poussee_avant_max / v.masse)
	var a := (-e.vit / TEMPS_FREIN).limit_length(a_max)
	var dir := a.normalized()
	var poussee: Vector3 = base * d_corps
	cible = _orientation_vers(v, poussee, dir)
	ordres = _ordres_orientation(v, cible, duree_s)
	var alignement := clampf(2.0 - 2.0 * poussee.angle_to(dir) / ANGLE_POUSSEE, 0.0, 1.0)
	if v.poussee_avant_max > 0.0:
		gaz = clampf(a.dot(poussee) * v.masse / v.poussee_avant_max, 0.0, 1.0) * alignement


# =====================================================================
# ORIENTATION
# =====================================================================
## Rotation la plus courte qui amène la direction « de » (monde) sur « vers » ; le reste de
## l'orientation est libre.
func _orientation_vers(v, de: Vector3, vers: Vector3) -> Quaternion:
	var axe := de.cross(vers)
	var angle := de.angle_to(vers)
	if axe.length() > 1e-9 and angle > 1e-9:
		return (Quaternion(axe.normalized(), angle) * v.orientation).normalized()
	if angle > PI - 1e-3:   # exactement à l'opposé : on bascule autour de l'axe du vaisseau qui tourne le plus vite
		var b := Basis(v.orientation)
		var meilleur := b.z
		var meilleur_acc := -1.0
		var de_corps: Vector3 = b.inverse() * de
		for k in 3:
			var acc: float = v.couple_max[k] / v.inertie[k]
			if absf(de_corps[k]) < 0.5 and acc > meilleur_acc:
				meilleur_acc = acc
				meilleur = b[k]
		return (Quaternion(meilleur.normalized(), PI) * v.orientation).normalized()
	return v.orientation


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
