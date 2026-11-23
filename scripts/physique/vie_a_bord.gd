extends RefCounted
## Atelier, étape 8 : LA VIE À BORD. Les parois de la cabine tiennent-elles la pression, combien d'air et
## d'oxygène reste-t-il au pilote, et que se passe-t-il quand l'air s'échappe (fuite). Vision Notion 16.2 :
## oxygène, pression, détection de fuite (la température et la ventilation viendront plus tard, les dégâts
## et les pannes aussi).
##
## Ce qu'on calcule (aucune valeur inventée : les lois de la physique, et des chiffres de fiches techniques) :
##
## 1. LES COMPARTIMENTS : la cabine du pilote (son volume d'air est mesuré sur le modèle 3D du cockpit :
##    outils/plan/cabine_cockpit_v27.py, 3,6 m³ une fois le pilote et le siège enlevés), et chaque volume
##    FERMÉ construit avec les panneaux de l'armature (étape 6), que l'atelier peut pressuriser (soute à
##    l'air). Un volume est fermé quand chaque bord de chaque panneau touche exactement un autre panneau ;
##    son volume vient du théorème de la divergence (somme des tétraèdres de ses triangles).
##
## 2. LA SOLIDITÉ DES PAROIS. Dans le vide, l'air de la cabine pousse chaque paroi vers le dehors avec la
##    pression de la cabine (101 kPa = 10 tonnes par mètre carré). Une paroi casse quand la contrainte dans
##    sa matière atteint sa résistance à la rupture (catalogue.gd, « resistance_mpa ») :
##    - paroi COURBE (verrière, baignoire du cockpit) : coque mince de rayon R et d'épaisseur e, contrainte
##      σ = p·R/e (formule des chaudières) → elle tient jusqu'à p = σ_rupture·e/R ;
##    - panneau PLAT de l'armature (tenu par ses poutres sur tout son tour) : grande flèche d'une plaque
##      ronde encastrée (formulaire de Roark, plaque « fixe et tenue ») : il se bombe, et travaille en
##      membrane. q·a⁴/(E·e⁴) = K1·(y/e) + K2·(y/e)³ et σ·a²/(E·e²) = K3·(y/e) + K4·(y/e)², au centre et au
##      bord ; un rectangle ou un triangle est ramené à la plaque ronde qui a la même contrainte au bord en
##      petite flèche (table de Roark pour les rectangles, cercle inscrit × 1,28 pour un triangle).
##      Exemple : une tôle d'aluminium de 2 mm et de 1 m de côté casse à 125 kPa.
##    MARGE = pression qui casse / pression de la cabine. Règle des structures habitées sous pression :
##    au moins ×2 (vert). Entre ×1 et ×2 : orange. Moins de ×1 : la paroi casse dans le vide (rouge).
##
## 3. LE GAZ (oxygène et azote, l'argon compté avec l'azote) : la loi des gaz parfaits p·V = n·R·T à 20 °C
##    (la cabine est chauffée ; la détente est comptée à température constante). Le RÉGULATEUR garde la
##    pression choisie (101,3 kPa par défaut, de 20 à 110) avec 21,2 kPa d'oxygène (comme au niveau de la
##    mer), en puisant dans les réserves (dans le système de survie : 20 kg d'oxygène et 30 kg d'azote, au
##    plus 0,1 kg/s). Une SOUPAPE s'ouvre si la cabine dépasse la consigne de 3 kPa, une autre fait entrer
##    l'air du dehors s'il est 2 kPa plus fort (comme dans un avion). Le PILOTE respire 0,84 kg d'oxygène
##    par jour (valeur de la NASA) ; le RECYCLEUR (réacteur de Bosch + électrolyse de l'eau) en rend 90 %.
##    Le régulateur et les soupapes ne servent que la cabine : une soute pressurisée est remplie au départ,
##    puis fermée (son air ne se renouvelle pas, et une soute percée ne vide pas les réserves du pilote).
##
## 4. LES FUITES : un trou, une paroi cassée, la VANNE de la cabine (touche F4 dans le jeu, 20 cm² ; ouverte,
##    elle coupe le régulateur : la cabine se vide en une minute, et se remplit quand on la referme). Le
##    débit est celui d'un orifice (coefficient 0,61) : quand la cabine a plus de 1,9 fois la pression du
##    dehors, l'air sort à la vitesse du son (débit « bloqué »), sinon plus doucement (Saint-Venant). L'air
##    qui sort d'un côté POUSSE le vaisseau de l'autre (quantité de mouvement du jet + pression au trou),
##    à l'endroit du trou : force et couple. La vanne et les soupapes soufflent des deux côtés (pas de
##    poussée). Le pas est découpé pour qu'un compartiment ne perde jamais plus du quart de son air d'un coup
##    (une verrière arrachée vide la cabine en quelques centièmes de seconde).
##
## 5. LE PILOTE : sous 10,6 kPa d'oxygène, le temps de conscience utile (tables de médecine aéronautique)
##    s'écoule : 25 min à 4 500 m, 1 min 30 à 7 600 m, une dizaine de secondes dans le vide. Sous 6,3 kPa
##    (limite d'Armstrong), l'eau du corps bout à 37 °C. Pour l'instant, c'est seulement affiché (comme
##    les G) : le jeu ne prend pas les commandes au pilote.
##
## La masse du vaisseau ne change pas (l'air de la cabine pèse 4 kg, les réserves sont comptées dans les
## 250 kg du système de survie).

