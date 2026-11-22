extends SceneTree
## Enregistre de courts extraits du son du cockpit (pour écouter le moteur audio sans lancer le jeu).
## Ligne de commande :
##   godot --headless --path . --script res://outils/extraits_son.gd -- <dossier de sortie>
## Ajouter `--son-boucles` après le dossier pour entendre l'ancienne version (boucles de la phase 1) :
## on peut ainsi comparer avant / après la phase 2 (sons fabriqués en direct par la partie C++).
## Phase 3 : extraits 5 à 7 (se poser, rouler, freiner ; train et ailes ; sur le ventre).
## Phase 4 : extraits 8 à 13 (virage serré : la structure chante et craque ; montée hors de l'air : la verrière se
## charge ; coque qui refroidit après une rentrée : tics ; orbite basse : rares grains de poussière ; 0,5 c et 0,9 c
## entre les étoiles : pluie de grains puis souffle du gaz). Pour 9 (altitude) et 12-13 (vitesse), le script
## force la position ou la vitesse ; 10 part d'une coque à 1 100 K et la laisse refroidir toute seule.
## Phase 4 aussi : 14 (petit propulseur à gauche, puis à droite : on entend de quel côté il souffle), 15 (moteurs
## poussés à x10 : la structure, surchargée, craque), 16 (atterrissage dur à 3,2 m/s : le train craque).
## Chaque extrait est une petite scène jouée en vrai (la physique du vaisseau tourne, le moteur audio
## l'écoute) ; ce qui sort du bus Master est enregistré dans un fichier .wav.
## Phase 5 (l'air en détail) : 17 (train qui sort dans l'air : trappes qui grondent, puis jambes qui sifflent, de 60 à
## 140 m/s), 18 (de Mach 0,7 à 1,3 : le tremblement transsonique), 19 (ailes qui décrochent, puis l'aile gauche seule
## en roulis : on l'entend à gauche), 20 (de Mach 1 à 2,2 : l'onde de choc bat devant la verrière), 21 (rentrée de 70 à
## 40 km, coque chaude, puis montée hors de l'air : tout s'efface). Le script force la vitesse et l'angle de l'air.
## Phase 6 (l'intérieur des moteurs ioniques) : 22 (allumage puis coupure dans le vide : « clac » du contacteur, sifflement
## qui part du grave, « whoomp » du plasma ; à la coupure le sifflement redescend en glissant, puis le contacteur
## s'ouvre), 23 (paliers de poussée 25, 50, 100 % : le sifflement monte avec √poussée, le réacteur gronde plus fort et
## un peu plus grave), 24 (moteur de l'aile gauche seul, puis de droite : chaque sifflement de son côté), 25 (12 s à
## fond : la chambre chauffe et le grondement monte lentement, puis redescend), 26 (vol vertical : les moteurs de
## levage sortent et sifflent plus aigu).
## `--seul=14` après le dossier : n'enregistre que les extraits dont le nom commence par « 14 ».
## Les commandes (gaz, manche) sont rejouées par le script ; les extraits 4 et 17 à 21 forcent la vitesse.

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
	# phase 4 : la tension des pièces et la poussière de l'espace
	["8-air-virage-serre", 11.0, "air_haut"],
	["9-montee-hors-de-l-air", 14.0, "air_montee"],
	["10-vide-coque-qui-refroidit", 14.0, "vide_chaud"],
	["11-orbite-basse-poussiere", 45.0, "orbite"],
	["12-espace-0-5-c", 10.0, "relativiste"],
	["13-espace-0-9-c", 10.0, "relativiste"],
	["14-espace-propulseur-gauche-puis-droite", 12.0, "vide"],
	["15-espace-poussee-x10-la-structure-craque", 10.0, "vide"],
	["16-sol-atterrissage-dur", 8.0, "sol_dur"],
	# phase 5 : l'air en détail
	["17-air-train-trappes-et-sifflement", 13.0, "air_train"],
	["18-air-tremblement-transsonique", 12.0, "air_11km"],
	["19-air-decrochage-puis-aile-gauche", 13.0, "air_train"],
	["20-air-choc-sur-la-verriere-mach-2", 12.0, "air_15km"],
	["21-rentree-puis-fondu-vers-le-silence", 14.0, "rentree"],
	# phase 6 : l'intérieur des moteurs ioniques (dans le vide : rien que la structure)
	["22-espace-allumage-puis-coupure", 12.0, "vide"],
	["23-espace-paliers-de-poussee", 14.0, "vide"],
	["24-espace-moteur-aile-gauche-puis-droite", 12.0, "vide"],
	["25-espace-la-chambre-chauffe", 20.0, "vide"],
	["26-espace-vol-vertical", 14.0, "vide"],
]

