extends SceneTree
## Générateur des sons du jeu (moteur audio, phase 1). À lancer dans le cloud (pas besoin sur le PC) :
##   godot --headless --path . --script res://outils/generateur_sons.gd
## Il fabrique par le calcul toutes les boucles et tous les coups de scripts/son/synthese.gd, les écrit dans
## res://sons/ (fichiers .wav) et décrit chacun dans res://sons/sons.json (niveau, durée, graine, part de
## chaque octave). Même graine = même fichier : on peut tout refaire à l'identique.

const Synthese = preload("res://scripts/son/synthese.gd")


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://sons/boucles"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://sons/coups"))
	var catalogue := {"taux": Synthese.TAUX, "boucles": {}, "coups": {}}
	for nom in Synthese.BOUCLES:
		var r: Array = Synthese.fabriquer_boucle(nom)
		var infos: Dictionary = r[1]
		Synthese.ecrire_wav(infos["fichier"], r[0])
		catalogue["boucles"][nom] = infos
		print("boucle %-10s %.1f s, %.1f dB eff., crête %.1f dB" % [nom, infos["duree"], infos["rms_dbfs"], infos["crete_dbfs"]])
	for nom in Synthese.COUPS:
		var liste := []
		for k in int(Synthese.COUPS[nom]["variantes"]):
			var r: Array = Synthese.fabriquer_coup(nom, k)
			var infos: Dictionary = r[1]
			Synthese.ecrire_wav(infos["fichier"], r[0])
			liste.append(infos)
		catalogue["coups"][nom] = liste
		print("coup %-16s %d variantes" % [nom, liste.size()])
	var f := FileAccess.open("res://sons/sons.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(catalogue, "\t"))
	f.close()
	print("Sons fabriqués en %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()