const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const Armature = preload("res://scripts/atelier/armature.gd")
const Plan = preload("res://scripts/atelier/plan.gd")

const R := 8.314462618               # J/(mol·K), constante des gaz parfaits
const M_O2 := 0.0319988              # kg/mol
const M_N2 := 0.0280134              # kg/mol (l'argon de l'air est compté avec l'azote)
const M_AIR := 0.0289647             # kg/mol, air sec
const X_O2_AIR := 0.2314             # part de l'oxygène dans la masse de l'air
const GAMMA := 1.4                   # air (molécules à deux atomes)
const CD := 0.61                     # coefficient de débit d'un trou à bord vif
const T_CABINE := 293.15             # K (20 °C)
const P_MER := 101325.0              # Pa
const PPO2_CIBLE := 21200.0          # Pa : l'oxygène de l'air au niveau de la mer
const PRESSION_MIN_KPA := 20.0
const PRESSION_MAX_KPA := 110.0
const SURPRESSION := 3000.0          # Pa au-dessus de la consigne : la soupape s'ouvre
const DEPRESSION := 2000.0           # Pa de plus dehors : l'autre soupape fait entrer l'air
const SURFACE_SOUPAPE := 0.001       # m² (10 cm²)
const SURFACE_VANNE := 0.002         # m² (20 cm²), vanne de la cabine (F4)
const DEBIT_REGULATEUR := 0.1        # kg/s au plus
const CONSOMMATION_O2 := 0.84 / 86400.0   # kg/s : un pilote au repos (NASA, BVAD)
const PART_RECYCLEE := 0.9           # le recycleur rend 90 % de l'oxygène respiré
const MARGE_SURE := 2.0              # règle des structures habitées sous pression
const LIMITE_ARMSTRONG := 6300.0     # Pa : l'eau bout à 37 °C
const SEUIL_HYPOXIE := 10600.0       # Pa d'oxygène : en dessous, le temps de conscience s'écoule
const RECUPERATION_S := 30.0         # s pour retrouver ses esprits quand l'oxygène revient
## Temps de conscience utile (médecine aéronautique) : [pression d'oxygène (Pa), secondes].
const CONSCIENCE := [[10600.0, 1500.0], [9200.0, 600.0], [8000.0, 240.0], [6300.0, 90.0], [5000.0, 45.0],
	[3900.0, 18.0], [2400.0, 10.0], [0.0, 9.0]]
const FRACTION_SOUS_PAS := 0.25      # un sous-pas fait perdre au plus le quart de l'air d'un compartiment
const SOUS_PAS_MAX := 64
const FUITE_MIN := 1.0e-6            # kg/s : en dessous, ce n'est pas une fuite (affichage)
## Plaque rectangulaire encastrée (formulaire de Roark) : contrainte au milieu du grand bord σ = β·q·b²/e²
## (b = largeur) ; rapport longueur / largeur → β. Plaque ronde encastrée : σ = 0,75·q·a²/e² au bord.
const BETA_RECTANGLE := [[1.0, 0.3078], [1.2, 0.3834], [1.4, 0.4356], [1.6, 0.468], [1.8, 0.4872],
	[2.0, 0.4974], [100.0, 0.5]]
const BETA_CERCLE := 0.75

# ---------------------------------------------------------------------------------------------------
# L'ÉTAT (dans le jeu)
# ---------------------------------------------------------------------------------------------------
var analyse := {}                    # voir analyser()
var comps: Array = []                # compartiments simulés (la cabine d'abord)
var consigne := P_MER                # Pa
var a_survie := false                # système de survie à bord (régulateur, réserves, recycleur)
var recycleur := false
var reserve_o2 := 0.0                # kg
var reserve_n2 := 0.0                # kg
var vanne_ouverte := false           # vanne de la cabine (F4) : vide la cabine sans pousser le vaisseau
var force := Vector3.ZERO            # N, repère du plan : poussée des jets d'air (moyenne du dernier pas)
var moment := Vector3.ZERO           # N·m autour de l'origine du plan
var debit_fuite := 0.0               # kg/s d'air perdu par les trous de la cabine (pas la vanne ni les soupapes)
var debit_reserve := 0.0             # kg/s pris dans les réserves par le régulateur
var debit_reserve_o2 := 0.0          # dont oxygène
var debit_reserve_n2 := 0.0          # dont azote
var evenements: Array = []           # textes à montrer au pilote (une paroi a cédé…), vidés par le jeu
var hypoxie := 0.0                   # 0 → 1 : part du temps de conscience utile déjà passée
var temps_conscience := INF          # s avant de perdre connaissance (INF : assez d'oxygène)
var p_dehors := 0.0


func _init(a: Dictionary = {}) -> void:
	analyse = a
	remettre()


