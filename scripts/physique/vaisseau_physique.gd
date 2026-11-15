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

# =====================================================================
# CARACTÉRISTIQUES DU VAISSEAU (modifiables)
# =====================================================================
var masse := 10000.0                                   # kg
var inertie := Vector3(133000.0, 160000.0, 33000.0)    # kg·m² : tangage (X), lacet (Y), roulis (Z)
var reactivite_moteurs := 0.3                          # secondes pour que la poussée suive la consigne
const POUSSEE_MOTEUR := 200000.0   # N, chacun des 5 moteurs arrière (seul, il pousse 2 fois le poids de 10 t)
const POUSSEE_RCS := 6000.0        # N, chacun des 12 propulseurs d'orientation

# =====================================================================
# ÉTAT
# =====================================================================
var px := 0.0
var py := 0.0
var pz := 0.0      # position (m), centre de la planète = 0
var vx := 0.0
var vy := 0.0
var vz := 0.0      # vitesse (m/s)
var orientation := Quaternion.IDENTITY
var omega := Vector3.ZERO                    # vitesse de rotation (rad/s), repère du vaisseau
var acceleration_ressentie := Vector3.ZERO   # ce que sent le pilote (m/s², repère monde) : pas la gravité
var au_sol := false
var ecrase := false
var vitesse_impact := 0.0

# planète
var gm := 0.0              # constante gravitationnelle × masse de la planète (m³/s²)
var rayon_planete := 0.0   # m (0 = pas de sol)

# autres astres (lunes, étoiles…) : chacun = { nom, gm, x, y, z } (position en m, double précision).
# Pour l'instant ils restent immobiles : leur propre mouvement viendra plus tard.
var autres_astres: Array = []

# couple dû au gradient de gravité (true = calculé, comme dans la réalité)
var gradient_gravite := true
var couple_gravite_actuel := Vector3.ZERO   # N·m, repère du vaisseau (pour les tests et l'affichage)

# propulseurs : chacun = { nom, position, direction, poussee_max, consigne (0..1), actuel (0..1) }
var moteurs: Array = []
var rcs: Array = []        # petits propulseurs d'orientation : en plus { axe (0,1,2), signe (+1/-1) }

# =====================================================================
# CRÉATION
# =====================================================================
func _init() -> void:
	# 5 moteurs arrière : 4 sur les ailes + 1 central. Ils poussent tous vers l'avant (-Z).
	var avant := Vector3(0, 0, -1)
	_ajouter_moteur("haut gauche", Vector3(-2.8, 0.9, 4.0), avant, POUSSEE_MOTEUR)
	_ajouter_moteur("haut droit", Vector3(2.8, 0.9, 4.0), avant, POUSSEE_MOTEUR)
	_ajouter_moteur("bas gauche", Vector3(-2.8, -0.9, 4.0), avant, POUSSEE_MOTEUR)
	_ajouter_moteur("bas droit", Vector3(2.8, -0.9, 4.0), avant, POUSSEE_MOTEUR)
	_ajouter_moteur("central", Vector3(0.0, 0.0, 4.4), avant, POUSSEE_MOTEUR)

	# Propulseurs d'orientation, par paires opposées : ils font tourner sans faire avancer.
	var nez := Vector3(0, 0, -6.0)
	var queue := Vector3(0, 0, 5.0)
	var aile_g := Vector3(-5.5, 0, 0)
	var aile_d := Vector3(5.5, 0, 0)
	var p := POUSSEE_RCS
	# tangage + = nez vers le haut
	_ajouter_rcs(nez, Vector3.UP, p, 0, 1)
	_ajouter_rcs(queue, Vector3.DOWN, p, 0, 1)
	_ajouter_rcs(nez, Vector3.DOWN, p, 0, -1)
	_ajouter_rcs(queue, Vector3.UP, p, 0, -1)
	# lacet + = nez vers la gauche
	_ajouter_rcs(nez, Vector3.LEFT, p, 1, 1)
	_ajouter_rcs(queue, Vector3.RIGHT, p, 1, 1)
	_ajouter_rcs(nez, Vector3.RIGHT, p, 1, -1)
	_ajouter_rcs(queue, Vector3.LEFT, p, 1, -1)
	# roulis + = vers la gauche
	_ajouter_rcs(aile_g, Vector3.DOWN, p, 2, 1)
	_ajouter_rcs(aile_d, Vector3.UP, p, 2, 1)
	_ajouter_rcs(aile_g, Vector3.UP, p, 2, -1)
	_ajouter_rcs(aile_d, Vector3.DOWN, p, 2, -1)
	_preparer_repartition()


