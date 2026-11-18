extends RefCounted
## Cockpit fonctionnel : les pièces du modèle 3D (cockpit.glb) suivent les commandes du pilote.
##
##   - levier des gaz, manche (3 axes), pédales : suivent les ordres en continu ;
##   - interrupteurs (train, ailes, stabilisateur, couper les gaz) : montrent l'état du vaisseau ;
##   - boutons et poignée : s'enfoncent quand on appuie (touche, manette ou clic de souris) ;
##   - voyants : allumés ou éteints selon l'état.
## Le modèle décrit chaque pièce dans ses « extras » (propriétés ajoutées dans Blender) :
## action, type, angles, course. Repère : Blender (x, y, z) = Godot (x, z, -y).
## Ce script ne touche jamais à la physique : il ne fait que montrer.

const DUREE_APPUI := 0.18      # s : un bouton reste enfoncé un court instant
const VITESSE_INTERRUPTEUR := 8.0   # retour en douceur des interrupteurs (1/s)
const MARGE_CLIC := 0.008      # m ajoutés autour de chaque pièce pour viser plus facilement

var racine: Node3D
var levier_gaz: Node3D
var levier_angles := Vector2(-30.0, 30.0)   # angle à gaz 0, à gaz 1 (degrés)
var manche: Node3D
var manche_max := Vector3(15.0, 10.0, 15.0) # tangage (X), lacet (Y), roulis (Z), degrés
var pedales: Array = []          # [nœud, angle max (degrés), +1 = gauche / -1 = droite]
var interrupteurs := {}          # action -> {noeud, off, on, angle}
var boutons := {}                # action -> {noeud, repos, direction, course, appui (0..1)}
var voyants: Array = []          # [MeshInstance3D, matériau, genre, seuil, énergie allumée, couleur, allumé]
var cliquables: Array = []       # [action, MeshInstance3D de la pièce]


func _init(r: Node3D) -> void:
	racine = r
	for n in racine.find_children("*", "Node3D", true, false):
		var e = n.get_meta("extras", {})
		if not (e is Dictionary):
			continue
		var nom: String = n.name
		if e.get("commande", "") == "gaz":
			levier_gaz = n
			levier_angles = Vector2(float(e.get("angle_gaz_0_deg", -30.0)), float(e.get("angle_gaz_1_deg", 30.0)))
		elif e.get("commande", "") == "manche":
			manche = n
			manche_max = Vector3(float(e.get("tangage_max_deg", 15.0)), float(e.get("lacet_max_deg", 10.0)), float(e.get("roulis_max_deg", 15.0)))
		elif e.get("commande", "") == "lacet":
			var a := float(e.get("angle_max_deg", 12.0))
			pedales.append([n, a, 1.0 if nom.ends_with("gauche") else -1.0])
		elif e.get("type", "") == "interrupteur":
			var off := float(e.get("angle_off_deg", -25.0))
			interrupteurs[e["action"]] = {"noeud": n, "off": off, "on": float(e.get("angle_on_deg", 25.0)), "angle": off}
			_cliquable(e["action"], n)
		elif e.get("type", "") in ["bouton", "poignee"]:
			var d: Array = e.get("direction_blender", [0, 0, -1])
			boutons[e["action"]] = {"noeud": n, "repos": (n as Node3D).position,
				"direction": Vector3(float(d[0]), float(d[2]), -float(d[1])),
				"course": float(e.get("course_m", 0.004)), "appui": 0.0}
			_cliquable(e["action"], n)
		elif e.has("voyant") and n is MeshInstance3D:
			_ajouter_voyant(n as MeshInstance3D, String(e["voyant"]), float(e.get("seuil", 0.5)))


## La pièce visible est l'enfant « …_piece » du pivot (ou le pivot lui-même s'il a un maillage).
func _cliquable(action: String, pivot: Node3D) -> void:
	for m in pivot.find_children("*", "MeshInstance3D", true, false):
		cliquables.append([action, m])
	if pivot is MeshInstance3D:
		cliquables.append([action, pivot])


## Chaque voyant reçoit sa propre copie du matériau, pour s'allumer seul.
func _ajouter_voyant(m: MeshInstance3D, genre: String, seuil: float) -> void:
	var mat := m.get_active_material(0)
	if mat == null:
		return
	mat = mat.duplicate()
	m.set_surface_override_material(0, mat)
	var energie := 1.0
	var couleur := Color.WHITE
	if mat is BaseMaterial3D:
		energie = (mat as BaseMaterial3D).emission_energy_multiplier
		couleur = (mat as BaseMaterial3D).albedo_color
	voyants.append([m, mat, genre, seuil, energie, couleur, false])