## La vie à bord d'un vaisseau (null : il n'a pas de cabine).
static func pour(plan):
	var a := analyser(plan)
	if not bool(a["a_cabine"]):
		return null
	return load("res://scripts/physique/vie_a_bord.gd").new(a)


## Tout comme au départ : cabine pleine à la consigne, réserves pleines, parois entières, vanne fermée.
func remettre() -> void:
	comps = []
	force = Vector3.ZERO
	moment = Vector3.ZERO
	debit_fuite = 0.0
	debit_reserve = 0.0
	debit_reserve_o2 = 0.0
	debit_reserve_n2 = 0.0
	evenements = []
	hypoxie = 0.0
	temps_conscience = INF
	vanne_ouverte = false
	if analyse.is_empty():
		return
	consigne = float(analyse["consigne"])
	var s: Dictionary = analyse["survie"]
	a_survie = bool(s["present"])
	recycleur = bool(s["recycleur"])
	reserve_o2 = float(s["oxygene_kg"])
	reserve_n2 = float(s["azote_kg"])
	for c in analyse["compartiments"]:
		if not bool(c["pressurise"]):
			continue
		var v := float(c["volume_m3"])
		var masses := masses_air(consigne, v)
		var parois := []
		for i in c["parois"]:
			var w: Dictionary = analyse["parois"][i]
			if bool(w["presente"]) and bool(w["etanche"]):
				parois.append({"nom": w["nom"], "p_rupture": float(w["p_rupture_pa"]), "surface": float(w["surface_m2"]),
					"centre": w["centre"], "normale": w["normale"], "casse": false})
		var trous := []
		for t in c["trous"]:
			trous.append(t.duplicate())
		comps.append({"nom": c["nom"], "cabine": bool(c["cabine"]), "volume": v, "m_o2": masses[0], "m_n2": masses[1],
			"parois": parois, "trous": trous, "regule": a_survie and bool(c["cabine"])})   # le régulateur ne sert que la cabine


## Masses d'oxygène et d'azote (kg) pour remplir v m³ à la pression p, avec 21,2 kPa d'oxygène.
static func masses_air(p: float, v: float) -> Array:
	var ppo2 := minf(PPO2_CIBLE, p)
	return [ppo2 * v * M_O2 / (R * T_CABINE), maxf(p - ppo2, 0.0) * v * M_N2 / (R * T_CABINE)]


static func pression_de(c: Dictionary) -> float:
	return (float(c["m_o2"]) / M_O2 + float(c["m_n2"]) / M_N2) * R * T_CABINE / float(c["volume"])


static func ppo2_de(c: Dictionary) -> float:
	return float(c["m_o2"]) / M_O2 * R * T_CABINE / float(c["volume"])


func pression_cabine() -> float:
	return pression_de(comps[0]) if not comps.is_empty() else P_MER


func ppo2_cabine() -> float:
	return ppo2_de(comps[0]) if not comps.is_empty() else PPO2_CIBLE


## Surface des trous de la cabine (m²), parois cassées comprises (pas la vanne).
func surface_trous_cabine() -> float:
	var s := 0.0
	if not comps.is_empty():
		for t in comps[0]["trous"]:
			s += float(t["surface"])
	return s


func fuite() -> bool:
	return debit_fuite > FUITE_MIN


## Secondes avant qu'une des réserves (oxygène ou azote) soit vide au débit actuel du régulateur (INF : il
## ne puise pas).
func autonomie() -> float:
	var t := INF
	if debit_reserve_o2 > 1.0e-12:
		t = minf(t, reserve_o2 / debit_reserve_o2)
	if debit_reserve_n2 > 1.0e-12:
		t = minf(t, reserve_n2 / debit_reserve_n2)
	return t


func inconscient() -> bool:
	return hypoxie >= 1.0


func ouvrir_vanne(oui: bool) -> void:
	vanne_ouverte = oui


