extends Node
## Droïde R-7 : petite IA locale (Qwen3-0.6B, extension NobodyWho) qui comprend les ordres du
## pilote en français et appelle les fonctions du vaisseau.
##
## Il sert aux ordres CALMES (environ 6 s de réflexion sur ce PC) : le pilotage fin et les
## urgences restent aux touches. Il ne fait rien de magique : il appuie sur les mêmes
## commandes que le pilote (pilote auto, train, ailes, vol vertical, stabilisateur).
##
## Entrée : parler au droïde (Entrée pour envoyer, Échap pour annuler).
## Sans l'extension ou sans le fichier du modèle, le jeu marche normalement : le droïde le dit.

const PiloteAuto = preload("res://scripts/physique/pilote_auto.gd")
const MODELE := "res://ia/Qwen_Qwen3-0.6B-Q4_K_M.gguf"
const THREADS := 2              # cœurs de calcul laissés à l'IA (le PC en a 4 : on en garde pour le jeu)
const DUREE_BULLE := 10.0       # s d'affichage de la réponse
const CONSIGNE := "Tu es R-7, le droïde du vaisseau spatial. Le pilote te parle en français. " \
	+ "Quand il donne un ordre ou pose une question sur le vaisseau, appelle la fonction qui convient, " \
	+ "puis réponds en une phrase courte en français, avec les chiffres donnés par la fonction. " \
	+ "Si aucune fonction ne convient, dis-le simplement."
## Choix fixes de la fonction « question » (le modèle ne peut pas en inventer d'autres).
const SUJETS := ["vitesse", "altitude", "g", "orbite", "train", "ailes", "vol_vertical", "pilote_auto", "tout"]

var jeu                          # nœud du jeu : vaisseau, ordinateur, stabilisateur
var chat = null
var pret := false                # modèle chargé
var occupe := false              # en train de réfléchir
var ecrit := false               # la boîte de saisie est ouverte (le jeu ignore alors clavier et manette)
var en_attente := ""             # ordre reçu pendant qu'il réfléchissait
var appels: PackedStringArray = []   # fonctions appelées pour l'ordre en cours (pour les tests)
var derniere_reponse := ""
var ordre_en_cours := ""        # texte de l'ordre en cours (pour vérifier le sens : sortir ou rentrer…)
var tete: Node3D = null
var bras: Array = []             # [nœud, rotation de repos]
var _repos_tete := Vector3.ZERO
var _t := 0.0
var _bulle_reste := 0.0
var saisie: LineEdit
var bulle: Label


## couche : CanvasLayer du HUD (null dans les tests). modele_droide : nœud du modèle 3D (ou null).
func installer(le_jeu, couche: CanvasLayer, modele_droide: Node) -> void:
	jeu = le_jeu
	if modele_droide != null:
		tete = modele_droide.find_child("Droide_tete", true, false) as Node3D
		for n in modele_droide.find_children("Droide_bras_*", "Node3D", true, false):
			if not String(n.name).ends_with("_coude") and not String(n.name).ends_with("_epaule"):
				bras.append([n, n.rotation])
		if tete != null:
			_repos_tete = tete.rotation
	if couche == null:
		return
	bulle = Label.new()
	bulle.add_theme_font_size_override("font_size", 18)
	bulle.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	bulle.add_theme_color_override("font_outline_color", Color.BLACK)
	bulle.add_theme_constant_override("outline_size", 6)
	bulle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bulle.anchor_left = 0.5
	bulle.anchor_right = 0.5
	bulle.anchor_top = 1.0
	bulle.anchor_bottom = 1.0
	bulle.offset_left = -330
	bulle.offset_right = 330
	bulle.offset_top = -150
	bulle.offset_bottom = -70
	bulle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	couche.add_child(bulle)
	saisie = LineEdit.new()
	saisie.placeholder_text = "Ordre au droïde R-7 (Entrée pour envoyer, Échap pour annuler)"
	saisie.anchor_left = 0.5
	saisie.anchor_right = 0.5
	saisie.anchor_top = 1.0
	saisie.anchor_bottom = 1.0
	saisie.offset_left = -330
	saisie.offset_right = 330
	saisie.offset_top = -62
	saisie.offset_bottom = -28
	saisie.visible = false
	saisie.text_submitted.connect(_envoyer)
	couche.add_child(saisie)
	if not ClassDB.class_exists("NobodyWhoChat"):
		_dire("R-7 hors ligne : extension NobodyWho absente (addons/nobodywho).")
	elif not FileAccess.file_exists(MODELE):
		_dire("R-7 hors ligne : fichier %s absent." % MODELE)
	else:
		# Le modèle (≈ 400 Mo, 2 cœurs) n'est chargé qu'au premier ordre (touche Entrée) : tant que
		# personne ne parle à R-7, il ne prend ni mémoire ni temps au jeu.
		_dire("R-7 en veille. Appuie sur Entrée pour lui parler.")


