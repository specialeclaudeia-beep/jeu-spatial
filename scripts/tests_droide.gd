extends Node
## Tests du droïde R-7 (à part des tests de physique).
## 1) Sans IA : chaque fonction du droïde agit bien sur le vrai vaisseau et le vrai pilote auto.
## 2) Avec le vrai modèle Qwen3 (si l'extension et le fichier sont là) : il choisit la bonne
##    fonction pour une liste d'ordres en français. Lent (environ 6 s par ordre).
## Ligne de commande :
##   Godot_console.exe --headless --path . res://scenes/tests_droide.tscn
##   (ajouter -- --sans-ia pour ne faire que la partie 1)

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const PiloteAuto = preload("res://scripts/physique/pilote_auto.gd")
const Droide = preload("res://scripts/droide.gd")

## ordre, fonction attendue ("" = aucune), argument attendu (null = ne pas vérifier)
const ORDRES := [
	["Stabilise le vaisseau, on tourne dans tous les sens !", "stabiliser:true", null],
	["Garde le cap.", "garder_cap", null],
	["Arrête-nous ici.", "s_arreter", null],
	["Pose-nous sur la planète.", "atterrir", null],
	["Atterris.", "atterrir", null],
	["Sors le train d'atterrissage.", "sortir_train:true", null],
	["Rentre le train.", "sortir_train:false", null],
	["Replie les ailes.", "ouvrir_ailes:false", null],
	["Passe en vol vertical, on va se poser.", "vol_vertical:true", null],
	["On va à quelle vitesse ?", "question:vitesse", null],
	["Quelle est notre altitude ?", "question:altitude", null],
	["Combien de g on prend ?", "question:g", null],
	["Le train est sorti ?", "question:train|question:tout", null],
	["Coupe le pilote automatique, je reprends la main.", "couper_pilote_auto", null],
	["Raconte-moi une blague.", "", null],
]


class FauxJeu extends Node:
	var vaisseau
	var ordinateur
	var stabilisateur := false
	var ecran_touches = null


var reussis := 0
var rates := 0


func _ready() -> void:
	var jeu := FauxJeu.new()
	jeu.vaisseau = VaisseauPhysique.new()
	jeu.vaisseau.gm = 9.81 * 600000.0 * 600000.0
	jeu.vaisseau.rayon_planete = 600000.0
	jeu.vaisseau.placer_en_orbite(100000.0)
	jeu.ordinateur = PiloteAuto.new()
	add_child(jeu)
	var d = Droide.new()
	add_child(d)
	d.installer(jeu, null, null)
	_partie_sans_ia(d, jeu)
	if "--sans-ia" in OS.get_cmdline_user_args():
		await _partie_dans_le_jeu()
		_fin()
		return
	await _partie_avec_ia(d, jeu)
	await _partie_dans_le_jeu()
	_fin()


## 3) Dans le vrai jeu : le droïde est bien branché, et le clavier est ignoré pendant qu'on lui écrit.
func _partie_dans_le_jeu() -> void:
	print("--- Droïde dans le vrai jeu ---")
	var j = (load("res://scenes/jeu.tscn") as PackedScene).instantiate()
	add_child(j)
	_verifier("le jeu crée le droïde", j.droide != null)
	_verifier("le droïde trouve sa tête dans le modèle 3D", j.droide.tete != null)
	j.droide.ouvrir_saisie(true)
	var gaz_avant: float = j.gaz
	Input.action_press("gaz_plus")
	for i in 30:
		await get_tree().physics_frame
	Input.action_release("gaz_plus")
	_verifier("saisie ouverte : Z (poussée) ignoré", j.gaz == gaz_avant, "gaz %.2f" % j.gaz)
	j.droide.ouvrir_saisie(false)
	Input.action_press("gaz_plus")
	for i in 30:
		await get_tree().physics_frame
	Input.action_release("gaz_plus")
	_verifier("saisie fermée : Z remarche", j.gaz > gaz_avant)
	if ClassDB.class_exists("NobodyWhoChat") and FileAccess.file_exists(Droide.MODELE) and not "--sans-ia" in OS.get_cmdline_user_args():
		var ok: bool = await j.droide.charger()
		if ok:
			await j.droide.ordonner("Sors le train d'atterrissage.")
			_verifier("dans le jeu, « Sors le train » sort le vrai train", j.vaisseau.train_consigne == 1.0)
			await j.droide.ordonner("Garde le cap.")
			_verifier("dans le jeu, « Garde le cap » active le vrai pilote auto", j.ordinateur.mode == PiloteAuto.CAP)
	j.queue_free()


func _verifier(nom: String, ok: bool, detail := "") -> void:
	if ok:
		reussis += 1
		print("[OK]    ", nom)
	else:
		rates += 1
		print("[RATÉ]  ", nom, "  ", detail)


