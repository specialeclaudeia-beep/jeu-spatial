extends RefCounted
## L'atmosphère dans le système de lumière, côté processeur : les MÊMES calculs que
## scripts/lumiere/atmosphere.gdshaderinc (voir ce fichier pour les explications), pour ce que la carte
## graphique ne peut pas faire seule : la lumière que reçoit le vaisseau (Soleil rougi, ciel bleu) et
## ce que voit le posemètre de l'œil (le ciel clair de jour). Couleurs : Vector3 (rouge, vert, bleu).

const RAYLEIGH := Vector3(5.802e-6, 13.558e-6, 33.1e-6)
const H_RAYLEIGH := 8000.0
const MIE := 3.996e-6
const MIE_EXT := 4.40e-6
const H_MIE := 1200.0
const G_MIE := 0.8
const OZONE := Vector3(0.650e-6, 1.881e-6, 0.085e-6)
const OZONE_CENTRE := 25000.0
const OZONE_DEMI := 15000.0
const HAUT := 100000.0
const LUM := Vector3(0.2126, 0.7152, 0.0722)

var rayon := 0.0   # m ; 0 = pas d'atmosphère


func _init(p_rayon := 0.0) -> void:
	rayon = p_rayon


## exp(y²)·erfc(y) pour y ≥ 0 (Abramowitz et Stegun 7.1.26 jusqu'à 3, puis développement asymptotique :
## erreur < 0,1 %).
static func erfcx(y: float) -> float:
	if y < 3.0:
		var t := 1.0 / (1.0 + 0.3275911 * y)
		return t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
	var u := 1.0 / (2.0 * y * y)
	return (1.0 - u + 3.0 * u * u - 15.0 * u * u * u) / (1.7724539 * y)


## Fonction de Chapman : quantité d'air traversée de la hauteur h (en hauteurs d'échelle) jusqu'à
## l'espace, sous le cosinus mu avec la verticale, rapportée à une colonne verticale depuis le niveau de
## la mer. x = rayon de la planète / hauteur d'échelle. Forme pour une grande planète (x > 50) :
## Ch = √(πX/2)·exp(y²)·erfc(y), y = √(X/2)·mu, X = x + h ; sous l'horizon, le chemin passe au plus
## bas puis remonte : 2 × le chemin depuis ce point le plus bas, moins le chemin en sens inverse.
static func chapman(x: float, h: float, mu: float) -> float:
	var gx := x + h
	if mu >= 0.0:
		return sqrt(1.5707963 * gx) * erfcx(sqrt(0.5 * gx) * mu) * exp(-h)
	var x0 := sqrt(maxf(1.0 - mu * mu, 0.0)) * gx
	return 2.0 * sqrt(1.5707963 * x0) * exp(x - x0) - sqrt(1.5707963 * gx) * erfcx(sqrt(0.5 * gx) * -mu) * exp(-h)


static func ozone_dessus(z: float) -> float:
	var a := OZONE_CENTRE - OZONE_DEMI
	var b := OZONE_CENTRE + OZONE_DEMI
	if z >= b:
		return 0.0
	if z <= a:
		return OZONE_DEMI
	if z >= OZONE_CENTRE:
		var u := (b - z) / OZONE_DEMI
		return 0.5 * OZONE_DEMI * u * u
	var w := (z - a) / OZONE_DEMI
	return OZONE_DEMI - 0.5 * OZONE_DEMI * w * w


## Épaisseur optique de la distance r (au centre) jusqu'à l'espace, sous le cosinus mu avec la verticale.
func epaisseur(r: float, mu: float) -> Vector3:
	var z := maxf(r - rayon, 0.0)
	var ch_r := chapman(rayon / H_RAYLEIGH, z / H_RAYLEIGH, mu)
	var ch_m := chapman(rayon / H_MIE, z / H_MIE, mu)
	var masse_air := ch_r / maxf(exp(-z / H_RAYLEIGH), 1e-30)
	return RAYLEIGH * (H_RAYLEIGH * ch_r) + Vector3.ONE * (MIE_EXT * H_MIE * ch_m) \
		+ OZONE * (ozone_dessus(z) * minf(masse_air, 40.0))


static func _exp3(v: Vector3) -> Vector3:
	return Vector3(exp(-v.x), exp(-v.y), exp(-v.z))


## Part de la lumière du Soleil (direction s) qui arrive au point q (q = point − centre de la planète).
func transmission_soleil(q: Vector3, s: Vector3) -> Vector3:
	if rayon <= 0.0:
		return Vector3.ONE
	var r := q.length()
	if r > rayon + HAUT:
		return Vector3.ONE
	return _exp3(epaisseur(r, q.dot(s) / r))


