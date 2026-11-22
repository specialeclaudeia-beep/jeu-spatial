extends RefCounted
## Le DESSIN du vaisseau (modèle 3D exporté de Blender) mis dans la pose de sa physique : ailes, train et
## ses trappes, moteurs de levage, tuyère orientable, amortisseurs et roues. Le jeu (scripts/jeu.gd) et
## l'atelier (scripts/atelier/atelier.gd) se servent du même code : le vaisseau posé dans le hangar a
## exactement la pose qu'il aura posé devant le hangar.
##
## Le modèle ne fait que suivre la physique (scripts/physique/vaisseau_physique.gd) : il ne la change jamais.

const PART_TRAPPES := 0.3     # part du mouvement du train pendant laquelle les trappes s'ouvrent

var exterieur: Node3D
var charnieres := {}                 # nom de l'aile -> nœud Charniere_* du modèle
var trains: Array = []               # [nœud Train_*, "rotation", "piston" ou "oblique", angle rentré (°) ou course sorti (m), position de repos, axe, pied (fusée + roue), axe de la jambe]
var trappes: Array = []              # [nœud Charniere_Trappe_*, angle ouvert (degrés), true = trappe des moteurs de levage]
var tuyere: Node3D                   # pivot de la tuyère orientable du moteur central
var moteurs_levage: Array = []       # [nœud Moteur_levage_*, position de repos, course (m)]
var amortisseurs: Array = []         # [nœud Amortisseur_*, position de repos, n° de roue de la physique]
var ressorts: Array = []             # [nœud Ressort_*, échelle de repos, n° de roue, longueur au repos (m)]
var roue_avant: Node3D = null
var roues_arriere: Array = []        # [nœud Roue_arriere_*, n° de roue de la physique] (modèle v27)
var amortisseur_avant: Node3D = null   # tourne avec le braquage de la roue avant
var rotation_amortisseur_avant := Basis.IDENTITY
var rayon_roue := 0.18


## p_exterieur : le modèle extérieur (vaisseau_exterieur.glb) ; v : la physique du vaisseau (noms des ailes).
func _init(p_exterieur: Node3D, v) -> void:
	exterieur = p_exterieur
	for nom in v.ailes_def:
		var n := exterieur.find_child("Charniere_" + nom, true, false) as Node3D
		if n != null:
			charnieres[nom] = n
	for nom in ["Train_avant", "Train_arriere_gauche", "Train_arriere_droit"]:
		var n := exterieur.find_child(nom, true, false) as Node3D
		if n != null:
			var extras = n.get_meta("extras", {})
			if not (extras is Dictionary):
				extras = {}
			if extras.get("type", "") == "piston":
				# jambe qui coulisse (vérin) : translation selon Z de Blender = Y de Godot
				trains.append([n, "piston", float(extras.get("course_sorti_m", -0.56)), n.position])
			elif extras.get("type", "") == "pivot_oblique":
				# modèle v26 : jambe arrière qui pivote autour d'un axe en biais (axe_godot). Sortie, elle
				# part vers l'extérieur sous le réacteur d'aile ; rentrée, elle se couche vers l'avant dans
				# le ventre. Le pied (v27 : la fusée et sa roue) reste parallèle à la coque (biellette).
				var a: Array = extras.get("axe_godot", [1.0, 0.0, 0.0])
				var cote := String(nom).trim_prefix("Train_arriere_")
				trains.append([n, "oblique", float(extras.get("angle_rentre_deg", 90.0)), n.position,
					Vector3(float(a[0]), float(a[1]), float(a[2])).normalized(),
					n.find_child("Pied_arriere_" + cote, true, false), n.find_child("Jambe_axe_arriere_" + cote, true, false)])
			else:
				# jambe qui pivote autour de X : angle rentré lu dans le modèle
				trains.append([n, "rotation", float(extras.get("angle_rentre_deg", -90.0)), n.position])
	# trappes du train : elles tournent autour de l'axe avant-arrière (Y de Blender = -Z de Godot)
	for n in exterieur.find_children("Charniere_Trappe_*", "Node3D", true, false):
		var extras = n.get_meta("extras", {})
		var ouvert := 0.0
		if extras is Dictionary and extras.has("angle_ouvert_deg"):
			ouvert = -float(extras["angle_ouvert_deg"])
		trappes.append([n, ouvert, String(n.name).contains("levage")])
	tuyere = exterieur.find_child("Pivot_tuyere_centrale", true, false) as Node3D
	for nom in ["Moteur_levage_gauche", "Moteur_levage_droit"]:
		var n := exterieur.find_child(nom, true, false) as Node3D
		if n != null:
			var extras = n.get_meta("extras", {})
			var course := -0.32
			if extras is Dictionary:
				course = float(extras.get("course_sorti_m", course))
			moteurs_levage.append([n, n.position, course])
	_trouver_amortisseurs()


