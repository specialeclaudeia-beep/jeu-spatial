extends RefCounted
## Einstein B : LA LUMIÈRE COURBÉE PAR UN TROU NOIR (lentille gravitationnelle).
##
## Près d'un trou noir, la lumière ne va plus tout droit : elle suit, comme le vaisseau, le chemin le
## plus droit de l'espace-temps courbé (géodésique de Schwarzschild). Une étoile située juste derrière
## le trou noir est vue tout autour de lui (« anneau d'Einstein ») ; une autre image d'elle apparaît de
## l'autre côté ; et au centre, une tache noire (« ombre ») : là, toute la lumière qui viendrait vers
## l'œil est en fait tombée dans le trou noir. Rien n'est inventé : chaque direction est calculée.
##
## Méthode (celle des vraies images de trous noirs, Luminet 1979, Event Horizon Telescope) : on suit à
## l'envers le rayon qui arrive dans l'œil. Dans le plan qui contient l'œil, le trou noir et ce rayon,
## avec u = 1/r (r = rayon de Schwarzschild) et b = « paramètre d'impact » du rayon :
##     (du/dφ)² = 1/b² − u² + r_s·u³          (r_s = 2·G·M/c², rayon de l'horizon)
## L'angle total φ parcouru par le rayon jusqu'à l'infini dit d'où vient sa lumière. Comme l'œil est le
## même pour tous les pixels d'une image, on calcule une fois une table (angle vu → angle d'origine), que
## les shaders du ciel et des étoiles lisent (ciel.gdshader, etoiles.gdshader).

const POINTS := 512        # échantillons des tables
const GL_N := 24           # points de Gauss-Legendre par intégrale
const MU_MAX := 2000.0     # grossissement le plus fort gardé (étoile exactement derrière : infini)

## Résultat du dernier calcul (lu par lumiere_jeu.gd)
var ombre := 0.0           # rayon angulaire de l'ombre (rad)
var table: ImageTexture    # ligne 0 : angle vu → angle d'origine ; ligne 1 : étoile → ses 2 images
var _r_calcule := 0.0
var _rs_calcule := 0.0
var psi_vu := PackedFloat64Array()   # angle d'origine pour chaque échantillon de la ligne 0
var thetas := PackedFloat64Array()   # angle vu de chaque échantillon de la ligne 0
var _gl_x := PackedFloat64Array()
var _gl_w := PackedFloat64Array()


func _init() -> void:
	_preparer_gauss()


## Rayon apparent de l'ombre vue depuis r_o (rayon de Schwarzschild) : sin θ = (b_c / r_o)·√(1 − r_s/r_o),
## b_c = (3√3/2)·r_s. Loin du trou noir : 2,6 fois l'angle sous lequel on verrait l'horizon.
static func angle_ombre(r_o: float, rs: float) -> float:
	var bc := 1.5 * sqrt(3.0) * rs
	var s := bc / r_o * sqrt(maxf(1.0 - rs / r_o, 0.0))
	if r_o < 1.5 * rs:
		return PI - asin(minf(s, 1.0))   # sous la sphère des photons, presque tout le ciel est noir
	return asin(minf(s, 1.0))


## Angle d'origine ψ (par rapport à la direction du trou noir, du même côté) de la lumière qui arrive
## dans l'œil sous l'angle θ (0 = droit vers le trou noir). Négatif : elle vient de l'autre côté
## (elle a fait le tour). NAN : ce rayon vient du trou noir lui-même (ombre).
func angle_origine(theta: float, r_o: float, rs: float) -> float:
	var u_o := 1.0 / r_o
	var s := sin(theta)
	if s < 1e-12:
		return 0.0 if theta < 1.0 else PI
	# 1/b² = u_o²·(1 − r_s·u_o) / sin²θ
	var inv_b2 := u_o * u_o * (1.0 - rs * u_o) / (s * s)
	var phi := 0.0
	if theta > 0.5 * PI:
		phi = _integrale(0.0, u_o, inv_b2, rs, -1.0)   # le rayon (à l'envers) s'éloigne tout de suite
	else:
		var u_p := _periastre(inv_b2, rs, u_o)
		if u_p < 0.0:
			return NAN
		phi = _integrale(u_o, u_p, inv_b2, rs, u_p) + _integrale(0.0, u_p, inv_b2, rs, u_p)
	return PI - phi


## Point le plus proche du rayon (u = 1/r) : plus petite racine de 1/b² = u²(1 − r_s·u) au-delà de u_o.
## −1 si le rayon tombe dans le trou noir (b plus petit que b_c).
static func _periastre(inv_b2: float, rs: float, u_o: float) -> float:
	var u_max := 2.0 / (3.0 * rs)    # sommet de u²(1 − r_s·u) : la sphère des photons (r = 1,5 r_s)
	if u_max * u_max * (1.0 - rs * u_max) < inv_b2:
		return -1.0
	var a := u_o
	var b := u_max
	for i in 60:
		var m := 0.5 * (a + b)
		if m * m * (1.0 - rs * m) < inv_b2:
			a = m
		else:
			b = m
	return 0.5 * (a + b)


