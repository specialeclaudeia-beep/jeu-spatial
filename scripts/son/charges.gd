extends RefCounted
## Tension de chaque pièce sonore (moteur audio, phase 4) : le principe de d'Alembert, exact pour un corps rigide.
##
## Le vaisseau de la physique est parfaitement rigide : il ne se tord pas. Mais on connaît, à chaque pas, son
## accélération ressentie, sa rotation et sa variation de rotation, et toutes les forces qui le poussent, à
## l'endroit où elles poussent. Une pièce (une aile, une jambe du train…) suit le vaisseau : pour cela, il faut
## que son attache lui donne exactement la force qui lui manque. C'est la charge de l'attache :
##     force  = Σ m a (ce qu'il faut pour que chaque masse de la pièce suive)  −  ce qui pousse déjà la pièce
##     moment = la même chose, en moments autour de l'attache
## « Ce qui pousse déjà » : son moteur, l'air sur elle (prise de aerodynamique.gd), le sol sur sa roue (prise de
## _forces_sol), la pression de la cabine sur la verrière, et la marée (près d'un trou noir, l'avant est plus attiré
## que l'arrière : le vaisseau est étiré). La pesanteur, elle, tire pareil sur toutes les masses : elle ne charge
## aucune attache en chute libre (le pilote en orbite ne sent rien) ; posé, c'est le sol qui charge le train.
##
## Pour une pièce de masse m, de centre c, d'attache a (positions vues du centre de gravité) :
##     F = m (a₀ + α × c + ω × (ω × c))
##     M = m (c − a) × (a₀ + α × a + ω × (ω × a)) + J α + ω × (J ω)       (J : inertie de la pièce autour de a)
## a₀ = accélération ressentie, ω = rotation, α = sa variation. C'est exact (pas d'approximation).
##
## TAUX DE CHARGE (0 à 1, 1 = rupture) : le modèle 3D donne les masses, pas l'épaisseur des longerons. On suppose
## donc que chaque pièce a été dimensionnée comme une vraie : la plus forte charge des cas de calcul (ressource à 9 g,
## poussée à −3 g, dérapage, pleine poussée × 1,25, vol vertical, posé à 3 m/s, posé sur une seule roue, virage au sol,
## freinage, cabine à 1,33 fois sa pression) multipliée par 1,5 (coefficient de sécurité des avions) donne la rupture. Ces cas sont calculés avec la
## VRAIE aérodynamique du jeu (aerodynamique.gd, à part, sans toucher la physique) au démarrage. Le taux est le plus
## grand rapport charge / rupture des 6 composantes (3 forces, 3 moments). Un vol normal : 0,05 à 0,2 ; la limite
## d'un cas de calcul : 0,67.
## Rien ici n'écrit dans la physique.

const Capteurs = preload("res://scripts/son/capteurs.gd")
const Pieces = preload("res://scripts/son/pieces_sonores.gd")
const Aerodynamique = preload("res://scripts/physique/aerodynamique.gd")

const SECURITE := 1.5            # rupture = 1,5 × la plus forte charge des cas de calcul
const G0 := 9.80665
const PLANCHER := 0.25           # une composante a au moins 25 % de la résistance de la plus forte de sa sorte
const MAREE_MIN := 1.0e-6        # s⁻² : en dessous, la marée ne charge rien d'audible (planète : 1e-6 ; trou noir : énorme)
const LISSAGE := 0.02            # s : variation de la charge lissée sur 20 ms
const DESCENTE_POSE := 3.05      # m/s : vitesse de descente du cas « posé » (règlements des avions : 10 pieds/s)
## Déformation à la rupture, pour l'énergie élastique que la pièce garde (craquements, relâchements) :
## ~1 % de rotation à l'emplanture et ~1 mm de cisaillement.
const ROTATION_RUPTURE := 0.01
const GLISSEMENT_RUPTURE := 0.001

