extends Control
## Tests automatiques du labo-lumière (scène tests.tscn, F6 dans Godot).
## Sans écran (dans le cloud), le programme s'arrête tout seul : code 0 si tout passe, 1 sinon.

const ChronoBoucle = preload("res://scripts/lumiere/chrono_boucle.gd")
const Compteur = preload("res://scripts/outils/compteur.gd")
const MorceauType = preload("res://scripts/lumiere/morceau_type.gd")
const BlocFactice = preload("res://scripts/mesure/bloc_factice.gd")
const Soleil = preload("res://scripts/lumiere/soleil.gd")
const Oeil = preload("res://scripts/lumiere/oeil.gd")
const Orbite = preload("res://scripts/lumiere/orbite.gd")
const Etoiles = preload("res://scripts/lumiere/etoiles.gd")
const EtoileProche = preload("res://scripts/lumiere/etoile_proche.gd")

var texte: RichTextLabel
var fond: ColorRect
var reussis := 0
var total := 0


func _ready() -> void:
	fond = ColorRect.new()
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
	_test_soleil_1ua()
	_test_penombre()
	_test_pupille()
	_test_adaptation()
	_test_halo_cie()
	await _test_labo_oeil()
	await _test_image_soleil()
	# Étape 6 (sans la partie C++) : catalogue, couleurs, vitesse, étoile compagne, Voie lactée.
	_test_catalogue_yale()
	_test_couleur_etoiles()
	_test_aberration_doppler()
	_test_etoile_compagne()
	_test_voie_lactee()
	# Étape 4 : la planète en rayons (partie C++).
	_test_cpp_charge()
	if not ClassDB.class_exists("ArbreLumiere"):
		return
	_test_arbre_adresses()
	_test_sans_fente()
	_test_glissement()
	_test_couleurs_stables()
	_test_choisir_survol()
	await _test_labo_planete()
	await _test_image_planete()
	# Étape 5 : retard de la lumière, petite lune, éclipses avec pénombre.
	_test_orbite_kepler()
	_test_retard_lumiere()
	_test_eclipse_cpp()
	await _test_labo_lune()
	await _test_image_eclipse()
	# Étape 6 : les étoiles dans le labo.
	await _test_labo_etoiles()
	await _test_image_ciel_etoile()


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


# ---------- Étape 3 : le vrai Soleil et l'œil du pilote ----------

func _test_soleil_1ua() -> void:
	var sol = Soleil.new()
	var ici := PackedFloat64Array([0.0, 0.0, 0.0])
	var angle := rad_to_deg(sol.rayon_angle(ici)) * 2.0
	var e: float = sol.eclairement(ici)
	var l := Soleil.luminance_moyenne()
	var e2: float = sol.eclairement(PackedFloat64Array([-Soleil.UA, 0.0, 0.0]))   # 2 UA
	var ok := absf(angle - 0.533) < 0.003 and absf(e - 126573.0) < 1300.0 \
		and absf(l - 1.86e9) < 0.1e9 and absf(e2 * 4.0 - e) < 1.0
	_resultat(ok, "Vrai Soleil à 1 UA : taille, éclairement, éclat",
		"diamètre %.3f° (attendu 0,533°), %d lux (attendu ≈ 126 600), éclat %.2f milliards de cd/m², à 2 UA %d lux (¼)" % [angle, roundi(e), l / 1e9, roundi(e2)])


func _test_penombre() -> void:
	var sol = Soleil.new()   # Soleil sur l'axe x, à 1 UA
	var astre := PackedFloat64Array([0.0, 0.0, 0.0])
	var r := 1000.0
	var libre: float = sol.part_visible(PackedFloat64Array([0.0, 5000.0, 0.0]), astre, r)
	var ombre: float = sol.part_visible(PackedFloat64Array([-3000.0, 0.0, 0.0]), astre, r)
	# On glisse sur le côté, derrière l'astre : la part visible doit monter de 0 à 1 sans sauter.
	var avant := -1.0
	var monte := true
	var milieu := false
	for i in 200:
		var y := 960.0 + i * 0.4   # le bord de l'ombre est à 1000 m, la pénombre fait ~30 m
		var v: float = sol.part_visible(PackedFloat64Array([-3000.0, y, 0.0]), astre, r)
		monte = monte and v >= avant - 1e-9
		milieu = milieu or (v > 0.3 and v < 0.7)
		avant = v
	var cache_entier: float = Soleil.recouvrement(1.0, 2.0, 0.5)
	var ok := libre == 1.0 and ombre == 0.0 and monte and milieu and cache_entier == 1.0
	_resultat(ok, "Ombre et pénombre de l'astre sur le Soleil",
		"hors de l'ombre %.2f, dans l'ombre %.2f, au bord : monte sans sauter %s, passe par la moitié %s" % [libre, ombre, monte, milieu])


func _test_pupille() -> void:
	var soleil := Oeil.pupille_cible(1e4)
	var noir := Oeil.pupille_cible(1e-4)
	var moyen := Oeil.pupille_cible(1.0)
	var o = Oeil.new()
	o.equilibrer(1e-4)
	o.avancer(1e4, 1.0)                 # on passe du noir au plein soleil
	var apres_ferme: float = o.pupille_mm
	o.equilibrer(1e4)
	o.avancer(1e-4, 1.0)                # et l'inverse
	var apres_ouvre: float = o.pupille_mm
	var ok := soleil <= 2.3 and noir >= 7.5 and absf(moyen - 4.9) < 0.05 and apres_ferme < 2.5 and apres_ouvre < 5.0
	_resultat(ok, "Pupille : 2 mm au soleil, 8 mm dans le noir, se ferme vite, s'ouvre lentement",
		"plein soleil %.1f mm, noir %.1f mm, 1 cd/m² %.1f mm ; 1 s après : fermée à %.1f mm, ouverte à %.1f mm" % [soleil, noir, moyen, apres_ferme, apres_ouvre])