## Un pas de temps : p_ext et t_ext = pression (Pa, 0 dans le vide) et température (K) de l'air du dehors.
func pas(dt: float, p_ext: float, t_ext: float) -> void:
	force = Vector3.ZERO
	moment = Vector3.ZERO
	debit_fuite = 0.0
	debit_reserve = 0.0
	debit_reserve_o2 = 0.0
	debit_reserve_n2 = 0.0
	p_dehors = maxf(p_ext, 0.0)
	if comps.is_empty() or dt <= 0.0:
		return
	var t_dehors := t_ext if t_ext > 1.0 else T_CABINE
	_ruptures()
	# le pilote respire (le recycleur rend une partie de l'oxygène)
	var cab: Dictionary = comps[0]
	cab["m_o2"] = maxf(float(cab["m_o2"]) - CONSOMMATION_O2 * dt * ((1.0 - PART_RECYCLEE) if recycleur else 1.0), 0.0)
	var reste := dt
	var n := 0
	var imp := Vector3.ZERO
	var mom := Vector3.ZERO
	var perdu := 0.0
	var pris_gaz := Vector2.ZERO   # kg d'oxygène, d'azote pris dans les réserves
	while reste > 0.0:
		n += 1
		var h := reste
		var flux := []
		for c in comps:
			var f := _debits(c, t_dehors)
			flux.append(f)
			var echange := float(f["sortie"]) + float(f["entree"])
			if echange > 0.0:
				var m_ref := maxf(float(c["m_o2"]) + float(c["m_n2"]), p_dehors * float(c["volume"]) * M_AIR / (R * t_dehors))
				h = minf(h, FRACTION_SOUS_PAS * m_ref / echange)
		if n >= SOUS_PAS_MAX:
			h = reste
		for i in comps.size():
			var c: Dictionary = comps[i]
			var f: Dictionary = flux[i]
			var avant := pression_de(c) - p_dehors
			c["m_o2"] = maxf(float(c["m_o2"]) + float(f["o2"]) * h, 0.0)
			c["m_n2"] = maxf(float(c["m_n2"]) + float(f["n2"]) * h, 0.0)
			if bool(f["ouvert"]):
				_borner(c, avant)
			imp += (f["force"] as Vector3) * h
			mom += (f["moment"] as Vector3) * h
			if bool(c["cabine"]):
				perdu += float(f["fuite"]) * h   # (l'air perdu par une soute ne compte pas comme une fuite de la cabine)
			pris_gaz += _reguler(c, h)
		reste -= h
	force = imp / dt
	moment = mom / dt
	debit_fuite = perdu / dt
	debit_reserve = (pris_gaz.x + pris_gaz.y) / dt
	debit_reserve_o2 = pris_gaz.x / dt
	debit_reserve_n2 = pris_gaz.y / dt
	_respirer(dt)


## Les parois qui ne tiennent plus la différence de pression cassent : elles deviennent un trou.
func _ruptures() -> void:
	for c in comps:
		var dp := absf(pression_de(c) - p_dehors)
		var cedees := []
		for w in c["parois"]:
			if bool(w["casse"]) or dp <= float(w["p_rupture"]):
				continue
			w["casse"] = true
			cedees.append(w)
			(c["trous"] as Array).append({"nom": w["nom"], "surface": w["surface"], "centre": w["centre"], "normale": w["normale"],
				"raison": "paroi cassée"})
		if cedees.is_empty():
			continue
		# un message par volume : la paroi qui a cédé (ou combien), et ce qu'elle tenait
		var ou := "" if bool(c["cabine"]) else String(c["nom"]).to_upper() + " : "
		var tenait := 0.0
		for w in cedees:
			tenait = maxf(tenait, float(w["p_rupture"]))
		if cedees.size() == 1 and ou == "":
			evenements.append("%s A CÉDÉ (%s kPa de différence, elle en tenait %s)" % [String(cedees[0]["nom"]).to_upper(),
				_kpa(dp), _kpa(tenait)])
		elif cedees.size() == 1:
			evenements.append("%s%s A CÉDÉ (%s kPa de différence)" % [ou, String(cedees[0]["nom"]).to_upper(), _kpa(dp)])
		else:
			evenements.append("%s%d PAROIS ONT CÉDÉ (%s kPa de différence)" % [ou, cedees.size(), _kpa(dp)])


static func _kpa(p: float) -> String:
	return ("%.0f" % (p / 1000.0)) if p >= 10000.0 else ("%.1f" % (p / 1000.0))


## Débits d'un compartiment (kg/s, + = entre) par ses trous, la vanne et les soupapes ; poussée des jets.
func _debits(c: Dictionary, t_dehors: float) -> Dictionary:
	var p := pression_de(c)
	var m_tot := float(c["m_o2"]) + float(c["m_n2"])
	var x_o2 := float(c["m_o2"]) / m_tot if m_tot > 0.0 else X_O2_AIR
	var m_mol := 1.0 / (x_o2 / M_O2 + (1.0 - x_o2) / M_N2)
	var voies := []   # [surface, centre, normale, compte comme fuite]
	for t in c["trous"]:
		voies.append([float(t["surface"]), t["centre"], t["normale"], true])
	if bool(c["cabine"]) and vanne_ouverte:
		voies.append([SURFACE_VANNE, Vector3.ZERO, Vector3.ZERO, false])
	if bool(c["regule"]):
		if p > consigne + SURPRESSION or p_dehors > p + DEPRESSION:
			voies.append([SURFACE_SOUPAPE, Vector3.ZERO, Vector3.ZERO, false])
	var sortie := 0.0
	var entree := 0.0
	var fuite_kg := 0.0
	var f_tot := Vector3.ZERO
	var m_tot_c := Vector3.ZERO
	for v in voies:
		var a := CD * float(v[0])
		if p > p_dehors:
			var e := ecoulement(a, p, T_CABINE, m_mol, p_dehors)
			sortie += e.x
			if bool(v[3]):
				fuite_kg += e.x
			var nv: Vector3 = v[2]
			if nv != Vector3.ZERO:
				var f := -nv * e.y        # l'air part le long de la normale : le vaisseau est poussé à l'opposé
				f_tot += f
				m_tot_c += (v[1] as Vector3).cross(f)
		elif p_dehors > p:
			entree += ecoulement(a, p_dehors, t_dehors, M_AIR, p).x
	return {"o2": -sortie * x_o2 + entree * X_O2_AIR, "n2": -sortie * (1.0 - x_o2) + entree * (1.0 - X_O2_AIR),
		"sortie": sortie, "entree": entree, "fuite": fuite_kg, "force": f_tot, "moment": m_tot_c, "ouvert": not voies.is_empty()}