var modele := Pieces.new()
var n := 0
var noms := PackedStringArray()
var matieres := PackedStringArray()
var masses := PackedFloat64Array()
var centres := PackedVector3Array()       # vus du centre de gravité
var attaches := PackedVector3Array()      # vues du centre de gravité
var attaches_modele := PackedVector3Array()   # repère du modèle (pour placer les sons)
var jonctions := PackedFloat64Array()     # dB perdus en plus sur le chemin jusqu'au pilote (emplanture)
var _d := PackedVector3Array()
var _s: Array = []                        # Basis : Σ m ρ ρᵀ autour de l'attache
var _j: Array = []                        # Basis : inertie autour de l'attache
var _propulseurs: Array = []              # par pièce : n° des propulseurs qui poussent sur elle
var _sol: Array = []                      # par pièce : n° des points du sol qui la touchent
var _air: Array = []                      # par pièce : n° des surfaces d'air (aerodynamique.gd) qui la poussent
var _pression := PackedByteArray()        # 1 = la pression de la cabine la pousse (verrière)
var _geo := -1
var _train := -1.0
var _nombre := -1

## Résultats (après calculer) : force et moment que l'attache exerce sur la pièce, repère du vaisseau.
var force := PackedVector3Array()
var moment := PackedVector3Array()
var taux := PackedFloat64Array()          # 0..1 (1 = rupture)
var variation := PackedFloat64Array()     # 1/s : vitesse de variation du taux, lissée
var limite_f := PackedVector3Array()      # N : rupture de chaque composante
var limite_m := PackedVector3Array()      # N·m
var energie_rupture := PackedFloat64Array()   # J : énergie élastique gardée par la pièce à la rupture
var pret := false
var _taux_avant := PackedFloat64Array()


func _init() -> void:
	n = modele.pieces.size()
	for p in modele.pieces:
		noms.append(p["nom"])
		matieres.append(p["matiere"])
		jonctions.append(float(p.get("jonction_db", 0.0)))
		_air.append(PackedInt32Array(p["air"]))
		_pression.append(1 if p.has("pression") else 0)
	for a in [masses, taux, variation, energie_rupture, _taux_avant]:
		a.resize(n)
	for a in [centres, attaches, attaches_modele, _d, force, moment, limite_f, limite_m]:
		a.resize(n)
	_s.resize(n)
	_j.resize(n)


## Masse, centre, attache et inertie de chaque pièce, pour la géométrie actuelle (ailes, tuyère, train).
func _geometrie(c: Capteurs) -> void:
	_geo = c.geometrie
	_train = c.train_sorti
	var cg := c.centre_gravite
	for i in n:
		var p: Dictionary = modele.pieces[i]
		var att := Pieces.attache(p, c.charnieres, c.angles_ailes)
		attaches_modele[i] = att
		var ra := att - cg
		var m := 0.0
		var mc := Vector3.ZERO
		var pos := []
		for pt in p["points"]:
			var q := Pieces.position(pt, c.charnieres, c.angles_ailes, c.angle_tuyere, c.pivot_tuyere, c.train_sorti) - cg
			pos.append(q)
			m += float(pt[1])
			mc += q * float(pt[1])
		var sx := Vector3.ZERO
		var sy := Vector3.ZERO
		var sz := Vector3.ZERO
		for k in pos.size():
			var r: Vector3 = (pos[k] as Vector3) - ra
			var mk := float(p["points"][k][1])
			sx += r * (mk * r.x)
			sy += r * (mk * r.y)
			sz += r * (mk * r.z)
		var s := Basis(sx, sy, sz)
		var tr := sx.x + sy.y + sz.z
		_s[i] = s
		_j[i] = Basis(Vector3(tr, 0, 0) - sx, Vector3(0, tr, 0) - sy, Vector3(0, 0, tr) - sz)
		masses[i] = m
		centres[i] = mc / maxf(m, 1e-9)
		attaches[i] = ra
		_d[i] = centres[i] - ra
	if c.nombre != _nombre:
		_repartir(c)