# =====================================================================
# CHARGEMENT ET QUESTIONS AU MODÈLE
# =====================================================================
func charger() -> bool:
	while occupe and not pret:   # déjà en train de charger (ouverture de la saisie) : on attend
		await get_tree().process_frame
	if pret:
		return true
	if not ClassDB.class_exists("NobodyWhoChat") or not FileAccess.file_exists(MODELE):
		return false
	occupe = true
	_dire("R-7 s'allume…")
	var options := {
		"system_prompt": CONSIGNE,
		"tools": outils(),
		"n_ctx": 2048,
		"n_threads": THREADS,
		"use_gpu": false,
		"sampler": ClassDB.class_call_static("NobodyWhoSamplerPresets", "greedy"),
		"template_variables": {"enable_thinking": false},
	}
	chat = await ClassDB.class_call_static("NobodyWhoChat", "create", ProjectSettings.globalize_path(MODELE), options)
	occupe = false
	pret = chat != null
	_dire("R-7 prêt. Appuie sur Entrée pour lui parler." if pret else "R-7 : échec du chargement du modèle.")
	if pret and en_attente != "":
		var o := en_attente
		en_attente = ""
		ordonner(o)
	return pret


## Envoie un ordre au droïde. Renvoie la réponse (texte). Un seul ordre à la fois : un ordre reçu
## pendant la réflexion attend son tour (le plus récent remplace l'ancien).
func ordonner(ordre: String) -> String:
	ordre = ordre.strip_edges()
	if ordre == "":
		return ""
	if not pret:
		en_attente = ordre
		if not occupe:
			if not await charger():
				_dire("R-7 hors ligne.")
		return ""
	if occupe:
		en_attente = ordre
		_dire("R-7 : un instant, je termine l'ordre précédent.")
		return ""
	if est_atterrissage(ordre):
		# ordre d'atterrissage : reconnu directement (le petit modèle le confond avec le train ou
		# l'arrêt quand on lui donne une fonction de plus), donc réponse immédiate
		appels.clear()
		derniere_reponse = atterrir()
		_dire("R-7 : " + derniere_reponse)
		return derniere_reponse
	occupe = true
	appels.clear()
	ordre_en_cours = ordre
	_dire("R-7 réfléchit…")
	await chat.reset_history()      # chaque ordre est indépendant : réponse plus rapide
	var flux = await chat.ask(ordre)
	var reponse = null
	if flux != null:
		reponse = await flux.completed()
	occupe = false
	print("(R-7 brut) ", reponse)
	derniere_reponse = nettoyer(str(reponse) if reponse != null else "")
	if appels.is_empty():
		# le petit modèle écrit parfois l'appel en texte au lieu de le faire : on le rattrape
		var rattrape := rattraper(derniere_reponse)
		if rattrape != "":
			derniere_reponse = rattrape
		elif ordre.ends_with("?"):
			derniere_reponse = question("tout")   # une question sur le vaisseau : on donne tout l'état
		elif derniere_reponse.begins_with("<") or derniere_reponse.begins_with("{") or derniere_reponse == "":
			derniere_reponse = "Je n'ai pas compris. Pouvez-vous reformuler ?"
	_dire("R-7 : " + (derniere_reponse if derniere_reponse != "" else "…"))
	if en_attente != "":
		var o := en_attente
		en_attente = ""
		ordonner(o)
	return derniere_reponse


