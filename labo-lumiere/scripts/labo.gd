extends Node3D
## Scène principale du labo (étape 0 : scène vide).
## Un ciel noir, une caméra libre et le compteur (F3). Une boule grise éclairée par une lampe Godot
## sert seulement de repère pour voir que la caméra bouge : elle disparaîtra quand le système
## de lumière dessinera la planète (étape 4).
##
## Caméra libre : W A S D (Z Q S D sur un clavier français), Espace / C pour monter / descendre,
## Maj pour aller plus vite, clic droit maintenu + souris pour regarder, molette pour la vitesse.

const Compteur = preload("res://scripts/outils/compteur.gd")

var camera: Camera3D
var compteur: CanvasLayer
var vitesse := 5.0          # m/s, changée avec la molette
var _lacet := 0.0
var _tangage := 0.0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var monde := WorldEnvironment.new()
	monde.environment = env
	add_child(monde)

	var lampe := DirectionalLight3D.new()   # lampe Godot provisoire, venue de la droite
	lampe.name = "LampeProvisoire"
	lampe.rotation_degrees = Vector3(-20, 60, 0)
	add_child(lampe)

	var boule := MeshInstance3D.new()
	boule.name = "Repere"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	boule.mesh = sphere
	add_child(boule)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0, 0, 5)
	camera.near = 0.05
	camera.far = 10000.0
	add_child(camera)
	camera.make_current()

	compteur = Compteur.new()
	compteur.name = "Compteur"
	add_child(compteur)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var m := e as InputEventMouseMotion
		_lacet -= m.relative.x * 0.004
		_tangage = clampf(_tangage - m.relative.y * 0.004, -1.55, 1.55)
		camera.rotation = Vector3(_tangage, _lacet, 0)
	elif e is InputEventMouseButton and e.is_pressed():
		var b := e as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_UP:
			vitesse = minf(vitesse * 1.25, 1.0e6)
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			vitesse = maxf(vitesse / 1.25, 0.01)


func _process(delta: float) -> void:
	# Touches physiques : la même position de touche sur un clavier français ou anglais.
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S): dir.z += 1
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1
	if Input.is_physical_key_pressed(KEY_SPACE): dir.y += 1
	if Input.is_physical_key_pressed(KEY_C): dir.y -= 1
	if dir != Vector3.ZERO:
		var v := vitesse * (5.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		camera.position += camera.global_transform.basis * dir.normalized() * v * delta
