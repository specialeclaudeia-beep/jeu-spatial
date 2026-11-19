extends RefCounted
## Grandes distances : LE SYSTÈME SOLAIRE BOUGE VRAIMENT.
##
## Avant, la planète restait immobile à 1 UA du Soleil : vu d'elle, le Soleil ne bougeait jamais, et sa
## gravité était presque annulée autour d'elle (on la retirait du vaisseau ET de la planète). Loin de la
## planète, le Soleil n'attirait donc presque pas : un vaisseau lâché à mi-chemin ne tombait pas vers lui.
##
## Maintenant :
## - le Soleil et son étoile compagne tournent l'un autour de l'autre (loi de Kepler, orbite ronde
##   autour de leur centre de masse commun : solution exacte à deux corps) ;
## - la planète tourne autour du Soleil, attirée par le Soleil ET par la compagne. Ce mouvement-là n'a pas
##   de formule : il est calculé pas à pas (méthode de Runge-Kutta, pas de 6 h, précise au mètre près
##   sur des siècles), puis gardé en mémoire par morceaux de 16 jours ;
## - le repère du jeu reste centré sur la planète (les nombres restent petits et précis près d'elle),
##   mais il TOMBE avec elle : la planète accélère exactement comme la gravité du Soleil et de la
##   compagne le veut à sa place. C'est ce qui rend juste le « terme indirect » de la gravité du vaisseau
##   (vaisseau_physique.gd) : loin de la planète, le vaisseau sent vraiment le Soleil.
##
## Repère « barycentrique » B : centré sur le centre de masse du Soleil et de la compagne, il ne tourne
## pas et n'accélère pas (c'est un vrai repère d'inertie). Le repère de la planète, c'est B décalé de la
## position de la planète : x_planète = x_B − R_p(t), même heure (Galilée ; la correction d'Einstein,
## v²/c² = 10⁻⁸ à 30 km/s, est négligée ici).
##
## Positions en mètres, 64 bits (PackedFloat64Array [x, y, z]). Au temps 0, le Soleil et la compagne sont
## exactement là où le jeu les mettait avant (vus de la planète) : rien ne change au départ.

const G_SOLEIL := 1.32712440018e20       # G × masse du Soleil, m³/s²
const PAS := 21600.0                     # s, pas du calcul de l'orbite de la planète (6 h)
const PAS_PAR_MORCEAU := 64              # 16 jours par morceau gardé en mémoire
const MORCEAUX_EN_MEMOIRE := 6           # morceaux détaillés gardés (le reste : un point de départ par morceau)

var gm_soleil := G_SOLEIL
var gm_compagne := 0.69 * G_SOLEIL
## Orbite du Soleil et de la compagne (ronde) : séparation D, vitesse angulaire Ω, axes e1 (au temps 0,
## du Soleil vers la compagne) et e2 (sens du mouvement).
var separation := 1.0
var omega_binaire := 0.0
var e1 := PackedFloat64Array([1.0, 0.0, 0.0])
var e2 := PackedFloat64Array([0.0, 0.0, -1.0])
var normale_binaire := Vector3.UP
var normale_planete := Vector3.UP        # axe de l'orbite de la planète autour du Soleil (au départ)

## Points de départ de chaque morceau (état de la planète dans B : x, y, z, vx, vy, vz), vers l'avenir
## (indice 0 = temps 0) et vers le passé (indice 0 = temps 0 aussi).
var _avant := []                         # Array de PackedFloat64Array(6), t = +k × morceau
var _arriere := []                       # t = −k × morceau
var _cache := {}                         # numéro de morceau (signé) → PackedFloat64Array (65 × 6 nombres)
var _ordre_cache: Array = []
var _dernier_t := NAN
var _dernier := PackedFloat64Array()     # [x, y, z, vx, vy, vz] de la planète au temps _dernier_t
var etats_calcules := 0                  # pas de Runge-Kutta faits (tests, mesure)