## Modèle v20 : amortisseurs, ressorts, roue avant ; v27 : roues arrière.
func _trouver_amortisseurs() -> void:
	var roue_de := {"Amortisseur_avant": 0, "Amortisseur_arriere_gauche": 1, "Amortisseur_arriere_droit": 2,
		"Ressort_arriere_gauche": 1, "Ressort_arriere_droit": 2}
	for nom in roue_de:
		var n := exterieur.find_child(nom, true, false) as Node3D
		if n == null:
			continue
		var e = n.get_meta("extras", {})
		if nom.begins_with("Ressort"):
			var l := 0.18
			if e is Dictionary:
				l = float(e.get("longueur_repos_m", l))
			ressorts.append([n, n.scale, roue_de[nom], l])
		else:
			amortisseurs.append([n, n.position, roue_de[nom]])
			if nom == "Amortisseur_avant":
				amortisseur_avant = n
				rotation_amortisseur_avant = n.basis
	roue_avant = exterieur.find_child("Roue_avant", true, false) as Node3D
	for cote in [["gauche", 1], ["droit", 2]]:
		var r := exterieur.find_child("Roue_arriere_" + cote[0], true, false) as Node3D
		if r != null:
			roues_arriere.append([r, cote[1]])
	if roue_avant != null:
		var e = roue_avant.get_meta("extras", {})
		if e is Dictionary:
			rayon_roue = float(e.get("rayon_m", rayon_roue))


## Ailes, train, moteurs de levage et tuyère : le modèle suit exactement l'état de la physique (mêmes
## angles que le calcul des poussées).
func poser(v) -> void:
	for nom in charnieres:
		(charnieres[nom] as Node3D).rotation = Vector3(0, 0, deg_to_rad(v.angle_aile(nom)))
	# sortie du train : d'abord les trappes s'ouvrent (premiers 30 %), puis les jambes descendent ;
	# en rentrant, c'est l'inverse (les jambes remontent, puis les trappes se ferment)
	var porte := clampf(v.train / PART_TRAPPES, 0.0, 1.0)
	var jambe := clampf((v.train - PART_TRAPPES) / (1.0 - PART_TRAPPES), 0.0, 1.0)
	for t in trains:
		if t[1] == "piston":
			(t[0] as Node3D).position = (t[3] as Vector3) + Vector3(0, float(t[2]) * jambe, 0)
		elif t[1] == "oblique":
			var q := Quaternion(t[4] as Vector3, deg_to_rad(float(t[2]) * (1.0 - jambe)))
			(t[0] as Node3D).quaternion = q
			if t[5] != null and t[6] != null:
				(t[5] as Node3D).quaternion = (q * (t[6] as Node3D).quaternion).inverse()
		else:
			(t[0] as Node3D).rotation = Vector3(deg_to_rad(lerpf(float(t[2]), 0.0, jambe)), 0, 0)
	# moteurs de levage : d'abord leurs trappes s'ouvrent, puis le vérin les descend (l'inverse en rentrant)
	var s_levage: float = v.sortie_levage()
	var porte_levage := clampf(s_levage / PART_TRAPPES, 0.0, 1.0)
	var verin := clampf((s_levage - PART_TRAPPES) / (1.0 - PART_TRAPPES), 0.0, 1.0)
	for t in trappes:
		var ouverture: float = porte_levage if t[2] else porte
		(t[0] as Node3D).rotation = Vector3(0, 0, deg_to_rad(float(t[1]) * ouverture))
	for m in moteurs_levage:
		(m[0] as Node3D).position = (m[1] as Vector3) + Vector3(0, float(m[2]) * verin, 0)
	if tuyere != null:
		# tuyère en 3 anneaux (v18) : chacun tourne d'un tiers de l'angle
		var n_tuyere := tuyere
		var tiers := deg_to_rad(v.angle_tuyere()) / 3.0
		for nom in ["Pivot_tuyere_centrale_2", "Pivot_tuyere_centrale_3", ""]:
			n_tuyere.rotation = Vector3(tiers, 0, 0)
			if nom == "":
				break
			n_tuyere = n_tuyere.find_child(nom, true, false) as Node3D
			if n_tuyere == null:
				break


## Amortisseurs et ressorts : ils s'écrasent comme dans la physique ; les roues tournent en roulant.
func amortir(v, delta: float) -> void:
	var c: PackedFloat64Array = v.compression_roues
	for a in amortisseurs:
		if a[2] < c.size():
			(a[0] as Node3D).position = (a[1] as Vector3) + Vector3(0, c[a[2]], 0)
	for r in ressorts:
		if r[2] >= c.size():
			continue
		var sc: Vector3 = r[1]
		sc.y *= maxf(0.05, (float(r[3]) - c[r[2]]) / float(r[3]))
		(r[0] as Node3D).scale = sc
	if amortisseur_avant != null:
		# la roue avant (et sa fourche) tourne avec le braquage, autour de l'axe de l'amortisseur
		amortisseur_avant.basis = rotation_amortisseur_avant * Basis(Vector3.UP, v.braquage)
	if delta <= 0.0 or c.is_empty():
		return
	if roue_avant != null and v.au_sol and c[0] > 0.0:
		var dir_roue := Vector3(-sin(v.braquage), 0.0, -cos(v.braquage))
		var avance: float = (Basis(v.orientation).inverse() * v.vitesse_par_rapport_au_sol()).dot(dir_roue)
		roue_avant.rotate_x(-avance / rayon_roue * delta)
	# roues arrière (v27) : elles roulent dans l'axe du vaisseau, et ne tournent pas frein de parc serré
	if v.au_sol and not v.frein_parc:
		var avance_ar: float = -(Basis(v.orientation).inverse() * v.vitesse_par_rapport_au_sol()).z
		for r in roues_arriere:
			if c[r[1]] > 0.0:
				(r[0] as Node3D).rotate_x(-avance_ar / rayon_roue * delta)