## Si le texte contient un appel de fonction écrit en toutes lettres
## ({"name": "...", "arguments": {...}}), l'exécute et renvoie son résultat ; sinon "".
func rattraper(t: String) -> String:
	var re := RegEx.create_from_string('"name"\\s*:\\s*"(\\w+)"')
	var m := re.search(t)
	if m == null:
		# autre forme vue : <question>sujet</question>
		var rt := RegEx.create_from_string('<(\\w+)>([^<]*)')
		for mt in rt.search_all(t):
			var n := mt.get_string(1)
			if n == "question":
				var sujet := mt.get_string(2).strip_edges()
				if sujet in SUJETS:
					return question(sujet)
			if n in ["garder_cap", "s_arreter", "atterrir", "couper_pilote_auto"]:
				return call(n)
		return ""
	var nom := m.get_string(1)
	var args := {}
	var ra := RegEx.create_from_string('"arguments"\\s*:\\s*(\\{[^}]*\\}?)')
	var ma := ra.search(t)
	if ma != null:
		var j := ma.get_string(1)
		if not j.ends_with("}"):
			j += "}"
		var lu = JSON.parse_string(j)
		if lu is Dictionary:
			args = lu
	var action := str(args.get("action", args.get("sortir", args.get("ouvrir", args.get("actif", "oui")))))
	match nom:
		"garder_cap": return garder_cap()
		"s_arreter": return s_arreter()
		"couper_pilote_auto": return couper_pilote_auto()
		"atterrir": return atterrir()
		"question": return question(args.get("sujet", "tout"))
		"pilote_auto": return mode_pilote(str(args.get("mode", "")))
	return action_outil(nom, action)


## Enlève la réflexion cachée éventuelle (<think>…</think>) et les espaces en trop.
static func nettoyer(t: String) -> String:
	var debut := t.find("<think>")
	while debut != -1:
		var fin := t.find("</think>", debut)
		t = t.substr(0, debut) + (t.substr(fin + 8) if fin != -1 else "")
		debut = t.find("<think>")
	return t.strip_edges()


# =====================================================================
# FONCTIONS DU VAISSEAU (appelées par le modèle)
# =====================================================================
func outils() -> Array:
	return [
		_outil_action("stabilisateur", "Le stabilisateur freine la rotation du vaisseau.", ["activer", "couper"]),
		ClassDB.class_call_static("NobodyWhoTool", "create", garder_cap, "Pilote automatique : garde le nez du vaisseau dans la direction actuelle."),
		ClassDB.class_call_static("NobodyWhoTool", "create", s_arreter, "Pilote automatique : freine jusqu'à l'arrêt complet (vol stationnaire près d'une planète)."),
		ClassDB.class_call_static("NobodyWhoTool", "create", couper_pilote_auto, "Coupe le pilote automatique : le pilote reprend les commandes."),
		_outil_action("train", "Sort ou rentre le train d'atterrissage.", ["sortir", "rentrer"]),
		_outil_action("ailes", "Ouvre ou replie les ailes.", ["ouvrir", "replier"]),
		_outil_action("vol_vertical", "Vol vertical, pour décoller ou se poser.", ["passer_en_vol_vertical", "revenir_au_vol_normal"]),
		ClassDB.class_call_static("NobodyWhoTool", "create_with_schema", "question",
			"Répond à toute question du pilote (quelle, combien, est-ce que…) sur l'état du vaisseau, y compris le train ou les ailes : ne change rien. Choisis le sujet.",
			{
				"type": "object",
				"properties": {
					"sujet": {
						"type": "string",
						"enum": SUJETS,
						"description": "vitesse, altitude, g (accélération ressentie, en g), orbite, train, ailes, vol_vertical, pilote_auto, ou tout (état complet).",
					},
				},
				"required": ["sujet"],
			},
			question),
	]


## Fonction à un seul choix « action » (ex. sortir / rentrer) : le petit modèle choisit mieux un
## mot proche de l'ordre du pilote qu'un vrai / faux.
func _outil_action(nom: String, description: String, choix: Array):
	return ClassDB.class_call_static("NobodyWhoTool", "create_with_schema", nom, description + " Choisis l'action.",
		{"type": "object", "properties": {"action": {"type": "string", "enum": choix}}, "required": ["action"]},
		func(action) -> String: return action_outil(nom, str(action)))


