extends Control
## Banc d'essai du droïde (petite IA locale), À PART DU JEU.
## Il ne touche pas au vaisseau : les « fonctions du vaisseau » ici ne font que noter qu'elles ont
## été appelées. On mesure :
##   - si l'IA choisit la bonne fonction pour chaque ordre (en français),
##   - le temps de réponse,
##   - la fluidité (images par seconde) pendant qu'elle réfléchit, avec un objet 3D qui tourne.
## Extension utilisée : NobodyWho (licence EUPL-1.2), dans addons/nobodywho.
## Les modèles se téléchargent tout seuls au premier lancement (puis restent sur le PC).

## nom, fichier téléchargé à la main dans le dossier ia/ du projet (prioritaire), adresse de secours
const MODELES := [
	["LFM2.5-350M", "res://ia/LFM2.5-350M-Q4_K_M.gguf", "hf://LiquidAI/LFM2.5-350M-GGUF/LFM2.5-350M-Q4_K_M.gguf"],
	["Qwen3-0.6B", "res://ia/Qwen_Qwen3-0.6B-Q4_K_M.gguf", "hf://NobodyWho/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf"],
]
const CONSIGNE := "Tu es R-7, le droïde du vaisseau spatial. Le pilote te parle en français. " \
	+ "Quand il donne un ordre, appelle la fonction du vaisseau qui convient, puis réponds en une phrase courte en français. " \
	+ "Si aucune fonction ne convient, dis-le simplement."
## ordre du pilote, fonction attendue ("" = aucune)
const ORDRES := [
	["Stabilise le vaisseau, on tourne dans tous les sens !", "stabiliser"],
	["Garde le cap.", "garder_cap"],
	["Arrête-nous ici.", "s_arreter"],
	["Sors le train d'atterrissage.", "sortir_train"],
	["Rentre le train.", "sortir_train"],
	["Replie les ailes.", "ouvrir_ailes"],
	["Passe en vol vertical, on va se poser.", "vol_vertical"],
	["On va à quelle vitesse ?", "etat_vaisseau"],
	["Quelle est notre altitude ?", "etat_vaisseau"],
	["Raconte-moi une blague.", ""],
]
const THREADS := 2   # cœurs de calcul laissés à l'IA (le PC en a 4 : on en garde pour le jeu)

var texte: RichTextLabel
var saisie: LineEdit
var cube: MeshInstance3D
var chat = null
var modele_actuel := -1
var appels: PackedStringArray = []
var occupe := false
var pire_image_ms := 0.0          # image la plus lente pendant que l'IA réfléchit
var images_pendant := 0
var temps_pendant := 0.0
var resultats := PackedStringArray()


func _ready() -> void:
	_creer_scene()
	if not ClassDB.class_exists("NobodyWhoChat"):
		_ecrire("[color=#ff6b6b]L'extension NobodyWho n'est pas installée[/color] (dossier addons/nobodywho). Voir LISEZMOI-banc-ia.md.")
		return
	_ecrire("[b]Banc d'essai du droïde[/b]\n1 : essai complet avec %s    2 : essai complet avec %s\nOu tape un ordre en bas puis Entrée (après un essai).\nAu premier lancement, le modèle se télécharge (200 à 400 Mo) : patiente." % [MODELES[0][0], MODELES[1][0]])


func _creer_scene() -> void:
	# un cube qui tourne : s'il saccade pendant que l'IA réfléchit, le jeu saccaderait aussi
	var vue := SubViewportContainer.new()
	vue.stretch = true
	vue.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vue)
	var sv := SubViewport.new()
	vue.add_child(sv)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	sv.add_child(cam)
	var lum := DirectionalLight3D.new()
	lum.rotation = Vector3(-0.6, 0.6, 0)
	sv.add_child(lum)
	cube = MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	cube.position = Vector3(1.6, 0.8, 0)
	sv.add_child(cube)
	texte = RichTextLabel.new()
	texte.bbcode_enabled = true
	texte.scroll_following = true
	texte.set_anchors_preset(Control.PRESET_FULL_RECT)
	texte.offset_left = 20
	texte.offset_top = 15
	texte.offset_right = -20
	texte.offset_bottom = -60
	add_child(texte)
	saisie = LineEdit.new()
	saisie.placeholder_text = "Ordre au droïde…"
	saisie.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	saisie.offset_left = 20
	saisie.offset_right = -20
	saisie.offset_top = -45
	saisie.offset_bottom = -10
	saisie.text_submitted.connect(_ordre_libre)
	add_child(saisie)


