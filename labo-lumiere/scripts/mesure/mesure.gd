extends Node3D
## Scène de mesure de vitesse (étape 2 du programme lumière).
## Elle fait tourner la boucle d'une image du système avec des rayons FACTICES (33 000 par défaut),
## en faisant pour chaque rayon le même genre de travail que le vrai système :
##   1 choisir, 2 éclairer (1 rayon sur 8 par image), 3 envoyer (une texture), 4 dessiner (MultiMesh).
## Elle enchaîne plusieurs essais de quelques secondes, puis affiche un tableau et l'enregistre dans
## mesures/resultats-pc.md. Avec l'option « -- --auto », Godot se ferme tout seul à la fin.
##
## Le but : savoir si GDScript est assez rapide sur le PC de Gwenaël, ou s'il faut passer une partie en C++.

const ChronoBoucle = preload("res://scripts/lumiere/chrono_boucle.gd")
const MorceauType = preload("res://scripts/lumiere/morceau_type.gd")
const ShaderRayons = preload("res://scripts/lumiere/rayons.gdshader")
const BlocFactice = preload("res://scripts/mesure/bloc_factice.gd")
const Compteur = preload("res://scripts/outils/compteur.gd")

const RAYON_PLANETE := 1000.0
const DISTANCE_OEIL := 1300.0          # 1,3 rayon : la planète remplit presque l'écran
const RAYONS_PAR_LIGNE := 256           # dans la texture des rayons (2 texels par rayon)
const NIVEAU_MORCEAUX := 4              # icosaèdre coupé 4 fois = 5 120 triangles, on garde ceux face à l'œil
const ATTENTE_S := 0.8                  # temps de chauffe avant de mesurer
const DUREE_S := 3.0                    # durée de mesure de chaque essai
const FICHIER_RESULTATS := "res://mesures/resultats-pc.md"
const BUDGET_IMAGE_MS := 16.7

## Les essais, dans l'ordre. parmi = on refait 1 rayon sur « parmi » à chaque image.
var essais: Array[Dictionary] = [
	{"nom": "Écran vide (repère)", "n": 33000, "calcul": false, "dessin": false, "fils": false, "parmi": 8},
	{"nom": "Dessin seul", "n": 33000, "calcul": false, "dessin": true, "fils": false, "parmi": 8},
	{"nom": "Tout, 1 seul fil de calcul", "n": 33000, "calcul": true, "dessin": true, "fils": false, "parmi": 8},
	{"nom": "Tout, plusieurs fils de calcul", "n": 33000, "calcul": true, "dessin": true, "fils": true, "parmi": 8},
	{"nom": "Changement brusque (tout réécl.)", "n": 33000, "calcul": true, "dessin": true, "fils": true, "parmi": 1},
	{"nom": "Deux fois plus de rayons (66 000)", "n": 66000, "calcul": true, "dessin": true, "fils": true, "parmi": 8},
]

var camera: Camera3D
var compteur
var chrono
var multimesh := MultiMesh.new()
var dessin := MultiMeshInstance3D.new()
var materiau := ShaderMaterial.new()
var image: Image
var texture: ImageTexture
var blocs: Array = []
var nb_rayons := 0
var tour := 0
var soleil := Vector3(0.6, 0.3, 0.74).normalized()
var temps := 0.0

