extends RefCounted
## Einstein C : UN TROU DE VER FIXE entre la maison et Alpha du Centaure.
##
## Un trou de ver d'Ellis (1973), celui que Kip Thorne a fait calculer pour le film Interstellar (sans la
## petite masse de leur version) :
##     ds² = −c² dt² + dl² + (a² + l²)(dθ² + sin²θ dφ²)
## l est la vraie distance comptée depuis la gorge : l > 0 ici, l < 0 de l'autre côté. Autour d'un point
## de distance l, la sphère a la taille r = √(a² + l²) : au plus étroit (l = 0), une sphère de rayon a.
## Le temps y passe partout au même rythme : un trou de ver d'Ellis n'attire rien (pas de gravité, pas de
## marée). Seul l'espace est courbé : un vaisseau sans moteur y va « tout droit » (géodésique), et ce
## chemin le plus droit peut passer par la gorge et ressortir 4,37 années-lumière plus loin.
##
## Physique : loin de la gorge (au-delà de 50 a), l'espace redevient plat à 0,02 % près : le vaisseau
## suit la physique habituelle (gravité d'Einstein des astres du système). Plus près, il compte sa
## position en (l, direction n) et suit les vraies équations du mouvement de cet espace :
##     dl/dt = u_l/γ,  dn/dt = u_t/(γ r),  du_l/dt = l·u_t²/(γ r²),  du_t/dt = −(l u_l/(γ r²))·u_t − (u_t²/(γ r))·n
## (u = vitesse propre, u_l le long de l, u_t de côté). La gravité des astres du système et la poussée
## des moteurs s'y ajoutent comme ailleurs.
## Lumière : même chemin que le vaisseau (dans un espace qui ne change pas avec le temps, la lumière et la
## matière suivent les mêmes lignes). Les angles sont calculés exactement en C++ (classe TrouDeVer, table
## refaite quand l'œil bouge, comme pour le trou noir).
##
## Les deux bouches sont reliées par une SYMÉTRIE : une direction m d'une bouche correspond à
## m − 2(m·k)k de l'autre (k = axe des bouches, commun). Un vaisseau qui passe le long de l'axe ressort
## dans le même sens et sans avoir tourné. Les bouches ne bougent pas dans leur système (« fixe ») et
## ont la même heure (l'heure du repère du système d'où l'on vient = l'heure du repère d'arrivée).

const C := 299792458.0
const A := 1000.0            # m, rayon de la gorge (celui d'Interstellar : environ 1 km)
const ZONE := 50.0           # en rayons de gorge : au-delà, l'espace est plat à 0,02 % près
const L_ZONE := ZONE * A
const PORTEE_LUMIERE := 3000.0 * A   # au-delà, la gorge fait moins d'un pixel : lumière droite
const PAS_MAX := 4000        # sous-pas au plus par pas de la physique (dans la zone)
const METRIQUE_PLATE := [1.0, 1.0, 1.0, 0.0]
const DISTANCE_SAUT := 30000.0       # m : saut d'essai (touche W) à 30 km de la gorge

var reperes
## Les deux bouches : système (indice dans reperes.systemes) et position du centre (repère du système).
var bouches: Array = []
var axe := PackedFloat64Array([0.0, 0.0, 1.0])

# État du vaisseau dans la zone de la gorge
var dans := false
var bouche := 0              # bouche dont on compte la position (0 : maison, 1 : Alpha du Centaure)
var l := 0.0
var n := PackedFloat64Array([0.0, 0.0, 1.0])
var traversees := 0          # passages par la gorge (tests, affichage)
var _derniere := PackedFloat64Array([0.0, 0.0, 0.0])   # position écrite au dernier pas

# Lumière
var cpp: Object = null       # TrouDeVer (partie C++)
var table: ImageTexture
var lumiere_active := false
var table_ms := 0.0
var angle_gorge := 0.0
var _l_calcule := -1.0
var _autre := {}             # étoile principale de l'autre côté (couleur calculée une fois)


