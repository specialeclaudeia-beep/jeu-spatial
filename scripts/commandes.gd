extends RefCounted
## Commandes du pilote, au clavier et à la manette (PS5 DualSense ou autre).
## Chaque action a une touche de clavier et un bouton (ou un stick) de manette, que le joueur
## peut changer dans l'écran de configuration (F2, ou Options sur la manette).
## Les réglages sont sauvegardés dans un petit fichier et rechargés à chaque partie.
##
## Les commandes ne font que DEMANDER une poussée ou une rotation (de 0 à 1) : c'est la physique
## du vaisseau qui fait le reste. Les sticks et les gâchettes sont analogiques : pousser à moitié
## demande la moitié.
##
## Une liaison est écrite sous forme de petit texte :
##   "l:90"     touche du clavier, repérée par ce qui est écrit dessus (ici Z, même en AZERTY)
##   "p:4194320" touche repérée par sa place sur le clavier (flèches, chiffres, F1…)
##   "b:0"      bouton de manette n° 0 (Croix sur une manette PlayStation)
##   "a:1:-1"   stick ou gâchette : axe n° 1, côté négatif (stick gauche vers le haut)
##   ""         rien

const FICHIER := "user://commandes.cfg"
## Numéro de la disposition par défaut. Quand il change (nouvelle disposition proposée),
## une sauvegarde plus ancienne est ignorée, pour ne pas mélanger l'ancienne et la nouvelle.
const VERSION_DISPOSITION := 2
const ZONE_MORTE := 0.1        # au repos, un stick n'est jamais pile au centre : en dessous de 10 %, on ignore
const SEUIL_CAPTURE := 0.6     # pour choisir un stick dans l'écran, il faut le pousser franchement

## Toutes les actions, dans l'ordre de l'écran de configuration.
## [nom interne, titre affiché, clavier par défaut, manette par défaut]
const ACTIONS := [
	["gaz_plus", "Plus de poussée", "l:90", "a:5:1"],                 # Z, R2
	["gaz_moins", "Moins de poussée", "l:83", "a:4:1"],               # S, L2
	["couper_gaz", "Couper la poussée", "l:32", "b:0"],               # Espace, Croix
	["tangage_haut", "Tangage : nez en haut", "p:4194320", "a:1:-1"], # flèche haut, stick gauche haut
	["tangage_bas", "Tangage : nez en bas", "p:4194322", "a:1:1"],    # flèche bas, stick gauche bas
	["lacet_gauche", "Lacet : tourner à gauche", "l:81", "b:9"],      # Q, L1
	["lacet_droite", "Lacet : tourner à droite", "l:68", "b:10"],     # D, R1
	["roulis_gauche", "Roulis : pencher à gauche", "l:65", "a:0:-1"], # A, stick gauche gauche
	["roulis_droite", "Roulis : pencher à droite", "l:69", "a:0:1"],  # E, stick gauche droite
	["stabilisateur", "Stabilisateur de rotation", "l:84", "b:3"],   # T, Triangle
	["pilote_cap", "Pilote auto : garder le cap", "l:75", ""],        # K
	["pilote_arret", "Pilote auto : s'arrêter", "l:78", ""],          # N
	["pilote_atterrir", "Pilote auto : atterrir", "l:76", ""],        # L
	["ailes", "Ouvrir / replier les ailes", "l:88", "b:11"],         # X, croix directionnelle haut
	["train", "Sortir / rentrer le train", "l:71", "b:12"],          # G, croix directionnelle bas
	["frein", "Freins des roues (au sol, maintenir)", "p:4194325", ""],   # Maj
	["vue", "Vue cockpit / extérieure", "l:86", "b:20"],             # V, pavé tactile
	["vol_vertical", "Vol vertical (décollage / atterrissage)", "l:70", "b:15"],  # F, bouton micro
	["pause", "Pause", "l:80", "b:2"],                                # P, Carré
	["aide", "Cacher / montrer l'aide", "l:72", "b:1"],               # H, Rond
	["recommencer", "Recommencer", "l:82", "b:4"],                    # R, Créer
	["remettre_orbite", "Remettre en orbite", "l:79", ""],            # O
	["atelier", "Retour à l'atelier (recharge l'atelier)", "p:4194334", ""],   # F3
	["temps_x1", "Temps x1", "p:49", ""],                             # 1
	["temps_x10", "Temps x10", "p:50", ""],                           # 2
	["temps_x100", "Temps x100", "p:51", ""],                         # 3
	["temps_x1000", "Temps x1000", "p:52", ""],                       # 4
	["temps_x10000", "Temps x10 000", "p:53", ""],                     # 5
	["temps_x100000", "Temps x100 000", "p:54", ""],                   # 6
	["temps_x1000000", "Temps x1 million (loin des astres)", "p:57", ""],        # 9
	["temps_x10000000", "Temps x10 millions (loin des astres)", "p:48", ""],     # 0
	["poussee_moins", "Puissance des moteurs : moins (÷10)", "p:55", ""],   # 7
	["poussee_plus", "Puissance des moteurs : plus (x10)", "p:56", ""],     # 8
	["temps_moins", "Temps moins rapide", "", "b:13"],                # croix directionnelle gauche
	["temps_plus", "Temps plus rapide", "", "b:14"],                  # croix directionnelle droite
	["regard_gauche", "Tourner la tête à gauche", "", "a:2:-1"],      # stick droit gauche
	["regard_droite", "Tourner la tête à droite", "", "a:2:1"],       # stick droit droite
	["regard_haut", "Lever la tête", "", "a:3:-1"],                   # stick droit haut
	["regard_bas", "Baisser la tête", "", "a:3:1"],                   # stick droit bas
	["regard_centre", "Regarder droit devant", "l:67", "b:8"],        # C, R3
	["phares", "Projecteur du vaisseau", "l:74", ""],                  # J
	["visiere", "Casque : visière claire / solaire / sans casque", "l:85", ""],   # U
	["tete_g", "Tête qui bouge avec les G (oui / non)", "l:73", ""],   # I
	["toile", "Toile de l'espace : la courbure d'Einstein (oui / non)", "l:89", ""],   # Y
	["trou_noir", "Aller au trou noir Gaia BH1 (saut d'essai)", "l:77", ""],          # M
	["trou_de_ver", "Aller au trou de ver (saut d'essai, il mène à Alpha du Centaure)", "l:87", ""],   # W
	["zoom", "Zoom (lire les instruments)", "l:66", "b:7"],          # B, L3 (maintenir)
	["tests", "Tests de physique", "p:4194332", ""],                  # F1
	["ecran_touches", "Configurer les commandes", "p:4194333", "b:6"], # F2, Options
]