func _ajouter_moteur(nom: String, pos: Vector3, dir: Vector3, poussee: float) -> void:
	moteurs.append({"nom": nom, "position": pos, "direction": dir, "poussee_max": poussee, "consigne": 0.0, "actuel": 0.0})


func _ajouter_rcs(pos: Vector3, dir: Vector3, poussee: float, axe: int, signe: int) -> void:
	rcs.append({"position": pos, "direction": dir, "poussee_max": poussee, "axe": axe, "signe": signe, "actuel": 0.0})

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
var poussee_avant_max := 0.0     # N, somme des moteurs vers l'avant
var couple_max := Vector3.ZERO   # N·m, rotation maximale demandée pour un ordre de 1 sur chaque axe
var _echelle_force := 1.0
const POIDS_ROTATION := 2.0      # la rotation compte plus que la poussée quand les deux ne sont pas possibles
const SOBRIETE := 0.001          # à résultat égal : moteurs proches des gaz, petits propulseurs coupés
const TOURS_CALCUL := 10         # nombre de passes du calcul (léger : environ 2 000 opérations)


func _preparer_repartition() -> void:
	_tous = moteurs + rcs
	poussee_avant_max = 0.0
	for m in moteurs:
		poussee_avant_max += float(m["poussee_max"]) * maxf(0.0, -(m["direction"] as Vector3).z)
	# rotation maximale sur chaque axe : ce que les propulseurs d'orientation peuvent donner dans les deux sens
	var plus := Vector3.ZERO
	var moins := Vector3.ZERO
	for t in rcs:
		var c: Vector3 = (t["position"] as Vector3).cross(t["direction"]) * float(t["poussee_max"])
		for k in 3:
			plus[k] += maxf(0.0, c[k])
			moins[k] += maxf(0.0, -c[k])
	couple_max = Vector3(minf(plus.x, moins.x), minf(plus.y, moins.y), minf(plus.z, moins.z))
	# échelle des forces : la plus petite poussée qui peut pousser de côté. Ainsi une erreur de force
	# de quelques kN compte autant qu'une erreur de rotation : pas de déplacement parasite.
	var f_cote := INF
	for t in _tous:
		var d0: Vector3 = t["direction"]
		if absf(d0.x) > 1e-6 or absf(d0.y) > 1e-6:
			f_cote = minf(f_cote, float(t["poussee_max"]))
	if f_cote == INF:
		f_cote = poussee_avant_max
	_echelle_force = f_cote
	_colonnes.clear()
	_niveaux.resize(_tous.size())
	for i in _tous.size():
		var t = _tous[i]
		var f: Vector3 = (t["direction"] as Vector3) * float(t["poussee_max"])
		var c2: Vector3 = (t["position"] as Vector3).cross(f)
		_colonnes.append(PackedFloat64Array([
			f.x / f_cote, f.y / f_cote, f.z / f_cote,
			POIDS_ROTATION * c2.x / couple_max.x, POIDS_ROTATION * c2.y / couple_max.y, POIDS_ROTATION * c2.z / couple_max.z]))
		_niveaux[i] = 0.0


func commander(gaz: float, tangage: float, lacet: float, roulis: float) -> void:
	gaz = clampf(gaz, 0.0, 1.0)
	# objectif, dans la même échelle que les colonnes
	var but := PackedFloat64Array([0.0, 0.0, -gaz * poussee_avant_max / _echelle_force,
		POIDS_ROTATION * clampf(tangage, -1.0, 1.0),
		POIDS_ROTATION * clampf(lacet, -1.0, 1.0),
		POIDS_ROTATION * clampf(roulis, -1.0, 1.0)])
	# point de départ (et solution préférée) : moteurs au niveau des gaz, petits propulseurs coupés
	var n := _tous.size()
	var prefere := PackedFloat64Array()
	prefere.resize(n)
	for i in n:
		prefere[i] = gaz if i < moteurs.size() else 0.0
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
	# les moteurs reçoivent une consigne (ils mettent un peu de temps à la suivre),
	# les propulseurs d'orientation réagissent tout de suite
	for i in n:
		var niveau := _niveaux[i]
		if niveau < 1e-6:
			niveau = 0.0
		if i < moteurs.size():
			_tous[i]["consigne"] = niveau
		else:
			_tous[i]["actuel"] = niveau