func _process(delta: float) -> void:
	cube.rotate_y(delta * 1.5)
	cube.rotate_x(delta * 0.7)
	if occupe:
		pire_image_ms = maxf(pire_image_ms, delta * 1000.0)
		images_pendant += 1
		temps_pendant += delta


func _unhandled_input(e: InputEvent) -> void:
	if occupe or not (e is InputEventKey and e.is_pressed()) or saisie.has_focus():
		return
	match (e as InputEventKey).keycode:
		KEY_1, KEY_KP_1: _essai_complet(0)
		KEY_2, KEY_KP_2: _essai_complet(1)


func _ecrire(t: String) -> void:
	texte.append_text(t + "\n")
	print(t.replace("[b]", "").replace("[/b]", ""))


# --- fonctions du vaisseau (factices : elles notent seulement l'appel) ---
func stabiliser() -> String:
	appels.append("stabiliser")
	return "Stabilisateur activé."

func garder_cap() -> String:
	appels.append("garder_cap")
	return "Pilote automatique : cap gardé."

func s_arreter() -> String:
	appels.append("s_arreter")
	return "Pilote automatique : freinage jusqu'à l'arrêt."

func sortir_train(sortir: bool) -> String:
	appels.append("sortir_train")
	return "Train sorti." if sortir else "Train rentré."

func ouvrir_ailes(ouvrir: bool) -> String:
	appels.append("ouvrir_ailes")
	return "Ailes ouvertes." if ouvrir else "Ailes repliées."

func vol_vertical(actif: bool) -> String:
	appels.append("vol_vertical")
	return "Vol vertical activé." if actif else "Vol vertical arrêté."

func etat_vaisseau() -> String:
	appels.append("etat_vaisseau")
	return "Vitesse 152 m/s, altitude 3 200 m, 1,0 g ressenti, train rentré, ailes ouvertes."


func _outils() -> Array:
	return [
		ClassDB.class_call_static("NobodyWhoTool", "create", stabiliser, "Freine la rotation du vaisseau (stabilisateur)."),
		ClassDB.class_call_static("NobodyWhoTool", "create", garder_cap, "Pilote automatique : garde le nez du vaisseau dans la direction actuelle."),
		ClassDB.class_call_static("NobodyWhoTool", "create", s_arreter, "Pilote automatique : freine jusqu'à l'arrêt complet (vol stationnaire près d'une planète)."),
		ClassDB.class_call_static("NobodyWhoTool", "create", sortir_train, "Sort (true) ou rentre (false) le train d'atterrissage."),
		ClassDB.class_call_static("NobodyWhoTool", "create", ouvrir_ailes, "Ouvre (true) ou replie (false) les ailes."),
		ClassDB.class_call_static("NobodyWhoTool", "create", vol_vertical, "Active (true) ou arrête (false) le vol vertical, pour décoller ou se poser."),
		ClassDB.class_call_static("NobodyWhoTool", "create", etat_vaisseau, "Donne l'état du vaisseau : vitesse, altitude, forces G, train, ailes."),
	]


