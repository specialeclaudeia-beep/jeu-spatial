extends Camera3D
## Caméra de l'atelier, comme dans Blender : elle tourne autour d'un point (la « cible »).
##   - clic molette (ou Alt + clic gauche, pour un pavé tactile) en glissant : tourner autour ;
##   - Maj + clic molette : déplacer (la cible glisse avec la souris) ;
##   - Ctrl + clic molette, ou molette : rapprocher / éloigner ;
##   - pavé numérique 1 / 3 / 7 : face / côté / dessus (Ctrl : l'autre côté), 5 : perspective / plan,
##     point (,) : cadrer la pièce choisie, Origine : cadrer tout le vaisseau.
## « vitesse » (réglage du menu, de ×0,25 à ×4) multiplie tous les mouvements.
## La caméra ne descend pas sous le sol du hangar (sol_min) : on ne voit jamais le dessous du décor.

signal bougee

const DISTANCE_MIN := 1.2
const DISTANCE_MAX := 140.0
const TANGAGE_MAX := deg_to_rad(89.0)
const SENSIBILITE_ROTATION := 0.006   # rad par pixel
const PAS_ZOOM := 1.12                # un cran de molette

var cible := Vector3.ZERO
var lacet := deg_to_rad(35.0)         # autour de la verticale (0 = vue de derrière, regard vers −Z, l'avant)
var tangage := deg_to_rad(-18.0)      # négatif = on regarde vers le bas
var distance := 22.0
var vitesse := 1.0
var sol_min := 0.15                   # hauteur la plus basse de la caméra (m) ; -INF = sans limite
var _glisse := ""                     # "", "tourner", "deplacer", "zoom"


func _ready() -> void:
	fov = 50.0
	near = 0.05
	far = 2000.0
	appliquer()


## Place la caméra d'après cible, lacet, tangage, distance.
func appliquer() -> void:
	distance = clampf(distance, DISTANCE_MIN, DISTANCE_MAX)
	tangage = clampf(tangage, -TANGAGE_MAX, TANGAGE_MAX)
	var dir := direction()
	var pos := cible - dir * distance
	if is_finite(sol_min) and pos.y < sol_min:
		# trop bas : on relève la caméra (en gardant la distance) juste au-dessus du sol
		var s := clampf((cible.y - sol_min) / distance, -1.0, 1.0)
		tangage = clampf(asin(s), -TANGAGE_MAX, TANGAGE_MAX)
		dir = direction()
		pos = cible - dir * distance
	if projection == PROJECTION_ORTHOGONAL:
		size = distance * 0.9
	global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.999 else Vector3.FORWARD), pos)
	bougee.emit()


## Direction du regard (de la caméra vers la cible).
func direction() -> Vector3:
	return Vector3(-sin(lacet) * cos(tangage), sin(tangage), -cos(lacet) * cos(tangage)).normalized()


func tourner(dx: float, dy: float) -> void:
	lacet -= dx * SENSIBILITE_ROTATION * vitesse
	tangage -= dy * SENSIBILITE_ROTATION * vitesse
	appliquer()


## Déplacer la cible dans le plan de l'écran : la scène suit la souris (dx, dy en pixels).
func deplacer(dx: float, dy: float, hauteur_ecran := 720.0) -> void:
	var b := global_transform.basis
	var metres_par_pixel := 2.0 * distance * tan(deg_to_rad(fov) * 0.5) / maxf(hauteur_ecran, 1.0)
	if projection == PROJECTION_ORTHOGONAL:
		metres_par_pixel = size / maxf(hauteur_ecran, 1.0)
	cible += (-b.x * dx + b.y * dy) * metres_par_pixel * vitesse
	appliquer()


## Rapprocher (crans > 0) ou éloigner (crans < 0).
func zoomer(crans: float) -> void:
	distance /= pow(PAS_ZOOM, crans * vitesse)
	appliquer()