func _init(r) -> void:
	reperes = r
	if ClassDB.class_exists("TrouDeVer"):
		cpp = ClassDB.instantiate("TrouDeVer")
	# Bouche de la maison : à 20 000 km de la planète, sur l'axe Z (dans le plan de l'orbite de départ).
	bouches.append({"systeme": 0, "p": PackedFloat64Array([0.0, 0.0, 2.0e7])})
	# Bouche d'Alpha du Centaure : à 1,25 UA d'Alpha du Centaure A (là où elle éclaire autant que le
	# Soleil sur la Terre : elle est 1,5 fois plus lumineuse). En sortant dans l'axe, on lui fait face.
	var ua: float = reperes.UA
	bouches.append({"systeme": 1, "p": PackedFloat64Array([0.0, 0.0, -1.25 * ua])})


# =====================================================================
# OUTILS
# =====================================================================
func _symetrie(m: PackedFloat64Array) -> PackedFloat64Array:
	var d := 2.0 * (m[0] * axe[0] + m[1] * axe[1] + m[2] * axe[2])
	return PackedFloat64Array([m[0] - d * axe[0], m[1] - d * axe[1], m[2] - d * axe[2]])


func _bouche_du_systeme(i: int) -> int:
	for k in bouches.size():
		if int(bouches[k]["systeme"]) == i:
			return k
	return -1


## Nom du système de l'autre côté de la bouche du système actuel ("" s'il n'y en a pas).
func nom_en_face() -> String:
	var k := _bouche_du_systeme(reperes.courant)
	if k < 0:
		return ""
	return String(reperes.systemes[int(bouches[1 - k]["systeme"])]["nom"])