## Un sous-pas trop long ne doit pas faire passer la pression de l'autre côté de celle du dehors.
func _borner(c: Dictionary, avant: float) -> void:
	var p := pression_de(c)
	if avant * (p - p_dehors) >= 0.0 or p <= 0.0:
		return
	var k := p_dehors / p
	c["m_o2"] = float(c["m_o2"]) * k
	c["m_n2"] = float(c["m_n2"]) * k


## Le régulateur remet ce qui manque (oxygène d'abord), sans dépasser son débit ni les réserves. Renvoie
## les kg pris dans les réserves.
func _reguler(c: Dictionary, h: float) -> Vector2:
	if not bool(c["regule"]) or (bool(c["cabine"]) and vanne_ouverte):
		return Vector2.ZERO   # vanne ouverte : on vide la cabine, le régulateur est coupé (il la remplit quand elle se ferme)
	var cible := masses_air(consigne, float(c["volume"]))
	var max_h := DEBIT_REGULATEUR * h
	var a_o2 := clampf(float(cible[0]) - float(c["m_o2"]), 0.0, minf(max_h, reserve_o2))
	var a_n2 := clampf(float(cible[1]) - float(c["m_n2"]), 0.0, minf(max_h - a_o2, reserve_n2))
	c["m_o2"] = float(c["m_o2"]) + a_o2
	c["m_n2"] = float(c["m_n2"]) + a_n2
	reserve_o2 -= a_o2
	reserve_n2 -= a_n2
	return Vector2(a_o2, a_n2)


func _respirer(dt: float) -> void:
	var tuc := temps_conscience_utile(ppo2_cabine())
	if tuc < INF:
		hypoxie = minf(hypoxie + dt / tuc, 1.0)
		temps_conscience = (1.0 - hypoxie) * tuc
	else:
		hypoxie = maxf(hypoxie - dt / RECUPERATION_S, 0.0)
		temps_conscience = INF


## Temps de conscience utile (s) avec cette pression d'oxygène (INF : assez d'oxygène).
static func temps_conscience_utile(ppo2: float) -> float:
	if ppo2 >= SEUIL_HYPOXIE:
		return INF
	for k in range(1, CONSCIENCE.size()):
		var a: Array = CONSCIENCE[k - 1]
		var b: Array = CONSCIENCE[k]
		if ppo2 >= float(b[0]):
			var u := (ppo2 - float(b[0])) / (float(a[0]) - float(b[0]))
			return lerpf(float(b[1]), float(a[1]), u)
	return float(CONSCIENCE[-1][1])


## Débit (kg/s, x) et poussée du jet (N, y) d'un gaz qui passe par un trou de surface utile a (m², déjà
## multipliée par le coefficient de débit), de la pression p1 (température t1, masse molaire m_mol) vers p2.
static func ecoulement(a: float, p1: float, t1: float, m_mol: float, p2: float) -> Vector2:
	if a <= 0.0 or p1 <= p2 or p1 <= 0.0:
		return Vector2.ZERO
	var g := GAMMA
	var rs := R / m_mol
	var r := p2 / p1
	var rc := pow(2.0 / (g + 1.0), g / (g - 1.0))          # 0,528 : au-delà, le jet sort à la vitesse du son
	if r <= rc:
		var debit := a * p1 * sqrt(g / (rs * t1)) * pow(2.0 / (g + 1.0), (g + 1.0) / (2.0 * (g - 1.0)))
		var u := sqrt(g * rs * t1 * 2.0 / (g + 1.0))          # vitesse du son dans le jet
		return Vector2(debit, debit * u + (p1 * rc - p2) * a)
	var k := 2.0 * g / (g - 1.0)
	var debit2 := a * p1 * sqrt(k / (rs * t1) * (pow(r, 2.0 / g) - pow(r, (g + 1.0) / g)))
	var u2 := sqrt(k * rs * t1 * (1.0 - pow(r, (g - 1.0) / g)))
	return Vector2(debit2, debit2 * u2)


# ---------------------------------------------------------------------------------------------------
# L'ANALYSE (atelier et jeu) : compartiments, parois, réserves
# ---------------------------------------------------------------------------------------------------
## La section « vie » du plan. Un vaisseau enregistré avant l'étape 8 à partir du chasseur garde la
## cabine du chasseur (mêmes pièces).
static func section(plan) -> Dictionary:
	var d: Dictionary = plan.donnees
	if d.get("vie", null) is Dictionary:
		return d["vie"]
	for p in plan.pieces:
		if String(p.get("id", "")) == "Cockpit_verriere":
			var defaut = Plan.par_defaut()
			if defaut != plan and defaut.donnees.get("vie", null) is Dictionary:
				return defaut.donnees["vie"]
			break
	return {}


