extends RefCounted
## L'AIR de la planète (programme de départ : atmosphère).
##
## Un air comme celui de la Terre (azote, oxygène : 28,96 g/mol), sur une planète qui a la même gravité
## au sol (9,81 m/s²). On part de l'« atmosphère type » mesurée sur Terre (US Standard Atmosphere 1976) :
## température par couches, puis pression et densité par la loi de l'équilibre de l'air (chaque couche
## porte le poids de l'air au-dessus d'elle). Cette loi se calcule avec l'altitude « géopotentielle »,
## qui tient compte de la gravité qui baisse en montant : notre planète est 10 fois plus petite que la
## Terre, sa gravité baisse plus vite, donc son air s'étire un peu plus en hauteur (à 100 km, il est
## comme celui de la Terre à 85,7 km). Au-dessus de 86 km (thermosphère), la densité vient des mesures
## (activité moyenne du Soleil), passées par la même conversion. Au-delà de 600 km : vide.
##
## L'air tourne avec la planète (comme sur Terre) : le vent, vu du repère de la physique, vaut ω × r.
## Rien de magique : tout ce que l'air fait au vaisseau passe par des forces (aerodynamique.gd).

const R_AIR := 287.053          # J/(kg·K), constante de l'air sec
const GAMMA_AIR := 1.4
const R_TERRE_GEO := 6356766.0  # m, rayon utilisé par l'atmosphère type pour son altitude géopotentielle
const HAUT := 600000.0          # m : au-dessus, plus d'air compté (densité < 10⁻¹³ kg/m³)

## Couches de l'atmosphère type 1976 : altitude géopotentielle de la base (m), température (K),
## gradient (K/m), pression à la base (Pa).
const COUCHES := [
	[0.0, 288.15, -0.0065, 101325.0],
	[11000.0, 216.65, 0.0, 22632.06],
	[20000.0, 216.65, 0.001, 5474.889],
	[32000.0, 228.65, 0.0028, 868.0187],
	[47000.0, 270.65, 0.0, 110.9063],
	[51000.0, 270.65, -0.0028, 66.93887],
	[71000.0, 214.65, -0.002, 3.956420],
	[84852.0, 186.946, 0.0, 0.3733835],
]
## Thermosphère (au-dessus de 86 km sur Terre) : altitude géométrique terrestre (m), densité (kg/m³),
## température (K). Entre deux lignes, la densité suit une exponentielle.
const HAUTE := [
	[86000.0, 6.958e-6, 186.87],
	[100000.0, 5.604e-7, 195.08],
	[110000.0, 9.708e-8, 240.0],
	[120000.0, 2.222e-8, 360.0],
	[150000.0, 2.076e-9, 634.4],
	[200000.0, 2.541e-10, 854.6],
	[300000.0, 1.916e-11, 976.0],
	[400000.0, 2.803e-12, 995.8],
	[500000.0, 5.215e-13, 999.2],
	[600000.0, 1.137e-13, 999.9],
]
const G0 := 9.80665

var rayon := 600000.0           # m, rayon de la planète (niveau de la mer)
var omega := 0.0                # rad/s : rotation de la planète autour de Y (l'air tourne avec elle)


func _init(p_rayon := 600000.0, p_omega := 0.0) -> void:
	rayon = p_rayon
	omega = p_omega


## Altitude géopotentielle (m) : celle qui donnerait le même travail contre la gravité avec une
## gravité constante. Elle dépend du rayon de la planète.
func geopotentielle(z: float) -> float:
	return rayon * z / (rayon + z)


## État de l'air à l'altitude z (m au-dessus du niveau de la mer) : [densité (kg/m³), température (K),
## pression (Pa), vitesse du son (m/s)].
func etat(z: float) -> Array:
	if z >= HAUT:
		return [0.0, 1000.0, 0.0, sqrt(GAMMA_AIR * R_AIR * 1000.0)]
	var h := geopotentielle(maxf(z, -5000.0))
	var t := 0.0
	var p := 0.0
	var rho := 0.0
	if h < 84852.0:
		var c: Array = COUCHES[0]
		for k in COUCHES.size():
			if h >= float(COUCHES[k][0]):
				c = COUCHES[k]
		var hb: float = c[0]
		var tb: float = c[1]
		var l: float = c[2]
		var pb: float = c[3]
		t = tb + l * (h - hb)
		if l == 0.0:
			p = pb * exp(-G0 * (h - hb) / (R_AIR * tb))
		else:
			p = pb * pow(tb / t, G0 / (R_AIR * l))
		rho = p / (R_AIR * t)
	else:
		# même altitude géopotentielle sur Terre, puis son altitude géométrique terrestre
		var z_terre := R_TERRE_GEO * h / (R_TERRE_GEO - h) if h < R_TERRE_GEO * 0.5 else HAUT
		var i := 0
		while i < HAUTE.size() - 2 and z_terre > float(HAUTE[i + 1][0]):
			i += 1
		var a: Array = HAUTE[i]
		var b: Array = HAUTE[i + 1]
		var f := clampf((z_terre - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.5)
		rho = float(a[1]) * pow(float(b[1]) / float(a[1]), f)
		t = lerpf(float(a[2]), float(b[2]), clampf(f, 0.0, 1.0))
		p = rho * R_AIR * t
	return [rho, t, p, sqrt(GAMMA_AIR * R_AIR * t)]


func densite(z: float) -> float:
	return float(etat(z)[0])


## Vitesse de l'air au point (x, y, z) du repère de la physique (m/s) : il tourne avec la planète.
func vent(x: float, _y: float, z: float) -> Vector3:
	return Vector3(omega * z, 0.0, -omega * x)


## Libre parcours moyen des molécules (m) : au-dessus de ~100 km, il dépasse la taille du vaisseau, et
## l'air n'est plus un « fluide » mais des molécules qui frappent la coque une à une.
static func libre_parcours(rho: float) -> float:
	return 6.63e-8 * 1.225 / maxf(rho, 1e-30)
