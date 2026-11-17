extends Control
## Tests automatiques du labo-lumière (scène tests.tscn, F6 dans Godot).
## Sans écran (dans le cloud), le programme s'arrête tout seul : code 0 si tout passe, 1 sinon.

const ChronoBoucle = preload("res://scripts/lumiere/chrono_boucle.gd")
const Compteur = preload("res://scripts/outils/compteur.gd")
const MorceauType = preload("res://scripts/lumiere/morceau_type.gd")
const BlocFactice = preload("res://scripts/mesure/bloc_factice.gd")

var texte: RichTextLabel
var reussis := 0
var total := 0


func _ready() -> void:
	var fond := ColorRect.new()
	fond.color = Color(0.03, 0.04, 0.07)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fond)
	texte = RichTextLabel.new()
	texte.bbcode_enabled = true
	texte.set_anchors_preset(Control.PRESET_FULL_RECT)
	texte.offset_left = 30
	texte.offset_top = 20
	texte.offset_right = -30
	texte.offset_bottom = -20
	texte.add_theme_font_size_override("normal_font_size", 17)
	add_child(texte)
	texte.text = "[b]Tests du labo-lumière[/b]\n\n"
	await get_tree().process_frame
	await _lancer()
	var bilan := "%d / %d tests réussis" % [reussis, total]
	texte.append_text("[b]%s[/b]\n" % bilan)
	print("RÉSULTAT : " + bilan)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if reussis == total else 1)


func _resultat(ok: bool, titre: String, detail: String) -> void:
	total += 1
	if ok:
		reussis += 1
	var etiquette := "[color=#5fe08a][OK][/color]" if ok else "[color=#ff6b6b][ÉCHEC][/color]"
	texte.append_text("%s [b]%s[/b]\n      %s\n\n" % [etiquette, titre, detail])
	print("%s %s : %s" % ["[OK]" if ok else "[ÉCHEC]", titre, detail])


func _lancer() -> void:
	_test_reglages()
	_test_chrono_lissage()
	_test_chrono_mesure()
	_test_adresse_64_bits()
	_test_compteur_f3()
	await _test_scene_labo()
	_test_systeme_independant()
	_test_morceau_type()
	_test_bloc_factice()
	await _test_scene_mesure()


func _test_reglages() -> void:
	var rendu: String = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	var l: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	var h: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	_resultat(rendu == "gl_compatibility" and l == 1280 and h == 720,
		"Réglages du projet", "rendu %s, fenêtre %d×%d (attendu : gl_compatibility, 1280×720)" % [rendu, l, h])


func _test_chrono_lissage() -> void:
	var c = ChronoBoucle.new()
	c.enregistrer(ChronoBoucle.CHOISIR, 2.0)       # 1re mesure : prise telle quelle
	var premier: float = c.moyennes_ms[0]
	for i in 200:
		c.enregistrer(ChronoBoucle.CHOISIR, 4.0)   # puis la moyenne glisse vers 4
	var ok := is_equal_approx(premier, 2.0) and absf(c.moyennes_ms[0] - 4.0) < 0.001
	c.enregistrer(ChronoBoucle.ECLAIRER, 1.0)
	c.enregistrer(ChronoBoucle.ENVOYER, 0.5)
	c.enregistrer(ChronoBoucle.DESSINER, -3.0)     # une durée négative est ramenée à 0
	ok = ok and absf(c.total_ms() - 5.5) < 0.001 and c.moyennes_ms[3] == 0.0
	ok = ok and c.depasse(ChronoBoucle.CHOISIR) and not c.depasse(ChronoBoucle.ECLAIRER)
	_resultat(ok, "Chronomètre : moyenne lissée et total",
		"1re mesure %.2f, après 200 mesures %.3f (attendu 4), total %.2f ms (attendu 5,5)" % [premier, c.moyennes_ms[0], c.total_ms()])