func _test_adaptation() -> void:
	var o = Oeil.new()
	o.equilibrer(1000.0)
	var gris: float = o.reponse(1000.0)
	var blanc: float = o.reponse(1e9)
	var jour_nuit: float = o.nuit()
	for i in 60:
		o.avancer(1e-4, 0.5)            # 30 s dans le noir, adaptation accélérée
	var nuit_rapide: float = o.nuit()
	var lent = Oeil.new()
	lent.temps_reel = true
	lent.equilibrer(1000.0)
	for i in 60:
		lent.avancer(1e-4, 0.5)         # 30 s à la vraie vitesse : à peine commencé
	var nuit_lente: float = lent.nuit()
	o.avancer(1000.0, 8.0)              # retour au jour : quelques secondes (ébloui avant)
	var g: float = o.gain()
	o.equilibrer(1000.0)
	var rapport: float = g / o.gain()
	var ok := absf(gris - 0.18) < 0.02 and blanc > 0.99 and jour_nuit == 0.0 and nuit_rapide > 0.9 \
		and nuit_lente < 0.5 and rapport > 0.5 and rapport < 2.0
	_resultat(ok, "Adaptation de l'œil : jour, nuit (lente au noir, rapide à la lumière)",
		"gris moyen %.2f, Soleil %.2f ; vision de nuit après 30 s : %d %% (accélérée), %d %% (vraie vitesse) ; retour au jour en 8 s : écart ×%.2f" % [gris, blanc, roundi(nuit_rapide * 100), roundi(nuit_lente * 100), rapport])


func _test_halo_cie() -> void:
	# Loi de Stiles-Holladay (voile ≈ 10 E / θ²) : la formule CIE doit la suivre de près entre 2 et 10°.
	var ok := true
	var details := PackedStringArray()
	for t: float in [2.0, 5.0, 10.0]:
		var r := Oeil.voile(1.0, t) / (10.0 / (t * t))
		ok = ok and r > 0.5 and r < 1.5
		details.append("%d° : ×%.2f" % [t, r])
	var champ_ok := Oeil.part_dans_le_champ(1.0) == 1.0 and Oeil.part_dans_le_champ(cos(deg_to_rad(100.0))) < 0.01
	_resultat(ok and champ_ok, "Halo : formule d'éblouissement de la CIE, Soleil hors du champ sans halo",
		"rapport avec 10 E/θ² : %s ; Soleil dans le dos : %s" % [", ".join(details), "aucun halo" if champ_ok else "halo (faux)"])


func _test_labo_oeil() -> void:
	var labo: Node = load("res://scenes/labo.tscn").instantiate()
	add_child(labo)
	labo.compagne.allumee = false   # étapes 3-4 : le Soleil seul (l'étoile compagne vient à l'étape 6)
	await get_tree().process_frame
	labo.set_process(false)
	labo.aller_a(3)                     # dans l'ombre de l'astre
	for i in 60:
		labo._process(0.5)              # 30 s
	var vis_ombre: float = labo.part_visible
	var nuit: float = labo.oeil.nuit()
	labo.aller_a(4)
	labo._process(0.016)
	var vis_bord: float = labo.part_visible
	labo.aller_a(2)                     # face au Soleil, en sortant du noir
	labo._process(0.1)
	var ebloui: float = labo.oeil.reponse(labo.luminance_vue)
	for i in 9:
		labo._process(0.1)
	var pupille: float = labo.oeil.pupille_mm
	for i in 40:
		labo._process(0.5)
	var habitue: float = labo.oeil.reponse(labo.luminance_vue)
	var infos: String = labo.compteur.infos
	labo.queue_free()
	var ok := vis_ombre == 0.0 and nuit > 0.9 and absf(vis_bord - 0.5) < 0.05 and pupille < 2.6 \
		and ebloui > 0.9 and habitue < 0.5 and infos.contains("pupille")
	_resultat(ok, "Labo : nuit dans l'ombre, éclipse à moitié, éblouissement face au Soleil",
		"ombre : Soleil visible %d %%, vision de nuit %d %% ; bord : %d %% ; face au Soleil : pupille %.1f mm, ébloui %.2f puis habitué %.2f" % [roundi(vis_ombre * 100), roundi(nuit * 100), roundi(vis_bord * 100), pupille, ebloui, habitue])


func _test_image_soleil() -> void:
	if DisplayServer.get_name() == "headless":
		_resultat(true, "Image du Soleil à l'écran", "sauté : pas d'écran ici (il passe sur le PC et dans le cloud avec écran virtuel)")
		return
	var labo: Node = load("res://scenes/labo.tscn").instantiate()
	add_child(labo)
	labo.compagne.allumee = false   # étapes 3-4 : le Soleil seul (l'étoile compagne vient à l'étape 6)
	texte.visible = false
	fond.visible = false
	await get_tree().process_frame
	labo.aller_a(2)
	labo._process(0.016)
	labo.oeil.equilibrer(labo.luminance_vue)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var c := img.get_size() / 2
	var centre := img.get_pixelv(c).get_luminance()
	var halo := img.get_pixelv(c + Vector2i(0, 40)).get_luminance()
	var loin := img.get_pixelv(c + Vector2i(0, 330)).get_luminance()
	labo.oeil.halo = false
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var sans := get_viewport().get_texture().get_image().get_pixelv(c + Vector2i(0, 40)).get_luminance()
	labo.queue_free()
	texte.visible = true
	fond.visible = true
	var ok := centre > 0.95 and halo > 0.1 and halo < 0.95 and loin < halo and sans < 0.05
	_resultat(ok, "Image du Soleil : disque blanc, halo autour, rien sans halo",
		"centre %.2f, à 40 px %.2f, à 330 px %.2f ; halo coupé (H) : %.2f" % [centre, halo, loin, sans])


# --- Étape 4 : planète en rayons -------------------------------------------------------------

func _nouvel_arbre() -> Object:
	var a: Object = ClassDB.instantiate("ArbreLumiere")
	a.configurer(600000.0, 7, 1024)
	return a


func _point(t: PackedFloat64Array, i: int) -> Vector3:
	return Vector3(t[i * 3], t[i * 3 + 1], t[i * 3 + 2])


## Numéro d'un coin du morceau (a le long de A→B, b le long de A→C), comme en C++.
func _coin(a: int, b: int) -> int:
	return MorceauType.numero_coin(a, b)