## {a_cabine, consigne (Pa), survie {present, piece, oxygene_kg, azote_kg, recycleur}, compartiments [
##  {id, nom, cabine, volume_m3, pressurise, ferme, parois [indices], trous [{nom, surface, centre, normale,
##  raison}], panneaux [ids]}], parois [{id, nom, genre (coque, plaque), element {genre, id}, dessins (autres
##  pièces qui la dessinent), matiere,
##  epaisseur_m, surface_m2, rayon_m, p_rupture_pa, marge, presente, etanche, centre, normale,
##  compartiment}], ouverts [{panneaux, bords_ouverts}], pire_marge, pire_paroi (indice ou -1)}
static func analyser(plan) -> Dictionary:
	var vie := section(plan)
	var res := {"a_cabine": false, "consigne": P_MER, "compartiments": [], "parois": [], "ouverts": [], "pire_marge": INF,
		"pire_paroi": -1, "survie": {"present": false, "piece": "", "oxygene_kg": 0.0, "azote_kg": 0.0, "recycleur": false}}
	var par_id := {}
	for p in plan.pieces:
		par_id[String(p["id"])] = p
	res["consigne"] = clampf(float(vie.get("pression_kpa", P_MER / 1000.0)), PRESSION_MIN_KPA, PRESSION_MAX_KPA) * 1000.0
	# le système de survie (régulateur, réserves, recycleur)
	var s: Dictionary = vie.get("survie", {})
	var piece_s := String(s.get("piece", ""))
	var present := not s.is_empty() and (piece_s == "" or par_id.has(piece_s))
	res["survie"] = {"present": present, "piece": piece_s, "oxygene_kg": float(s.get("oxygene_kg", 0.0)) if present else 0.0,
		"azote_kg": float(s.get("azote_kg", 0.0)) if present else 0.0,
		"recycleur": present and bool(vie.get("recycleur", true))}
	# 1. la cabine du pilote
	var cab: Dictionary = vie.get("cabine", {})
	if not cab.is_empty():
		var c := {"id": "cabine", "nom": String(cab.get("nom", "cabine du pilote")), "cabine": true,
			"volume_m3": float(cab.get("volume_m3", 0.0)), "pressurise": true, "ferme": true, "parois": [], "trous": [], "panneaux": []}
		for w in cab.get("parois", []):
			var paroi := _paroi_coque(w, par_id.get(String(w.get("piece", "")), {}))
			_ajouter_paroi(res, c, paroi)
		if float(c["volume_m3"]) > 0.0:
			res["compartiments"].append(c)
			res["a_cabine"] = true
	# 2. les volumes fermés de l'armature
	var soutes: Array = vie.get("soutes", [])
	for v in volumes_armature(plan.donnees):
		var pressurise := false
		for pid in v["panneaux"]:
			if soutes.has(pid):
				pressurise = true
		if not bool(v["ferme"]):
			res["ouverts"].append({"panneaux": v["panneaux"], "bords_ouverts": v["bords_ouverts"], "pressurise": pressurise})
			continue
		var c2 := {"id": "soute:" + String(v["panneaux"][0]), "nom": "volume fermé %d" % (res["compartiments"].size() + (0 if res["a_cabine"] else 1)),
			"cabine": false, "volume_m3": float(v["volume_m3"]), "pressurise": pressurise, "ferme": true, "parois": [], "trous": [],
			"panneaux": v["panneaux"]}
		for f in v["faces"]:
			_ajouter_paroi(res, c2, _paroi_plaque(f))
		res["compartiments"].append(c2)
	# la paroi la plus faible (compartiments pressurisés)
	for c3 in res["compartiments"]:
		if not bool(c3["pressurise"]):
			continue
		for i in c3["parois"]:
			var w: Dictionary = res["parois"][i]
			w["marge"] = float(w["p_rupture_pa"]) / float(res["consigne"])
			if bool(w["presente"]) and bool(w["etanche"]) and float(w["marge"]) < float(res["pire_marge"]):
				res["pire_marge"] = w["marge"]
				res["pire_paroi"] = i
	return res


static func _ajouter_paroi(res: Dictionary, c: Dictionary, paroi: Dictionary) -> void:
	paroi["compartiment"] = res["compartiments"].size()
	paroi["marge"] = float(paroi["p_rupture_pa"]) / float(res["consigne"])
	var i: int = res["parois"].size()
	res["parois"].append(paroi)
	c["parois"].append(i)
	if not bool(paroi["presente"]):
		c["trous"].append({"nom": paroi["nom"], "surface": paroi["surface_m2"], "centre": paroi["centre"], "normale": paroi["normale"],
			"raison": "paroi enlevée"})
	elif not bool(paroi["etanche"]):
		c["trous"].append({"nom": paroi["nom"], "surface": paroi["surface_m2"], "centre": paroi["centre"], "normale": paroi["normale"],
			"raison": "matière qui laisse passer l'air"})