## Quels propulseurs et quels points du sol poussent sur chaque pièce.
func _repartir(c: Capteurs) -> void:
	_nombre = c.nombre
	_propulseurs.clear()
	_sol.clear()
	for p in modele.pieces:
		var liste := PackedInt32Array()
		for t in c.nombre:
			var sur := false
			var aile: int = c.aile_de[t] if t < c.aile_de.size() else -1
			if p.has("reacteur"):
				sur = aile == int(p["aile"]) and c.types[t] != Capteurs.TYPE_RCS
			elif int(p.get("aile", -1)) >= 0:
				sur = aile == int(p["aile"])
			elif p.has("central"):
				sur = c.types[t] == Capteurs.TYPE_MOTEUR and aile < 0 and c.positions[t].z > 2.0
			elif p.has("nez"):
				sur = c.types[t] == Capteurs.TYPE_LEVAGE or (aile < 0 and c.positions[t].z < Pieces.Z_NEZ)
			if sur:
				liste.append(t)
		_propulseurs.append(liste)
		var s := PackedInt32Array()
		if p.has("roue"):
			s.append(int(p["roue"]))
		elif p.has("nez"):
			for k in c.points_sol.size():
				if c.points_sol[k].z < Pieces.Z_NEZ:
					s.append(k)
		_sol.append(s)


## Charges de toutes les pièces pour la photo c (sans le taux).
func charger(c: Capteurs) -> void:
	if c.geometrie != _geo or absf(c.train_sorti - _train) > 0.005 or c.nombre != _nombre:
		_geometrie(c)
	var a0 := c.acceleration
	var w := c.omega
	var al := c.alpha
	var cg := c.centre_gravite
	var dp := c.pression_cabine - c.pression_dehors   # étape 8 : la cabine qui fuit ne pousse plus ses parois
	var maree := c.maree_k > MAREE_MIN
	var nn := c.maree_dir
	var k_m := c.maree_k
	var n_air := c.air_f.size()
	for i in n:
		var m := masses[i]
		var ci := centres[i]
		var ra := attaches[i]
		var j: Basis = _j[i]
		var f := (a0 + al.cross(ci) + w.cross(w.cross(ci))) * m
		var a_att := a0 + al.cross(ra) + w.cross(w.cross(ra))
		var mo := _d[i].cross(a_att) * m + j * al + w.cross(j * w)
		if maree:
			# la marée tire chaque masse vers k (3 n (n·r) − r) : une force du dehors, comme le moteur
			f -= (nn * (3.0 * nn.dot(ci)) - ci) * (k_m * m)
			mo -= _d[i].cross((nn * (3.0 * nn.dot(ra)) - ra) * k_m) * m + ((_s[i] as Basis) * nn).cross(nn) * (3.0 * k_m)
		for t in _propulseurs[i]:
			var ft: Vector3 = c.directions[t] * c.forces[t]
			if ft != Vector3.ZERO:
				f -= ft
				mo -= (c.positions[t] - cg - ra).cross(ft)
		for g in _air[i]:
			if g < n_air:
				f -= c.air_f[g]
				mo -= c.air_c[g] - ra.cross(c.air_f[g])
		for s in _sol[i]:
			if s < c.sol_f.size():
				var fs: Vector3 = c.sol_f[s]
				f -= fs
				mo -= (c.points_sol[s] - cg - ra).cross(fs)
		if _pression[i] == 1:
			var fp := Pieces.VERRIERE_NORMALE.normalized() * (dp * Pieces.VERRIERE_SURFACE)
			f -= fp
			mo -= (Pieces.VERRIERE_CENTRE - cg - ra).cross(fp)
		force[i] = f
		moment[i] = mo


## Charges, taux et variation (120 fois par seconde). dt : temps réel depuis la photo précédente.
func calculer(c: Capteurs, dt: float) -> void:
	if not pret:
		calibrer(c)
	charger(c)
	var k := clampf(dt / LISSAGE, 0.0, 1.0)
	for i in n:
		var t := taux_de(force[i], moment[i], limite_f[i], limite_m[i])
		var brut := (t - _taux_avant[i]) / dt if dt > 0.0 else 0.0
		variation[i] += (brut - variation[i]) * k
		_taux_avant[i] = t
		taux[i] = t


static func taux_de(f: Vector3, m: Vector3, lf: Vector3, lm: Vector3) -> float:
	return maxf(maxf(maxf(absf(f.x) / lf.x, absf(f.y) / lf.y), maxf(absf(f.z) / lf.z, absf(m.x) / lm.x)),
		maxf(absf(m.y) / lm.y, absf(m.z) / lm.z))