func _test_cpp_charge() -> void:
	var ok := ClassDB.class_exists("ArbreLumiere")
	var fichiers := DirAccess.get_files_at("res://scripts/lumiere/bin/")
	var dll := "liblumiere.windows.template_release.x86_64.dll" in fichiers \
		and "liblumiere.windows.template_debug.x86_64.dll" in fichiers
	_resultat(ok and dll, "Partie C++ chargée (GDExtension), DLL Windows présentes",
		"classe ArbreLumiere %s ; DLL pour le PC %s" % ["trouvée" if ok else "ABSENTE", "présentes" if dll else "ABSENTES"])


func _test_arbre_adresses() -> void:
	var a := _nouvel_arbre()
	var r: PackedInt64Array = a.racines()
	var enfant: int = _enfant(r[5], 3)
	var petit: int = enfant
	for i in 24:
		petit = _enfant(petit, i % 4)
	var ok: bool = r.size() == 20 and a.niveau_de(r[0]) == 0 and a.niveau_de(enfant) == 1 \
		and a.niveau_de(petit) == 25 and (petit >> 50) == r[5]
	_resultat(ok, "Arbre : 20 faces de départ, adresses de 64 bits, niveaux",
		"%d faces, niveau d'un enfant %d, d'un descendant %d (attendu 25), face retrouvée %s" % [
			r.size(), a.niveau_de(enfant), a.niveau_de(petit), (petit >> 50) == r[5]])


func _test_sans_fente() -> void:
	# 1. Deux faces voisines de l'icosaèdre ont exactement les mêmes coins sur leur bord commun.
	# 2. Les coins d'un parent se retrouvent à l'identique chez ses enfants (le relief ne change pas).
	var a := _nouvel_arbre()
	var r: PackedInt64Array = a.racines()
	var p0: PackedFloat64Array = a.coins_morceau(r[0])
	var p1: PackedFloat64Array = a.coins_morceau(r[1])
	var pire_bord := INF
	var communs := 0
	for i in 45:
		var meilleur := INF
		for j in 45:
			meilleur = minf(meilleur, _point(p0, i).distance_to(_point(p1, j)))
		if meilleur < 100.0:
			communs += 1
			pire_bord = meilleur if pire_bord == INF else maxf(pire_bord, meilleur)
	var parent: int = _enfant(_enfant(r[7], 1), 2)
	var pp: PackedFloat64Array = a.coins_morceau(parent)
	var pire_enfant := 0.0
	var e0: PackedFloat64Array = a.coins_morceau(_enfant(parent, 0))
	for b in range(0, 5):
		for c in range(0, 5 - b):
			# Le coin (2c, 2b) de l'enfant 0 est le coin (c, b) du parent.
			pire_enfant = maxf(pire_enfant, _point(e0, _coin(2 * c, 2 * b)).distance_to(_point(pp, _coin(c, b))))
	var ok := communs == 9 and pire_bord < 0.2 and pire_enfant < 0.05
	_resultat(ok, "Pas de fente : bords communs et coins du parent identiques",
		"%d coins communs entre 2 faces (attendu 9), écart %.3f m ; parent/enfant : écart %.3f m" % [communs, pire_bord, pire_enfant])


func _test_glissement() -> void:
	# Un enfant part de la forme de son parent (glissement doux) et arrive sur son vrai relief.
	var a := _nouvel_arbre()
	var parent: int = _enfant(_enfant(a.racines()[2], 0), 3)
	for i in 6:
		parent = _enfant(parent, 3 if i % 2 else 1)
	var pp: PackedFloat64Array = a.coins_morceau(parent)
	var enfant: int = _enfant(parent, 0)
	var dep: PackedFloat64Array = a.coins_depart_morceau(enfant)
	var cib: PackedFloat64Array = a.coins_morceau(enfant)
	var pire_pair := 0.0
	var pire_milieu := 0.0
	var bouge := 0.0
	for b in 9:
		for c in 9 - b:
			var k := _coin(c, b)
			if c % 2 == 0 and b % 2 == 0:
				pire_pair = maxf(pire_pair, _point(dep, k).distance_to(_point(cib, k)))
			elif b % 2 == 0:
				var m := (_point(pp, _coin((c - 1) / 2, b / 2)) + _point(pp, _coin((c + 1) / 2, b / 2))) * 0.5
				pire_milieu = maxf(pire_milieu, _point(dep, k).distance_to(m))
				bouge = maxf(bouge, _point(dep, k).distance_to(_point(cib, k)))
	var ok := pire_pair < 0.05 and pire_milieu < 0.05 and bouge > 0.01
	_resultat(ok, "Glissement : un nouveau triangle part de la forme de son parent",
		"coins déjà là : écart %.3f m ; nouveaux coins au départ sur le parent : écart %.3f m ; ils bougent ensuite de %.2f m" % [pire_pair, pire_milieu, bouge])


func _test_couleurs_stables() -> void:
	# Couleurs stables : la couleur d'un rayon du parent ≈ la moyenne des rayons de ses enfants
	# qui couvrent la même surface (pas de saut de teinte quand un triangle se coupe).
	var a := _nouvel_arbre()
	var pires := PackedFloat64Array()
	var r: PackedInt64Array = a.racines()
	for essai in 4:
		var parent: int = r[essai * 5]
		for i in 3 + essai * 2:
			parent = _enfant(parent, (i + essai) % 4)
		var cp: PackedFloat32Array = a.couleurs_morceau(parent)
		var moy_p := 0.0
		for v in cp:
			moy_p += v
		var moy_e := 0.0
		for k in 4:
			var ce: PackedFloat32Array = a.couleurs_morceau(_enfant(parent, k))
			for v in ce:
				moy_e += v
		moy_p /= cp.size()
		moy_e /= cp.size() * 4
		pires.append(absf(moy_e - moy_p) / maxf(moy_p, 1e-6))
	var pire := 0.0
	for v in pires:
		pire = maxf(pire, v)
	_resultat(pire < 0.08, "Couleurs stables : parent = moyenne de ses enfants",
		"plus grand écart sur 4 essais : %.1f %% (attendu moins de 8 %%)" % (pire * 100.0))