## Une paroi courbe de la cabine (pièce de structure modélisée) : son épaisseur vient de sa masse.
static func _paroi_coque(w: Dictionary, p: Dictionary) -> Dictionary:
	var id := String(w.get("piece", ""))
	var paroi := {"id": id, "nom": String(w.get("nom", id)), "genre": "coque", "element": {"genre": "piece", "id": id},
		"dessins": (w.get("dessins", []) as Array).duplicate(),
		"rayon_m": float(w.get("rayon_m", 1.0)), "normale": Catalogue.vecteur(w.get("normale", [0.0, 0.0, 0.0])),
		"surface_m2": float(w.get("surface_m2", 0.0)), "centre": Catalogue.vecteur(w.get("centre", [0.0, 0.0, 0.0])),
		"matiere": "", "epaisseur_m": 0.0, "p_rupture_pa": 0.0, "presente": not p.is_empty(), "etanche": true}
	if p.is_empty():
		return paroi
	var mat := String(p.get("matiere", "aluminium"))
	var d: Dictionary = Catalogue.MATIERES.get(mat, Catalogue.MATIERES["aluminium"])
	var surface := float(p.get("surface_m2", paroi["surface_m2"]))
	var e := float(p.get("masse_kg", 0.0)) / (float(d["densite"]) * maxf(surface, 1e-6))
	paroi["matiere"] = mat
	paroi["surface_m2"] = surface
	paroi["epaisseur_m"] = e
	paroi["etanche"] = bool(d.get("etanche", true))
	paroi["centre"] = Catalogue.vecteur(p.get("centre", paroi["centre"]))
	paroi["p_rupture_pa"] = rupture_coque(float(d.get("resistance_mpa", 0.0)) * 1.0e6, e, float(paroi["rayon_m"]))
	return paroi


## Un panneau plat de l'armature, bord d'un volume fermé.
static func _paroi_plaque(f: Dictionary) -> Dictionary:
	var e: Dictionary = f["panneau"]
	var r: Dictionary = Armature.reglages_complets(Armature.PANNEAU, e.get("reglages", {}))
	var mat := String(r["matiere"])
	var d: Dictionary = Catalogue.MATIERES.get(mat, Catalogue.MATIERES["aluminium"])
	var pts: Array = f["points"]
	var t := float(r["epaisseur_m"])
	var a := rayon_equivalent(pts)
	return {"id": String(e["id"]), "nom": "panneau " + String(e["id"]).replace("panneau_", "n° "), "genre": "plaque",
		"element": {"genre": "ajout", "id": String(e["id"])}, "dessins": [], "matiere": mat, "epaisseur_m": t,
		"surface_m2": Catalogue.surface_panneau(pts), "rayon_m": a, "centre": f["centre"], "normale": f["normale"],
		"p_rupture_pa": rupture_plaque(float(d.get("resistance_mpa", 0.0)) * 1.0e6, float(d.get("module_gpa", 70.0)) * 1.0e9,
			float(d.get("poisson", 0.3)), t, a),
		"presente": true, "etanche": bool(d.get("etanche", true))}


## Pression (Pa) qui casse une coque mince de rayon r et d'épaisseur e : σ = p·r/e.
static func rupture_coque(sigma: float, e: float, r: float) -> float:
	return sigma * e / maxf(r, 1e-6)


## Pression (Pa) qui casse une plaque plate ronde encastrée de rayon a (grande flèche, Roark : plaque fixe
## et tenue). Pour chaque endroit (centre, bord), la flèche relative w = y/e où la contrainte atteint σ, puis
## la pression qui donne cette flèche ; le premier endroit qui casse décide.
static func rupture_plaque(sigma: float, module: float, nu: float, e: float, a: float) -> float:
	if e <= 0.0 or a <= 0.0 or module <= 0.0:
		return 0.0
	var k1 := 5.33 / (1.0 - nu * nu)
	var k2 := 2.6 / (1.0 - nu * nu)
	var s := sigma * a * a / (module * e * e)
	var w := INF
	for k in [[2.0 / (1.0 - nu), 0.976], [4.0 / (1.0 - nu * nu), 1.73]]:   # centre, bord
		var k3 := float(k[0])
		var k4 := float(k[1])
		w = minf(w, (-k3 + sqrt(k3 * k3 + 4.0 * k4 * s)) / (2.0 * k4))
	return module * pow(e / a, 4.0) * (k1 * w + k2 * w * w * w)


## Rayon de la plaque ronde qui a la même raideur qu'un panneau de 3 ou 4 coins.
static func rayon_equivalent(pts: Array) -> float:
	var surface := Catalogue.surface_panneau(pts)
	if surface <= 1e-9:
		return 0.0
	var tour := 0.0
	for i in pts.size():
		tour += (Catalogue.vecteur(pts[i]) - Catalogue.vecteur(pts[(i + 1) % pts.size()])).length()
	if pts.size() == 3:
		return 1.281 * 2.0 * surface / maxf(tour, 1e-9)   # triangle : 1,28 × le cercle inscrit
	# quadrilatère : rectangle de même surface et de même tour (largeur b, longueur l = surface / b)
	var demi := tour * 0.5
	var delta := maxf(demi * demi - 4.0 * surface, 0.0)
	var b := maxf((demi - sqrt(delta)) * 0.5, 1e-6)
	var l := surface / b
	return b * sqrt(_interpoler(BETA_RECTANGLE, l / b) / BETA_CERCLE)