static func phase_rayleigh(c: float) -> float:
	return 3.0 / (16.0 * PI) * (1.0 + c * c)


static func phase_mie(c: float) -> float:
	var g2 := G_MIE * G_MIE
	return 3.0 / (8.0 * PI) * (1.0 - g2) * (1.0 + c * c) / ((2.0 + g2) * pow(maxf(1.0 + g2 - 2.0 * G_MIE * c, 1e-6), 1.5))


## Chemin de lumière depuis q (q = œil − centre) dans la direction d, jusqu'à t_max : [lumière ajoutée
## par l'air (par lux du Soleil), transmission]. Mêmes points de calcul que la carte graphique.
func chemin(q: Vector3, d: Vector3, t_max: float, s: Vector3, n: int) -> Array:
	if rayon <= 0.0:
		return [Vector3.ZERO, Vector3.ONE]
	var rh := rayon + HAUT
	var b := q.dot(d)
	var c := q.dot(q) - rh * rh
	var delta := b * b - c
	if delta <= 0.0:
		return [Vector3.ZERO, Vector3.ONE]
	var sq := sqrt(delta)
	var t0 := maxf(-b - sq, 0.0)
	var t1 := minf(-b + sq, t_max)
	var cs := q.dot(q) - rayon * rayon
	var ds := b * b - cs
	if ds > 0.0 and cs > 0.0:
		var ts := -b - sqrt(ds)
		if ts > 0.0:
			t1 = minf(t1, ts)
	if t1 <= t0:
		return [Vector3.ZERO, Vector3.ONE]
	var mu_s := d.dot(s)
	var ph_r := phase_rayleigh(mu_s)
	var ph_m := phase_mie(mu_s)
	var acc := [Vector3.ZERO, Vector3.ZERO]   # tau, somme
	var tp := clampf(-b, t0, t1)
	var part := (tp - t0) / (t1 - t0)
	var na := 0 if part < 0.02 else (n if part > 0.98 else n / 2)
	if na > 0:
		_morceau(q, d, s, t0, tp, na, true, ph_r, ph_m, acc)
	if n - na > 0:
		_morceau(q, d, s, tp, t1, n - na, false, ph_r, ph_m, acc)
	return [acc[1], _exp3(acc[0])]


func _morceau(q: Vector3, d: Vector3, s: Vector3, ta: float, tb: float, m: int, vers_b: bool,
		ph_r: float, ph_m: float, acc: Array) -> void:
	var l := tb - ta
	var tau: Vector3 = acc[0]
	var somme: Vector3 = acc[1]
	for i in m:
		var k0 := float(i) / m
		var k1 := float(i + 1) / m
		var u0 := 1.0 - (1.0 - k0) * (1.0 - k0) if vers_b else k0 * k0
		var u1 := 1.0 - (1.0 - k1) * (1.0 - k1) if vers_b else k1 * k1
		var pas := l * (u1 - u0)
		var p := q + d * (ta + l * 0.5 * (u0 + u1))
		var r := p.length()
		var z := maxf(r - rayon, 0.0)
		var dr := exp(-z / H_RAYLEIGH)
		var dm := exp(-z / H_MIE)
		var dz := maxf(1.0 - absf(z - OZONE_CENTRE) / OZONE_DEMI, 0.0)
		var ext := RAYLEIGH * dr + Vector3.ONE * (MIE_EXT * dm) + OZONE * dz
		var tau_milieu := tau + ext * (0.5 * pas)
		tau += ext * pas
		var vers_soleil := _exp3(epaisseur(r, p.dot(s) / r))
		somme += _exp3(tau_milieu) * vers_soleil * (RAYLEIGH * (dr * ph_r) + Vector3.ONE * (MIE * dm * ph_m)) * pas
	acc[0] = tau
	acc[1] = somme


## Éclairement du ciel sur une surface tournée vers le haut en q (part de l'éclairement du Soleil hors
## de l'atmosphère), même simplification que atmo_eclairement_ciel.
func eclairement_ciel(q: Vector3, s: Vector3) -> Vector3:
	if rayon <= 0.0:
		return Vector3.ZERO
	var r := q.length()
	if r > rayon + HAUT:
		return Vector3.ZERO
	var mu := q.dot(s) / r
	var t_s := _exp3(epaisseur(r, mu))
	var air := exp(-maxf(r - rayon, 0.0) / H_RAYLEIGH)
	var crepuscule := 0.003 * smoothstep(-0.2, 0.0, mu)
	return ((Vector3.ONE - t_s) * maxf(mu, 0.0) + Vector3(0.6, 0.75, 1.0) * crepuscule) * air


static func lum(v: Vector3) -> float:
	return v.dot(LUM)