func _test_chrono_mesure() -> void:
	var c = ChronoBoucle.new()
	c.debut(ChronoBoucle.ECLAIRER)
	var debut := Time.get_ticks_usec()
	while Time.get_ticks_usec() - debut < 3000:   # on attend 3 ms en calculant
		pass
	var ms: float = c.fin(ChronoBoucle.ECLAIRER)
	_resultat(ms >= 2.9 and ms < 50.0, "Chronomètre : mesure d'une vraie durée",
		"%.2f ms mesurées pour une attente de 3 ms" % ms)


func _test_adresse_64_bits() -> void:
	# Une adresse de triangle = 5 bits de face + 2 bits par niveau jusqu'au niveau 29 = 63 bits.
	var adresse := 19   # face 19 (la dernière des 20 faces)
	for niveau in 29:
		adresse = (adresse << 2) | 3
	var face := adresse >> 58
	var dernier := adresse & 3
	_resultat(face == 19 and dernier == 3 and adresse > 0, "Les adresses de 64 bits tiennent dans un int",
		"adresse niveau 29 = %d, face relue %d (attendu 19)" % [adresse, face])


func _test_compteur_f3() -> void:
	var cpt = Compteur.new()
	add_child(cpt)
	var visible_au_depart: bool = cpt.visible
	var f3 := InputEventKey.new()
	f3.keycode = KEY_F3
	f3.pressed = true
	cpt._unhandled_input(f3)
	var cache: bool = not cpt.visible
	cpt._unhandled_input(f3)
	var revenu: bool = cpt.visible
	cpt.chrono.nb_rayons = 33000
	var t: String = cpt.texte()
	var contenu := t.contains("Images/s") and t.contains("choisir") and t.contains("éclairer") \
		and t.contains("envoyer") and t.contains("dessiner") and t.contains("Rayons : 33000")
	cpt.queue_free()
	_resultat(visible_au_depart and cache and revenu and contenu, "Compteur : F3 cache et montre, tout est affiché",
		"visible au départ %s, caché après F3 %s, revenu après F3 %s, texte complet %s" % [visible_au_depart, cache, revenu, contenu])


func _test_scene_labo() -> void:
	var paquet: PackedScene = load("res://scenes/labo.tscn")
	var labo: Node = paquet.instantiate() if paquet else null
	if labo == null:
		_resultat(false, "Scène du labo", "labo.tscn ne se charge pas")
		return
	add_child(labo)
	await get_tree().process_frame
	var cam: Camera3D = labo.get_node_or_null("Camera")
	var cpt: Node = labo.get_node_or_null("Compteur")
	var ok: bool = cam != null and cam.current and cpt != null and cpt.visible
	labo.queue_free()
	_resultat(ok, "Scène du labo : caméra et compteur présents",
		"caméra %s, compteur %s" % ["active" if cam and cam.current else "absente", "visible" if cpt and cpt.visible else "absent"])


func _test_systeme_independant() -> void:
	# Le dossier scripts/lumiere sera copié tel quel dans le jeu (étape 8) :
	# il ne doit rien charger en dehors de lui-même.
	var fautifs := PackedStringArray()
	var dossier := "res://scripts/lumiere/"
	for f in DirAccess.get_files_at(dossier):
		if not (f.ends_with(".gd") or f.ends_with(".gdshader")):
			continue
		var code := FileAccess.get_file_as_string(dossier + f)
		var pos := code.find("res://")
		while pos != -1:
			if not code.substr(pos).begins_with(dossier):
				fautifs.append(f)
				break
			pos = code.find("res://", pos + 1)
	_resultat(fautifs.is_empty(), "Le système (scripts/lumiere) ne dépend de rien d'autre",
		"aucun lien vers le reste du labo" if fautifs.is_empty() else "liens vers l'extérieur dans : " + ", ".join(fautifs))


