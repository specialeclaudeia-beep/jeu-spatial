extends RefCounted
## Moteurs et petits propulseurs (moteur audio, phase 1) : ce que le pilote en entend dans le cockpit.
##
## Deux chemins, comme dans un vrai vaisseau :
##  1. par la structure (toujours, même dans le vide) : la poussée n'est jamais parfaitement régulière ; ses
##     petites variations font vibrer les supports, la coque, puis le cockpit. Plus la poussée est forte,
##     plus ça vibre (énergie ∝ force²). Le son perd un peu de force à chaque mètre de structure, et beaucoup
##     au passage d'une emplanture d'aile.
##  2. par l'air (seulement dans une atmosphère) : le jet brasse l'air autour de lui et fait du bruit (loi
##     de Lighthill : la pression du bruit est proportionnelle à la densité de l'air). Ce bruit doit remonter
##     jusqu'au cockpit : à l'avant d'un jet, il est plus faible ; contre le vent, il remonte mal ; plus vite
##     que le son, il n'arrive plus du tout par l'air. Puis il traverse la verrière (fluides_son.gd).
##
## Les moteurs sont des moteurs ioniques / à plasma, sans carburant (décision du 21/11). Le jeu ne connaît
## pas la vitesse de leur jet : on prend 3 000 m/s, pour le son seulement (aucun effet sur la physique).
## Les niveaux de référence par la structure sont des réglages « à l'oreille », à valider à l'écoute.
##
## Événements (sons brefs) : vanne d'un petit propulseur qui s'ouvre ou se ferme, moteur qui s'allume ou se
## coupe (la structure se relâche).

const Capteurs = preload("res://scripts/son/capteurs.gd")
const Fluides = preload("res://scripts/son/fluides_son.gd")

const VITESSE_JET := 3000.0        # m/s, pour le son seulement
const RENDEMENT_JET := 0.005       # part de la puissance d'un jet très rapide qui devient du bruit (0,2 à 1 %)
const RHO_REF := 1.225             # kg/m³ : air au niveau de la mer (référence de Lighthill)
const SON_REF := 340.3             # m/s
const DIAMETRE_MOTEUR := 0.6       # m : sortie d'un moteur
const DIAMETRE_RCS := 0.08         # m : sortie d'une petite buse
const STROUHAL_JET := 0.03         # le bruit d'un jet de fusée est le plus fort vers f = 0,03 × U / D
const FP_MOTEUR := STROUHAL_JET * VITESSE_JET / DIAMETRE_MOTEUR   # 150 Hz : grave
const FP_RCS := STROUHAL_JET * VITESSE_JET / DIAMETRE_RCS         # 1 125 Hz : plus aigu
const ECART_SOURCE := 3.0          # m : le bruit naît quelques diamètres après la sortie du jet
const DIRECTIVITE_AVANT_DB := -15.0  # devant un jet (à l'opposé de son souffle), il fait ~15 dB de moins
const ATTENUATION_STRUCTURE := 1.0   # dB perdus par mètre de structure (coque en aluminium, jonctions)
const JONCTION_AILE_DB := 6.0        # dB perdus au passage d'une emplanture d'aile
# niveaux dans le cockpit, au bout d'une structure de longueur nulle (réglages à l'oreille)
const STRUCTURE_MOTEUR_DB := 90.0    # un moteur à 200 kN
const STRUCTURE_RCS_DB := 74.0       # un petit propulseur à 6 kN (souffle de la vanne et de la buse)
const F_REF_RCS := 6000.0
const CLAC_OUVERTURE_DB := 92.0      # vanne qui s'ouvre à pleine poussée
const CLAC_FERMETURE_DB := 84.0
const ALLUMAGE_DB := 88.0            # moteur qui s'allume vers 200 kN
const COUPURE_DB := 80.0
# seuils (avec un écart, pour ne pas « crépiter » autour d'une seule valeur)
const SEUIL_OUVERT := 0.03
const SEUIL_FERME := 0.01
const SEUIL_ALLUME := 0.02
const SEUIL_ETEINT := 0.008
const ECART_CLACS := 0.07            # s : une même vanne ne claque pas plus de ~14 fois par seconde
const ECART_MOTEUR := 0.5            # s

var attenuation := PackedFloat64Array()   # dB : chemin dans la structure jusqu'au pilote, par propulseur
var _geometrie := -1
var _ouvert := PackedByteArray()
var _dernier := PackedFloat64Array()
var _max_recent := PackedFloat64Array()   # N : plus forte poussée récente (pour le relâchement)
## Sons brefs demandés depuis la dernière lecture : [nom, niveau (dB dans le cockpit), position, n°, intensité 0..1]
var evenements: Array = []
## Dernier calcul (lu par le chef d'orchestre et par les tests).
var niveau_structure := -INF     # dB : grondement des moteurs par la structure
var niveau_rcs := -INF           # dB : souffle des petits propulseurs par la structure
var bandes_jet := PackedFloat64Array()    # Pa² par octave : bruit des jets des moteurs arrivé par l'air
var niveau_jet := -INF
var bandes_jet_rcs := PackedFloat64Array()  # Pa² par octave : bruit des jets des petits propulseurs
var niveau_jet_rcs := -INF
var tiers_jet := PackedFloat64Array()       # les mêmes, par tiers d'octave (partie C++, phase 2)
var tiers_jet_rcs := PackedFloat64Array()
var _transm_connue := PackedFloat64Array()
var _k_moteur := PackedFloat64Array()
var _k_rcs := PackedFloat64Array()
var _k30_moteur := PackedFloat64Array()
var _k30_rcs := PackedFloat64Array()
var regime := 0.0                # 0..1 : poussée des moteurs / poussée maximale réelle (x1)