## Actions qui varient en douceur (sticks, gâchettes) : les autres sont de simples appuis.
const ANALOGIQUES := ["gaz_plus", "gaz_moins", "tangage_haut", "tangage_bas",
	"lacet_gauche", "lacet_droite", "roulis_gauche", "roulis_droite",
	"regard_gauche", "regard_droite", "regard_haut", "regard_bas"]

const NOMS_BOUTONS := {
	0: "Croix", 1: "Rond", 2: "Carré", 3: "Triangle", 4: "Créer", 5: "PS", 6: "Options",
	7: "L3", 8: "R3", 9: "L1", 10: "R1",
	11: "Croix dir. ↑", 12: "Croix dir. ↓",
	13: "Croix dir. ←", 14: "Croix dir. →",
	15: "Micro", 20: "Pavé tactile",
}

## liaisons[nom] = {"clavier": "...", "manette": "..."}
var liaisons: Dictionary = {}


func _init() -> void:
	remettre_par_defaut()


func remettre_par_defaut() -> void:
	liaisons.clear()
	for a in ACTIONS:
		liaisons[a[0]] = {"clavier": a[2], "manette": a[3]}


static func titre(nom: String) -> String:
	for a in ACTIONS:
		if a[0] == nom:
			return a[1]
	return nom


## Donne une touche / un bouton / un stick à une action ("clavier" ou "manette").
## Si une autre action l'utilisait déjà, elle le perd (pour éviter qu'un bouton fasse deux choses).
## Renvoie le titre de l'action qui l'a perdu, ou "".
func assigner(nom: String, genre: String, code: String) -> String:
	var perdu := ""
	if code != "":
		for autre in liaisons:
			if autre != nom and liaisons[autre][genre] == code:
				liaisons[autre][genre] = ""
				perdu = titre(autre)
	liaisons[nom][genre] = code
	return perdu


# =====================================================================
# TRADUCTIONS : événement ↔ texte ↔ nom lisible
# =====================================================================

## Transforme ce que le joueur vient d'appuyer en texte de liaison ("" si ce n'est pas utilisable).
static func code_depuis_evenement(e: InputEvent) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		if k.key_label != KEY_NONE:
			return "l:%d" % k.key_label
		if k.physical_keycode != KEY_NONE:
			return "p:%d" % k.physical_keycode
	elif e is InputEventJoypadButton:
		return "b:%d" % (e as InputEventJoypadButton).button_index
	elif e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		if absf(m.axis_value) >= SEUIL_CAPTURE:
			return "a:%d:%d" % [m.axis, 1 if m.axis_value > 0.0 else -1]
	return ""