func ajouter_astre(nom: String, gm_astre: float, x: float, y: float, z: float) -> void:
	autres_astres.append({"nom": nom, "gm": gm_astre, "x": x, "y": y, "z": z})

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
	for t in _tous:
		var niveau := float(t["actuel"])
		if niveau > 0.0:
			var f: Vector3 = t["direction"] * (float(t["poussee_max"]) * niveau)
			f_corps += f
			couple += (t["position"] as Vector3).cross(f)
	return [f_corps, couple]


## Avance la simulation de dt secondes.
func pas(dt: float) -> void:
	# 1. Les moteurs suivent leur consigne avec un petit temps de réponse
	var k := clampf(dt / maxf(reactivite_moteurs, 1e-9), 0.0, 1.0)
	for m in moteurs:
		m["actuel"] = float(m["actuel"]) + (float(m["consigne"]) - float(m["actuel"])) * k

	# 2. Somme des forces et des couples, dans le repère du vaisseau
	var effet := effet_propulseurs()
	var f_corps: Vector3 = effet[0]
	var couple: Vector3 = effet[1]
	# le gradient de gravité ajoute son propre petit couple
	couple_gravite_actuel = couple_gravite()
	couple += couple_gravite_actuel
	var base := Basis(orientation)
	var a_p: Vector3 = (base * f_corps) / masse   # accélération due à la poussée (repère monde)

	# 3. Translation : méthode de Verlet (stable pour les orbites)
	var g := gravite(px, py, pz)
	var h := dt * 0.5
	vx += (float(g[0]) + a_p.x) * h
	vy += (float(g[1]) + a_p.y) * h
	vz += (float(g[2]) + a_p.z) * h
	px += vx * dt
	py += vy * dt
	pz += vz * dt
	g = gravite(px, py, pz)
	vx += (float(g[0]) + a_p.x) * h
	vy += (float(g[1]) + a_p.y) * h
	vz += (float(g[2]) + a_p.z) * h

	acceleration_ressentie = a_p

	# 4. Contact avec le sol
	au_sol = false
	if rayon_planete > 0.0:
		_contact_sol(dt, g)

	# 5. Rotation du corps rigide
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
		o[k] = clampf(-omega[k] * gain, -1.0, 1.0)
	return o


func _contact_sol(dt: float, g: Array) -> void:
	var r := sqrt(px * px + py * py + pz * pz)
	if r >= rayon_planete:
		return
	au_sol = true
	var nx := px / r
	var ny := py / r
	var nz := pz / r
	px = nx * rayon_planete
	py = ny * rayon_planete
	pz = nz * rayon_planete
	var vr := vx * nx + vy * ny + vz * nz
	if vr < 0.0:
		vitesse_impact = -vr
		if vitesse_impact > 10.0:
			ecrase = true
		vx -= vr * nx
		vy -= vr * ny
		vz -= vr * nz
	# frottement du sol : freine le glissement
	var fr := clampf(1.0 - dt * 1.5, 0.0, 1.0)
	vx *= fr
	vy *= fr
	vz *= fr
	# le sol pousse vers le haut : c'est ce qui fait sentir son poids (≈ 1 g posé)
	var n := Vector3(nx, ny, nz)
	var g_vers_bas := -(float(g[0]) * nx + float(g[1]) * ny + float(g[2]) * nz)
	var pousse_sol := maxf(0.0, g_vers_bas - acceleration_ressentie.dot(n))
	acceleration_ressentie += n * pousse_sol

# =====================================================================
# MESURES (pour les instruments)
# =====================================================================
func distance_centre() -> float:
	return sqrt(px * px + py * py + pz * pz)


func altitude() -> float:
	return distance_centre() - rayon_planete


func vitesse() -> float:
	return sqrt(vx * vx + vy * vy + vz * vz)


func vitesse_verticale() -> float:
	var r := distance_centre()
	return (vx * px + vy * py + vz * pz) / r if r > 0.0 else 0.0


func vitesse_horizontale() -> float:
	var v := vitesse()
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
	orientation = Quaternion.IDENTITY   # l'avant (-Z) est déjà dans le sens de la vitesse
	omega = Vector3.ZERO
	au_sol = false
	ecrase = false
	vitesse_impact = 0.0
	for m in moteurs:
		m["consigne"] = 0.0
		m["actuel"] = 0.0