## p_soleil, p_compagne : positions vues de la planète au temps 0 (m).
func configurer(p_soleil: PackedFloat64Array, p_compagne: PackedFloat64Array, masse_compagne := 0.69) -> void:
	gm_compagne = masse_compagne * G_SOLEIL
	var dx := p_compagne[0] - p_soleil[0]
	var dy := p_compagne[1] - p_soleil[1]
	var dz := p_compagne[2] - p_soleil[2]
	separation = sqrt(dx * dx + dy * dy + dz * dz)
	omega_binaire = sqrt((gm_soleil + gm_compagne) / (separation * separation * separation))
	var u := Vector3(dx, dy, dz) / separation
	normale_binaire = _perpendiculaire(Vector3.UP, u)
	var w := normale_binaire.cross(u)
	e1 = PackedFloat64Array([dx / separation, dy / separation, dz / separation])
	e2 = PackedFloat64Array([w.x, w.y, w.z])
	# La planète : orbite ronde autour du Soleil au départ, dans le sens où elle tourne sur elle-même.
	var ds := sqrt(p_soleil[0] ** 2 + p_soleil[1] ** 2 + p_soleil[2] ** 2)
	var r_hat := Vector3(-p_soleil[0], -p_soleil[1], -p_soleil[2]) / ds   # du Soleil vers la planète
	normale_planete = _perpendiculaire(Vector3.UP, r_hat)
	var dir_v := normale_planete.cross(r_hat)
	var v_c := sqrt(gm_soleil / ds)
	var s0 := soleil(0.0)
	var vs := vitesse_soleil(0.0)
	var etat := PackedFloat64Array([s0[0] - p_soleil[0], s0[1] - p_soleil[1], s0[2] - p_soleil[2],
		vs[0] + dir_v.x * v_c, vs[1] + dir_v.y * v_c, vs[2] + dir_v.z * v_c])
	_avant = [etat]
	_arriere = [etat]
	_cache.clear()
	_ordre_cache.clear()
	_dernier_t = NAN


## Axe a rendu perpendiculaire à u (longueur 1), en gardant son sens.
static func _perpendiculaire(a: Vector3, u: Vector3) -> Vector3:
	var p := a - u * a.dot(u)
	if p.length() < 1e-6:
		p = Vector3.RIGHT - u * u.x
	return p.normalized()


# =====================================================================
# LE SOLEIL ET LA COMPAGNE (formule exacte de Kepler, dans B)
# =====================================================================
func _separation_vec(t: float) -> PackedFloat64Array:
	var a := omega_binaire * t
	var c := cos(a) * separation
	var s := sin(a) * separation
	return PackedFloat64Array([e1[0] * c + e2[0] * s, e1[1] * c + e2[1] * s, e1[2] * c + e2[2] * s])


func _separation_vit(t: float) -> PackedFloat64Array:
	var a := omega_binaire * t
	var c := cos(a) * separation * omega_binaire
	var s := sin(a) * separation * omega_binaire
	return PackedFloat64Array([e2[0] * c - e1[0] * s, e2[1] * c - e1[1] * s, e2[2] * c - e1[2] * s])


func _part(compagne: bool) -> float:
	var m := gm_soleil + gm_compagne
	return gm_soleil / m if compagne else -gm_compagne / m


## Position du Soleil dans B (m).
func soleil(t: float) -> PackedFloat64Array:
	var d := _separation_vec(t)
	var k := _part(false)
	return PackedFloat64Array([d[0] * k, d[1] * k, d[2] * k])


func vitesse_soleil(t: float) -> PackedFloat64Array:
	var d := _separation_vit(t)
	var k := _part(false)
	return PackedFloat64Array([d[0] * k, d[1] * k, d[2] * k])


func compagne(t: float) -> PackedFloat64Array:
	var d := _separation_vec(t)
	var k := _part(true)
	return PackedFloat64Array([d[0] * k, d[1] * k, d[2] * k])


func vitesse_compagne(t: float) -> PackedFloat64Array:
	var d := _separation_vit(t)
	var k := _part(true)
	return PackedFloat64Array([d[0] * k, d[1] * k, d[2] * k])


## Durée d'un tour du Soleil et de la compagne l'un autour de l'autre (s).
func periode_binaire() -> float:
	return TAU / omega_binaire