func _init() -> void:
	bandes_jet.resize(10)
	bandes_jet_rcs.resize(10)
	tiers_jet.resize(30)
	tiers_jet_rcs.resize(30)


## Distance dans la structure de chaque propulseur jusqu'au pilote (refaite quand les ailes bougent).
func _preparer(c: Capteurs, oreille: Vector3) -> void:
	_geometrie = c.geometrie
	attenuation.resize(c.nombre)
	if _ouvert.size() != c.nombre:
		_ouvert.resize(c.nombre)
		_dernier.resize(c.nombre)
		_max_recent.resize(c.nombre)
		_dernier.fill(-1.0e9)
	for i in c.nombre:
		var d := (c.positions[i] - oreille).length()
		attenuation[i] = ATTENUATION_STRUCTURE * d + (JONCTION_AILE_DB if c.sur_aile[i] else 0.0)


## Niveaux continus. oreille : tête du pilote (repère du modèle) ; transm : Fluides.transmissions() pour
## l'air du dehors (ou vide si pas d'air).
func calculer(c: Capteurs, oreille: Vector3, transm: PackedFloat64Array) -> void:
	if c.geometrie != _geometrie or attenuation.size() != c.nombre:
		_preparer(c, oreille)
	var p_struct := 0.0
	var p_rcs := 0.0
	var f_moteurs := 0.0
	var p2_moteurs := 0.0   # Pa² des jets arrivés sur la verrière (avant la forme du spectre)
	var p2_rcs := 0.0
	var dans_air := c.densite > 0.0 and transm.size() == 30
	var son := Fluides.vitesse_son(c.temperature) if dans_air else SON_REF
	if dans_air and transm != _transm_connue:   # l'air du dehors a changé : on refait les formes
		_k_moteur = _transfert_jet(FP_MOTEUR, transm)
		_k_rcs = _transfert_jet(FP_RCS, transm)
		_k30_moteur = _transfert_jet(FP_MOTEUR, transm, true)
		_k30_rcs = _transfert_jet(FP_RCS, transm, true)
		_transm_connue = transm.duplicate()
	for i in c.nombre:
		var f := c.forces[i]
		if f <= 0.0:
			continue
		var rcs := c.types[i] == Capteurs.TYPE_RCS
		if rcs:
			p_rcs += pow(10.0, (STRUCTURE_RCS_DB - attenuation[i]) / 10.0) * (f / F_REF_RCS) * (f / F_REF_RCS)
		else:
			p_struct += pow(10.0, (STRUCTURE_MOTEUR_DB - attenuation[i]) / 10.0) * pow(f / c.poussee_reference, 2.0)
			f_moteurs += f
		if dans_air:
			var p2 := _jet_par_air(c, i, oreille, son)
			if rcs:
				p2_rcs += p2
			else:
				p2_moteurs += p2
	# même forme pour tous les moteurs (et pour tous les petits propulseurs) : on multiplie une seule fois
	for b in 10:
		bandes_jet[b] = p2_moteurs * _k_moteur[b] if dans_air else 0.0
		bandes_jet_rcs[b] = p2_rcs * _k_rcs[b] if dans_air else 0.0
	for t in 30:
		tiers_jet[t] = p2_moteurs * _k30_moteur[t] if dans_air else 0.0
		tiers_jet_rcs[t] = p2_rcs * _k30_rcs[t] if dans_air else 0.0
	niveau_structure = _db(p_struct)
	niveau_rcs = _db(p_rcs)
	niveau_jet = _niveau_bandes(bandes_jet)
	niveau_jet_rcs = _niveau_bandes(bandes_jet_rcs)
	regime = f_moteurs / (5.0 * c.poussee_reference) if c.poussee_reference > 0.0 else 0.0


static func _niveau_bandes(bandes: PackedFloat64Array) -> float:
	var tot := 0.0
	for e in bandes:
		tot += e
	return 10.0 * log(tot / (Fluides.P_REF * Fluides.P_REF)) / log(10.0) if tot > 0.0 else -INF