# =====================================================================
# CAS DE CALCUL (au démarrage) : la résistance de chaque pièce
# =====================================================================
## Les cas de calcul, chacun une photo « fabriquée » (même géométrie que le vaisseau : ailes ouvertes, vol normal).
func cas_de_calcul(c: Capteurs) -> Dictionary:
	var cas := {}
	var base := _photo_vide(c)
	var m := c.masse
	# 1 à 3 : l'air, avec la vraie aérodynamique du jeu (une copie à part : la physique n'en sait rien)
	var aero := Aerodynamique.new()
	var echelle_9g := 0.0
	for e in [["ressource 9 g", 12.0, 0.0, 9.0], ["poussée −3 g", -6.0, 0.0, -3.0], ["dérapage", 4.0, 8.0, 0.0]]:
		var a := deg_to_rad(float(e[1]))
		var b := deg_to_rad(float(e[2]))
		var vent := Vector3(sin(b), sin(a), cos(a) * cos(b)).normalized() * 250.0
		aero.forces(vent, Vector3.ZERO, 1.0, 300.0, 1.0, 0.0)
		var tot := Vector3.ZERO
		for f in aero.prise_f:
			tot += f
		var s := echelle_9g
		if float(e[3]) != 0.0:
			s = float(e[3]) * G0 * m / tot.y
		if echelle_9g == 0.0:
			echelle_9g = s
		var ph := _copie(base)
		for g in aero.prise_surfaces:
			ph.air_f[g] = aero.prise_f[g] * s
			ph.air_c[g] = aero.prise_c[g] * s
		ph.acceleration = tot * s / m
		cas[e[0]] = ph
	# 4 : pleine poussée × 1,25 (tous les moteurs arrière, vol normal)
	var pp := _copie(base)
	var somme := Vector3.ZERO
	for t in c.nombre:
		if c.types[t] == Capteurs.TYPE_MOTEUR:
			pp.forces[t] = 1.25 * c.poussee_reference
			somme += pp.directions[t] * pp.forces[t]
	pp.acceleration = somme / m
	cas["pleine poussée"] = pp
	# 5 : vol vertical à pleine poussée (moteurs de levage et moteur central vers le haut)
	var vv := _copie(base)
	somme = Vector3.ZERO
	for t in c.nombre:
		var central := c.types[t] == Capteurs.TYPE_MOTEUR and c.aile_de[t] < 0
		if c.types[t] == Capteurs.TYPE_LEVAGE or central:
			vv.forces[t] = 1.25 * (c.poussee_levage if c.types[t] == Capteurs.TYPE_LEVAGE else c.poussee_reference)
			vv.directions[t] = Vector3.UP
			somme += Vector3.UP * vv.forces[t]
	vv.acceleration = somme / m
	cas["vol vertical"] = vv
	# 6 à 11 : le train (cas des règlements des avions) : posé en descendant à 3,05 m/s (10 pieds par seconde)
	# pendant que les roues se mettent à tourner (le pneu frotte : 0,8 fois la charge vers l'arrière) ; à l'instant
	# où la roue touche, c'est l'amortisseur du jeu qui freine la descente (force = amortissement × vitesse) ;
	# posé sur une seule roue (1,5 fois le poids) ; virage au sol (poussée de côté : 0,5 fois la charge) ;
	# freinage à fond
	var parts := _parts_roues(c)
	var pose := _copie(base)
	pose.train_sorti = 1.0
	somme = Vector3.ZERO
	for k in mini(3, c.amorti_train.size()):
		var fy: float = c.amorti_train[k] * DESCENTE_POSE
		pose.sol_f[k] = Vector3(0.0, fy, 0.8 * fy)
		somme += pose.sol_f[k]
	pose.acceleration = somme / m
	cas["posé à 3 m/s"] = pose
	for e in [["roue avant seule", 1.5, 0.25, 0.0, 0], ["roue arrière gauche seule", 1.5, 0.25, 0.0, 1],
			["roue arrière droite seule", 1.5, 0.25, 0.0, 2], ["virage au sol", 1.0, 0.0, 0.5, -1], ["freinage", 1.0, 0.8, 0.0, -1]]:
		var ph := _copie(base)
		ph.train_sorti = 1.0
		somme = Vector3.ZERO
		for k in 3:
			var seule := int(e[4])
			if seule >= 0 and k != seule:
				continue
			var fy: float = float(e[1]) * c.masse * G0 * (float(parts[k]) if seule < 0 else 1.0)
			ph.sol_f[k] = Vector3(float(e[3]) * fy, fy, float(e[2]) * fy)
			somme += ph.sol_f[k]
		ph.acceleration = somme / m
		cas[e[0]] = ph
	# 8 : cabine à 1,33 fois sa pression (épreuve des cabines pressurisées)
	var pc := _copie(base)
	pc.pression_dehors = Pieces.P_CABINE * (1.0 - 1.33)
	cas["cabine"] = pc
	return cas