## État affiché. etat = {gaz, tangage, lacet, roulis, train, ailes, stabilisateur} (ordres de -1 à 1,
## train / ailes = consigne : 1 = sorti / ouvertes).
func mettre_a_jour(etat: Dictionary, delta: float) -> void:
	var gaz := float(etat.get("gaz", 0.0))
	if levier_gaz != null:
		levier_gaz.rotation = Vector3(deg_to_rad(lerpf(levier_angles.x, levier_angles.y, gaz)), 0, 0)
	var t := float(etat.get("tangage", 0.0))
	var l := float(etat.get("lacet", 0.0))
	var r := float(etat.get("roulis", 0.0))
	if manche != null:
		# manche tiré vers soi = nez en haut ; penché à gauche = roulis à gauche ; tourné à gauche = lacet à gauche
		manche.rotation = Vector3(deg_to_rad(t * manche_max.x), deg_to_rad(l * manche_max.y), deg_to_rad(r * manche_max.z))
	for p in pedales:
		# lacet à gauche : on pousse la pédale gauche ; à droite : la pédale droite
		var enfonce := maxf(0.0, l * float(p[2]))
		(p[0] as Node3D).rotation = Vector3(deg_to_rad(float(p[1]) * enfonce), 0, 0)

	var allumes := {
		"train": float(etat.get("train", 0.0)) > 0.5,
		"ailes": float(etat.get("ailes", 1.0)) > 0.5,
		"stabilisateur": bool(etat.get("stabilisateur", false)),
		"couper_gaz": gaz <= 0.0,
	}
	var k := clampf(delta * VITESSE_INTERRUPTEUR, 0.0, 1.0)
	for action in interrupteurs:
		var i: Dictionary = interrupteurs[action]
		var on: bool = allumes.get(action, false)
		if action == "couper_gaz":
			on = float(i.get("appui", 0.0)) > 0.0   # interrupteur qui revient tout seul en place
		var cible: float = i["on"] if on else i["off"]
		i["angle"] = lerpf(float(i["angle"]), cible, k)
		(i["noeud"] as Node3D).rotation = Vector3(deg_to_rad(float(i["angle"])), 0, 0)
		if i.has("appui"):
			i["appui"] = maxf(0.0, float(i["appui"]) - delta / DUREE_APPUI)

	for action in boutons:
		var b: Dictionary = boutons[action]
		b["appui"] = maxf(0.0, float(b["appui"]) - delta / DUREE_APPUI)
		var enfonce := 1.0 if float(b["appui"]) > 0.0 else 0.0
		(b["noeud"] as Node3D).position = (b["repos"] as Vector3) + (b["direction"] as Vector3) * float(b["course"]) * enfonce

	for v in voyants:
		var on: bool
		if v[2] == "gaz":
			on = gaz >= float(v[3]) - 1e-6
		else:
			on = allumes.get(v[2], false)
		_allumer(v, on)


## Système de lumière (étape 8 du jeu) : les matières du modèle ont été remplacées par celles du
## système (ShaderMaterial) ; chaque voyant reprend la sienne, avec sa luminance d'origine (cd/m²).
func rebrancher_matieres() -> void:
	for v in voyants:
		var m := (v[0] as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		if m == null:
			continue
		v[1] = m
		var lum: float = m.get_shader_parameter("emission_luminance")
		var a = m.get_shader_parameter("albedo_lin")
		var c = m.get_shader_parameter("emission_couleur")
		if lum <= 0.0 or not (c is Vector3) or (c as Vector3).is_zero_approx():
			# voyant sans lumière propre dans le modèle : il émet sa couleur
			m.set_shader_parameter("emission_couleur", a if a is Vector3 else Vector3.ONE)
			lum = maxf(lum, 40.0)
		v[4] = lum
		v[5] = a if a is Vector3 else Vector3.ONE
		_allumer(v, v[6])


func _allumer(v: Array, on: bool) -> void:
	var mat = v[1]
	if mat is ShaderMaterial:
		# éteint : plus de lumière propre, verre coloré assombri
		(mat as ShaderMaterial).set_shader_parameter("emission_luminance", float(v[4]) if on else 0.0)
		(mat as ShaderMaterial).set_shader_parameter("albedo_lin", (v[5] as Vector3) * (1.0 if on else 0.1))
	if mat is BaseMaterial3D:
		# éteint : plus de lumière propre, et la couleur s'assombrit (verre coloré éteint)
		(mat as BaseMaterial3D).emission_energy_multiplier = float(v[4]) if on else 0.0
		(mat as BaseMaterial3D).albedo_color = (v[5] as Color) if on else (v[5] as Color).darkened(0.75)
	v[6] = on


## Vrai si le voyant de ce genre (et de ce seuil, pour les gaz) est allumé. Pour les tests.
func voyant_allume(genre: String, seuil := -1.0) -> bool:
	for v in voyants:
		if v[2] == genre and (seuil < 0.0 or absf(float(v[3]) - seuil) < 1e-6):
			return bool(v[6])
	return false


## Un bouton (ou l'interrupteur « couper les gaz ») a été actionné : il s'enfonce un instant.
func appuyer(action: String) -> void:
	if boutons.has(action):
		boutons[action]["appui"] = 1.0
	if interrupteurs.has(action) and action == "couper_gaz":
		interrupteurs[action]["appui"] = 1.0


## Quelle commande se trouve sous ce rayon (clic de souris) ? "" si aucune.
## On compare le rayon à la boîte de chaque pièce, sans moteur physique (plus léger).
func action_sous_rayon(origine: Vector3, direction: Vector3) -> String:
	var meilleure := ""
	var d_min := INF
	for c in cliquables:
		var m: MeshInstance3D = c[1]
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var inv := m.global_transform.affine_inverse()
		var o: Vector3 = inv * origine
		var d: Vector3 = inv.basis * direction
		var boite := m.mesh.get_aabb().grow(MARGE_CLIC)
		var p = boite.intersects_ray(o, d)
		if p != null:
			var dist := (m.global_transform * (p as Vector3)).distance_to(origine)
			if dist < d_min:
				d_min = dist
				meilleure = c[0]
	return meilleure
