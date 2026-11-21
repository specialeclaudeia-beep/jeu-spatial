extends SceneTree
## Enregistre de courts extraits du son du cockpit (pour écouter le moteur audio sans lancer le jeu).
## Ligne de commande :
##   godot --headless --path . --script res://outils/extraits_son.gd -- <dossier de sortie>
## Ajouter `--son-boucles` après le dossier pour entendre l'ancienne version (boucles de la phase 1) :
## on peut ainsi comparer avant / après la phase 2 (sons fabriqués en direct par la partie C++).
## Phase 3 : extraits 5 à 7 (se poser, rouler, freiner ; train et ailes ; sur le ventre).
## Chaque extrait est une petite scène jouée en vrai (la physique du vaisseau tourne, le moteur audio
## l'écoute) ; ce qui sort du bus Master est enregistré dans un fichier .wav.
## Les commandes (gaz, manche) sont rejouées par le script ; seul l'extrait « souffle » force la vitesse.

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const Atmosphere = preload("res://scripts/physique/atmosphere.gd")
const MoteurAudio = preload("res://scripts/son/moteur_audio.gd")
const Jeu = preload("res://scripts/jeu.gd")
const R := 600000.0
const GM := 9.81 * 600000.0 * 600000.0

const EXTRAITS := [
	["1-espace-petits-propulseurs", 11.0, "vide"],
	["2-espace-moteurs-a-fond", 9.0, "vide"],
	["3-air-depart-moteurs-a-fond", 10.0, "air_bas"],
	["4-air-souffle-de-30-a-600-ms", 10.0, "air_souffle"],
	# phase 3 : le sol et les vérins (sans air, pour n'entendre que la structure)
	["5-sol-pose-roulage-freins", 14.0, "sol"],
	["6-vide-train-et-ailes", 13.0, "vide"],
	["7-sol-sur-le-ventre", 8.0, "ventre"],
]

var dossier := "res://extraits"


class Pilotage extends Node:
	var v
	var nom := ""
	var t := 0.0

	func _physics_process(delta: float) -> void:
		t += delta
		var gaz := 0.0
		var tangage := 0.0
		var lacet := 0.0
		var roulis := 0.0
		match nom:
			"1-espace-petits-propulseurs":
				# petits coups de manche, puis les 5 moteurs à 30 % pendant 3 s
				if t > 1.0 and t < 1.35: roulis = 1.0
				elif t > 2.0 and t < 2.35: roulis = -1.0
				elif t > 3.0 and t < 3.6: tangage = 0.6
				elif t > 4.2 and t < 4.5: lacet = 1.0
				elif t > 4.5 and t < 4.8: lacet = -1.0
				elif t > 5.3 and t < 5.5: tangage = -1.0
				if t > 6.5 and t < 9.5: gaz = 0.3
			"2-espace-moteurs-a-fond":
				if t > 1.0 and t < 6.5: gaz = clampf((t - 1.0) / 2.0, 0.0, 1.0)
			"3-air-depart-moteurs-a-fond":
				if t > 1.0 and t < 8.5: gaz = 1.0
			"4-air-souffle-de-30-a-600-ms":
				var u := 30.0 * pow(20.0, clampf((t - 0.5) / 9.0, 0.0, 1.0))
				v.vx = 0.0
				v.vy = 0.0
				v.vz = -u
			"5-sol-pose-roulage-freins":
				# posé à 1,2 m/s en roulant à 50 m/s, roue avant qui braque un peu, freins à 5 s, arrêt
				v.braquage_consigne = 0.3 * sin(t * 0.8)
				v.frein = 0.6 if t > 5.0 else 0.0
			"6-vide-train-et-ailes":
				if t > 0.5 and t < 0.6: v.sortir_train(true)
				if t > 4.5 and t < 4.6: v.ouvrir_ailes(false)
				if t > 8.0 and t < 8.1: v.ouvrir_ailes(true)
				if t > 11.0 and t < 11.1: v.sortir_train(false)
		v.commander(gaz, tangage, lacet, roulis)
		v.pas(delta)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			dossier = a   # (--son-boucles est lu par le moteur audio lui-même)
	DirAccess.make_dir_recursive_absolute(dossier)
	_tout()


func _tout() -> void:
	await process_frame
	MoteurAudio.preparer_bus()
	var master := AudioServer.get_bus_index("Master")
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(master, rec)
	for e in EXTRAITS:
		var v = VaisseauPhysique.new()
		match String(e[2]):
			"air_bas", "air_souffle":
				v.gm = 0.0              # pas de chute : on écoute, on ne pilote pas
				v.rayon_planete = R
				v.atmosphere = Atmosphere.new(R, 0.0)
				v.px = R + (100.0 if e[2] == "air_bas" else 1000.0)
				v.orientation = Quaternion(Vector3.BACK, deg_to_rad(-90.0))
			"sol", "ventre":
				v.gm = GM
				v.rayon_planete = R
				v.orientation = Quaternion(Vector3(0, 0, 1), -PI / 2)
				if e[2] == "sol":
					v.sortir_train(true)
					v.train = 1.0
				v.px = R + (1.86 if e[2] == "sol" else 1.15)
				v.vx = -1.2 if e[2] == "sol" else -0.8
				v.vz = -50.0 if e[2] == "sol" else -20.0
		var p := Node3D.new()
		root.add_child(p)
		var pil := Pilotage.new()
		pil.v = v
		pil.nom = e[0]
		root.add_child(pil)
		var s = MoteurAudio.new()
		root.add_child(s)
		s.installer(v, p, null, Jeu.OEIL_PILOTE_DEFAUT - VaisseauPhysique.CENTRE_GRAVITE)
		rec.set_recording_active(true)
		await create_timer(float(e[1])).timeout
		rec.set_recording_active(false)
		var w: AudioStreamWAV = rec.get_recording()
		var chemin := dossier.path_join(String(e[0]) + ".wav")
		w.save_to_wav(chemin)
		print("%s : %.1f s, son %.2f ms par image, %d sons brefs" % [chemin, w.get_length(), s.ms_par_image, s.joues])
		s.queue_free()
		pil.queue_free()
		p.queue_free()
		await process_frame
		await process_frame
	quit()