## Pression² (Pa²) du bruit du jet n° i qui arrive sur la verrière (avant de la traverser).
func _jet_par_air(c: Capteurs, i: int, oreille: Vector3, son: float) -> float:
	var sortie := -c.directions[i]                      # le jet part à l'opposé de la force
	var source := c.positions[i] + sortie * ECART_SOURCE
	var vers := oreille - source
	var r := maxf(vers.length(), 1.0)
	var u := vers / r
	# directivité : maximum vers l'arrière du jet, −15 dB devant lui
	var cos_psi := sortie.dot(u)
	var dir_db := DIRECTIVITE_AVANT_DB * (1.0 - cos_psi) * 0.5 + 3.0
	# le vent emporte le son : contre lui, le son remonte mal ; à Mach 1 contre lui, plus du tout
	var m := c.vent.dot(u) / son
	var remontee := clampf(1.0 + m, 0.0, 1.0)
	if remontee <= 0.0:
		return 0.0
	# Lighthill : puissance du bruit ∝ puissance du jet ; pression ∝ densité de l'air
	var puissance := RENDEMENT_JET * 0.5 * c.forces[i] * VITESSE_JET
	var rho_rel := c.densite / RHO_REF
	return puissance * RHO_REF * SON_REF * pow(10.0, dir_db / 10.0) / (4.0 * PI * r * r) * rho_rel * rho_rel * remontee * remontee


## Pour un jet dont le bruit culmine à fp : part de sa pression² qui arrive dans chaque octave du cockpit
## (forme du spectre × passage par la verrière ; une onde qui frappe une paroi y double sa pression).
## par_tiers : 30 valeurs (tiers d'octave) au lieu de 10 (octaves).
static func _transfert_jet(fp: float, transm: PackedFloat64Array, par_tiers := false) -> PackedFloat64Array:
	var k := PackedFloat64Array()
	k.resize(30 if par_tiers else 10)
	var cabine := pow(10.0, Fluides.GAIN_CABINE_DB / 10.0)
	for b in 10:
		var e := 0.0
		for t in 3:
			var f: float = Fluides.BANDES[b] * Fluides.TIERS[t]
			var et := forme_jet(f, fp) * f * Fluides.LARGEUR_TIERS * 4.0 * transm[b * 3 + t]
			if par_tiers:
				k[b * 3 + t] = et * cabine
			e += et
		if not par_tiers:
			k[b] = e * cabine
	return k


## Spectre du bruit d'un jet (par Hz, ∫ = 1) : monte jusqu'à fp, puis −9 dB par octave.
static func forme_jet(f: float, fp: float) -> float:
	var x := f / fp
	return 2.0 * x / pow(1.0 + x * x, 2.0) / fp


## Repère les vannes qui s'ouvrent ou se ferment, les moteurs qui s'allument ou se coupent (120 fois/s).
func detecter(c: Capteurs, oreille: Vector3) -> void:
	if c.geometrie != _geometrie or attenuation.size() != c.nombre:
		_preparer(c, oreille)
	var t := c.temps
	for i in c.nombre:
		var niveau := c.niveaux[i]
		var f := c.forces[i]
		_max_recent[i] = maxf(f, _max_recent[i] * 0.995)
		if c.types[i] == Capteurs.TYPE_RCS:
			if not _ouvert[i] and niveau > SEUIL_OUVERT:
				_ouvert[i] = 1
				if t - _dernier[i] >= ECART_CLACS:
					_dernier[i] = t
					evenements.append(["rcs_ouverture", CLAC_OUVERTURE_DB + 10.0 * log(minf(niveau, 1.0)) / log(10.0) - attenuation[i], c.positions[i], i, minf(niveau, 1.0)])
			elif _ouvert[i] and niveau < SEUIL_FERME:
				_ouvert[i] = 0
				if t - _dernier[i] >= ECART_CLACS:
					_dernier[i] = t
					var avant := maxf(_max_recent[i] / F_REF_RCS, 0.03)
					evenements.append(["rcs_fermeture", CLAC_FERMETURE_DB + 10.0 * log(minf(avant, 1.0)) / log(10.0) - attenuation[i], c.positions[i], i, minf(avant, 1.0)])
		else:
			if c.poussees_max[i] <= 0.0:
				_ouvert[i] = 0
				continue
			if not _ouvert[i] and niveau > SEUIL_ALLUME:
				_ouvert[i] = 1
				if t - _dernier[i] >= ECART_MOTEUR:
					_dernier[i] = t
					var cible := maxf(c.consignes[i], niveau) * c.poussees_max[i]
					evenements.append(["moteur_allumage", ALLUMAGE_DB + 20.0 * log(cible / c.poussee_reference) / log(10.0) - attenuation[i], c.positions[i], i, clampf(cible / c.poussee_reference, 0.0, 1.0)])
			elif _ouvert[i] and niveau < SEUIL_ETEINT:
				_ouvert[i] = 0
				if t - _dernier[i] >= ECART_MOTEUR:
					_dernier[i] = t
					var avant := maxf(_max_recent[i], 1.0)
					evenements.append(["moteur_coupure", COUPURE_DB + 20.0 * log(avant / c.poussee_reference) / log(10.0) - attenuation[i], c.positions[i], i, clampf(avant / c.poussee_reference, 0.0, 1.0)])


static func _db(p2_rel: float) -> float:
	return 10.0 * log(p2_rel) / log(10.0) if p2_rel > 0.0 else -INF