## Fabrique l'événement que Godot reconnaîtra (null si la liaison est vide ou abîmée).
static func evenement_depuis_code(code: String) -> InputEvent:
	var morceaux := code.split(":")
	if morceaux.size() < 2 or not morceaux[1].is_valid_int():
		return null
	var n := morceaux[1].to_int()
	match morceaux[0]:
		"l":
			var k := InputEventKey.new()
			k.key_label = n as Key
			k.device = -1
			return k
		"p":
			var k := InputEventKey.new()
			k.physical_keycode = n as Key
			k.device = -1
			return k
		"b":
			var b := InputEventJoypadButton.new()
			b.button_index = n as JoyButton
			b.device = -1
			return b
		"a":
			if morceaux.size() < 3 or not morceaux[2].is_valid_int():
				return null
			var m := InputEventJoypadMotion.new()
			m.axis = n as JoyAxis
			m.axis_value = 1.0 if morceaux[2].to_int() > 0 else -1.0
			m.device = -1
			return m
	return null


## Nom à afficher pour le joueur.
static func nom_lisible(code: String) -> String:
	if code == "":
		return "—"
	var morceaux := code.split(":")
	var n := morceaux[1].to_int() if morceaux.size() > 1 else 0
	match morceaux[0]:
		"l":
			return _nom_touche(n)
		"p":
			# on montre ce qui est écrit sur la touche à cet endroit (clavier AZERTY ou autre)
			var etiquette := KEY_NONE
			if DisplayServer.get_name() != "headless":
				etiquette = DisplayServer.keyboard_get_label_from_physical(n as Key)
			return _nom_touche(etiquette if etiquette != KEY_NONE else n)
		"b":
			return NOMS_BOUTONS.get(n, "Bouton %d" % n)
		"a":
			var positif := morceaux.size() > 2 and morceaux[2].to_int() > 0
			match n:
				JOY_AXIS_LEFT_X:
					return "Stick gauche → droite" if positif else "Stick gauche ← gauche"
				JOY_AXIS_LEFT_Y:
					return "Stick gauche ↓ bas" if positif else "Stick gauche ↑ haut"
				JOY_AXIS_RIGHT_X:
					return "Stick droit → droite" if positif else "Stick droit ← gauche"
				JOY_AXIS_RIGHT_Y:
					return "Stick droit ↓ bas" if positif else "Stick droit ↑ haut"
				JOY_AXIS_TRIGGER_LEFT:
					return "L2"
				JOY_AXIS_TRIGGER_RIGHT:
					return "R2"
			return "Axe %d %s" % [n, "+" if positif else "−"]
	return code


static func _nom_touche(k: int) -> String:
	match k:
		KEY_SPACE: return "Espace"
		KEY_UP: return "Flèche haut"
		KEY_DOWN: return "Flèche bas"
		KEY_LEFT: return "Flèche gauche"
		KEY_RIGHT: return "Flèche droite"
		KEY_ENTER: return "Entrée"
		KEY_SHIFT: return "Maj"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_TAB: return "Tab"
	return OS.get_keycode_string(k)


# =====================================================================
# MISE EN PLACE DANS GODOT, SAUVEGARDE
# =====================================================================

## Donne toutes les liaisons à Godot (à refaire après chaque changement).
func appliquer() -> void:
	for a in ACTIONS:
		var nom: String = a[0]
		if InputMap.has_action(nom):
			InputMap.action_erase_events(nom)
		else:
			InputMap.add_action(nom, ZONE_MORTE)
		InputMap.action_set_deadzone(nom, ZONE_MORTE)
		for genre in ["clavier", "manette"]:
			var e := evenement_depuis_code(liaisons[nom][genre])
			if e != null:
				InputMap.action_add_event(nom, e)


func sauvegarder(chemin := FICHIER) -> bool:
	var f := ConfigFile.new()
	f.set_value("general", "version", VERSION_DISPOSITION)
	for nom in liaisons:
		f.set_value(nom, "clavier", liaisons[nom]["clavier"])
		f.set_value(nom, "manette", liaisons[nom]["manette"])
	return f.save(chemin) == OK


## Recharge les réglages sauvegardés. Une action absente du fichier (ajoutée dans une nouvelle
## version du jeu) garde sa liaison par défaut.
func charger(chemin := FICHIER) -> bool:
	remettre_par_defaut()
	var f := ConfigFile.new()
	if f.load(chemin) != OK:
		return false
	if f.get_value("general", "version", 1) != VERSION_DISPOSITION:
		return false   # sauvegarde d'une ancienne disposition : on repart de la nouvelle
	for nom in liaisons:
		for genre in ["clavier", "manette"]:
			var code = f.get_value(nom, genre, liaisons[nom][genre])
			if code is String and (code == "" or evenement_depuis_code(code) != null):
				liaisons[nom][genre] = code
	return true


## Résumé court pour l'aide à l'écran : « Z / R2 ».
func resume(nom: String) -> String:
	var morceaux := PackedStringArray()
	for genre in ["clavier", "manette"]:
		if liaisons[nom][genre] != "":
			morceaux.append(nom_lisible(liaisons[nom][genre]))
	return " / ".join(morceaux) if morceaux.size() > 0 else "—"