## Vues toutes faites : "face" (de devant), "arriere", "droite", "gauche", "dessus", "dessous", "trois_quarts".
func vue(nom: String) -> void:
	match nom:
		"face":
			lacet = PI
			tangage = 0.0
		"arriere":
			lacet = 0.0
			tangage = 0.0
		"droite":
			lacet = PI / 2.0
			tangage = 0.0
		"gauche":
			lacet = -PI / 2.0
			tangage = 0.0
		"dessus":
			tangage = -TANGAGE_MAX
		"dessous":
			tangage = TANGAGE_MAX
		_:
			lacet = deg_to_rad(35.0)
			tangage = deg_to_rad(-18.0)
	appliquer()


## Cadrer une boîte (AABB, repère du monde) : la cible au centre, assez loin pour tout voir.
func cadrer(boite: AABB) -> void:
	cible = boite.get_center()
	var r := maxf(boite.size.length() * 0.5, 0.3)
	distance = clampf(r / sin(deg_to_rad(fov) * 0.5) * 1.05, DISTANCE_MIN, DISTANCE_MAX)
	appliquer()


func basculer_projection() -> void:
	projection = PROJECTION_PERSPECTIVE if projection == PROJECTION_ORTHOGONAL else PROJECTION_ORTHOGONAL
	appliquer()


## Souris et clavier. Renvoie vrai si l'événement a été utilisé par la caméra.
func traiter(e: InputEvent, hauteur_ecran: float) -> bool:
	if e is InputEventMouseButton:
		var b := e as InputEventMouseButton
		var molette := b.button_index == MOUSE_BUTTON_MIDDLE
		var alt_gauche := b.button_index == MOUSE_BUTTON_LEFT and b.alt_pressed
		if molette or alt_gauche:
			if b.pressed:
				_glisse = "deplacer" if b.shift_pressed else ("zoom" if b.ctrl_pressed else "tourner")
			else:
				_glisse = ""
			return true
		if b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoomer(b.factor if b.factor > 0.0 else 1.0)
			return true
		if b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoomer(-(b.factor if b.factor > 0.0 else 1.0))
			return true
	elif e is InputEventMouseMotion and _glisse != "":
		var m := e as InputEventMouseMotion
		match _glisse:
			"tourner":
				tourner(m.relative.x, m.relative.y)
			"deplacer":
				deplacer(m.relative.x, m.relative.y, hauteur_ecran)
			"zoom":
				zoomer(-m.relative.y * 0.03)
		return true
	elif e is InputEventPanGesture:
		# deux doigts sur le pavé tactile : tourner (Maj : déplacer, Ctrl : zoom)
		var g := e as InputEventPanGesture
		if g.shift_pressed:
			deplacer(-g.delta.x * 8.0, -g.delta.y * 8.0, hauteur_ecran)
		elif g.ctrl_pressed:
			zoomer(-g.delta.y * 0.5)
		else:
			tourner(-g.delta.x * 8.0, -g.delta.y * 8.0)
		return true
	elif e is InputEventMagnifyGesture:
		zoomer(((e as InputEventMagnifyGesture).factor - 1.0) * 6.0)
		return true
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		var ctrl := k.ctrl_pressed
		match k.keycode:
			KEY_KP_1:
				vue("arriere" if ctrl else "face")
				return true
			KEY_KP_3:
				vue("gauche" if ctrl else "droite")
				return true
			KEY_KP_7:
				vue("dessous" if ctrl else "dessus")
				return true
			KEY_KP_5:
				basculer_projection()
				return true
			KEY_KP_4, KEY_KP_6:
				lacet += (0.26 if k.keycode == KEY_KP_4 else -0.26) * vitesse
				appliquer()
				return true
			KEY_KP_8, KEY_KP_2:
				tangage += (0.26 if k.keycode == KEY_KP_2 else -0.26) * vitesse
				appliquer()
				return true
			KEY_KP_ADD:
				zoomer(1.0)
				return true
			KEY_KP_SUBTRACT:
				zoomer(-1.0)
				return true
	return false


func glisse_en_cours() -> bool:
	return _glisse != ""