## ∫ du / √(1/b² − u² + r_s·u³) de a à b. Si fin > 0, b est un point de retour (racine) : on change
## de variable u = fin − t² pour que l'intégrale reste nette malgré la racine.
func _integrale(a: float, b: float, inv_b2: float, rs: float, fin: float) -> float:
	var somme := 0.0
	if fin > 0.0:
		var t_max := sqrt(maxf(fin - a, 0.0))
		for i in GL_N:
			var t := 0.5 * t_max * (_gl_x[i] + 1.0)
			var u := fin - t * t
			var f := inv_b2 - u * u + rs * u * u * u
			# près de la racine, f ≈ |f'(fin)|·t² : on divise d'abord par t
			var g := f / maxf(t * t, 1e-300)
			if g > 0.0:
				somme += _gl_w[i] * 2.0 / sqrt(g)
		return somme * 0.5 * t_max
	for i in GL_N:
		var u := a + 0.5 * (b - a) * (_gl_x[i] + 1.0)
		var f := inv_b2 - u * u + rs * u * u * u
		if f > 0.0:
			somme += _gl_w[i] / sqrt(f)
	return somme * 0.5 * (b - a)


## Calcule les tables pour un œil à r_o (rayon de Schwarzschild) d'un trou noir d'horizon r_s.
## Ne refait le calcul que si r_o a changé de plus de 0,2 %. Renvoie vrai si la table a changé.
func calculer(r_o: float, rs: float) -> bool:
	if table != null and absf(r_o / _r_calcule - 1.0) < 0.002 and rs == _rs_calcule:
		return false
	_r_calcule = r_o
	_rs_calcule = rs
	ombre = angle_ombre(r_o, rs)
	var img := Image.create(POINTS, 2, false, Image.FORMAT_RGBAF)
	# Ligne 0 : θ = ombre + (π − ombre)·x², x de 0 à 1 (serré près du bord de l'ombre, où tout change vite)
	psi_vu.resize(POINTS)
	thetas.resize(POINTS)
	for k in POINTS:
		var x := (k + 0.5) / POINTS if k == 0 else float(k) / (POINTS - 1)
		var th := ombre + (PI - ombre) * x * x
		thetas[k] = th
		var psi := angle_origine(th, r_o, rs)
		if is_nan(psi):
			psi = -50.0   # tout contre le bord : la lumière a fait beaucoup de tours
		psi_vu[k] = maxf(psi, -50.0)
		img.set_pixel(k, 0, Color(psi_vu[k], 0.0, 0.0, 1.0))
	# Ligne 1 : pour une étoile à l'angle ψ = π·s² du trou noir : ses deux images (θ1 du même côté,
	# θ2 de l'autre côté) et leur grossissement μ = (sin θ dθ) / (sin ψ dψ).
	for k in POINTS:
		var s := float(k) / (POINTS - 1)
		var psi_s := maxf(PI * s * s, 1e-6)
		var i1 := _image(thetas, psi_s)
		var i2 := _image(thetas, -psi_s)
		img.set_pixel(k, 1, Color(i1[0], i1[1], i2[0], i2[1]))
	if table == null:
		table = ImageTexture.create_from_image(img)
	else:
		table.update(img)
	return true


## Image d'une étoile à l'angle (signé) psi : [θ, grossissement] (grossissement 0 : pas d'image).
## ψ(θ) monte avec θ : on cherche par dichotomie dans la table.
func _image(thetas: PackedFloat64Array, psi: float) -> Array:
	var n := thetas.size()
	if psi < psi_vu[0] or psi > psi_vu[n - 1]:
		return [0.0, 0.0]
	var a := 0
	var b := n - 1
	while b - a > 1:
		var m := (a + b) / 2
		if psi_vu[m] < psi:
			a = m
		else:
			b = m
	var dpsi := psi_vu[b] - psi_vu[a]
	if dpsi <= 0.0:
		return [thetas[a], 0.0]
	var f := (psi - psi_vu[a]) / dpsi
	var th := thetas[a] + (thetas[b] - thetas[a]) * f
	var dth := thetas[b] - thetas[a]
	var mu := absf(sin(th) * dth / (sin(absf(psi)) * dpsi))
	return [th, minf(mu, MU_MAX)]


## Angle de déviation total d'un rayon qui passe loin (paramètre d'impact b, venu de l'infini et
## reparti à l'infini) : 2·∫₀^{u_p} − π. Sert aux tests (Einstein : 2·r_s/b quand b est grand).
func deviation_infini(b: float, rs: float) -> float:
	var inv_b2 := 1.0 / (b * b)
	var u_p := _periastre(inv_b2, rs, 0.0)
	if u_p < 0.0:
		return NAN
	return 2.0 * _integrale(0.0, u_p, inv_b2, rs, u_p) - PI


func _preparer_gauss() -> void:
	# Points et poids de Gauss-Legendre (méthode de Newton sur les polynômes de Legendre)
	_gl_x.resize(GL_N)
	_gl_w.resize(GL_N)
	for i in GL_N:
		var x := cos(PI * (i + 0.75) / (GL_N + 0.5))
		var dp := 0.0
		for it in 100:
			var p0 := 1.0
			var p1 := x
			for k in range(2, GL_N + 1):
				var p2 := ((2.0 * k - 1.0) * x * p1 - (k - 1.0) * p0) / k
				p0 = p1
				p1 = p2
			dp = GL_N * (x * p1 - p0) / (x * x - 1.0)
			var dx := p1 / dp
			x -= dx
			if absf(dx) < 1e-15:
				break
		_gl_x[i] = x
		_gl_w[i] = 2.0 / ((1.0 - x * x) * dp * dp)