## Distance du point p (repère du système actuel) au centre de la bouche de ce système (INF s'il n'y en a pas).
func distance_bouche(p: PackedFloat64Array) -> float:
	var k := _bouche_du_systeme(reperes.courant)
	if k < 0:
		return INF
	var c: PackedFloat64Array = bouches[k]["p"]
	return sqrt((p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2)


## Vraie distance à la gorge (l), pour l'affichage.
func distance_gorge(v) -> float:
	if dans:
		return absf(l)
	var r := distance_bouche(PackedFloat64Array([v.px, v.py, v.pz]))
	return sqrt(maxf(r * r - A * A, 0.0))


# =====================================================================
# PHYSIQUE
# =====================================================================
## Pour vaisseau.pas() : en combien de morceaux couper dt pour ne pas sauter par-dessus la zone
## de la gorge à grande vitesse.
func morceaux(v, dt: float) -> int:
	if dans:
		return 1
	var d := distance_bouche(PackedFloat64Array([v.px, v.py, v.pz]))
	if d == INF:
		return 1
	var trajet: float = v.vitesse() * dt
	var r_zone := sqrt(A * A + L_ZONE * L_ZONE)
	if d - trajet > r_zone or trajet < 0.25 * r_zone:
		return 1
	return clampi(int(ceil(trajet / (0.25 * r_zone))), 1, PAS_MAX)


## Pour vaisseau._pas_un() : fait avancer le vaisseau s'il est dans la zone de la gorge (vrai), sinon
## ne fait rien (faux : la physique habituelle s'en charge). a_p = accélération des moteurs (repère monde).
func translater(v, a_p: Vector3, dt: float) -> bool:
	var p := PackedFloat64Array([v.px, v.py, v.pz])
	if dans and (absf(p[0] - _derniere[0]) > 1.0 or absf(p[1] - _derniere[1]) > 1.0 or absf(p[2] - _derniere[2]) > 1.0):
		dans = false   # quelqu'un a déplacé le vaisseau (saut d'essai, remise en orbite)
	if dans and _bouche_du_systeme(reperes.courant) != bouche:
		dans = false
	if not dans:
		var k := _bouche_du_systeme(reperes.courant)
		if k < 0:
			return false
		var c: PackedFloat64Array = bouches[k]["p"]
		var x := PackedFloat64Array([p[0] - c[0], p[1] - c[1], p[2] - c[2]])
		var r := sqrt(x[0] * x[0] + x[1] * x[1] + x[2] * x[2])
		if r * r >= A * A + L_ZONE * L_ZONE:
			return false
		# entrée dans la zone : même position, même vitesse ; on compte maintenant en (l, n)
		dans = true
		bouche = k
		l = sqrt(maxf(r * r - A * A, 0.0))
		n = PackedFloat64Array([x[0] / r, x[1] / r, x[2] / r])
	v._lire_vitesse()
	var h := 0.5 * dt
	var m0: Array = v.metrique(v.px, v.py, v.pz)
	var rythme0: float = float(m0[0]) / v.gamma()
	v._pousser_u(v.gravite(v.px, v.py, v.pz), a_p, h, METRIQUE_PLATE)
	_deriver(v, dt)
	_ecrire_position(v)
	v._pousser_u(v.gravite(v.px, v.py, v.pz), a_p, h, METRIQUE_PLATE)
	v._ecrire_vitesse()
	var m1: Array = v.metrique(v.px, v.py, v.pz)
	v.temps_univers += dt
	v.temps_pilote += dt * 0.5 * (rythme0 + float(m1[0]) / v.gamma())
	v.acceleration_ressentie = a_p
	if l > L_ZONE:
		dans = false   # sortie : l'espace est plat, la physique habituelle reprend
	return true


func _ecrire_position(v) -> void:
	var c: PackedFloat64Array = bouches[bouche]["p"]
	var r := sqrt(A * A + l * l)
	v.px = c[0] + r * n[0]
	v.py = c[1] + r * n[1]
	v.pz = c[2] + r * n[2]
	_derniere = PackedFloat64Array([v.px, v.py, v.pz])


## Trajet sans poussée pendant dt (géodésique d'Ellis), méthode de Runge-Kutta d'ordre 4.
## État : [l, n (3), u_l, u_t (3)], la vitesse propre u du vaisseau = u_l·n + u_t.
func _deriver(v, dt: float) -> void:
	var ux: float = v.ux
	var uy: float = v.uy
	var uz: float = v.uz
	var u2 := ux * ux + uy * uy + uz * uz
	if u2 == 0.0:
		return
	var gam := sqrt(1.0 + u2 / (C * C))
	var ul := ux * n[0] + uy * n[1] + uz * n[2]
	var y := PackedFloat64Array([l, n[0], n[1], n[2], ul, ux - ul * n[0], uy - ul * n[1], uz - ul * n[2]])
	var vitesse := sqrt(u2) / gam
	var reste := dt
	var compte := 0
	while reste > 0.0 and compte < PAS_MAX:
		var r := sqrt(A * A + y[0] * y[0])
		var hs := minf(reste, 0.02 * r / vitesse)
		if compte == PAS_MAX - 1:
			hs = reste
		var avant := y[0]
		y = _rk4(y, hs, gam)
		_normaliser(y, u2)
		if avant > 0.0 and y[0] <= 0.0:
			y = _traverser(v, y)
		reste -= hs
		compte += 1
	l = y[0]
	n = PackedFloat64Array([y[1], y[2], y[3]])
	v.ux = y[4] * y[1] + y[5]
	v.uy = y[4] * y[2] + y[6]
	v.uz = y[4] * y[3] + y[7]


static func _derivee(y: PackedFloat64Array, gam: float) -> PackedFloat64Array:
	var r2 := A * A + y[0] * y[0]
	var r := sqrt(r2)
	var t2 := y[5] * y[5] + y[6] * y[6] + y[7] * y[7]
	var kt := -y[0] * y[4] / (gam * r2)
	var kn := -t2 / (gam * r)
	var ir := 1.0 / (gam * r)
	return PackedFloat64Array([y[4] / gam, y[5] * ir, y[6] * ir, y[7] * ir, y[0] * t2 / (gam * r2),
		kt * y[5] + kn * y[1], kt * y[6] + kn * y[2], kt * y[7] + kn * y[3]])


static func _rk4(y: PackedFloat64Array, h: float, gam: float) -> PackedFloat64Array:
	var k1 := _derivee(y, gam)
	var y2 := y.duplicate()
	for i in 8:
		y2[i] = y[i] + 0.5 * h * k1[i]
	var k2 := _derivee(y2, gam)
	for i in 8:
		y2[i] = y[i] + 0.5 * h * k2[i]
	var k3 := _derivee(y2, gam)
	for i in 8:
		y2[i] = y[i] + h * k3[i]
	var k4 := _derivee(y2, gam)
	var out := y.duplicate()
	for i in 8:
		out[i] = y[i] + h / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return out


## n de longueur 1, u_t perpendiculaire à n, |u| inchangé (une géodésique garde sa vitesse).
static func _normaliser(y: PackedFloat64Array, u2: float) -> void:
	var nl := sqrt(y[1] * y[1] + y[2] * y[2] + y[3] * y[3])
	y[1] /= nl
	y[2] /= nl
	y[3] /= nl
	var tn := y[5] * y[1] + y[6] * y[2] + y[7] * y[3]
	y[5] -= tn * y[1]
	y[6] -= tn * y[2]
	y[7] -= tn * y[3]
	var w2 := y[4] * y[4] + y[5] * y[5] + y[6] * y[6] + y[7] * y[7]
	if w2 > 0.0:
		var k := sqrt(u2 / w2)
		for i in [4, 5, 6, 7]:
			y[i] *= k


## Passage de la gorge (l devient négatif) : on compte maintenant depuis l'autre bouche, dans le repère
## de son système. l → −l, n → symétrie(n), u_l → −u_l, u_t → symétrie(u_t) ; l'orientation du vaisseau
## tourne avec (rotation T = symétrie ∘ retournement le long de n : aucune rotation dans l'axe).
func _traverser(v, y: PackedFloat64Array) -> PackedFloat64Array:
	var nn := PackedFloat64Array([y[1], y[2], y[3]])
	var n2 := _symetrie(nn)
	var t2 := _symetrie(PackedFloat64Array([y[5], y[6], y[7]]))
	# rotation des axes du vaisseau : w ↦ symétrie(w − 2(w·n)n)
	var cols: Array[Vector3] = []
	for e in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var w := PackedFloat64Array([e.x, e.y, e.z])
		var wn := w[0] * nn[0] + w[1] * nn[1] + w[2] * nn[2]
		var s := _symetrie(PackedFloat64Array([w[0] - 2.0 * wn * nn[0], w[1] - 2.0 * wn * nn[1], w[2] - 2.0 * wn * nn[2]]))
		cols.append(Vector3(s[0], s[1], s[2]))
	var rot := Basis(cols[0], cols[1], cols[2]).orthonormalized()
	v.orientation = (Quaternion(rot) * v.orientation).normalized()
	bouche = 1 - bouche
	traversees += 1
	var out := PackedFloat64Array([-y[0], n2[0], n2[1], n2[2], -y[4], t2[0], t2[1], t2[2]])
	# changement de système : position et vitesse écrites dans le repère de l'autre bouche
	l = out[0]
	n = n2
	var c: PackedFloat64Array = bouches[bouche]["p"]
	var r := sqrt(A * A + l * l)
	var p := PackedFloat64Array([c[0] + r * n2[0], c[1] + r * n2[1], c[2] + r * n2[2]])
	var u := PackedFloat64Array([out[4] * n2[0] + out[5], out[4] * n2[1] + out[6], out[4] * n2[2] + out[7]])
	reperes.sauter(v, int(bouches[bouche]["systeme"]), p, u)
	_derniere = p
	return out


## Saut d'essai (touche W) : à DISTANCE_SAUT de la gorge de la maison, côté planète, immobile, le nez
## vers la gorge. Il suffit de mettre les gaz (ou d'attendre : la planète l'attire doucement).
func aller(v, altitude_depart: float) -> void:
	reperes.revenir_maison(v)
	v.placer_en_orbite(altitude_depart)
	var c: PackedFloat64Array = bouches[0]["p"]
	var r := DISTANCE_SAUT
	v.px = c[0] - r * axe[0]
	v.py = c[1] - r * axe[1]
	v.pz = c[2] - r * axe[2]
	v.vx = 0.0
	v.vy = 0.0
	v.vz = 0.0
	v._lire_vitesse()
	var k := Vector3(axe[0], axe[1], axe[2])
	var haut := Vector3.UP if absf(k.y) < 0.9 else Vector3.RIGHT
	v.orientation = Quaternion(Basis.looking_at(k, haut))
	dans = false


# =====================================================================
# LUMIÈRE
# =====================================================================
## Donne au système de lumière la direction de la gorge, sa table d'angles et l'étoile d'en face.
## À appeler APRÈS reperes.regler_lentille (qui coupe la lentille quand il n'y a pas de trou noir).
## oeil = l'œil dans le repère du système actuel (physique), v = le vaisseau.
func regler_lumiere(lumiere, oeil: PackedFloat64Array, v) -> void:
	lumiere_active = false
	var k := _bouche_du_systeme(reperes.courant)
	if k < 0 or cpp == null or lumiere == null or not lumiere.lentille_autorisee:
		return
	var c: PackedFloat64Array = bouches[k]["p"]
	var dx := c[0] - oeil[0]
	var dy := c[1] - oeil[1]
	var dz := c[2] - oeil[2]
	var r := sqrt(dx * dx + dy * dy + dz * dz)
	if r > PORTEE_LUMIERE:
		return
	# vraie distance de l'œil à la gorge (le vaisseau la connaît mieux dans la zone)
	var l_o := absf(l) if dans and bouche == k else sqrt(maxf(r * r - A * A, 0.0))
	if dans and bouche == k:
		dx = -n[0]
		dy = -n[1]
		dz = -n[2]
		r = 1.0
	var t0 := Time.get_ticks_usec()
	if table == null or absf(l_o - _l_calcule) > 0.002 * maxf(l_o, A):
		var donnees: PackedFloat32Array = cpp.table(l_o, A)
		var img := Image.create_from_data(512, 4, false, Image.FORMAT_RGBAF, donnees.to_byte_array())
		if table == null:
			table = ImageTexture.create_from_image(img)
		else:
			table.update(img)
		angle_gorge = cpp.angle_gorge(l_o, A)
		_l_calcule = l_o
		table_ms = (Time.get_ticks_usec() - t0) / 1000.0
	# étoile principale de l'autre côté, vue de l'autre bouche (repère de son système)
	var j := 1 - k
	var sj: Dictionary = reperes.systemes[int(bouches[j]["systeme"])]
	var e: Dictionary = sj["etoiles"][0]
	if _autre.get("nom", "") != e["nom"]:
		var EtoileProche = load("res://scripts/lumiere/etoile_proche.gd")
		var ep = EtoileProche.new()
		ep.rayon = e["rayon"]
		ep.temperature = e["temperature"]
		var col: Color = ep.couleur()
		_autre = {"nom": e["nom"], "couleur": Vector3(col.r, col.g, col.b),
			"luminance": ep.luminance_moyenne() / (1.0 - 0.6 / 3.0), "temperature": float(e["temperature"])}
	var cj: PackedFloat64Array = bouches[j]["p"]
	var pe: PackedFloat64Array = e["p"]
	var de := Vector3(pe[0] - cj[0], pe[1] - cj[1], pe[2] - cj[2])
	var dist := de.length()
	var rayon := asin(minf(float(e["rayon"]) / dist, 1.0)) if dist > 0.0 else 0.0
	lumiere.regler_trou_de_ver(Vector3(dx / r, dy / r, dz / r), angle_gorge, table, Vector3(axe[0], axe[1], axe[2]),
		de / maxf(dist, 1e-30), rayon, _autre["couleur"], _autre["luminance"], _autre["temperature"])
	lumiere_active = true
