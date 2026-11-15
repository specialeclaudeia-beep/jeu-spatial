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
	_ajouter_moteur("haut gauche", Vector3(-2.8, 0.9, 4.0), avant, 40000.0)
	_ajouter_moteur("haut droit", Vector3(2.8, 0.9, 4.0), avant, 40000.0)
	_ajouter_moteur("bas gauche", Vector3(-2.8, -0.9, 4.0), avant, 40000.0)
	_ajouter_moteur("bas droit", Vector3(2.8, -0.9, 4.0), avant, 40000.0)
	_ajouter_moteur("central", Vector3(0.0, 0.0, 4.4), avant, 40000.0)

	# Propulseurs d'orientation, par paires opposées : ils font tourner sans faire avancer.
	var nez := Vector3(0, 0, -6.0)
	var queue := Vector3(0, 0, 5.0)
	var aile_g := Vector3(-5.5, 0, 0)
	var aile_d := Vector3(5.5, 0, 0)
	var p := 1500.0
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


func _ajouter_moteur(nom: String, pos: Vector3, dir: Vector3, poussee: float) -> void:
	moteurs.append({"nom": nom, "position": pos, "direction": dir, "poussee_max": poussee, "consigne": 0.0, "actuel": 0.0})


func _ajouter_rcs(pos: Vector3, dir: Vector3, poussee: float, axe: int, signe: int) -> void:
	rcs.append({"position": pos, "direction": dir, "poussee_max": poussee, "axe": axe, "signe": signe, "actuel": 0.0})

# =====================================================================
# COMMANDES
# =====================================================================
## Règle la consigne des 5 moteurs à partir de la manette des gaz et des ordres de rotation.
## Pour tourner, on augmente ou diminue la poussée de certains moteurs (le vrai couple vient
## de leur position). Sans gaz, seuls les propulseurs d'orientation peuvent tourner le vaisseau.
func commander(gaz: float, tangage: float, lacet: float, roulis: float) -> void:
	gaz = clampf(gaz, 0.0, 1.0)
	for m in moteurs:
		var pos: Vector3 = m["position"]
		var d := 0.0
		# tangage + (nez en haut) : les moteurs du BAS poussent plus (couple = position × force)
		if absf(pos.y) > 0.01:
			d += tangage * -signf(pos.y)
		# lacet + (nez à gauche) : les moteurs de DROITE poussent plus
		if absf(pos.x) > 0.01:
			d += lacet * signf(pos.x)
		m["consigne"] = clampf(gaz * (1.0 + 0.6 * d), 0.0, 1.0)
	var ordres := [tangage, lacet, roulis]
	for t in rcs:
		var o: float = ordres[t["axe"]] * t["signe"]
		t["actuel"] = clampf(o, 0.0, 1.0)

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


## Avance la simulation de dt secondes.
func pas(dt: float) -> void:
	# 1. Les moteurs suivent leur consigne avec un petit temps de réponse
	var k := clampf(dt / maxf(reactivite_moteurs, 1e-9), 0.0, 1.0)
	for m in moteurs:
		m["actuel"] = float(m["actuel"]) + (float(m["consigne"]) - float(m["actuel"])) * k

	# 2. Somme des forces et des couples, dans le repère du vaisseau
	var f_corps := Vector3.ZERO
	var couple := Vector3.ZERO
	for m in moteurs:
		var f: Vector3 = m["direction"] * (float(m["poussee_max"]) * float(m["actuel"]))
		f_corps += f
		couple += (m["position"] as Vector3).cross(f)
	for t in rcs:
		if float(t["actuel"]) > 0.0:
			var f2: Vector3 = t["direction"] * (float(t["poussee_max"]) * float(t["actuel"]))
			f_corps += f2
			couple += (t["position"] as Vector3).cross(f2)
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

	# 5. Rotation : équations d'Euler du corps rigide  I·dω/dt = couple − ω × (I·ω)
	var iw := Vector3(inertie.x * omega.x, inertie.y * omega.y, inertie.z * omega.z)
	var dw := (couple - omega.cross(iw)) / inertie
	omega += dw * dt
	var angle := omega.length() * dt
	if angle > 0.0:
		orientation = (orientation * Quaternion(omega.normalized(), angle)).normalized()


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