## Exécute une fonction à choix « action ». Le 2e choix de la liste (rentrer, replier, couper,
## arreter) veut dire « non » ; tout le reste veut dire « oui ».
func action_outil(nom: String, action: String) -> String:
	var non := action.to_lower().strip_edges() in ["rentrer", "replier", "couper", "arreter", "arrêter", "revenir_au_vol_normal", "false", "non"]
	# le petit modèle se trompe parfois de sens : si le verbe de l'ordre est clair, il a le dernier mot
	var sens := sens_ordre(ordre_en_cours)
	if sens != 0:
		non = sens < 0
	match nom:
		"stabilisateur", "stabiliser": return stabiliser(not non)
		"train", "sortir_train": return sortir_train(not non)
		"ailes", "ouvrir_ailes": return ouvrir_ailes(not non)
		"vol_vertical": return vol_vertical(not non)
	return ""


## Vrai si l'ordre demande d'atterrir (atterris, pose-nous, on se pose…), sans être une question.
static func est_atterrissage(ordre: String) -> bool:
	var o := ordre.to_lower()
	if o.strip_edges().ends_with("?"):
		return false
	for m in ["atterri", "pose-nous", "pose nous", "pose le vaisseau", "on se pose", "pose-toi", "pose toi"]:
		if o.contains(m) and not o.contains("train d'atterri"):
			return true
	return false


## Sens du verbe de l'ordre : 1 (sors, ouvre, active…), -1 (rentre, replie, coupe…), 0 (pas clair).
static func sens_ordre(ordre: String) -> int:
	var mots := ordre.to_lower().replace("'", " ").replace(",", " ").replace(".", " ").replace("!", " ").replace("?", " ").split(" ", false)
	var oui := 0
	var non := 0
	for m in mots:
		for r in ["rentr", "repli", "coup", "arrêt", "arret", "désactiv", "desactiv", "quitt", "étein", "etein", "ferm", "enlèv", "enlev"]:
			if m.begins_with(r):
				non += 1
		for r in ["sor", "ouvr", "ouvre", "activ", "pass", "allum", "déploi", "deploi", "mets", "met"]:
			if m.begins_with(r):
				oui += 1
	return signi(oui - non) if (oui == 0) != (non == 0) else 0


func stabiliser(actif: bool) -> String:
	appels.append("stabiliser:%s" % actif)
	jeu.stabilisateur = actif
	return "Stabilisateur activé." if actif else "Stabilisateur coupé."


func mode_pilote(m: String) -> String:
	match m:
		"garder_cap", "cap": return garder_cap()
		"s_arreter", "arreter", "arrêter": return s_arreter()
		"atterrir": return atterrir()
		"couper", "aucun": return couper_pilote_auto()
	return "Mode de pilote automatique inconnu."


func garder_cap() -> String:
	appels.append("garder_cap")
	jeu.ordinateur.activer(PiloteAuto.CAP, jeu.vaisseau)
	return "Pilote automatique : cap gardé."


func s_arreter() -> String:
	appels.append("s_arreter")
	if jeu.vaisseau.au_sol:
		return "Le vaisseau est déjà posé au sol."
	jeu.ordinateur.activer(PiloteAuto.ARRET, jeu.vaisseau)
	return "Pilote automatique : freinage jusqu'à l'arrêt."


func atterrir() -> String:
	appels.append("atterrir")
	if jeu.vaisseau.au_sol:
		return "Le vaisseau est déjà posé au sol."
	jeu.ordinateur.activer(PiloteAuto.ATTERRIR, jeu.vaisseau)
	return "Pilote automatique : atterrissage en cours."


func couper_pilote_auto() -> String:
	appels.append("couper_pilote_auto")
	jeu.ordinateur.activer(PiloteAuto.AUCUN, jeu.vaisseau)
	return "Pilote automatique coupé : à vous les commandes."


func sortir_train(sortir: bool) -> String:
	appels.append("sortir_train:%s" % sortir)
	jeu.vaisseau.sortir_train(sortir)
	return "Train sorti." if sortir else "Train rentré."


func ouvrir_ailes(ouvrir: bool) -> String:
	appels.append("ouvrir_ailes:%s" % ouvrir)
	jeu.vaisseau.ouvrir_ailes(ouvrir)
	return "Ailes ouvertes." if ouvrir else "Ailes repliées."


func vol_vertical(actif: bool) -> String:
	appels.append("vol_vertical:%s" % actif)
	jeu.vaisseau.passer_vol_vertical(actif)
	return "Vol vertical activé." if actif else "Vol vertical arrêté."