# Suivi des essais
var essai_en_cours := -1
var temps_essai := 0.0
var images_ms := PackedFloat64Array()
var sommes_ms := PackedFloat64Array([0, 0, 0, 0])
var gpu_ms := 0.0
var nb_images := 0
var dernier_us := 0
var resultats: Array[Dictionary] = []
var fini := false
var ecran: Label
var _oeil_du_tour := Vector3.ZERO
var _focale_px := 0.0
var _parmi := 8


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # sinon tout est bloqué à 60
	Engine.max_fps = 0

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var monde := WorldEnvironment.new()
	monde.environment = env
	add_child(monde)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 1.0
	camera.far = 10000.0
	add_child(camera)
	camera.make_current()
	_placer_oeil(0.0)

	materiau.shader = ShaderRayons
	materiau.set_shader_parameter("rayon_planete", RAYON_PLANETE)
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = MorceauType.creer()
	dessin.name = "Planete"
	dessin.multimesh = multimesh
	dessin.material_override = materiau
	# La boîte englobante est calculée sur le morceau plat : on la remplace par toute la planète.
	dessin.custom_aabb = AABB(Vector3.ONE * -RAYON_PLANETE * 1.1, Vector3.ONE * RAYON_PLANETE * 2.2)
	add_child(dessin)

	compteur = Compteur.new()
	compteur.name = "Compteur"
	compteur.mesurer_dessin = false
	add_child(compteur)
	chrono = compteur.chrono

	ecran = Label.new()
	ecran.position = Vector2(20, 110)
	ecran.add_theme_font_size_override("font_size", 16)
	ecran.add_theme_color_override("font_outline_color", Color.BLACK)
	ecran.add_theme_constant_override("outline_size", 6)
	var calque := CanvasLayer.new()
	calque.layer = 99
	calque.add_child(ecran)
	add_child(calque)

	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_commencer_essai(0)


## Construit les rayons factices (n) : les triangles de la planète face à l'œil, coupés en 64.
func construire(n: int) -> void:
	var nb_morceaux := ceili(float(n) / MorceauType.NB_TRIANGLES)
	nb_rayons = nb_morceaux * MorceauType.NB_TRIANGLES
	var triangles := _icosaedre(NIVEAU_MORCEAUX)
	# Les morceaux les plus proches du point de la planète sous l'œil d'abord.
	var vers_oeil := camera.position.normalized()
	triangles.sort_custom(func(a, b): return (a[0] + a[1] + a[2]).normalized().dot(vers_oeil) > (b[0] + b[1] + b[2]).normalized().dot(vers_oeil))
	multimesh.instance_count = 0
	multimesh.instance_count = nb_morceaux
	var centres := PackedFloat64Array()
	centres.resize(nb_rayons * 3)
	var tailles := PackedFloat32Array()
	tailles.resize(nb_rayons)
	var adresses := PackedInt64Array()
	adresses.resize(nb_rayons)
	var maillage: ArrayMesh = multimesh.mesh
	var sommets: PackedVector3Array = maillage.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for m in nb_morceaux:
		var t: Array = triangles[m % triangles.size()]
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var normale := (a + b + c).normalized()
		multimesh.set_instance_transform(m, Transform3D(Basis(b - a, c - a, normale), a))
		var cote := a.distance_to(b) / MorceauType.COUPES
		for k in MorceauType.NB_TRIANGLES:
			var uv: Vector3 = (sommets[3 * k] + sommets[3 * k + 1] + sommets[3 * k + 2]) / 3.0
			var p := (a + (b - a) * uv.x + (c - a) * uv.y).normalized() * RAYON_PLANETE
			var r := m * MorceauType.NB_TRIANGLES + k
			centres[3 * r] = p.x
			centres[3 * r + 1] = p.y
			centres[3 * r + 2] = p.z
			tailles[r] = cote * 0.58
			adresses[r] = ((m + 1) << 12) | k
	# Découpe en blocs : un par fil de calcul possible, et au moins 4.
	var nb_blocs := maxi(4, OS.get_processor_count())
	blocs.clear()
	var par_bloc := ceili(float(nb_rayons) / nb_blocs)
	var debut := 0
	while debut < nb_rayons:
		var fin := mini(debut + par_bloc, nb_rayons)
		var bloc = BlocFactice.new()
		bloc.preparer(debut, centres.slice(debut * 3, fin * 3), tailles.slice(debut, fin), adresses.slice(debut, fin))
		blocs.append(bloc)
		debut = fin
	# Premier éclairage complet, pour que la planète ait déjà ses couleurs.
	for bloc in blocs:
		bloc.eclairer(0, 1, 0.0)
	var lignes := ceili(float(nb_rayons) / RAYONS_PAR_LIGNE)
	image = Image.create_from_data(RAYONS_PAR_LIGNE * 2, lignes, false, Image.FORMAT_RGBA8, _octets_de_tous())
	texture = ImageTexture.create_from_image(image)
	materiau.set_shader_parameter("rayons", texture)
	chrono.nb_rayons = nb_rayons