func _test_choisir_survol() -> void:
	# Survol à 300 m d'altitude puis montée en orbite : les morceaux suivent, jamais plus que les
	# places, et le calcul C++ reste dans le budget (choisir 2 ms + éclairer 3 ms par image).
	var a := _nouvel_arbre()
	var axes := PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, -1, 0])   # regarde vers l'horizon
	var tan_v := tan(deg_to_rad(37.5))
	var tan_h := tan_v * 16.0 / 9.0
	var r := 600000.0
	var pire_ms := 0.0
	var total_ms := 0.0
	var max_morceaux := 0
	var niveau_bas := 0
	var nb := 0
	for i in 240:
		var ang := i * 0.00005                       # on avance de 30 m par image
		var alt: float = 300.0 + a.hauteur_sol(PackedFloat64Array([sin(ang), cos(ang), 0.0])) if i < 180 else 300.0 + (i - 180) * 20000.0
		var cam := PackedFloat64Array([sin(ang) * (r + alt), cos(ang) * (r + alt), 0.0])
		axes = PackedFloat32Array([cos(ang), -sin(ang), 0, 0, 0, 1, sin(ang), cos(ang), 0])
		var t0 := Time.get_ticks_usec()
		var n: int = a.choisir(cam, axes, tan_h, tan_v, 720.0, i / 60.0)
		a.eclairer(96, 3.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if i >= 30:
			pire_ms = maxf(pire_ms, ms)
			total_ms += ms
			nb += 1
		max_morceaux = maxi(max_morceaux, n)
		if i == 170:
			niveau_bas = a.niveau_max_affiche()
	var niveau_haut: int = a.niveau_max_affiche()
	var moyen := total_ms / nb
	var ok := max_morceaux <= 1024 and max_morceaux > 150 and niveau_bas >= 12 and niveau_haut < niveau_bas and moyen < 5.0
	_resultat(ok, "Choisir + éclairer en C++ : survol à 300 m puis montée en orbite",
		"%d morceaux au plus (places 1024), niveau le plus fin %d au ras du sol, %d en orbite ; calcul %.2f ms par image en moyenne (pire %.1f ms, budget 5)" % [
			max_morceaux, niveau_bas, niveau_haut, moyen, pire_ms])


func _test_labo_planete() -> void:
	var labo: Node = load("res://scenes/labo.tscn").instantiate()
	add_child(labo)
	labo.compagne.allumee = false   # étapes 3-4 : le Soleil seul (l'étoile compagne vient à l'étape 6)
	await get_tree().process_frame
	labo.set_process(false)
	var ok: bool = labo.avec_planete
	labo.aller_a(5)                                  # rase-mottes, en plein jour
	for i in 60:
		labo._process(0.05)
	var jour: float = labo.luminance_vue
	var rayons: int = labo.planete.arbre.nb_rayons()
	labo.aller_a(3)                                  # côté nuit
	for i in 20:
		labo._process(0.05)
	var nuit: float = labo.luminance_vue
	# On fonce vers le sol : l'œil s'arrête au-dessus.
	labo.pos_oeil = PackedFloat64Array([0.0, 600000.0 - 50000.0, 0.0])
	labo._process(0.016)
	var alt: float = labo.altitude
	labo.queue_free()
	ok = ok and jour > 100.0 and nuit < 0.01 and rayons > 2000 and alt >= 1.5 and alt < 3.0
	_resultat(ok, "Labo : planète en rayons, jour, nuit, sol infranchissable",
		"jour %.0f cd/m² avec %d rayons ; nuit %.5f cd/m² (rayons + fond du ciel) ; sous le sol → remis à %.1f m" % [jour, rayons, nuit, alt])


func _test_image_planete() -> void:
	if DisplayServer.get_name() == "headless":
		_resultat(true, "Image de la planète à l'écran", "sauté : pas d'écran ici (il passe sur le PC et dans le cloud avec écran virtuel)")
		return
	var labo: Node = load("res://scenes/labo.tscn").instantiate()
	add_child(labo)
	labo.compagne.allumee = false   # étapes 3-4 : le Soleil seul (l'étoile compagne vient à l'étape 6)
	texte.visible = false
	fond.visible = false
	await get_tree().process_frame
	labo.aller_a(1)                                  # vue d'orbite, planète à moitié éclairée
	for i in 30:
		await get_tree().process_frame
	labo.oeil.equilibrer(labo.luminance_vue)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	labo.queue_free()
	texte.visible = true
	fond.visible = true
	# Côté jour (gauche de l'écran ou droite) : des pixels clairs ; côté nuit : très sombres ; bords : ciel noir.
	var clairs := 0
	var sombres := 0
	for y in range(100, 620, 20):
		for x in range(200, 1080, 20):
			var l := img.get_pixel(x, y).get_luminance()
			if l > 0.25:
				clairs += 1
			elif l < 0.04:
				sombres += 1
	var ok := clairs > 150 and sombres > 150
	_resultat(ok, "Image de la planète : moitié jour, moitié nuit",
		"%d points clairs, %d points sombres sur 1 144" % [clairs, sombres])


## Adresse d'un enfant (comme ArbreLumiere.adresse_enfant), sans nommer la classe C++ : les tests
## doivent se charger même si la partie C++ manque.
func _enfant(adresse: int, i: int) -> int:
	return (adresse << 2) | (i & 3)


# --- Étape 5 : retard de la lumière, lune, éclipses ------------------------------------------

func _test_orbite_kepler() -> void:
	var o = Orbite.new()
	var gm: float = Orbite.gm_boule(600000.0, 3000.0)
	o.configurer(gm, 6.0e6, Vector3.RIGHT, Vector3.FORWARD)
	var t: float = o.periode()
	var attendu := TAU * sqrt(pow(6.0e6, 3.0) / gm)
	var p0: PackedFloat64Array = o.position(0.0)
	var p4: PackedFloat64Array = o.position(t / 4.0)
	var p1: PackedFloat64Array = o.position(t)
	var rayon := sqrt(p4[0] * p4[0] + p4[1] * p4[1] + p4[2] * p4[2])
	# Un quart de tour : l'astre est passé de la direction u à la direction v.
	var quart := Vector3(p4[0], p4[1], p4[2]).normalized().dot(Vector3.FORWARD)
	var boucle := absf(p1[0] - p0[0]) + absf(p1[2] - p0[2])
	var ok := absf(t - attendu) < 1e-6 * attendu and absf(rayon - 6.0e6) < 1e-3 and quart > 0.999999 and boucle < 1e-3
	# Vitesse sur l'orbite = 2 π r / période.
	ok = ok and absf(o.vitesse() - TAU * 6.0e6 / t) < 1e-6
	_resultat(ok, "Lune : vraie gravité (loi de Kepler)",
		"masse de la planète %s kg, un tour en %.1f h, vitesse %.0f m/s, rayon gardé %.3f m près" % [
			String.num_scientific(gm / Orbite.G), t / 3600.0, o.vitesse(), absf(rayon - 6.0e6)])


func _test_retard_lumiere() -> void:
	# Œil au centre de l'orbite : la lumière met exactement rayon / c.
	var o = Orbite.new()
	o.configurer(Orbite.gm_boule(600000.0, 3000.0), 6.0e6, Vector3.RIGHT, Vector3.FORWARD)
	var centre := PackedFloat64Array([0.0, 0.0, 0.0])
	var r1: float = o.retard(100.0, centre)
	var ok := absf(r1 - 6.0e6 / Orbite.C) < 1e-12
	# Astre très rapide (planète énorme, pour voir l'effet) : on le voit là où il ÉTAIT, et la distance
	# de ce point à l'œil est bien c × retard.
	var rapide = Orbite.new()
	rapide.configurer(1.0e21, 1.0e8, Vector3.RIGHT, Vector3.FORWARD)   # ~3 000 km/s
	var oeil := PackedFloat64Array([-2.0e8, 0.0, 0.0])
	var r2: float = rapide.retard(0.0, oeil)
	var vu: PackedFloat64Array = rapide.position_vue(0.0, oeil)
	var vrai: PackedFloat64Array = rapide.position(0.0)
	var d := sqrt(pow(vu[0] - oeil[0], 2.0) + pow(vu[1] - oeil[1], 2.0) + pow(vu[2] - oeil[2], 2.0))
	var ecart := sqrt(pow(vu[0] - vrai[0], 2.0) + pow(vu[2] - vrai[2], 2.0))
	ok = ok and absf(d - Orbite.C * r2) < 1.0 and absf(ecart - rapide.vitesse() * r2) < 0.01 * ecart
	var s = Soleil.new()
	var r_soleil: float = s.retard(centre)
	ok = ok and absf(r_soleil - 499.0) < 1.0
	_resultat(ok, "Retard de la lumière",
		"lune vue du centre : %.2f ms ; astre rapide vu %.0f km en arrière (%.2f s de retard) ; Soleil : %.1f s" % [
			r1 * 1000.0, ecart / 1000.0, r2, r_soleil])


func _test_eclipse_cpp() -> void:
	var a := _nouvel_arbre()
	var s := Soleil.new()   # Soleil sur l'axe x, à 1 UA
	var alpha: float = s.rayon_angle(PackedFloat64Array([0.0, 0.0, 0.0]))
	var occ := PackedFloat64Array([1.0e6, 0.0, 0.0, 1000.0])
	var accord := true
	for y in [0.0, 900.0, 990.0, 1000.0, 1010.0, 1100.0, 5000.0]:
		var p := PackedFloat64Array([0.0, y, 0.0])
		var cpp: float = a.part_visible(p, occ, Vector3.RIGHT, alpha)
		var gd: float = s.part_visible(p, PackedFloat64Array([1.0e6, 0.0, 0.0]), 1000.0)
		accord = accord and absf(cpp - gd) < 1e-3
	# Posemètre : une grosse lune entre le Soleil et la face éclairée assombrit ce que l'œil voit.
	a.choisir(PackedFloat64Array([2.0e6, 0.0, 0.0]), PackedFloat32Array([-1, 0, 0, 0, 0, -1, 0, 1, 0]), 1.0, 0.6, 720.0, 0.0)
	for i in 30:
		a.eclairer(400, 50.0)
		a.choisir(PackedFloat64Array([2.0e6, 0.0, 0.0]), PackedFloat32Array([-1, 0, 0, 0, 0, -1, 0, 1, 0]), 1.0, 0.6, 720.0, 0.0)
	var axes := PackedFloat32Array([-1, 0, 0, 0, 0, -1, 0, 1, 0])
	var oeil := PackedFloat64Array([2.0e6, 0.0, 0.0])
	var plein: PackedFloat32Array = a.posemetre(oeil, axes, 1.0, 0.6, Vector3.RIGHT, 126000.0, 2e-4)
	var cache: PackedFloat32Array = a.posemetre(oeil, axes, 1.0, 0.6, Vector3.RIGHT, 126000.0, 2e-4,
		PackedFloat64Array([3.0e6, 0.0, 0.0, 300000.0]), alpha)
	var cov: PackedFloat32Array = a.couverture()
	var milieu := 4 * 16 + 8
	var ok := accord and cache[milieu] < 0.01 * plein[milieu] and plein[milieu] > 100.0 and cov.size() == 144 \
		and cov[milieu] > 0.85 and cov[0] < 0.5
	_resultat(ok, "Éclipse : ombre et pénombre dans la partie C++",
		"même part du Soleil que soleil.gd : %s ; centre de l'écran %.0f cd/m² → %.2f dans l'ombre d'une lune ; couverture %.2f / %.2f" % [
			accord, plein[milieu], cache[milieu], cov[milieu], cov[0]])


func _test_labo_lune() -> void:
	var labo: Node = load("res://scenes/labo.tscn").instantiate()
	add_child(labo)
	await get_tree().process_frame
	labo.set_process(false)
	var ok: bool = labo.lune != null
	if not ok:
		labo.queue_free()
		_resultat(false, "Labo : petite lune et éclipses", "lune absente")
		return
	labo.aller_a(2)                                  # en plein jour, face au Soleil
	for i in 30:
		labo._process(0.05)
	var jour: float = labo.luminance_vue
	labo.aller_a(6)                                  # éclipse totale vue du sol
	for i in 40:
		labo._process(0.05)
	var totale: float = labo.part_visible
	var eclipse: float = labo.luminance_vue
	var rayons_lune: int = labo.lune.arbre.nb_rayons()
	# On avance le temps (×1000) : l'ombre de la lune s'en va, le Soleil revient.
	labo.acceleration = 1000.0
	for i in 30:
		labo._process(0.05)
	var apres: float = labo.part_visible
	labo.acceleration = 1.0
	labo.aller_a(8)                                  # éclipse de lune, près de la lune
	for i in 40:
		labo._process(0.05)
	var d_lune: float = labo._distance_lune()
	var loin_lune: int = labo.lune.arbre.nb_rayons()
	# On descend à 20 km de son sol : les triangles de la lune se coupent.
	var vers: Vector3 = Vector3(labo.pos_oeil[0] - labo.pos_lune[0], labo.pos_oeil[1] - labo.pos_lune[1],
		labo.pos_oeil[2] - labo.pos_lune[2]).normalized() * (labo.RAYON_LUNE + 20000.0)
	labo.pos_oeil = PackedFloat64Array([labo.pos_lune[0] + vers.x, labo.pos_lune[1] + vers.y, labo.pos_lune[2] + vers.z])
	labo.camera.basis = Basis.looking_at(-vers, vers.cross(Vector3.RIGHT).normalized())
	for i in 40:
		labo._process(0.05)
	var pres_lune: int = labo.lune.arbre.nb_rayons()
	# On fonce dans la lune : l'œil s'arrête au-dessus de son sol.
	labo.pos_oeil = labo.pos_lune.duplicate()
	labo._process(0.016)
	var alt: float = labo._altitude_lune()
	var retard: float = labo.retard_lune
	labo.queue_free()
	ok = totale < 0.001 and eclipse < 0.01 * jour and apres > 0.999 and rayons_lune > 0 and pres_lune > maxi(2000, loin_lune) \
		and d_lune < 700000.0 and alt >= 1.5 and alt < 3.0 and retard > 0.0
	_resultat(ok, "Labo : petite lune, éclipse de Soleil totale, éclipse de lune",
		"Soleil visible pendant l'éclipse %.3f, l'œil voit %.4f au lieu de %.0f cd/m², puis Soleil revenu %.2f ; lune à 500 km %d rayons, à 20 km %d ; sous son sol → %.1f m" % [
			totale, eclipse, jour, apres, loin_lune, pres_lune, alt])


func _test_image_eclipse() -> void:
	if DisplayServer.get_name() == "headless":
		_resultat(true, "Image : ombre de la lune sur la planète", "sauté : pas d'écran ici (il passe sur le PC et dans le cloud avec écran virtuel)")
		return
	var labo: Node = load("res://scenes/labo.tscn").instantiate()
	add_child(labo)
	texte.visible = false
	fond.visible = false
	await get_tree().process_frame
	labo.aller_a(7)
	for i in 30:
		await get_tree().process_frame
	labo.oeil.equilibrer(labo.luminance_vue)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var g: Vector3 = labo._vers_planete(labo._lieu_eclipse()) * 600000.0
	var cam: Camera3D = labo.camera
	var rel := g - Vector3(labo.pos_oeil[0], labo.pos_oeil[1], labo.pos_oeil[2])
	var ombre_px := cam.unproject_position(rel)
	var centre_px := cam.unproject_position(-Vector3(labo.pos_oeil[0], labo.pos_oeil[1], labo.pos_oeil[2]))
	var lumiere_px := centre_px + (centre_px - ombre_px) * 0.5   # de l'autre côté du centre, en plein jour
	var dans_ombre := img.get_pixelv(Vector2i(ombre_px)).get_luminance()
	var au_soleil := img.get_pixelv(Vector2i(lumiere_px)).get_luminance()
	labo.queue_free()
	texte.visible = true
	fond.visible = true
	var ok := dans_ombre < 0.05 and au_soleil > 0.3
	_resultat(ok, "Image : ombre de la lune sur la planète",
		"dans l'ombre %.2f, au soleil %.2f (pixels %s et %s)" % [dans_ombre, au_soleil, Vector2i(ombre_px), Vector2i(lumiere_px)])



# ---------------------------------------------------------------------------------------------
# Étape 6 : les étoiles
# ---------------------------------------------------------------------------------------------

func _test_catalogue_yale() -> void:
	var e = Etoiles.new()
	var ok: bool = e.charger()
	if not ok:
		_resultat(false, "Catalogue de Yale", "fichier etoiles_yale.bin absent ou abîmé")
		return
	# Sirius : la plus brillante, ascension droite 6 h 45 min 9 s, déclinaison −16° 43'.
	var sirius := Etoiles.direction_ciel(e.ascension[0], e.declinaison[0])
	var attendu := Etoiles.direction_ciel_degres(101.2875, -16.7161)
	var ecart := rad_to_deg(sirius.angle_to(attendu)) * 60.0
	var faible := 0
	var max_mag := -9.0
	for m in e.magnitude:
		max_mag = maxf(max_mag, m)
		if m > 6.0:
			faible += 1
	# Une étoile de magnitude 0 donne 2,54e-6 lux ; 5 magnitudes = 100 fois moins.
	var lux_ok := absf(Etoiles.lux(0.0) - 2.54e-6) < 1e-9 and absf(Etoiles.lux(0.0) / Etoiles.lux(5.0) - 100.0) < 0.01
	ok = e.nombre > 9000 and absf(e.magnitude[0] + 1.46) < 0.01 and ecart < 2.0 and max_mag < 8.1 and lux_ok
	_resultat(ok, "Catalogue de Yale : 9 096 étoiles, Sirius à sa place",
		"%d étoiles (dont %d plus faibles que 6), la plus brillante V = %.2f à %.1f' de Sirius, magnitude 0 → %s lux" % [
			e.nombre, faible, e.magnitude[0], ecart, _sci(Etoiles.lux(0.0))])


func _test_couleur_etoiles() -> void:
	# Le Soleil (B-V = 0,65) : environ 5 800 K, couleur proche de celle de soleil.gd.
	var t_soleil := Etoiles.temperature(0.65)
	var s := Etoiles.corps_noir(Etoiles.T_SOLEIL)
	var c := Soleil.COULEUR
	var proche := absf(s.r - c.r) < 0.1 and absf(s.g - c.g) < 0.1 and absf(s.b - c.b) < 0.1
	var rouge := Etoiles.corps_noir(3000.0)
	var bleue := Etoiles.corps_noir(20000.0)
	# Efficacité : maximale vers 6 600 K, faible pour les étoiles très froides ou très chaudes.
	var eff_ok := Etoiles.efficacite(3000.0) < 0.5 and Etoiles.efficacite(30000.0) < 0.2 and Etoiles.efficacite(6600.0) > 1.0
	var lum := 0.2126 * bleue.r + 0.7152 * bleue.g + 0.0722 * bleue.b
	var ok := absf(t_soleil - 5800.0) < 150.0 and proche and rouge.r > rouge.b * 3.0 and bleue.b > bleue.r and eff_ok \
		and absf(lum - 1.0) < 0.01
	_resultat(ok, "Couleur des étoiles : corps noir vu par l'œil",
		"B-V 0,65 → %d K ; Soleil (%.2f, %.2f, %.2f) ; 3 000 K (%.2f, %.2f, %.2f) ; 20 000 K (%.2f, %.2f, %.2f) ; efficacité 3 000 K %.2f, 6 600 K %.2f, 30 000 K %.2f" % [
			roundi(t_soleil), s.r, s.g, s.b, rouge.r, rouge.g, rouge.b, bleue.r, bleue.g, bleue.b,
			Etoiles.efficacite(3000.0), Etoiles.efficacite(6600.0), Etoiles.efficacite(30000.0)])


func _test_aberration_doppler() -> void:
	var n := Vector3(1, 0, 0)
	var arret: Array = Etoiles.aberration(n, Vector3.ZERO)
	var devant: Array = Etoiles.aberration(Vector3(0, 0, -1), Vector3(0, 0, -0.9))
	var cote: Array = Etoiles.aberration(n, Vector3(0, 0, -0.9))
	var derriere: Array = Etoiles.aberration(Vector3(0, 0, 1), Vector3(0, 0, -0.9))
	# À 0,9 c, une étoile vue « sur le côté » au repos se voit à 25,8° de l'avant (cos = 0,9).
	var angle_cote := rad_to_deg((cote[0] as Vector3).angle_to(Vector3(0, 0, -1)))
	# Aller-retour : avec la vitesse opposée, on retrouve la direction de départ.
	var q := Vector3(0.3, -0.5, 0.8).normalized()
	var aller: Array = Etoiles.aberration(q, Vector3(0.2, 0.5, -0.4))
	var retour: Array = Etoiles.aberration(aller[0], -Vector3(0.2, 0.5, -0.4))
	var aller_retour := rad_to_deg((retour[0] as Vector3).angle_to(q)) * 3600.0
	# Petite vitesse : décalage ≈ v/c radians (30 km/s → 20,6 secondes d'arc, l'aberration de la Terre).
	var terre: Array = Etoiles.aberration(n, Vector3(0, 0, -30000.0 / Etoiles.C))
	var terre_s := rad_to_deg((terre[0] as Vector3).angle_to(n)) * 3600.0
	# Doppler : devant, le Soleil vu à 0,9 c est un corps noir à 4,36 × 5 772 K, bleu ; derrière, rouge.
	var f_devant := Etoiles.facteur_eclat(devant[1], Etoiles.T_SOLEIL)
	var f_derriere := Etoiles.facteur_eclat(derriere[1], Etoiles.T_SOLEIL)
	var ok: bool = (arret[0] as Vector3).is_equal_approx(n) and absf(arret[1] - 1.0) < 1e-9 \
		and absf(devant[1] - 4.3589) < 0.001 and absf(angle_cote - 25.84) < 0.05 and aller_retour < 0.1 \
		and absf(terre_s - 20.6) < 0.1 and absf(derriere[1] - 0.2294) < 0.001 and f_devant > 1.0 and f_derriere < 0.01 \
		and absf(Etoiles.facteur_eclat(1.0, 5000.0) - 1.0) < 1e-9
	_resultat(ok, "Grande vitesse : aberration et effet Doppler",
		"à 0,9 c : D devant %.3f, derrière %.3f, étoile du côté vue à %.2f° de l'avant ; aller-retour %.4f\" ; 30 km/s → %.1f\" ; éclat du Soleil ×%.1f devant, ×%.4f derrière" % [
			devant[1], derriere[1], angle_cote, aller_retour, terre_s, f_devant, f_derriere])


func _test_etoile_compagne() -> void:
	var c = EtoileProche.new()
	var o := PackedFloat64Array([0.0, 0.0, 0.0])
	var e1: float = c.eclairement(o)
	c.position = PackedFloat64Array([10.0 * Soleil.UA, 0.0, 0.0])
	var e2: float = c.eclairement(o)
	var retard: float = c.retard(o) / 2.0
	var coul: Color = c.couleur()
	c.allumee = false
	var eteinte: float = c.eclairement(o)
	# Naine orange (4 400 K, 0,7 rayon solaire) à 5 UA : 0,7² / 5² × (4 400 / 5 772)⁴ × efficacité ≈ 610 lux.
	var ok := e1 > 550.0 and e1 < 680.0 and absf(e1 / e2 - 4.0) < 0.001 and absf(retard - 2494.0) < 2.0 \
		and coul.r > coul.b * 1.5 and eteinte == 0.0
	_resultat(ok, "Étoile compagne : vraie lumière d'une naine orange à 5 UA",
		"%.0f lux à 5 UA, %.0f à 10 UA (1/d²) ; sa lumière met %s ; couleur (%.2f, %.2f, %.2f) ; éteinte %.0f lux" % [
			e1, e2, "%d min %02d s" % [floori(retard / 60.0), roundi(fmod(retard, 60.0))], coul.r, coul.g, coul.b, eteinte])


func _test_voie_lactee() -> void:
	var centre := Etoiles.fond(Etoiles.centre_galaxie())
	var pole := Etoiles.fond(Etoiles.pole_galaxie())
	# Un point de la bande, à 90° du centre (vers la constellation du Cygne / de Persée).
	var bande_dir := Etoiles.pole_galaxie().cross(Etoiles.centre_galaxie()).normalized()
	var bande := Etoiles.fond(bande_dir)
	var somme := 0.0
	for i in 2000:
		var z := 1.0 - 2.0 * (i + 0.5) / 2000.0
		var phi := i * 2.399963
		var r := sqrt(1.0 - z * z)
		somme += Etoiles.fond(Vector3(r * cos(phi), z, r * sin(phi)))
	var moyenne := somme / 2000.0
	var angle_pole := rad_to_deg(Etoiles.pole_galaxie().angle_to(Etoiles.centre_galaxie()))
	var ok := centre > bande and bande > 2.0 * pole and moyenne > 5e-5 and moyenne < 2.5e-4 and absf(angle_pole - 90.0) < 0.01
	_resultat(ok, "Voie lactée : plus claire vers le centre de la galaxie, sombre vers ses pôles",
		"centre %s, bande %s, pôle %s cd/m², moyenne du ciel %s ; pôle et centre à %.2f°" % [
			_sci(centre), _sci(bande), _sci(pole), _sci(moyenne), angle_pole])


## Nombre très petit ou très grand, écrit « 1,2e-4 ».
static func _sci(x: float) -> String:
	if x == 0.0:
		return "0"
	var p := floori(log(absf(x)) / log(10.0))
	return "%.1fe%d" % [x / pow(10.0, p), p]


func _test_labo_etoiles() -> void:
	var labo: Node = load("res://scenes/labo.tscn").instantiate()
	add_child(labo)
	await get_tree().process_frame
	labo.set_process(false)
	var noeud: MultiMeshInstance3D = labo.noeud_etoiles
	var nb := noeud.multimesh.instance_count if noeud else 0
	# Ciel étoilé côté nuit : l'œil s'habitue au noir (vision de nuit), le sol n'est PAS éclairé.
	labo.aller_a(0)
	for i in 30:
		labo._process(0.05)
	labo.oeil.equilibrer(labo.luminance_vue)
	labo._process(0.05)
	var nuit: float = labo.luminance_vue
	var vision_nuit: float = labo.oeil.nuit()
	var gain_nuit: float = labo.oeil.gain()
	var cos_s: float = Vector3(labo.pos_oeil[0], labo.pos_oeil[1], labo.pos_oeil[2]).normalized().dot(labo._soleil_planete())
	# En plein jour face au Soleil : l'œil s'est fermé, une étoile de magnitude 0 ne se voit plus.
	labo.aller_a(2)
	for i in 30:
		labo._process(0.05)
	labo.oeil.equilibrer(labo.luminance_vue)
	labo._process(0.05)
	var gain_jour: float = labo.oeil.gain()
	var pic := Etoiles.lux(0.0) / (2.0 * PI * 0.36 * pow(deg_to_rad(labo.camera.fov) / 720.0, 2.0))
	var vue_nuit := pic * gain_nuit / (pic * gain_nuit + 1.0)
	var vue_jour := pic * gain_jour / (pic * gain_jour + 1.0)
	# L'étoile compagne éclaire le sol quand le Soleil est couché (point de vue 9), et rien sans elle.
	labo.aller_a(9)
	for i in 20:
		labo._process(0.05)
	var avec: float = labo.luminance_vue
	labo.compagne.allumee = false
	for i in 3:
		labo._process(0.05)
	var sans: float = labo.luminance_vue
	labo.compagne.allumee = true
	# Essai à grande vitesse (B) : 0,1 c puis 0,5 c droit devant.
	labo.changer_vitesse_essai()
	labo.changer_vitesse_essai()
	labo._process(0.016)
	var b: float = labo.beta.length()
	var vitesse_ok: bool = absf(b - 0.5) < 1e-6 and labo.doppler_soleil != 1.0
	labo.vitesse_essai = 0.0
	labo._process(0.016)
	var b0: float = labo.beta.length()
	labo.queue_free()
	var ok: bool = nb > 9000 and nuit < 0.01 and cos_s < -0.3 and vision_nuit > 0.9 and vue_nuit > 0.5 and vue_jour < 0.01 \
		and avec > 20.0 * sans and vitesse_ok and b0 == 0.0
	_resultat(ok, "Labo : ciel étoilé, étoiles effacées le jour, lumière de l'étoile compagne, grande vitesse",
		"%d étoiles ; nuit : œil habitué à %.4f cd/m² (vision de nuit %d %%), une étoile de magnitude 0 → %.2f à l'écran ; face au Soleil → %.4f ; sol avec la compagne %.2f, sans %.4f cd/m² ; 0,5 c → Doppler du Soleil ×%.2f" % [
			nb, nuit, roundi(vision_nuit * 100.0), vue_nuit, vue_jour, avec, sans, labo.doppler_soleil])


func _test_image_ciel_etoile() -> void:
	if DisplayServer.get_name() == "headless":
		_resultat(true, "Image : ciel étoilé et sol dans le noir", "sauté : pas d'écran ici (il passe sur le PC et dans le cloud avec écran virtuel)")
		return
	var labo: Node = load("res://scenes/labo.tscn").instantiate()
	add_child(labo)
	texte.visible = false
	fond.visible = false
	labo.compteur.visible = false
	await get_tree().process_frame
	labo.aller_a(0)
	for i in 30:
		await get_tree().process_frame
	labo.oeil.equilibrer(labo.luminance_vue)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# Points clairs dans le ciel (moitié haute) et sol noir (bas de l'image, sous l'horizon).
	var etoiles_vues := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in range(0, h / 2, 2):
		for x in range(0, w, 2):
			if img.get_pixel(x, y).get_luminance() > 0.35:
				etoiles_vues += 1
	var sol := 0.0
	var n := 0
	for x in range(0, w, 16):
		sol += img.get_pixel(x, h - 20).get_luminance()
		n += 1
	sol /= n
	labo.queue_free()
	texte.visible = true
	fond.visible = true
	var ok := etoiles_vues > 40 and sol < 0.05
	_resultat(ok, "Image : ciel étoilé et sol dans le noir",
		"%d pixels d'étoiles dans le haut de l'image, sol %.3f" % [etoiles_vues, sol])