static func _interpoler(table: Array, x: float) -> float:
	if x <= float(table[0][0]):
		return float(table[0][1])
	for k in range(1, table.size()):
		if x <= float(table[k][0]):
			var a: Array = table[k - 1]
			var b: Array = table[k]
			return lerpf(float(a[1]), float(b[1]), (x - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(table[-1][1])


## Les groupes de panneaux de l'armature qui se touchent bord à bord : [{panneaux (ids, triés), ferme,
## bords_ouverts, volume_m3, faces [{panneau, points (tournés vers le dehors), centre, normale}]}].
static func volumes_armature(donnees: Dictionary) -> Array:
	if not Armature.a_armature(donnees):
		return []
	var g := Armature.graphe(donnees)
	var panneaux: Dictionary = g["panneaux"]
	if panneaux.is_empty():
		return []
	var connecteurs: Dictionary = g["connecteurs"]
	var bords := {}      # clé du bord → [panneaux]
	var noeuds := {}     # panneau → [connecteurs], dans l'ordre du tour
	for id in panneaux:
		var n: Array = panneaux[id].get("noeuds", [])
		var ok := n.size() >= 3
		for c in n:
			ok = ok and connecteurs.has(String(c))
		if not ok:
			continue
		noeuds[id] = n
		for i in n.size():
			var k := Armature.cle([n[i], n[(i + 1) % n.size()]])
			if not bords.has(k):
				bords[k] = []
			bords[k].append(id)
	# groupes : panneaux reliés par un bord commun
	var groupe := {}
	var sortie := []
	for depart in noeuds:
		if groupe.has(depart):
			continue
		var liste := [depart]
		groupe[depart] = true
		var k_l := 0
		while k_l < liste.size():
			var id: String = liste[k_l]
			k_l += 1
			var n: Array = noeuds[id]
			for i in n.size():
				for autre in bords[Armature.cle([n[i], n[(i + 1) % n.size()]])]:
					if not groupe.has(autre):
						groupe[autre] = true
						liste.append(autre)
		sortie.append(_volume_groupe(liste, noeuds, bords, connecteurs, panneaux))
	return sortie


static func _volume_groupe(liste: Array, noeuds: Dictionary, bords: Dictionary, connecteurs: Dictionary, panneaux: Dictionary) -> Dictionary:
	liste.sort()
	var ouverts := 0
	var multiples := 0
	var vus := {}
	for id in liste:
		var n: Array = noeuds[id]
		for i in n.size():
			var k := Armature.cle([n[i], n[(i + 1) % n.size()]])
			if vus.has(k):
				continue
			vus[k] = true
			var nb: int = (bords[k] as Array).size()
			if nb == 1:
				ouverts += 1
			elif nb > 2:
				multiples += 1
	var res := {"panneaux": liste, "ferme": ouverts == 0 and multiples == 0 and liste.size() >= 4, "bords_ouverts": ouverts,
		"volume_m3": 0.0, "faces": []}
	if not bool(res["ferme"]):
		return res
	# orienter les panneaux de proche en proche : deux voisins parcourent leur bord commun en sens inverse
	var sens := {liste[0]: 1}
	var file := [liste[0]]
	var k_f := 0
	while k_f < file.size():
		var id: String = file[k_f]
		k_f += 1
		var n: Array = _tour(noeuds[id], int(sens[id]))
		for i in n.size():
			var a := String(n[i])
			var b := String(n[(i + 1) % n.size()])
			for autre in bords[Armature.cle([a, b])]:
				if sens.has(autre) or autre == id:
					continue
				var m: Array = noeuds[autre]
				var meme := false
				for j in m.size():
					if String(m[j]) == a and String(m[(j + 1) % m.size()]) == b:
						meme = true
				sens[autre] = -1 if meme else 1
				file.append(autre)
	var volume := 0.0
	var faces := []
	for id in liste:
		var pts := []
		for c in _tour(noeuds[id], int(sens.get(id, 1))):
			pts.append(Armature.position(connecteurs[String(c)]))
		var centre := Vector3.ZERO
		for q in pts:
			centre += q
		centre /= float(pts.size())
		var normale := Vector3.ZERO
		for t in Catalogue.triangles_panneau(pts):
			var p0: Vector3 = pts[t[0]]
			var p1: Vector3 = pts[t[1]]
			var p2: Vector3 = pts[t[2]]
			volume += p0.dot(p1.cross(p2)) / 6.0
			normale += (p1 - p0).cross(p2 - p0)
		faces.append({"panneau": panneaux[id], "points": pts, "centre": centre, "normale": normale.normalized()})
	if volume < 0.0:
		volume = -volume
		for f in faces:
			f["normale"] = -(f["normale"] as Vector3)
			(f["points"] as Array).reverse()
	res["volume_m3"] = volume
	res["faces"] = faces
	if volume < 0.001:
		res["ferme"] = false   # tout à plat : ce n'est pas un volume
	return res


static func _tour(n: Array, s: int) -> Array:
	var t := n.duplicate()
	if s < 0:
		t.reverse()
	return t