func _octets_de_tous() -> PackedByteArray:
	var tout := PackedByteArray()
	for bloc in blocs:
		tout.append_array(bloc.octets)
	var lignes := ceili(float(nb_rayons) / RAYONS_PAR_LIGNE)
	tout.resize(lignes * RAYONS_PAR_LIGNE * BlocFactice.OCTETS_PAR_RAYON)
	return tout


## Triangles d'un icosaèdre coupé `niveau` fois en 4, remis sur la sphère.
func _icosaedre(niveau: int) -> Array:
	var p := (1.0 + sqrt(5.0)) / 2.0
	var s: Array[Vector3] = [
		Vector3(-1, p, 0), Vector3(1, p, 0), Vector3(-1, -p, 0), Vector3(1, -p, 0),
		Vector3(0, -1, p), Vector3(0, 1, p), Vector3(0, -1, -p), Vector3(0, 1, -p),
		Vector3(p, 0, -1), Vector3(p, 0, 1), Vector3(-p, 0, -1), Vector3(-p, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var tris: Array = []
	for f in faces:
		tris.append([s[f[0]].normalized() * RAYON_PLANETE, s[f[1]].normalized() * RAYON_PLANETE, s[f[2]].normalized() * RAYON_PLANETE])
	for _n in niveau:
		var suivants: Array = []
		for t in tris:
			var ab: Vector3 = ((t[0] + t[1]) * 0.5).normalized() * RAYON_PLANETE
			var bc: Vector3 = ((t[1] + t[2]) * 0.5).normalized() * RAYON_PLANETE
			var ca: Vector3 = ((t[2] + t[0]) * 0.5).normalized() * RAYON_PLANETE
			suivants.append([t[0], ab, ca])
			suivants.append([ab, t[1], bc])
			suivants.append([ca, bc, t[2]])
			suivants.append([ab, bc, ca])
		tris = suivants
	return tris


## L'œil bouge un peu (la valeur des calculs change à chaque image, comme en vol).
func _placer_oeil(t: float) -> void:
	camera.position = Vector3(sin(t * 0.3) * 20.0, cos(t * 0.21) * 15.0, DISTANCE_OEIL)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _commencer_essai(i: int) -> void:
	essai_en_cours = i
	var e: Dictionary = essais[i]
	if e["n"] + 63 < nb_rayons or e["n"] > nb_rayons:
		construire(e["n"])
	dessin.visible = e["dessin"]
	temps_essai = 0.0
	images_ms = PackedFloat64Array()
	sommes_ms = PackedFloat64Array([0, 0, 0, 0])
	gpu_ms = 0.0
	nb_images = 0
	dernier_us = 0


func _process(delta: float) -> void:
	var maintenant := Time.get_ticks_usec()
	var image_ms := float(maintenant - dernier_us) / 1000.0 if dernier_us > 0 else 0.0
	dernier_us = maintenant
	if fini:
		return
	temps += delta
	temps_essai += delta
	_placer_oeil(temps)
	soleil = Vector3(cos(temps * 0.2) * 0.6, 0.3, 0.74).normalized()
	materiau.set_shader_parameter("soleil", soleil)

	var e: Dictionary = essais[essai_en_cours]
	var ms := PackedFloat64Array([0, 0, 0, 0])
	if e["calcul"]:
		ms = _une_image(e["fils"], e["parmi"])
	var dessin_ms := maxf(image_ms - ms[0] - ms[1] - ms[2], 0.0)
	chrono.enregistrer(ChronoBoucle.DESSINER, dessin_ms)

	if temps_essai > ATTENTE_S and image_ms > 0.0:
		images_ms.append(image_ms)
		for k in 3:
			sommes_ms[k] += ms[k]
		sommes_ms[3] += dessin_ms
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		nb_images += 1
	ecran.text = "Mesure de vitesse : essai %d / %d\n%s\n(ne touche à rien, ça dure environ %d secondes en tout)" % [
		essai_en_cours + 1, essais.size(), e["nom"], int(essais.size() * (ATTENTE_S + DUREE_S)) + 5]
	if temps_essai > ATTENTE_S + DUREE_S:
		_finir_essai()


## Une image de la boucle : renvoie les ms de choisir, éclairer, envoyer.
func _une_image(fils: bool, parmi: int) -> PackedFloat64Array:
	var ms := PackedFloat64Array([0, 0, 0, 0])
	_oeil_du_tour = camera.global_position
	_focale_px = (get_viewport().get_visible_rect().size.y * 0.5) / tan(deg_to_rad(camera.fov * 0.5))
	_parmi = parmi
	tour += 1

	chrono.debut(ChronoBoucle.CHOISIR)
	if fils:
		var g := WorkerThreadPool.add_group_task(_choisir_bloc, blocs.size(), -1, true, "choisir")
		WorkerThreadPool.wait_for_group_task_completion(g)
	else:
		for i in blocs.size():
			_choisir_bloc(i)
	ms[0] = chrono.fin(ChronoBoucle.CHOISIR)

	chrono.debut(ChronoBoucle.ECLAIRER)
	if fils:
		var g := WorkerThreadPool.add_group_task(_eclairer_bloc, blocs.size(), -1, true, "eclairer")
		WorkerThreadPool.wait_for_group_task_completion(g)
	else:
		for i in blocs.size():
			_eclairer_bloc(i)
	ms[1] = chrono.fin(ChronoBoucle.ECLAIRER)

	chrono.debut(ChronoBoucle.ENVOYER)
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, _octets_de_tous())
	texture.update(image)
	ms[2] = chrono.fin(ChronoBoucle.ENVOYER)
	return ms


# Ces deux fonctions tournent dans les fils de calcul : chacune ne touche qu'à SON bloc.
func _choisir_bloc(i: int) -> void:
	blocs[i].choisir(_oeil_du_tour, _focale_px)


func _eclairer_bloc(i: int) -> void:
	blocs[i].eclairer(tour, _parmi, temps)


func _finir_essai() -> void:
	var e: Dictionary = essais[essai_en_cours]
	var tri := images_ms.duplicate()
	tri.sort()
	var n := maxi(nb_images, 1)
	var moyenne := 0.0
	for v in images_ms:
		moyenne += v
	moyenne /= n
	resultats.append({
		"nom": e["nom"], "rayons": nb_rayons if e["dessin"] or e["calcul"] else 0,
		"images_s": 1000.0 / maxf(moyenne, 0.001), "image_ms": moyenne,
		"pire_ms": tri[int(tri.size() * 0.95)] if tri.size() > 0 else 0.0,
		"choisir": sommes_ms[0] / n, "eclairer": sommes_ms[1] / n, "envoyer": sommes_ms[2] / n,
		"dessiner": sommes_ms[3] / n, "gpu": gpu_ms / n, "calcul": e["calcul"],
	})
	if essai_en_cours + 1 < essais.size():
		_commencer_essai(essai_en_cours + 1)
	else:
		_terminer()


func _terminer() -> void:
	fini = true
	var rapport := rapport_texte()
	print(rapport)
	var dossier := DirAccess.open("res://")
	if dossier and not dossier.dir_exists("mesures"):
		dossier.make_dir("mesures")
	var f := FileAccess.open(FICHIER_RESULTATS, FileAccess.WRITE)
	if f:
		f.store_string(rapport)
		f.close()
	ecran.text = rapport.replace("|", " ").replace("**", "") + "\n\nRésultats enregistrés dans labo-lumiere/mesures/resultats-pc.md. Tu peux fermer la fenêtre."
	dessin.visible = true
	if OS.get_cmdline_user_args().has("--auto"):
		get_tree().quit()


## Le verdict : GDScript suffit-il ? (règle du programme : budget choisir 2 + éclairer 3 + envoyer 1 ms,
## et l'image complète sous 16,7 ms, sinon on propose le C++ pour les deux temps les plus lents).
func verdict() -> String:
	var normal: Dictionary = {}
	var brusque: Dictionary = {}
	for r in resultats:
		if r["nom"].begins_with("Tout, plusieurs"):
			normal = r
		elif r["nom"].begins_with("Changement"):
			brusque = r
	if normal.is_empty():
		return "pas de verdict (essai manquant)"
	var calcul: float = normal["choisir"] + normal["eclairer"] + normal["envoyer"]
	var lents := [["choisir", normal["choisir"]], ["éclairer", normal["eclairer"]], ["envoyer", normal["envoyer"]]]
	lents.sort_custom(func(a, b): return a[1] > b[1])
	var ok_calcul := calcul <= 6.0
	var ok_image: bool = normal["image_ms"] <= BUDGET_IMAGE_MS
	var t := ""
	if ok_calcul and ok_image:
		t = "GDScript SUFFIT : calcul %.1f ms sur 6, image %.1f ms sur 16,7." % [calcul, normal["image_ms"]]
	elif ok_calcul:
		t = "GDScript suffit pour le calcul (%.1f ms sur 6), mais l'image prend %.1f ms : c'est le DESSIN qui freine (carte graphique), le C++ n'y changerait rien." % [calcul, normal["image_ms"]]
	elif calcul <= 9.0:
		t = "LIMITE : calcul %.1f ms sur 6. GDScript peut suffire en allégeant ; sinon C++ pour « %s » et « %s »." % [calcul, lents[0][0], lents[1][0]]
	else:
		t = "C++ CONSEILLÉ : calcul %.1f ms sur 6. Les deux temps les plus lents : « %s » et « %s »." % [calcul, lents[0][0], lents[1][0]]
	if not brusque.is_empty():
		t += " Changement brusque (tout refait d'un coup) : %.1f ms pour éclairer." % brusque["eclairer"]
	return t


func rapport_texte() -> String:
	var l := PackedStringArray()
	l.append("# Mesure de vitesse du système de lumière (étape 2)")
	l.append("")
	l.append("Date : %s · Godot %s · %s · %s, %d fils · rendu %s · fenêtre %s" % [
		Time.get_datetime_string_from_system(), Engine.get_version_info()["string"],
		RenderingServer.get_video_adapter_name(), OS.get_processor_name(), OS.get_processor_count(),
		ProjectSettings.get_setting("rendering/renderer/rendering_method"), str(get_viewport().get_visible_rect().size)])
	l.append("")
	l.append("| Essai | Rayons | Images/s | Image (ms) | Pire 5 % (ms) | Choisir | Éclairer | Envoyer | Dessiner | Carte graph. |")
	l.append("|---|---|---|---|---|---|---|---|---|---|")
	for r in resultats:
		l.append("| %s | %d | %.0f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f |" % [
			r["nom"], r["rayons"], r["images_s"], r["image_ms"], r["pire_ms"],
			r["choisir"], r["eclairer"], r["envoyer"], r["dessiner"], r["gpu"]])
	l.append("")
	l.append("Budget visé : choisir 2 ms, éclairer 3 ms, envoyer 1 ms, dessiner 8 ms, image 16,7 ms (60 images/s).")
	l.append("« Dessiner » = image complète moins les 3 temps de calcul. « Carte graph. » = temps donné par Godot (0 s'il ne sait pas le mesurer).")
	l.append("")
	l.append("**Verdict : " + verdict() + "**")
	return "\n".join(l) + "\n"


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.is_pressed() and (e as InputEventKey).keycode == KEY_ESCAPE:
		get_tree().quit()