func _partie_sans_ia(d, jeu) -> void:
	print("--- Droïde, sans IA ---")
	d.garder_cap()
	_verifier("garder_cap active le mode CAP", jeu.ordinateur.mode == PiloteAuto.CAP)
	d.s_arreter()
	_verifier("s_arreter active le mode ARRET", jeu.ordinateur.mode == PiloteAuto.ARRET)
	d.atterrir()
	_verifier("atterrir active le mode ATTERRIR", jeu.ordinateur.mode == PiloteAuto.ATTERRIR)
	d.couper_pilote_auto()
	_verifier("couper_pilote_auto rend la main", jeu.ordinateur.mode == PiloteAuto.AUCUN)
	d.sortir_train(true)
	_verifier("sortir_train(true)", jeu.vaisseau.train_consigne == 1.0)
	d.sortir_train(false)
	_verifier("sortir_train(false)", jeu.vaisseau.train_consigne == 0.0)
	d.ouvrir_ailes(false)
	_verifier("ouvrir_ailes(false)", jeu.vaisseau.ailes_consigne == 0.0)
	d.ouvrir_ailes(true)
	d.vol_vertical(true)
	_verifier("vol_vertical(true)", jeu.vaisseau.vertical_consigne == 1.0)
	d.vol_vertical(false)
	d.stabiliser(true)
	_verifier("stabiliser(true)", jeu.stabilisateur == true)
	d.stabiliser(false)
	var alt: String = d.question("altitude")
	_verifier("question(altitude) donne 100 km", alt.contains("100 km"), alt)
	var vit: String = d.question("vitesse")
	_verifier("question(vitesse) donne la vitesse orbitale", vit.contains("%.0f m/s" % jeu.vaisseau.vitesse()), vit)
	var tout: String = d.question("n'importe quoi")
	_verifier("sujet inconnu : état complet", tout.contains("Altitude") and tout.contains("Train"), tout)
	_verifier("nettoyer enlève <think>", Droide.nettoyer("<think>\nhmm\n</think>\n\nTrain sorti.") == "Train sorti.")
	_verifier("rattrape un appel écrit en texte", d.rattraper('{"name": "question", "arguments": {"sujet": "altitude"}}').contains("100 km"))
	d.rattraper('<tool_call>{"name": "sortir_train", "arguments": {"sortir": false}')
	_verifier("rattrape un appel coupé (train rentré)", jeu.vaisseau.train_consigne == 0.0 and "sortir_train:false" in d.appels)
	_verifier("rattrape <question>g</question>", d.rattraper("<question>g</question>").contains(" g."))
	d.action_outil("ailes", "replier")
	_verifier("ailes : replier", jeu.vaisseau.ailes_consigne == 0.0)
	d.action_outil("ailes", "ouvrir")
	_verifier("ailes : ouvrir", jeu.vaisseau.ailes_consigne == 1.0)
	d.action_outil("train", "sortir")
	d.action_outil("train", "rentrer")
	_verifier("train : rentrer", jeu.vaisseau.train_consigne == 0.0)
	_verifier("sens : « Rentre le train. »", Droide.sens_ordre("Rentre le train.") == -1)
	_verifier("sens : « Sors le train d'atterrissage. »", Droide.sens_ordre("Sors le train d'atterrissage.") == 1)
	_verifier("sens : « Passe en vol vertical, on va se poser. »", Droide.sens_ordre("Passe en vol vertical, on va se poser.") == 1)
	_verifier("sens : « Replie les ailes »", Droide.sens_ordre("Replie les ailes") == -1)
	_verifier("sens : « Coupe le stabilisateur »", Droide.sens_ordre("Coupe le stabilisateur") == -1)
	_verifier("sens : « Le train ? » pas clair", Droide.sens_ordre("Le train ?") == 0)
	d.ordre_en_cours = "Rentre le train."
	d.action_outil("train", "sortir")
	_verifier("le verbe de l'ordre corrige le sens choisi par l'IA", jeu.vaisseau.train_consigne == 0.0)
	d.ordre_en_cours = ""
	_verifier("atterrissage : « Atterris. »", Droide.est_atterrissage("Atterris."))
	_verifier("atterrissage : « Pose-nous sur la planète. »", Droide.est_atterrissage("Pose-nous sur la planète."))
	_verifier("pas atterrissage : « Sors le train d'atterrissage. »", not Droide.est_atterrissage("Sors le train d'atterrissage."))
	_verifier("pas atterrissage : « On atterrit quand ? »", not Droide.est_atterrissage("On atterrit quand ?"))
	_verifier("texte normal : rien à rattraper", d.rattraper("Bonjour pilote.") == "")
	_verifier("tous les sujets ont une réponse", Droide.SUJETS.all(func(s): return d.etat(s) != ""))


func _partie_avec_ia(d, jeu) -> void:
	print("--- Droïde, avec le vrai modèle ---")
	if not ClassDB.class_exists("NobodyWhoChat") or not FileAccess.file_exists(Droide.MODELE):
		print("(extension ou modèle absent : partie sautée)")
		return
	var debut := Time.get_ticks_msec()
	var ok_charge: bool = await d.charger()
	_verifier("chargement du modèle (%.1f s)" % ((Time.get_ticks_msec() - debut) / 1000.0), ok_charge)
	if not ok_charge:
		return
	var bons := 0
	var total := 0.0
	for o in ORDRES:
		jeu.ordinateur.activer(PiloteAuto.AUCUN, jeu.vaisseau)
		var t0 := Time.get_ticks_msec()
		var rep: String = await d.ordonner(o[0])
		var s := (Time.get_ticks_msec() - t0) / 1000.0
		total += s
		var attendu: String = o[1]
		var ok: bool = (attendu == "" and d.appels.is_empty()) or (attendu != "" and Array(attendu.split("|")).any(func(a): return a in d.appels))
		if ok:
			bons += 1
		print("%s « %s » → %s en %.1f s : %s" % ["[OK]  " if ok else "[RATÉ]", o[0],
			", ".join(d.appels) if d.appels.size() else "aucune", s, rep])
	print("BILAN IA : %d / %d ordres compris, %.1f s en moyenne" % [bons, ORDRES.size(), total / ORDRES.size()])
	# on exige au moins 12 ordres sur 13 (le petit modèle n'est pas parfait)
	_verifier("au moins 13 ordres sur %d compris (%d)" % [ORDRES.size(), bons], bons >= 13)


func _fin() -> void:
	print("=== Droïde : %d réussis, %d ratés ===" % [reussis, rates])
	get_tree().quit(0 if rates == 0 else 1)