var dossier := "res://extraits"
var seul := ""


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
		var cote := Vector3.ZERO
		var seul := ""
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
			"16-sol-atterrissage-dur":
				# posé à 3,2 m/s (un peu plus que le cas de calcul du train, 3 m/s), freins à 3 s
				v.frein = 0.6 if t > 3.0 else 0.0
			"6-vide-train-et-ailes":
				if t > 0.5 and t < 0.6: v.sortir_train(true)
				if t > 4.5 and t < 4.6: v.ouvrir_ailes(false)
				if t > 8.0 and t < 8.1: v.ouvrir_ailes(true)
				if t > 11.0 and t < 11.1: v.sortir_train(false)
			"8-air-virage-serre":
				# 3 km, 220 m/s : on tire à fond sur le manche en virant, puis on relâche d'un coup
				gaz = 0.6
				if t > 2.0 and t < 7.0:
					tangage = 1.0
					roulis = 0.4 if t < 3.0 else 0.0
			"9-montee-hors-de-l-air":
				# de 2 à 40 km en 12 s, vaisseau immobile : la pression du dehors tombe, la verrière se charge
				v.px = R + 2000.0 + 38000.0 * clampf((t - 1.0) / 12.0, 0.0, 1.0)
				v.vx = 0.0
				v.vy = 0.0
				v.vz = 0.0
			"14-espace-propulseur-gauche-puis-droite":
				# un seul petit propulseur à la fois (allumé à la main, après la commande) : bout de l'aile gauche
				# pendant 2 s, puis bout de l'aile droite ; puis petits coups des propulseurs du flanc du cockpit,
				# gauche puis droite, et encore les bouts d'aile
				if t > 1.0 and t < 3.0: seul = "bout aile haut gauche"
				elif t > 4.0 and t < 6.0: seul = "bout aile haut droit"
				elif t > 7.0 and t < 7.4: seul = "lateral gauche"
				elif t > 7.9 and t < 8.3: seul = "lateral droit"
				elif t > 8.8 and t < 9.2: seul = "bout aile haut gauche"
				elif t > 9.7 and t < 10.1: seul = "bout aile haut droit"
			"22-espace-allumage-puis-coupure":
				if t > 1.5 and t < 5.0: gaz = 1.0
			"23-espace-paliers-de-poussee":
				if t > 1.0 and t < 3.5: gaz = 0.25
				elif t > 3.5 and t < 6.0: gaz = 0.5
				elif t > 6.0 and t < 8.5: gaz = 1.0
				elif t > 8.5 and t < 11.0: gaz = 0.5
			"25-espace-la-chambre-chauffe":
				if t > 1.0 and t < 13.0: gaz = 1.0
			"26-espace-vol-vertical":
				if t < 0.1: v.passer_vol_vertical(true)
				if t > 5.0 and t < 7.5: gaz = 0.5
				elif t > 7.5 and t < 10.5: gaz = 0.9
			"15-espace-poussee-x10-la-structure-craque":
				# moteurs imaginaires x10 (touche du jeu) : 120 g, bien au-delà de ce que la structure supporte
				if t < 0.1: v.regler_poussee(10.0)
				if t > 1.0 and t < 4.0: gaz = clampf((t - 1.0) / 2.0, 0.0, 1.0)
				elif t > 5.5 and t < 8.5: gaz = 1.0
			"17-air-train-trappes-et-sifflement":
				# 1 000 m : de 60 à 140 m/s ; le train sort à 1 s (trappes d'abord), rentre à 10 s
				_vent(60.0 + 80.0 * clampf((t - 0.5) / 11.0, 0.0, 1.0), 1.0)
				if t > 1.0 and t < 1.1: v.sortir_train(true)
				if t > 10.0 and t < 10.1: v.sortir_train(false)
			"18-air-tremblement-transsonique":
				# 11 km, ailes qui portent (4°) : de Mach 0,7 à 1,3 (vitesse du son 295 m/s)
				_vent(295.07 * (0.7 + 0.6 * clampf((t - 0.5) / 10.5, 0.0, 1.0)), 4.0)
			"19-air-decrochage-puis-aile-gauche":
				# 90 m/s : l'angle monte de 2° à 25° (décrochage), redescend ; puis 16° en roulis : les ailes gauches décrochent seules
				if t < 7.0:
					var a := 2.0 + 23.0 * clampf((t - 0.5) / 3.0, 0.0, 1.0) - 23.0 * clampf((t - 5.0) / 1.5, 0.0, 1.0)
					_vent(90.0, a)
				else:
					_vent(90.0, 16.0)
					v.omega = Vector3(0.0, 0.0, 1.0 if t > 8.0 and t < 11.5 else 0.0)
			"20-air-choc-sur-la-verriere-mach-2":
				# 15 km : de Mach 1 à 2,2
				_vent(295.07 * (1.0 + 1.2 * clampf((t - 0.5) / 10.5, 0.0, 1.0)), 1.0)
			"21-rentree-puis-fondu-vers-le-silence":
				# de 70 à 40 km en freinant de 6 à 2,5 km/s, puis remontée à 200 km : tout s'efface
				var k := clampf((t - 0.5) / 7.0, 0.0, 1.0)
				var h := 70000.0 - 30000.0 * k
				if t > 8.5:
					h = 40000.0 + 160000.0 * clampf((t - 8.5) / 4.5, 0.0, 1.0)
				v.px = R + h
				_vent(6000.0 - 3500.0 * k, 2.0)
			"12-espace-0-5-c":
				v.vz = -0.5 * 299792458.0
			"13-espace-0-9-c":
				v.vz = -0.9 * 299792458.0
		if nom.begins_with("19") or nom.begins_with("17") or nom.begins_with("18") or nom.begins_with("20") or nom.begins_with("21"):
			v.orientation = Quaternion(Vector3.BACK, deg_to_rad(-90.0))   # le vaisseau reste face au vent
			if not nom.begins_with("19") or t < 7.0:
				v.omega = Vector3.ZERO
		v.commander(gaz, tangage, lacet, roulis, cote)
		if nom.begins_with("24"):
			# un seul moteur d'aile à la fois (le plus à gauche, puis le plus à droite), donné après la commande
			var aile := ""
			if t > 1.0 and t < 4.5: aile = "gauche"
			elif t > 6.0 and t < 9.5: aile = "droite"
			var i_g := 0
			var i_d := 0
			for i in 5:
				if v.moteurs[i]["position"].x < v.moteurs[i_g]["position"].x: i_g = i
				if v.moteurs[i]["position"].x > v.moteurs[i_d]["position"].x: i_d = i
			if aile != "":
				v.moteurs[i_g if aile == "gauche" else i_d]["consigne"] = 1.0
		if seul != "":
			for r in v.rcs:
				if r["nom"] == seul:
					r["actuel"] = 1.0
		v.pas(delta)

	## L'air arrive de face à la vitesse u, avec l'angle a (degrés) par en dessous (le haut du vaisseau vers le ciel, +x).
	func _vent(u: float, a: float) -> void:
		v.vx = -u * sin(deg_to_rad(a))
		v.vy = 0.0
		v.vz = -u * cos(deg_to_rad(a))


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seul="):
			seul = a.substr(7)
		elif not a.begins_with("--"):
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
		if seul != "" and not String(e[0]).begins_with(seul + "-"):
			continue
		var v = VaisseauPhysique.new()
		match String(e[2]):
			"air_bas", "air_souffle":
				v.gm = 0.0              # pas de chute : on écoute, on ne pilote pas
				v.rayon_planete = R
				v.atmosphere = Atmosphere.new(R, 0.0)
				v.px = R + (100.0 if e[2] == "air_bas" else 1000.0)
				v.orientation = Quaternion(Vector3.BACK, deg_to_rad(-90.0))
			"air_haut", "air_montee":
				v.gm = 0.0
				v.rayon_planete = R
				v.atmosphere = Atmosphere.new(R, 0.0)
				v.px = R + (3000.0 if e[2] == "air_haut" else 2000.0)
				v.vz = -220.0 if e[2] == "air_haut" else 0.0
				v.orientation = Quaternion(Vector3.BACK, deg_to_rad(-90.0))
			"air_train", "air_11km", "air_15km", "rentree":
				v.gm = 0.0
				v.rayon_planete = R
				v.atmosphere = Atmosphere.new(R, 0.0)
				v.px = R + {"air_train": 1000.0, "air_11km": 11000.0, "air_15km": 15000.0, "rentree": 70000.0}[e[2]]
				v.orientation = Quaternion(Vector3.BACK, deg_to_rad(-90.0))
				if e[2] == "rentree":
					v.temperature_nez = 1200.0
			"vide_chaud":
				v.temperature_nez = 1100.0   # juste après une rentrée dans l'air
			"orbite":
				# 250 km au-dessus de la planète, en orbite (moteurs coupés : on n'entend presque rien)
				v.gm = GM
				v.rayon_planete = R
				v.atmosphere = Atmosphere.new(R, 0.0)
				v.px = R + 250000.0
				v.vz = -sqrt(GM / (R + 250000.0))
				v.orientation = Quaternion(Vector3.BACK, deg_to_rad(-90.0))
			"sol", "ventre", "sol_dur":
				v.gm = GM
				v.rayon_planete = R
				v.orientation = Quaternion(Vector3(0, 0, 1), -PI / 2)
				if e[2] != "ventre":
					v.sortir_train(true)
					v.train = 1.0
				v.px = R + (1.15 if e[2] == "ventre" else 1.86)
				v.vx = {"sol": -1.2, "ventre": -0.8, "sol_dur": -3.2}[e[2]]
				v.vz = {"sol": -50.0, "ventre": -20.0, "sol_dur": -40.0}[e[2]]
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
		print("%s : %.1f s, son %.2f ms par image, %d sons brefs (craquements %d, relâchements %d, tics %d, grains %d)" % [chemin,
			w.get_length(), s.ms_par_image, s.joues, s.tension.craquements, s.tension.relachements, s.tension.tics,
			s.poussiere.grains_joues])
		if int(String(e[0]).get_slice("-", 0)) >= 22:
			print("   moteurs ioniques : bobines %.0f dB, chambre %.0f dB, réacteur %.0f dB (%.1f Hz), %d contacteurs (fin de l'extrait)" % [
				float(s.couches["bobines"]["lisse"]), float(s.couches["plasma"]["lisse"]), float(s.couches["reacteur"]["lisse"]),
				s.ionique.f_bourdon, s.ionique.contacts])
		elif int(String(e[0]).get_slice("-", 0)) >= 17:
			print("   air : sifflement %.0f dB, trappes %.0f dB, tremblement %.0f dB, choc verrière %.0f dB, souffle %.0f dB (fin de l'extrait)" % [
				float(s.couches["sifflement"]["lisse"]), float(s.couches["cavites"]["lisse"]), float(s.couches["tremblement"]["lisse"]),
				float(s.couches["choc_verriere"]["lisse"]), float(s.couches["souffle"]["lisse"])])
		s.queue_free()
		pil.queue_free()
		p.queue_free()
		await process_frame
		await process_frame
	quit()