func _test_morceau_type() -> void:
	var m: ArrayMesh = MorceauType.creer()
	var tab := m.surface_get_arrays(0)
	var sommets: PackedVector3Array = tab[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = tab[Mesh.ARRAY_TEX_UV]
	# Chaque numéro 0..63 apparaît sur exactement 3 sommets, et l'aire totale = celle du triangle de base (0,5).
	var vus := {}
	var aire := 0.0
	for k in sommets.size() / 3:
		var a := sommets[3 * k]
		var b := sommets[3 * k + 1]
		var c := sommets[3 * k + 2]
		aire += (b - a).cross(c - a).length() * 0.5
		vus[int(uvs[3 * k].x)] = true
	var ok := sommets.size() == 192 and vus.size() == 64 and absf(aire - 0.5) < 1e-4
	_resultat(ok, "Morceau type : 64 petits triangles numérotés",
		"%d sommets (attendu 192), %d numéros (attendu 64), aire %.4f (attendu 0,5)" % [sommets.size(), vus.size(), aire])


func _test_bloc_factice() -> void:
	var n := 800
	var centres := PackedFloat64Array()
	var tailles := PackedFloat32Array()
	var adresses := PackedInt64Array()
	for i in n:
		var p := Vector3(sin(i * 0.1), cos(i * 0.37), sin(i * 0.05) + 0.5).normalized() * 1000.0
		centres.append_array([p.x, p.y, p.z])
		tailles.append(5.0)
		adresses.append(i)
	var bloc = BlocFactice.new()
	bloc.preparer(0, centres, tailles, adresses)
	bloc.eclairer(3, 8, 1.0)   # 1 rayon sur 8 : les rayons 3, 11, 19…
	var faits := 0
	var bon_tour := true
	for i in n:
		if bloc.rayons[i * 13 + 12] == 1.0:
			faits += 1
			bon_tour = bon_tour and i % 8 == 3
	bloc.choisir(Vector3(0, 0, 1300), 1000.0)
	var ok: bool = faits == n / 8 and bon_tour and bloc.nb_visibles > 0 and bloc.nb_visibles < n
	_resultat(ok, "Rayons factices : 1 sur 8 éclairé par image, horizon respecté",
		"%d rayons refaits (attendu %d), %d visibles sur %d" % [faits, n / 8, bloc.nb_visibles, n])


func _test_scene_mesure() -> void:
	var paquet: PackedScene = load("res://scenes/mesure.tscn")
	var m: Node = paquet.instantiate() if paquet else null
	if m == null:
		_resultat(false, "Scène de mesure", "mesure.tscn ne se charge pas")
		return
	add_child(m)
	m.set_process(false)          # on la pilote à la main, sans attendre ses 25 secondes
	await get_tree().process_frame
	m.construire(2000)
	var ms1: PackedFloat64Array = m._une_image(false, 8)
	var ms2: PackedFloat64Array = m._une_image(true, 8)
	var octets_ok: bool = m.image.get_width() == 512 and m.nb_rayons == 2048
	m.resultats.append({"nom": "Tout, plusieurs fils de calcul", "rayons": 2048, "images_s": 70.0, "image_ms": 14.0,
		"pire_ms": 15.0, "choisir": 1.0, "eclairer": 2.0, "envoyer": 0.5, "dessiner": 8.0, "gpu": 0.0, "calcul": true})
	var v: String = m.verdict()
	var rapport: String = m.rapport_texte()
	m.queue_free()
	var ok: bool = ms1[0] >= 0.0 and ms2[1] >= 0.0 and octets_ok and v.begins_with("GDScript SUFFIT") and rapport.contains("| Essai |")
	_resultat(ok, "Scène de mesure : une image avec 1 fil et plusieurs fils, verdict",
		"1 fil : choisir %.2f / éclairer %.2f ms ; plusieurs fils : %.2f / %.2f ms ; texture %s ; verdict « %s »" % [ms1[0], ms1[1], ms2[0], ms2[1], "bonne" if octets_ok else "fausse", v.left(30)])