## Part du poids que porte chaque roue (centre de gravité près des roues arrière).
static func _parts_roues(c: Capteurs) -> Array:
	var za: float = c.points_sol[0].z
	var zr: float = c.points_sol[1].z
	var cg := c.centre_gravite.z
	var avant := (zr - cg) / (zr - za)
	return [avant, (1.0 - avant) * 0.5, (1.0 - avant) * 0.5]


func _photo_vide(c: Capteurs) -> Capteurs:
	var e := Capteurs.new()
	e.nombre = c.nombre
	e.types = c.types.duplicate()
	e.aile_de = c.aile_de.duplicate()
	e.positions = c.positions.duplicate()
	e.directions = c.directions.duplicate()
	e.forces.resize(c.nombre)
	e.forces.fill(0.0)
	e.centre_gravite = c.centre_gravite
	e.masse = c.masse
	e.inertie = c.inertie
	e.charnieres = c.charnieres.duplicate()
	e.angles_ailes = c.angles_ailes_ouvertes.duplicate()
	e.angles_ailes_ouvertes = c.angles_ailes_ouvertes.duplicate()
	e.pivot_tuyere = c.pivot_tuyere
	e.angle_tuyere = 0.0
	e.train_sorti = 0.0
	e.geometrie = -100
	e.points_sol = c.points_sol.duplicate()
	e.poussee_reference = c.poussee_reference
	e.poussee_levage = c.poussee_levage
	var n_air := c.air_f.size() if c.air_f.size() > 0 else Aerodynamique.new().prise_surfaces
	e.air_f.resize(n_air)
	e.air_c.resize(n_air)
	e.air_f.fill(Vector3.ZERO)
	e.air_c.fill(Vector3.ZERO)
	e.sol_f.resize(c.points_sol.size())
	e.sol_f.fill(Vector3.ZERO)
	e.pression_dehors = Pieces.P_CABINE
	return e


func _copie(e: Capteurs) -> Capteurs:
	var k := _photo_vide(e)
	k.angles_ailes = e.angles_ailes.duplicate()
	k.directions = e.directions.duplicate()
	return k


## La résistance de chaque pièce, depuis les cas de calcul (une fois, au démarrage).
func calibrer(c: Capteurs) -> void:
	var cas := cas_de_calcul(c)
	var lf := []
	var lm := []
	for i in n:
		lf.append(Vector3.ZERO)
		lm.append(Vector3.ZERO)
	for nom in cas:
		charger(cas[nom])
		for i in n:
			lf[i] = (lf[i] as Vector3).max(force[i].abs())
			lm[i] = (lm[i] as Vector3).max(moment[i].abs())
	for i in n:
		var f: Vector3 = lf[i]
		var mo: Vector3 = lm[i]
		var mini_f := maxf(PLANCHER * maxf(f.x, maxf(f.y, f.z)), 3.0 * masses[i] * G0)
		var mini_m := maxf(PLANCHER * maxf(mo.x, maxf(mo.y, mo.z)), 1.5 * masses[i] * G0)
		limite_f[i] = f.max(Vector3(mini_f, mini_f, mini_f)) * SECURITE
		limite_m[i] = mo.max(Vector3(mini_m, mini_m, mini_m)) * SECURITE
		energie_rupture[i] = 0.5 * (limite_m[i].length() * ROTATION_RUPTURE + limite_f[i].length() * GLISSEMENT_RUPTURE)
	_geo = -1   # la vraie géométrie sera refaite au prochain calcul
	pret = true
	charger(c)
	for i in n:
		_taux_avant[i] = taux_de(force[i], moment[i], limite_f[i], limite_m[i])
		taux[i] = _taux_avant[i]
		variation[i] = 0.0