func question(sujet) -> String:
	appels.append("question:" + str(sujet))
	return etat(str(sujet))


## Texte de réponse pour un sujet (un sujet inconnu donne l'état complet).
func etat(sujet: String) -> String:
	var v = jeu.vaisseau
	var morceaux := {
		"vitesse": "Vitesse %.0f m/s (verticale %+.0f m/s, horizontale %.0f m/s)." % [v.vitesse(), v.vitesse_verticale(), v.vitesse_horizontale()],
		"altitude": "Altitude %s." % distance(v.altitude()),
		"g": "Accélération ressentie %.1f g." % (v.acceleration_ressentie.length() / 9.80665),
		"orbite": _orbite(v),
		"train": "Train %s." % ("sorti" if v.train_consigne >= 0.5 else "rentré"),
		"ailes": "Ailes %s." % ("ouvertes" if v.ailes_consigne >= 0.5 else "repliées"),
		"vol_vertical": "Vol vertical %s." % ("activé" if v.vertical_consigne >= 0.5 else "désactivé"),
		"pilote_auto": "Pilote automatique : %s. Stabilisateur %s." % [jeu.ordinateur.nom_mode(), "activé" if jeu.stabilisateur else "coupé"],
	}
	if morceaux.has(sujet):
		return morceaux[sujet]
	return " ".join([morceaux["vitesse"], morceaux["altitude"], morceaux["g"], morceaux["train"], morceaux["ailes"], morceaux["vol_vertical"], morceaux["pilote_auto"]])


func _orbite(v) -> String:
	if v.au_sol:
		return "Posé au sol."
	var o: Dictionary = v.orbite()
	if o["apo"] == INF:
		return "Trajectoire d'évasion."
	return "Orbite : périapside %s, apoapside %s." % [distance(o["peri"]), distance(o["apo"])]


static func distance(m: float) -> String:
	if absf(m) >= 10000.0:
		return "%.0f km" % (m / 1000.0)
	return "%.0f m" % m


# =====================================================================
# SAISIE, BULLE ET ANIMATION
# =====================================================================
func _unhandled_input(e: InputEvent) -> void:
	if saisie == null or ecrit or not (e is InputEventKey and e.is_pressed() and not e.is_echo()):
		return
	var k := (e as InputEventKey).keycode
	if (k == KEY_ENTER or k == KEY_KP_ENTER) and jeu.ecran_touches == null:
		ouvrir_saisie(true)
		get_viewport().set_input_as_handled()


func ouvrir_saisie(oui: bool) -> void:
	ecrit = oui
	saisie.visible = oui
	saisie.clear()
	if oui:
		saisie.grab_focus()
		if not pret and not occupe:
			charger()   # on commence à charger pendant que le pilote tape son ordre
	else:
		saisie.release_focus()


func _input(e: InputEvent) -> void:
	if ecrit and e is InputEventKey and e.is_pressed() and (e as InputEventKey).keycode == KEY_ESCAPE:
		ouvrir_saisie(false)
		get_viewport().set_input_as_handled()


func _envoyer(t: String) -> void:
	ouvrir_saisie(false)
	ordonner(t)


func _dire(t: String) -> void:
	print(t)
	if bulle != null:
		bulle.text = t
		_bulle_reste = DUREE_BULLE


func _process(delta: float) -> void:
	_t += delta
	if bulle != null and not occupe and _bulle_reste > 0.0:
		_bulle_reste -= delta
		if _bulle_reste <= 0.0:
			bulle.text = ""
	if tete == null:
		return
	# il réfléchit : la tête balaie lentement de gauche à droite et les bras bougent un peu ;
	# sinon, tout revient doucement au repos
	var k := minf(1.0, 4.0 * delta)
	if occupe:
		tete.rotation = tete.rotation.lerp(_repos_tete + Vector3(0, 0.6 * sin(_t * 1.3), 0), k)
	else:
		tete.rotation = tete.rotation.lerp(_repos_tete, k)
	for i in bras.size():
		var b: Array = bras[i]
		var voulu: Vector3 = b[1] + (Vector3(0.25 * sin(_t * 2.0 + i * PI), 0, 0) if occupe else Vector3.ZERO)
		(b[0] as Node3D).rotation = (b[0] as Node3D).rotation.lerp(voulu, k)