# =====================================================================
# LA PLANÈTE (calculée pas à pas)
# =====================================================================
## Gravité (Newton) du Soleil et de la compagne au point x de B, au temps t.
func _acceleration(t: float, x: float, y: float, z: float) -> Array:
	var s := soleil(t)
	var c := compagne(t)
	var dx := x - s[0]
	var dy := y - s[1]
	var dz := z - s[2]
	var r2 := dx * dx + dy * dy + dz * dz
	var k := -gm_soleil / (r2 * sqrt(r2))
	var ex := x - c[0]
	var ey := y - c[1]
	var ez := z - c[2]
	var q2 := ex * ex + ey * ey + ez * ez
	var k2 := -gm_compagne / (q2 * sqrt(q2))
	return [k * dx + k2 * ex, k * dy + k2 * ey, k * dz + k2 * ez]


## Un pas de Runge-Kutta (ordre 4) de durée h depuis l'état e au temps t.
func _rk4(t: float, e: PackedFloat64Array, h: float) -> PackedFloat64Array:
	etats_calcules += 1
	var a1 := _acceleration(t, e[0], e[1], e[2])
	var h2 := h * 0.5
	var x2 := e[0] + e[3] * h2
	var y2 := e[1] + e[4] * h2
	var z2 := e[2] + e[5] * h2
	var u2 := e[3] + float(a1[0]) * h2
	var v2 := e[4] + float(a1[1]) * h2
	var w2 := e[5] + float(a1[2]) * h2
	var a2 := _acceleration(t + h2, x2, y2, z2)
	var x3 := e[0] + u2 * h2
	var y3 := e[1] + v2 * h2
	var z3 := e[2] + w2 * h2
	var u3 := e[3] + float(a2[0]) * h2
	var v3 := e[4] + float(a2[1]) * h2
	var w3 := e[5] + float(a2[2]) * h2
	var a3 := _acceleration(t + h2, x3, y3, z3)
	var x4 := e[0] + u3 * h
	var y4 := e[1] + v3 * h
	var z4 := e[2] + w3 * h
	var u4 := e[3] + float(a3[0]) * h
	var v4 := e[4] + float(a3[1]) * h
	var w4 := e[5] + float(a3[2]) * h
	var a4 := _acceleration(t + h, x4, y4, z4)
	var s := h / 6.0
	return PackedFloat64Array([
		e[0] + s * (e[3] + 2.0 * u2 + 2.0 * u3 + u4),
		e[1] + s * (e[4] + 2.0 * v2 + 2.0 * v3 + v4),
		e[2] + s * (e[5] + 2.0 * w2 + 2.0 * w3 + w4),
		e[3] + s * (float(a1[0]) + 2.0 * float(a2[0]) + 2.0 * float(a3[0]) + float(a4[0])),
		e[4] + s * (float(a1[1]) + 2.0 * float(a2[1]) + 2.0 * float(a3[1]) + float(a4[1])),
		e[5] + s * (float(a1[2]) + 2.0 * float(a2[2]) + 2.0 * float(a3[2]) + float(a4[2]))])


## Point de départ du morceau k (k ≥ 0 vers l'avenir, k < 0 vers le passé), calculé si besoin.
func _depart(k: int) -> PackedFloat64Array:
	var liste: Array = _avant if k >= 0 else _arriere
	var n := absi(k)
	var sens := 1.0 if k >= 0 else -1.0
	while liste.size() <= n:
		var j := liste.size() - 1
		var e: PackedFloat64Array = liste[j]
		var t := sens * j * PAS * PAS_PAR_MORCEAU
		for i in PAS_PAR_MORCEAU:
			e = _rk4(t, e, sens * PAS)
			t += sens * PAS
		liste.append(e)
	return liste[n]