func _charger(i: int) -> bool:
	if modele_actuel == i and chat != null:
		return true
	_ecrire("\n[b]Chargement de %s[/b] (téléchargement au premier lancement)…" % MODELES[i][0])
	var debut := Time.get_ticks_msec()
	var options := {
		"system_prompt": CONSIGNE,
		"tools": _outils(),
		"n_ctx": 2048,
		"n_threads": THREADS,
		"use_gpu": false,
		"sampler": ClassDB.class_call_static("NobodyWhoSamplerPresets", "greedy"),
		"template_variables": {"enable_thinking": false},
	}
	var chemin: String = MODELES[i][2]
	if FileAccess.file_exists(MODELES[i][1]):
		chemin = ProjectSettings.globalize_path(MODELES[i][1])
		_ecrire("Fichier trouvé : %s" % chemin)
	else:
		_ecrire("Fichier %s absent : téléchargement automatique." % MODELES[i][1])
	occupe = true
	chat = await ClassDB.class_call_static("NobodyWhoChat", "create", chemin, options)
	occupe = false
	if chat == null:
		_ecrire("[color=#ff6b6b]Échec du chargement[/color] (voir l'onglet Erreurs de Godot).")
		return false
	modele_actuel = i
	_ecrire("Chargé en %.1f s." % ((Time.get_ticks_msec() - debut) / 1000.0))
	return true


## Envoie un ordre, renvoie [réponse, durée en s, fonctions appelées].
func _demander(ordre: String) -> Array:
	appels.clear()
	await chat.reset_history()
	pire_image_ms = 0.0
	images_pendant = 0
	temps_pendant = 0.0
	occupe = true
	var debut := Time.get_ticks_msec()
	var flux = await chat.ask(ordre)
	var reponse = null
	if flux != null:
		reponse = await flux.completed()
	occupe = false
	return [str(reponse) if reponse != null else "(pas de réponse)", (Time.get_ticks_msec() - debut) / 1000.0, appels.duplicate()]


func _essai_complet(i: int) -> void:
	if not await _charger(i):
		return
	var bons := 0
	var total_s := 0.0
	var pire_s := 0.0
	var pire_img := 0.0
	var ips_total := 0.0
	_ecrire("[b]Essai de %d ordres avec %s (%d cœurs)[/b]" % [ORDRES.size(), MODELES[i][0], THREADS])
	for o in ORDRES:
		var r: Array = await _demander(o[0])
		var fonctions: PackedStringArray = r[2]
		var attendu: String = o[1]
		var ok: bool = (attendu == "" and fonctions.is_empty()) or (attendu != "" and attendu in fonctions)
		if ok:
			bons += 1
		total_s += r[1]
		pire_s = maxf(pire_s, r[1])
		pire_img = maxf(pire_img, pire_image_ms)
		var ips := images_pendant / maxf(temps_pendant, 0.001)
		ips_total += ips
		_ecrire("%s « %s » → %s en %.1f s (%.0f images/s, pire image %.0f ms)\n      %s" % [
			"[color=#5fe08a][OK][/color]" if ok else "[color=#ff6b6b][RATÉ][/color]", o[0],
			", ".join(fonctions) if fonctions.size() else "aucune fonction", r[1], ips, pire_image_ms, r[0].strip_edges()])
	var bilan := "%s : %d / %d ordres compris, %.1f s en moyenne (pire %.1f s), %.0f images/s en moyenne pendant la réflexion, pire image %.0f ms." % [
		MODELES[i][0], bons, ORDRES.size(), total_s / ORDRES.size(), pire_s, ips_total / ORDRES.size(), pire_img]
	_ecrire("[b]BILAN %s[/b]\n" % bilan)
	resultats.append(bilan)
	var f := FileAccess.open("user://banc_ia_resultats.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(resultats) + "\n")
		_ecrire("(Résultats enregistrés dans %s)" % ProjectSettings.globalize_path("user://banc_ia_resultats.txt"))


func _ordre_libre(t: String) -> void:
	saisie.clear()
	if occupe or t.strip_edges() == "":
		return
	if chat == null and not await _charger(0):
		return
	var r: Array = await _demander(t)
	var fonctions: PackedStringArray = r[2]
	_ecrire("« %s » → %s en %.1f s\n      %s" % [t, ", ".join(fonctions) if fonctions.size() else "aucune fonction", r[1], str(r[0]).strip_edges()])
