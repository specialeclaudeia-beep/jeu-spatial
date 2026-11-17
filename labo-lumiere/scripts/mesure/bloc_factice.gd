extends RefCounted
## Un bloc de rayons FACTICES pour la mesure de vitesse (étape 2).
## Les rayons sont rangés par blocs pour que chaque fil de calcul travaille sur SON bloc, sans
## jamais toucher aux tableaux d'un autre (pas de mélange entre fils).
## Le travail fait par rayon imite celui du vrai système (étape 4) :
## - choisir : distance à l'œil, taille à l'écran, couper au-dessus de 8 px, fusionner sous 6 px,
##   test d'horizon, liste des visibles, plus le calcul des milieux pour les triangles coupés ;
## - éclairer : normale, graine tirée de l'adresse, relief sur 12 échelles (une par niveau),
##   couleur du sol, direction moyenne non normalisée, puis les 13 nombres du rayon et ses 8 octets.

const NOMBRES_PAR_RAYON := 13
const OCTETS_PAR_RAYON := 8     # 2 texels RGBA8 : couleur + énergie, direction + étalement
const ECHELLES_RELIEF := 12
const COUPER_PX := 8.0
const FUSIONNER_PX := 6.0

var debut: int = 0               # numéro du premier rayon du bloc
var nb: int = 0                  # nombre de rayons du bloc
var centres := PackedFloat64Array()   # 3 nombres par rayon, en 64 bits (positions exactes)
var tailles := PackedFloat32Array()   # rayon du triangle, en mètres
var adresses := PackedInt64Array()
var etats := PackedByteArray()        # 0 garder, 1 couper, 2 fusionner, 3 caché
var visibles := PackedInt32Array()
var nb_visibles: int = 0
var nb_coupes: int = 0
var milieux := PackedFloat64Array()   # brouillon pour les triangles coupés
var rayons := PackedFloat32Array()    # 13 nombres par rayon
var octets := PackedByteArray()       # ce qui part vers la carte graphique


func preparer(p_debut: int, p_centres: PackedFloat64Array, p_tailles: PackedFloat32Array, p_adresses: PackedInt64Array) -> void:
	debut = p_debut
	centres = p_centres
	tailles = p_tailles
	adresses = p_adresses
	nb = tailles.size()
	etats.resize(nb)
	visibles.resize(nb)
	milieux.resize(9 * 64)
	rayons.resize(nb * NOMBRES_PAR_RAYON)
	octets.resize(nb * OCTETS_PAR_RAYON)


## Temps 1 « choisir » : un passage sur tous les triangles du bloc, et sur leurs parents (un tiers de plus,
## comme dans un vrai arbre où chaque parent a 4 enfants).
func choisir(oeil: Vector3, focale_px: float) -> void:
	var ox := float(oeil.x)
	var oy := float(oeil.y)
	var oz := float(oeil.z)
	var n_vis := 0
	var n_coupes := 0
	var passages := nb + nb / 3
	for k in passages:
		var i := k % nb
		var cx := centres[3 * i]
		var cy := centres[3 * i + 1]
		var cz := centres[3 * i + 2]
		var dx := cx - ox
		var dy := cy - oy
		var dz := cz - oz
		var d := sqrt(dx * dx + dy * dy + dz * dz)
		# Horizon : le triangle regarde-t-il l'œil ?
		if cx * dx + cy * dy + cz * dz > 0.0:
			if k < nb:
				etats[i] = 3
			continue
		var px := tailles[i] * focale_px / maxf(d, 1e-6)
		if k >= nb:
			continue   # un parent : seulement le test
		if px > COUPER_PX:
			etats[i] = 1
			if n_coupes < 64:   # les milieux des 3 côtés, remis sur la sphère
				var l := sqrt(cx * cx + cy * cy + cz * cz)
				for m in 3:
					var b := 9 * n_coupes + 3 * m
					milieux[b] = cx / l
					milieux[b + 1] = cy / l
					milieux[b + 2] = cz / l
				n_coupes += 1
		elif px < FUSIONNER_PX:
			etats[i] = 2
		else:
			etats[i] = 0
		visibles[n_vis] = debut + i
		n_vis += 1
	nb_visibles = n_vis
	nb_coupes = n_coupes