## Les 65 états du morceau k (de son début à sa fin, tous les 6 h), en mémoire.
func _morceau(k: int) -> PackedFloat64Array:
	if _cache.has(k):
		return _cache[k]
	# le morceau k va de k × durée à (k+1) × durée. Vers le passé, on le calcule depuis sa fin (−k…).
	var etats := PackedFloat64Array()
	etats.resize((PAS_PAR_MORCEAU + 1) * 6)
	if k >= 0:
		var e := _depart(k)
		var t := k * PAS * PAS_PAR_MORCEAU
		for i in PAS_PAR_MORCEAU + 1:
			for c in 6:
				etats[i * 6 + c] = e[c]
			if i < PAS_PAR_MORCEAU:
				e = _rk4(t, e, PAS)
				t += PAS
	else:
		var e := _depart(k + 1)   # fin du morceau (point de départ vers le passé)
		var t := (k + 1) * PAS * PAS_PAR_MORCEAU
		for i in range(PAS_PAR_MORCEAU, -1, -1):
			for c in 6:
				etats[i * 6 + c] = e[c]
			if i > 0:
				e = _rk4(t, e, -PAS)
				t -= PAS
	_cache[k] = etats
	_ordre_cache.append(k)
	if _ordre_cache.size() > MORCEAUX_EN_MEMOIRE:
		_cache.erase(_ordre_cache.pop_front())
	return etats


## État de la planète dans B au temps t : [x, y, z, vx, vy, vz] (interpolation d'Hermite entre deux
## pas de 6 h : la position et la vitesse sont justes aux deux bouts, l'écart au milieu est < 1 mm).
func planete(t: float) -> PackedFloat64Array:
	if t == _dernier_t:
		return _dernier
	var duree := PAS * PAS_PAR_MORCEAU
	var k := int(floor(t / duree))
	var etats := _morceau(k)
	var local := (t - k * duree) / PAS
	var i := clampi(int(floor(local)), 0, PAS_PAR_MORCEAU - 1)
	var s := local - i
	var h := PAS
	var s2 := s * s
	var s3 := s2 * s
	var h00 := 2.0 * s3 - 3.0 * s2 + 1.0
	var h10 := s3 - 2.0 * s2 + s
	var h01 := -2.0 * s3 + 3.0 * s2
	var h11 := s3 - s2
	var d00 := (6.0 * s2 - 6.0 * s) / h
	var d10 := 3.0 * s2 - 4.0 * s + 1.0
	var d01 := (-6.0 * s2 + 6.0 * s) / h
	var d11 := 3.0 * s2 - 2.0 * s
	var r := PackedFloat64Array()
	r.resize(6)
	var a := i * 6
	var b := a + 6
	for c in 3:
		var p0 := etats[a + c]
		var v0 := etats[a + 3 + c]
		var p1 := etats[b + c]
		var v1 := etats[b + 3 + c]
		r[c] = h00 * p0 + h10 * h * v0 + h01 * p1 + h11 * h * v1
		r[3 + c] = d00 * p0 + d10 * v0 + d01 * p1 + d11 * v1
	_dernier_t = t
	_dernier = r
	return r


# =====================================================================
# VU DE LA PLANÈTE (repère du jeu)
# =====================================================================
## Position du Soleil vue de la planète au temps t (m).
func soleil_vu(t: float) -> PackedFloat64Array:
	var p := planete(t)
	var s := soleil(t)
	return PackedFloat64Array([s[0] - p[0], s[1] - p[1], s[2] - p[2]])


func compagne_vue(t: float) -> PackedFloat64Array:
	var p := planete(t)
	var c := compagne(t)
	return PackedFloat64Array([c[0] - p[0], c[1] - p[1], c[2] - p[2]])


## Vitesse de la planète par rapport au Soleil (m/s).
func vitesse_autour_du_soleil(t: float) -> PackedFloat64Array:
	var p := planete(t)
	var vs := vitesse_soleil(t)
	return PackedFloat64Array([p[3] - vs[0], p[4] - vs[1], p[5] - vs[2]])


## Repère de la planète → B (position, même heure).
func vers_b(t: float, x: PackedFloat64Array) -> PackedFloat64Array:
	var p := planete(t)
	return PackedFloat64Array([x[0] + p[0], x[1] + p[1], x[2] + p[2]])


func depuis_b(t: float, x: PackedFloat64Array) -> PackedFloat64Array:
	var p := planete(t)
	return PackedFloat64Array([x[0] - p[0], x[1] - p[1], x[2] - p[2]])


## Vitesse de la planète dans B (m/s).
func vitesse_planete(t: float) -> PackedFloat64Array:
	var p := planete(t)
	return PackedFloat64Array([p[3], p[4], p[5]])