## Temps 2 « éclairer » : recalcule les rayons dont le numéro tombe dans le tour de cette image
## (1 sur `parmi`). Avec parmi = 1, tout est refait (changement brusque).
func eclairer(tour: int, parmi: int, date: float) -> void:
	var premier := posmod(tour - debut, parmi)
	var i := premier
	while i < nb:
		var cx := centres[3 * i]
		var cy := centres[3 * i + 1]
		var cz := centres[3 * i + 2]
		var l := sqrt(cx * cx + cy * cy + cz * cz)
		var nx := cx / l
		var ny := cy / l
		var nz := cz / l
		# Relief : une petite bosse par échelle, tirée de la graine (l'adresse du triangle).
		var graine: int = adresses[i] & 0x7FFFFFFF
		var hauteur := 0.0
		var pente_x := 0.0
		var pente_z := 0.0
		var ampleur := 0.5
		for e in ECHELLES_RELIEF:
			graine = (graine * 1103515245 + 12345) & 0x7FFFFFFF
			var h := float(graine & 0xFFFF) / 65535.0 - 0.5
			hauteur += h * ampleur
			pente_x += float((graine >> 16) & 0xFF) / 255.0 * ampleur - 0.5 * ampleur
			pente_z += h * ampleur * 0.5
			ampleur *= 0.5
		# Couleur du sol : mer, plage, terre ou neige selon la hauteur et la latitude.
		var r: float
		var g: float
		var b: float
		if hauteur < -0.05:
			r = 0.02; g = 0.08; b = 0.25
		elif hauteur < 0.0:
			r = 0.7; g = 0.65; b = 0.45
		elif absf(ny) + hauteur > 0.95:
			r = 0.9; g = 0.9; b = 0.92
		else:
			r = 0.15 + hauteur * 0.3; g = 0.35 - hauteur * 0.2; b = 0.1
		# Direction moyenne non normalisée : la normale penchée par le relief, raccourcie par la rugosité.
		var mx := nx + pente_x * 0.3
		var my := ny
		var mz := nz + pente_z * 0.3
		var lm := sqrt(mx * mx + my * my + mz * mz)
		var garde := 0.9 - absf(hauteur) * 0.2   # longueur gardée = 1 − étalement
		mx = mx / lm * garde
		my = my / lm * garde
		mz = mz / lm * garde
		var o := i * NOMBRES_PAR_RAYON
		rayons[o] = r
		rayons[o + 1] = g
		rayons[o + 2] = b
		rayons[o + 3] = 1.0            # énergie
		rayons[o + 4] = mx
		rayons[o + 5] = my
		rayons[o + 6] = mz
		rayons[o + 7] = 1.0 - garde    # étalement
		rayons[o + 8] = 0.8            # rugosité
		rayons[o + 9] = 0.0            # métal
		rayons[o + 10] = hauteur
		rayons[o + 11] = 0.0           # graduation
		rayons[o + 12] = date
		var q := i * OCTETS_PAR_RAYON
		octets[q] = int(clampf(r, 0.0, 1.0) * 255.0)
		octets[q + 1] = int(clampf(g, 0.0, 1.0) * 255.0)
		octets[q + 2] = int(clampf(b, 0.0, 1.0) * 255.0)
		octets[q + 3] = 255
		octets[q + 4] = int((mx * 0.5 + 0.5) * 255.0)
		octets[q + 5] = int((my * 0.5 + 0.5) * 255.0)
		octets[q + 6] = int((mz * 0.5 + 0.5) * 255.0)
		octets[q + 7] = int((1.0 - garde) * 255.0)
		i += parmi
