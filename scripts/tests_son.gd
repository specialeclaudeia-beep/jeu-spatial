extends Node
## Tests automatiques du moteur audio (phases 1 et 2). À part des tests de physique.
## Ligne de commande (dans le cloud ou sur le PC) :
##   godot --headless --path . res://scenes/tests_son.tscn
## Sans écran, Godot calcule quand même le son (pilote audio « Dummy ») : on peut mesurer ce qui sort.

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const Atmosphere = preload("res://scripts/physique/atmosphere.gd")
const MoteurAudio = preload("res://scripts/son/moteur_audio.gd")
const Fluides = preload("res://scripts/son/fluides_son.gd")
const MoteursSon = preload("res://scripts/son/moteurs_son.gd")
const Capteurs = preload("res://scripts/son/capteurs.gd")
const Synthese = preload("res://scripts/son/synthese.gd")
const Jeu = preload("res://scripts/jeu.gd")
const Resonances = preload("res://scripts/son/resonances.gd")
const TAUX := 48000   # rendu hors ligne de la partie C++ (échantillons par seconde)
const R := 600000.0
const GM := 9.81 * 600000.0 * 600000.0
const PAS := 1.0 / 120.0

var reussis := 0
var total := 0
var _pilotes: Array = []


func _ready() -> void:
	await get_tree().process_frame
	var debut := Time.get_ticks_msec()
	_test_physique_intacte()
	_test_capteurs()
	_test_paroi()
	_test_couche_limite()
	_test_vide()
	_test_jets()
	_test_structure()
	_test_evenements()
	_test_temps_pause()
	_test_voix()
	_test_plafond()
	_test_repetitions()
	_test_generateur()
	_test_vitesse()
	_test_cpp_niveaux()
	_test_cpp_resonances()
	_test_cpp_detecteur()
	_test_vol_10_minutes()
	await _test_cpp_en_direct()
	await _test_calibration()
	print("Tests du son : %d / %d réussis (%.1f s)" % [reussis, total, (Time.get_ticks_msec() - debut) / 1000.0])
	if DisplayServer.get_name() == "headless":
		get_tree().quit()


func _resultat(ok: bool, titre: String, detail: String) -> void:
	total += 1
	if ok:
		reussis += 1
	print("%s %s : %s" % ["[OK]" if ok else "[ÉCHEC]", titre, detail])


# =====================================================================
# OUTILS
# =====================================================================
func _vaisseau_vide():
	var v = VaisseauPhysique.new()
	v.reactivite_moteurs = 1e-6
	return v


## Vaisseau dans l'air à l'altitude z, nez en avant, qui vole à la vitesse u (m/s).
func _vaisseau_air(z: float, u: float):
	var v = VaisseauPhysique.new()
	v.reactivite_moteurs = 1e-6
	v.gm = GM
	v.rayon_planete = R
	v.atmosphere = Atmosphere.new(R, 0.0)
	v.px = R + z
	v.vz = -u
	v.orientation = Quaternion(Vector3.BACK, deg_to_rad(-90.0))   # haut du vaisseau vers le ciel
	v.pas(1.0 / 240.0)   # calcule l'air autour de lui
	return v


## Moteur audio branché sur v. auto = laissé tourner tout seul (sinon on l'appelle à la main).
func _son(v, auto := false):
	var p := Node3D.new()
	add_child(p)
	_pilotes.append(p)
	var s = MoteurAudio.new()
	add_child(s)
	s.installer(v, p, null, Jeu.OEIL_PILOTE_DEFAUT - VaisseauPhysique.CENTRE_GRAVITE)
	s.set_process(auto)
	s.set_physics_process(auto)
	return s


func _liberer(s) -> void:
	s.queue_free()
	for p in _pilotes:
		p.queue_free()
	_pilotes.clear()


## Fait tourner le moteur audio n images (à la main), le vaisseau immobile.
func _images(s, n: int, dt := 1.0 / 60.0) -> void:
	for i in n:
		s._physics_process(dt)
		s.mettre_a_jour(dt)


func _niveau(s, nom: String) -> float:
	return float(s.couches[nom]["lisse"])


func _db(x: float) -> float:
	return 10.0 * log(x) / log(10.0)


func _etat_physique(v) -> Array:
	var e := [v.px, v.py, v.pz, v.vx, v.vy, v.vz, v.ux, v.uy, v.uz, v.orientation, v.omega, v.temperature_nez,
		v.temps_pilote, v.densite_air, v.vitesse_air, v.au_sol]
	for m in v.moteurs + v.rcs:
		e.append(m["actuel"])
		e.append(m["position"])
	return e


# =====================================================================
# 1. LA PHYSIQUE NE CHANGE PAS
# =====================================================================
func _test_physique_intacte() -> void:
	var a = _vaisseau_air(3000.0, 150.0)
	var b = _vaisseau_air(3000.0, 150.0)
	var s = _son(b)
	for i in 120 * 60:
		var t := i * PAS
		var ordre := Vector3(0.6 * sin(t * 0.7), 0.4 * sin(t * 1.3), 0.8 * sin(t * 2.1))
		var gaz := 0.5 + 0.5 * sin(t * 0.25)
		for v in [a, b]:
			v.commander(gaz, ordre.x, ordre.y, ordre.z)
			v.pas(PAS)
		s._physics_process(PAS)   # le son lit après chaque pas…
		if i % 2 == 0:
			s.mettre_a_jour(1.0 / 60.0)   # … et décide 60 fois par seconde
	var ea := _etat_physique(a)
	var eb := _etat_physique(b)
	var pareil := ea.size() == eb.size()
	var ecarts := 0
	for k in ea.size():
		if ea[k] != eb[k]:
			pareil = false
			ecarts += 1
	_resultat(pareil and s.joues > 0, "La physique ne change pas",
		"60 s de vol dans l'air (gaz et manche qui bougent), un vaisseau avec le son, un sans : %d valeurs sur %d différentes (attendu 0, à la décimale près). Sons brefs joués : %d." % [ecarts, ea.size(), s.joues])
	_liberer(s)


func _test_capteurs() -> void:
	var v = _vaisseau_air(2000.0, 120.0)
	var s = _son(v)
	_images(s, 3)
	var c = s.capteurs
	var vent_ok: bool = absf(c.vent.length() - v.vitesse_air) < 0.05 and c.vent.z > 119.0   # la physique calcule vitesse_air en cours de pas
	var air_ok: bool = c.densite == v.densite_air
	var types_ok: bool = c.nombre == v.moteurs.size() + v.rcs.size() and c.types[4] == Capteurs.TYPE_MOTEUR \
		and c.types[5] == Capteurs.TYPE_LEVAGE and c.types[c.nombre - 1] == Capteurs.TYPE_RCS
	_resultat(vent_ok and air_ok and types_ok, "Capteurs : la photo de la physique",
		"Vent vu du vaisseau %.3f m/s (physique, en cours de pas : %.3f), vers l'arrière (z = %+.1f) : %s. Densité de l'air lue : %s. %d propulseurs lus (5 moteurs, 2 de levage, %d petits) : %s." % [
			c.vent.length(), v.vitesse_air, c.vent.z, _oui(vent_ok), _oui(air_ok), c.nombre, v.rcs.size(), _oui(types_ok)])
	_liberer(s)


# =====================================================================
# 2. LOIS PHYSIQUES DU SON
# =====================================================================
func _test_paroi() -> void:
	# loi de masse : une onde qui frappe une paroi de m kg/m² passe avec un rapport 2Z / (ω m) (−6 dB par octave)
	var z := 1.225 * 340.3
	var t1 := 2.0 * Fluides.transmission(1000.0, z)
	var t2 := 2.0 * Fluides.transmission(2000.0, z)
	var loi := 20.0 * log(TAU * 1000.0 * Fluides.PAROI_MASSE / (2.0 * z)) / log(10.0)
	var perte1 := -20.0 * log(t1) / log(10.0)
	var octave := 20.0 * log(t1 / t2) / log(10.0)
	var resonance := -20.0 * log(2.0 * Fluides.transmission(Fluides.PAROI_F0, z)) / log(10.0)
	_resultat(absf(perte1 - loi) < 0.5 and absf(octave - 6.0) < 0.3 and resonance < perte1 - 20.0,
		"Verrière : loi de masse",
		"À 1 kHz, la paroi (%.0f kg/m²) arrête %.1f dB (loi de masse : %.1f dB) ; une octave plus haut, %.2f dB de plus (attendu 6). À sa résonance (%.0f Hz), elle laisse bien plus passer : %.1f dB." % [
			Fluides.PAROI_MASSE, perte1, loi, octave, Fluides.PAROI_F0, resonance])


func _test_couche_limite() -> void:
	var t := 288.15
	var tr := Fluides.transmissions(1.225 * Fluides.vitesse_son(t))
	var s100 := Fluides.souffle(1.225, t, 100.0, 100.0 / 340.3, -1.0, tr)
	var rapport := float(s100["p_paroi"]) / float(s100["q"])
	var s200 := Fluides.souffle(1.225, t, 200.0, 200.0 / 340.3, -1.0, tr)
	# très haut et très vite (60 km, 2 km/s) : air si fin que la couche limite reste lisse (laminaire)
	var t60 := 247.0
	var s60 := Fluides.souffle(3.1e-4, t60, 2000.0, 2000.0 / Fluides.vitesse_son(t60), -1.0, Fluides.transmissions(3.1e-4 * Fluides.vitesse_son(t60)))
	var t30 := 226.5
	var s30 := Fluides.souffle(0.018, t30, 1000.0, 1000.0 / Fluides.vitesse_son(t30), -1.0, Fluides.transmissions(0.018 * Fluides.vitesse_son(t30)))
	# molécules isolées : plus de fluide, plus de souffle
	var s_rare := Fluides.souffle(1.0e-10, 200.0, 7000.0, 25.0, -1.0, Fluides.transmissions(1e-10 * 283.0))
	var ok: bool = rapport > 0.003 and rapport < 0.012 and float(s200["niveau"]) > float(s100["niveau"]) \
		and float(s60["turbulent"]) == 0.0 and float(s60["niveau"]) < float(s30["niveau"]) - 30.0 and float(s30["turbulent"]) > 0.9 \
		and float(s_rare["niveau"]) == -INF and float(s_rare["fluide"]) == 0.0
	_resultat(ok, "Souffle : remous de l'air sur la coque",
		"À 100 m/s au sol, la pression tremble de %.2f %% de la pression du vent (mesures : 0,3 à 1 %%) : %.0f dB dans le cockpit, %.0f dB à 200 m/s. À 30 km et 1 km/s : %.0f dB ; à 60 km et 2 km/s, l'air trop fin reste lisse : %.0f dB. Air de molécules isolées : silence (%s)." % [
			rapport * 100.0, s100["niveau"], s200["niveau"], s30["niveau"], s60["niveau"], str(s_rare["niveau"])])


func _test_vide() -> void:
	var v = _vaisseau_vide()
	v.moteurs[4]["actuel"] = 1.0
	v.moteurs[4]["consigne"] = 1.0
	var s = _son(v)
	_images(s, 30)
	var ok: bool = _niveau(s, "souffle") == -INF and _niveau(s, "jet") == -INF and _niveau(s, "structure") > 75.0 \
		and (s.couches["structure"]["lecteur"] as AudioStreamPlayer).playing and not (s.couches["jet"]["lecteur"] as AudioStreamPlayer).playing
	_resultat(ok, "Dans le vide : seulement la structure",
		"Moteur central à fond, sans air : souffle %s, jet par l'air %s (silence), grondement par la structure %.1f dB dans le cockpit." % [
			str(_niveau(s, "souffle")), str(_niveau(s, "jet")), _niveau(s, "structure")])
	_liberer(s)


func _jet_air(rho: float, u: float) -> float:
	# bruit du jet central qui arrive sur la verrière (Pa²), dans un air de densité rho, vol à u m/s
	var c := Capteurs.new()
	var v = _vaisseau_vide()
	v.moteurs[4]["actuel"] = 1.0
	c.lire(v, 0.0)
	c.densite = rho
	c.temperature = 288.15
	c.vent = Vector3(0, 0, u)
	var m := MoteursSon.new()
	var oreille: Vector3 = Jeu.OEIL_PILOTE_DEFAUT
	return m._jet_par_air(c, 4, oreille, Fluides.vitesse_son(288.15))


func _test_jets() -> void:
	var p0 := _jet_air(1.225, 0.0)
	var p_demi := _jet_air(0.6125, 0.0)
	var p_m05 := _jet_air(1.225, 0.5 * Fluides.vitesse_son(288.15))
	var p_m105 := _jet_air(1.225, 1.05 * Fluides.vitesse_son(288.15))
	var lighthill := _db(p_demi / p0)
	var m05 := _db(p_m05 / p0)
	var spl := 10.0 * log(p0 / 4e-10) / log(10.0)
	var ok: bool = absf(lighthill + 6.02) < 0.01 and m05 < -5.0 and m05 > -6.6 and p_m105 == 0.0 and spl > 125.0 and spl < 150.0
	_resultat(ok, "Jets : bruit par l'air",
		"Moteur central à fond au sol, à l'arrêt : %.0f dB sur la verrière. Air 2 fois moins dense : %.2f dB (Lighthill : −6,02). En vol à Mach 0,5, le son remonte mal le vent : %.1f dB ; à Mach 1,05, il n'arrive plus du tout par l'air (%s)." % [
			spl, lighthill, m05, "silence" if p_m105 == 0.0 else "ERREUR"])


func _test_structure() -> void:
	var v = _vaisseau_vide()
	var s = _son(v)
	v.moteurs[4]["actuel"] = 0.5
	_images(s, 3)
	var l1 := _niveau(s, "structure")
	v.moteurs[4]["actuel"] = 1.0
	_images(s, 3)
	var l2 := _niveau(s, "structure")
	v.moteurs[4]["actuel"] = 0.0
	v.moteurs[0]["actuel"] = 1.0   # moteur d'aile, à peu près à la même distance : passe par l'emplanture
	_images(s, 60)
	var l_aile := _niveau(s, "structure")
	for m in v.moteurs:
		m["actuel"] = 1.0 if m["poussee_max"] > 0.0 and String(m["nom"]) != "levage gauche" and String(m["nom"]) != "levage droit" else 0.0
	_images(s, 3)
	var l5 := _niveau(s, "structure")
	var ok: bool = absf(l2 - l1 - 6.02) < 0.05 and l_aile < l2 - 4.0 and l5 > l2 and l5 < 95.0
	_resultat(ok, "Moteurs : grondement par la structure",
		"Moteur central à 50 %% : %.1f dB, à 100 %% : %.1f dB (+%.2f dB : énergie ∝ force²). Un moteur d'aile seul : %.1f dB (l'emplanture arrête une partie). Les 5 moteurs à fond : %.1f dB." % [
			l1, l2, l2 - l1, l_aile, l5])
	_liberer(s)


func _test_evenements() -> void:
	var v = _vaisseau_vide()
	var s = _son(v)
	_images(s, 2)
	v.rcs[0]["actuel"] = 1.0
	s._physics_process(PAS)
	var ouverture: Array = s._demandes.duplicate()
	v.rcs[0]["actuel"] = 0.0
	s._physics_process(PAS)   # trop tôt : la même vanne ne reclaque pas avant 70 ms
	var trop_tot: int = s._demandes.size()
	s.mettre_a_jour(1.0 / 60.0)
	s.capteurs.temps += 0.1
	v.rcs[0]["actuel"] = 1.0
	s._physics_process(PAS)
	v.rcs[0]["actuel"] = 0.0
	s.capteurs.temps += 0.1
	s._physics_process(PAS)
	var fermeture: Array = s._demandes.duplicate()
	s.mettre_a_jour(1.0 / 60.0)
	v.moteurs[4]["actuel"] = 0.6
	v.moteurs[4]["consigne"] = 1.0
	s._physics_process(PAS)
	var allumage: Array = s._demandes.duplicate()
	var ok: bool = ouverture.size() == 1 and ouverture[0][0] == "rcs_ouverture" and trop_tot == 1 \
		and fermeture.size() == 2 and fermeture[1][0] == "rcs_fermeture" and allumage.size() == 1 and allumage[0][0] == "moteur_allumage" \
		and float(ouverture[0][1]) > 80.0 and float(ouverture[0][1]) < 92.0 and float(allumage[0][1]) > 75.0
	_resultat(ok, "Sons brefs : vannes et allumages",
		"Vanne du nez ouverte : « %s » à %.1f dB ; refermée 8 ms après : rien (%d demande) ; puis « %s ». Moteur central allumé : « %s » à %.1f dB." % [
			ouverture[0][0] if ouverture.size() else "rien", float(ouverture[0][1]) if ouverture.size() else 0.0, trop_tot,
			fermeture[1][0] if fermeture.size() > 1 else "rien", allumage[0][0] if allumage.size() else "rien", float(allumage[0][1]) if allumage.size() else 0.0])
	_liberer(s)


# =====================================================================
# 3. LE CHEF D'ORCHESTRE
# =====================================================================
func _test_temps_pause() -> void:
	var v = _vaisseau_vide()
	v.moteurs[4]["actuel"] = 1.0
	var s = _son(v)
	s.regler(false, 10, true)
	_images(s, 20)
	var a_x10: bool = s.fondu == 1.0 and (s.couches["structure"]["lecteur"] as AudioStreamPlayer).playing
	s.regler(false, 100, true)
	_images(s, 7)    # 0,117 s
	var x100: bool = s.fondu == 0.0 and s.voix_actives() == 0
	v.rcs[0]["actuel"] = 1.0
	_images(s, 2)
	var rien_x100: bool = s._demandes.is_empty()
	v.rcs[0]["actuel"] = 0.0
	s.regler(false, 1, true)
	_images(s, 10)
	var retour: bool = s.fondu == 1.0
	s.regler(true, 1, true)
	_images(s, 3)
	var pendant: float = s.fondu
	_images(s, 4)
	var pause: bool = s.fondu == 0.0 and s.voix_actives() == 0 and pendant > 0.0 and pendant < 1.0
	s.regler(false, 1, false)   # vue extérieure : toujours l'oreille du pilote
	_images(s, 10)
	var dehors: bool = s.fondu == 1.0 and s.ecoute.position.is_equal_approx(s.oreille_scene) and (s.couches["structure"]["lecteur"] as AudioStreamPlayer).playing
	v.ecrase = true
	_images(s, 8)
	var ecrase: bool = s.fondu == 0.0
	_resultat(a_x10 and x100 and rien_x100 and retour and pause and dehors and ecrase, "Temps accéléré, pause, vues",
		"x10 : son normal (%s) ; x100 : silence en 0,1 s (%s), aucune vanne entendue (%s) ; retour à x1 (%s). Pause : fondu (%.2f après 50 ms), silence après 0,1 s (%s). Vue extérieure : on entend toujours le cockpit (%s). Vaisseau écrasé : silence (%s)." % [
			_oui(a_x10), _oui(x100), _oui(rien_x100), _oui(retour), pendant, _oui(pause), _oui(dehors), _oui(ecrase)])
	_liberer(s)


func _oui(b: bool) -> String:
	return "oui" if b else "NON"


func _test_voix() -> void:
	# tempête : tous les petits propulseurs claquent sans arrêt, les moteurs s'allument et se coupent
	var v = _vaisseau_air(800.0, 60.0)
	var s = _son(v)
	var noeuds: int = s.get_child_count() + _pilotes[0].get_child_count()
	var voix_max := 0
	var invalide := false
	for i in 600:
		s.capteurs.temps += PAS
		for k in v.rcs.size():
			v.rcs[k]["actuel"] = 1.0 if (i + k) % 3 == 0 else 0.0
		for k in 5:
			v.moteurs[k]["actuel"] = 1.0 if (i / 40 + k) % 2 == 0 else 0.0
			v.moteurs[k]["consigne"] = v.moteurs[k]["actuel"]
		s._physics_process(PAS)
		if i % 2 == 0:
			s.mettre_a_jour(1.0 / 60.0)
			voix_max = maxi(voix_max, s.voix_actives())
			for nom in s.couches:
				var vol: float = (s.couches[nom]["lecteur"] as AudioStreamPlayer).volume_db
				invalide = invalide or is_nan(vol) or is_inf(vol)
			for vx in s.voix:
				var vol: float = (vx["lecteur"] as AudioStreamPlayer3D).volume_db
				invalide = invalide or is_nan(vol) or is_inf(vol)
	var apres: int = s.get_child_count() + _pilotes[0].get_child_count()
	var ok: bool = voix_max <= MoteurAudio.VOIX_MAX and voix_max > 8 and not invalide and apres == noeuds and s.joues > 50
	_resultat(ok, "Tempête de sons : 24 voix au plus",
		"5 s de vannes qui claquent sans arrêt (22 propulseurs) et de moteurs qui s'allument : au plus %d voix en même temps (limite 24), %d sons brefs joués, %d écartés (trop faibles, cachés ou sans lecteur libre). Lecteurs créés au départ et jamais recréés : %s. Volume invalide : %s." % [
			voix_max, s.joues, s.oublies, _oui(apres == noeuds), "oui" if invalide else "aucun"])
	_liberer(s)


func _test_plafond() -> void:
	var v = _vaisseau_air(200.0, 0.0)
	v.regler_poussee(100000.0)
	for k in 5:
		v.moteurs[k]["actuel"] = 1.0
	var s = _son(v)
	_images(s, 60)
	var total_db: float = MoteurAudio._somme_db(s.couches.values().map(func(k): return float(k["lisse"])))
	var sortie: float = total_db - MoteurAudio.ZERO_DBFS + s.gain
	var ok: bool = total_db > 180.0 and sortie <= MoteurAudio.PLAFOND + 0.05 and sortie > MoteurAudio.PLAFOND - 1.0
	_resultat(ok, "Poussée x100 000 : volume plafonné",
		"Les 5 moteurs à fond au sol, puissance x100 000 : %.0f dB dans le cockpit (impossible à rendre), joués à %.1f dB pleine échelle (plafond %.0f)." % [
			total_db, sortie, MoteurAudio.PLAFOND])
	_liberer(s)


func _test_repetitions() -> void:
	var v = _vaisseau_vide()
	var s = _son(v)
	var suite := []
	for i in 1000:
		var k: int = s._choisir("rcs_ouverture")
		s._retenir("rcs_ouverture", k)
		suite.append(k)
	var n: int = s.coups["rcs_ouverture"].size()
	var repete := 0
	for i in suite.size():
		for j in range(maxi(0, i - (n - 1)), i):
			if suite[j] == suite[i]:
				repete += 1
	_resultat(repete == 0 and n == 6, "Sons brefs : jamais deux fois le même de suite",
		"1 000 vannes qui s'ouvrent, %d variantes : %d fois la même variante parmi %d sons consécutifs (attendu 0)." % [n, repete, n])
	_liberer(s)


func _test_generateur() -> void:
	var r: Array = Synthese.fabriquer_coup("rcs_fermeture", 0)
	var neuf := Synthese.en_16_bits(r[0])
	var fichier := FileAccess.get_file_as_bytes("res://sons/coups/rcs_fermeture_1.wav")
	var ecart := 0
	var ok := fichier.size() == neuf.size() + 44
	if ok:
		for i in range(0, neuf.size(), 2):
			ecart = maxi(ecart, absi(neuf.decode_s16(i) - fichier.decode_s16(44 + i)))
	_resultat(ok and ecart <= 1, "Générateur : même graine, même son",
		"Vanne qui se referme refaite à partir de sa graine (%d) : %d échantillons, écart maximal %d (sur 32 767) avec le fichier du jeu." % [
			r[1]["graine"], neuf.size() / 2, ecart])


func _test_vitesse() -> void:
	var v = _vaisseau_air(3000.0, 200.0)
	for m in v.moteurs:
		m["actuel"] = 0.7
	var s = _son(v)
	_images(s, 10)
	var t0 := Time.get_ticks_usec()
	for i in 300:
		s._physics_process(PAS)
		s._physics_process(PAS)
		s.mettre_a_jour(1.0 / 60.0)
	var us := float(Time.get_ticks_usec() - t0) / 300.0
	_resultat(us < 400.0, "Léger : temps de calcul du son",
		"Dans l'air, moteurs allumés : %.0f microsecondes par image (2 photos de la physique + 1 décision), soit %.1f %% d'une image à 60 i/s. (Le mélange des sons, lui, est fait par Godot en C++.)" % [
			us, us / 16667.0 * 100.0])
	_liberer(s)


# =====================================================================
# 3 bis. PHASE 2 : SONS FABRIQUÉS EN DIRECT (partie C++)
# =====================================================================
func _cpp(titre: String) -> bool:
	if ClassDB.class_exists("SyntheSon") and ClassDB.class_exists("AnalyseSon"):
		return true
	_resultat(false, titre, "la partie C++ (SyntheSon) n'est pas chargée")
	return false


## Calcule n échantillons d'une lecture C++ (hors ligne), par morceaux de 4 800 ; les donne à l'analyse.
func _mixer(pb, n: int, analyse = null, garder := false) -> PackedVector2Array:
	var tout := PackedVector2Array()
	while n > 0:
		var k := mini(n, 4800)
		var b: PackedVector2Array = pb.mix_audio(1.0, k)
		if analyse != null:
			analyse.ajouter(b)
		if garder:
			tout.append_array(b)
		n -= k
	return tout


func _test_cpp_niveaux() -> void:
	var titre := "Partie C++ : le niveau et la couleur demandés sortent"
	if not _cpp(titre):
		return
	var flux = ClassDB.instantiate("SyntheSon")
	flux.taux = TAUX
	# couleur du grondement des moteurs, 1e-3 en tout (−30 dB pleine échelle)
	var e := PackedFloat32Array()
	e.resize(30)
	var tot := 0.0
	for j in 30:
		var f := Resonances.centre(j)
		e[j] = Synthese.spectre("structure", f) * f
		tot += e[j]
	var e_max := 0.0
	for j in 30:
		e[j] *= 1e-3 / tot
		e_max = maxf(e_max, e[j])
	flux.regler_bandes(e)
	var pb = flux.instantiate_playback()
	pb.start(0.0)
	_mixer(pb, TAUX / 2)
	var a = ClassDB.instantiate("AnalyseSon")
	var son := _mixer(pb, TAUX * 20, a, true)
	var r: Dictionary = a.resultat()
	var sp: PackedFloat64Array = a.spectre_tiers(son, TAUX)
	var pire_bande := 0.0
	var n_bandes := 0
	for j in 30:
		if e[j] > e_max * 0.03:   # bandes à moins de 15 dB du maximum
			pire_bande = maxf(pire_bande, absf(_db(sp[j] / e[j])))
			n_bandes += 1
	var ecart_g := _db(float(r["gauche"]["energie"]) / 1e-3)
	var ecart_d := _db(float(r["droite"]["energie"]) / 1e-3)
	# son pur : 440 Hz, 1e-2 → crête √(2 × 0,01)
	flux.couper()
	flux.regler_raie(0, 440.0, 0.01)
	_mixer(pb, TAUX)
	a.remettre()
	_mixer(pb, TAUX * 2, a)
	var rr: Dictionary = a.resultat()
	var ecart_raie := _db(float(rr["gauche"]["energie"]) / 0.01)
	flux.couper()
	_mixer(pb, TAUX / 2)
	var silence: bool = flux.est_silencieux()
	_resultat(absf(ecart_g) < 0.2 and absf(ecart_d) < 0.3 and pire_bande < 1.0 and absf(ecart_raie) < 0.05 \
		and silence and int(r["craquements"]) == 0 and int(r["non_finis"]) == 0, titre,
		"Grondement demandé à −30 dB : sorti à %+.2f dB (gauche) et %+.2f dB (droite) de la cible ; couleur : %d tiers d'octave vérifiés, plus grand écart %.2f dB (tolérance 1). Son pur à 440 Hz : %+.3f dB. Coupé : silence (%s). 20 s : %d craquement, %d valeur invalide." % [
			ecart_g, ecart_d, n_bandes, pire_bande, ecart_raie, _oui(silence), r["craquements"], r["non_finis"]])


func _test_cpp_resonances() -> void:
	var titre := "Résonances des panneaux du cockpit"
	if not _cpp(titre):
		return
	var res = Resonances.new()
	var fr: float = res.frequence_recouvrement()
	# une résonance seule à 60 Hz : elle monte, puis s'éteint en 1 / (π f η) comme une vraie plaque
	var flux = ClassDB.instantiate("SyntheSon")
	flux.taux = TAUX
	flux.regler_modes(PackedFloat32Array([60.0]), PackedFloat32Array([Resonances.PERTE]))
	flux.regler_energie_modes(PackedFloat32Array([1e-3]))
	var pb = flux.instantiate_playback()
	pb.start(0.0)
	_mixer(pb, TAUX * 4)
	var a = ClassDB.instantiate("AnalyseSon")
	_mixer(pb, TAUX * 10, a)
	var niveau := _db(float(a.resultat()["gauche"]["energie"]) / 1e-3)
	flux.regler_energie_modes(PackedFloat32Array([0.0]))
	var mesures := []
	for k in 6:   # 6 fois 0,25 s
		a.remettre()
		_mixer(pb, TAUX / 4, a)
		mesures.append(_db(float(a.resultat()["gauche"]["energie"])))
	var pente := (float(mesures[5]) - float(mesures[1])) / 1.0   # dB par seconde
	var attendu := -10.0 * 2.0 * PI * 60.0 * Resonances.PERTE / log(10.0)
	# tout le cockpit : 32 résonances + le reste en bruit lisse, même énergie au total
	var e := PackedFloat32Array()
	e.resize(30)
	e.fill(1e-5)
	var parts: Array = res.partager(e)
	var somme := 0.0
	for x in parts[0]:
		somme += x
	for x in parts[1]:
		somme += x
	_resultat(absf(niveau) < 0.5 and absf(pente / attendu - 1.0) < 0.1 and res.frequences.size() == 32 \
		and absf(somme / 30e-5 - 1.0) < 1e-4 and fr > 150.0 and fr < 600.0, titre,
		"%d résonances de %.0f à %.0f Hz (plancher, parois, tableau de bord, cloison arrière) ; au-delà de %.0f Hz elles se chevauchent (son lisse). Une résonance à 60 Hz : niveau %+.2f dB de la cible ; coupée, elle s'éteint de %.1f dB par seconde (plaque d'aluminium rivetée, perte 1 %% : %.1f). Partage bruit / résonances : énergie gardée à %.4f %%." % [
			res.frequences.size(), res.frequences[0], res.frequences[res.frequences.size() - 1], fr, niveau, pente, attendu,
			somme / 30e-5 * 100.0])


func _test_cpp_detecteur() -> void:
	var titre := "Détecteur de craquements (outil des tests)"
	if not _cpp(titre):
		return
	var flux = ClassDB.instantiate("SyntheSon")
	flux.taux = TAUX
	var e := PackedFloat32Array()
	e.resize(30)
	for j in 30:
		e[j] = 1e-4 * pow(10.0, -0.1 * absf(j - 10))
	flux.regler_bandes(e)
	var pb = flux.instantiate_playback()
	pb.start(0.0)
	_mixer(pb, TAUX / 2)
	var son := _mixer(pb, TAUX * 3, null, true)
	var a = ClassDB.instantiate("AnalyseSon")
	a.ajouter(son)
	var propre: int = a.resultat()["craquements"]
	# même son (valeur efficace 0,029), avec un saut brusque de 0,05 à 1,5 s : un petit « tic » à peine plus fort
	# que le bruit lui-même
	var abime := son.duplicate()
	for i in range(TAUX * 3 / 2, abime.size()):
		abime[i] += Vector2(0.05, 0.05)
	a.remettre()
	a.ajouter(abime)
	var r: Dictionary = a.resultat()
	var trouve: int = r["craquements"]
	var quand: float = float(r["gauche"]["premier_clic"]) / TAUX
	# montée brusque mais douce (le son passe de rien à −11 dB en 10 ms, comme un moteur qui s'allume net)
	var flux2 = ClassDB.instantiate("SyntheSon")
	flux2.taux = TAUX
	var pb2 = flux2.instantiate_playback()
	pb2.start(0.0)
	a.remettre()
	_mixer(pb2, TAUX / 2, a)
	for j in 30:
		e[j] *= 100.0
	flux2.regler_bandes(e)
	_mixer(pb2, TAUX, a)
	var montee: int = a.resultat()["craquements"]
	_resultat(propre == 0 and trouve >= 1 and absf(quand - 1.5) < 0.01 and montee == 0, titre,
		"Bruit propre : %d craquement ; avec un petit saut caché dedans : %d trouvé(s) (gauche et droite), à %.3f s (vrai : 1,500 s) ; un son qui démarre fort en 10 ms : %d (ce n'est pas un clic)." % [
			propre, trouve, quand, montee])


## 10 minutes de vol, calculées plus vite que le temps réel : tout ce qui change le son, souvent et brusquement.
## Chaque voix C++ est calculée ici (comme le fil audio de Godot le ferait) et écoutée par le détecteur.
func _test_vol_10_minutes() -> void:
	var titre := "10 minutes de vol sans un seul craquement"
	if not _cpp(titre):
		return
	var t_debut := Time.get_ticks_msec()
	var v = _vaisseau_air(1000.0, 150.0)
	var s = _son(v)
	s.hors_ligne = true
	var lectures := {}
	var analyses := {}
	for nv in s.voix_directes:
		var flux = s.voix_directes[nv]["flux"]
		flux.taux = TAUX
		flux.remettre_mesures()
		var pb = flux.instantiate_playback()
		pb.start(0.0)
		lectures[nv] = pb
		analyses[nv] = ClassDB.instantiate("AnalyseSon")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var gaz := 0.0
	var ordre := Vector3.ZERO
	var prochain_ordre := 0.0
	var prochain_gaz := 0.0
	var gaz_doux := false
	var gaz_cible := 0.0
	var accel := 1
	var en_pause := false
	var fin_reglage := 0.0
	var energie_max := 0.0
	var secondes_son := 0.0   # temps où une voix est audible
	var air := 0
	for i in 600 * 120:
		var t := i * PAS
		var morceau := int(t / 20.0)
		if i % (20 * 120) == 0:
			# toutes les 20 s, un autre endroit : dans le vide, près du sol, très haut et très vite
			air = morceau % 3
			v.ecrase = false
			v.omega = Vector3.ZERO
			v.orientation = Quaternion(Vector3.BACK, deg_to_rad(-90.0))
			match air:
				0:
					v.atmosphere = null
					v.gm = 0.0
					v.px = R + 5.0e5
					v.vx = 0.0
					v.vz = 0.0
				1:
					v.atmosphere = Atmosphere.new(R, 0.0)
					v.gm = GM
					v.px = R + 1500.0
					v.vx = 0.0
					v.vz = -rng.randf_range(80.0, 250.0)
				2:
					v.atmosphere = Atmosphere.new(R, 0.0)
					v.gm = GM
					v.px = R + 25000.0
					v.vx = 0.0
					v.vz = -rng.randf_range(500.0, 1200.0)
			v.py = 0.0
			v.pz = 0.0
			v.vy = 0.0
		# manche : de petits coups (les vannes claquent), parfois rien
		if t >= prochain_ordre:
			prochain_ordre = t + rng.randf_range(0.05, 2.0)
			ordre = Vector3.ZERO if rng.randf() < 0.4 else Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		# gaz : coupé net, à fond net, ou qui glisse
		if t >= prochain_gaz:
			prochain_gaz = t + rng.randf_range(0.2, 4.0)
			gaz_doux = rng.randf() < 0.5
			gaz_cible = [0.0, 1.0, rng.randf()][rng.randi() % 3]
			if not gaz_doux:
				gaz = gaz_cible
		if gaz_doux:
			gaz = move_toward(gaz, gaz_cible, PAS * 0.5)
		v.commander(gaz, ordre.x, ordre.y, ordre.z)
		v.pas(PAS)
		# de temps en temps : pause, temps accéléré, vue de dehors
		if t >= fin_reglage:
			fin_reglage = t + rng.randf_range(1.0, 15.0)
			var tirage := rng.randf()
			en_pause = tirage < 0.1
			accel = 100 if tirage > 0.9 else (10 if tirage > 0.8 else 1)
			s.regler(en_pause, accel, rng.randf() < 0.8)
		s.capteurs.temps = t
		s._physics_process(PAS)
		if i % 2 == 0:
			s.mettre_a_jour(1.0 / 60.0)
			var audible := false
			for nv in lectures:
				var morceau_son: PackedVector2Array = lectures[nv].mix_audio(1.0, TAUX / 60)
				analyses[nv].ajouter(morceau_son)
				var en: float = s.voix_directes[nv]["flux"].energie_en_cours()
				energie_max = maxf(energie_max, en)
				audible = audible or en > 1e-6
			if audible:
				secondes_son += 1.0 / 60.0
	var craquements := 0
	var invalides := 0
	var lignes := PackedStringArray()
	var charge := 0.0
	for nv in analyses:
		var r: Dictionary = analyses[nv].resultat()
		var m: Dictionary = s.voix_directes[nv]["flux"].mesures()
		craquements += int(r["craquements"])
		invalides += int(r["non_finis"]) + int(m["non_finis"])
		charge += float(m["charge"])
		lignes.append("voix %s : %d craquement sur %.0f s, crête %.2f" % [nv, r["craquements"],
			float(r["gauche"]["echantillons"]) / TAUX, r["crete"]])
	var duree := (Time.get_ticks_msec() - t_debut) / 1000.0
	_resultat(craquements == 0 and invalides == 0 and secondes_son > 300.0 and charge < 0.02, titre,
		"600 s de vol (vide, près du sol, 25 km à Mach 3 ; gaz coupés et remis net, vannes, pause, x10, x100) : %s ; son audible %.0f s. %d valeur invalide. Coût de la partie C++ : %.2f %% d'un cœur du processeur (budget 1 à 2 %%). Calculé en %.0f s." % [
			"; ".join(lignes), secondes_son, invalides, charge * 100.0, duree])
	_liberer(s)


## En vrai, dans le fil audio de Godot : les voix démarrent, s'arrêtent, repartent (moteur, pause, x100).
func _test_cpp_en_direct() -> void:
	var titre := "Son en direct : démarrer, couper, reprendre sans clic"
	if not _cpp(titre):
		return
	var v = _vaisseau_vide()
	var s = _son(v, true)
	for vx in s.voix:
		(vx["lecteur"] as AudioStreamPlayer3D).bus = "Alarmes"   # les claquements voulus (vannes) à part
	var captures := {}
	for nom in ["Structure", "Exterieur"]:
		var i_bus := AudioServer.get_bus_index(nom)
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 1.0
		AudioServer.add_bus_effect(i_bus, cap)
		captures[nom] = [cap, i_bus, AudioServer.get_bus_effect_count(i_bus) - 1, ClassDB.instantiate("AnalyseSon")]
	s.remettre_mesures_fil_audio()
	# [instant (s), action]
	var etapes := [[0.3, "moteur"], [1.5, "roulis"], [2.3, "lacher"], [3.0, "pause"], [4.0, "reprise"],
		[5.0, "x100"], [6.0, "x1"], [7.0, "coupe"], [8.5, "moteur"], [9.3, "pause"], [9.8, "fin"]]
	var depart := Time.get_ticks_msec()
	var k := 0
	var arrets := 0
	var departs := 0
	var joue_avant := false
	var l_structure := s.voix_directes["structure"]["lecteur"] as AudioStreamPlayer
	while k < etapes.size():
		await get_tree().process_frame
		var t := (Time.get_ticks_msec() - depart) / 1000.0
		while k < etapes.size() and t >= float(etapes[k][0]):
			match etapes[k][1]:
				"moteur":
					v.moteurs[4]["actuel"] = 1.0
				"roulis":
					v.commander(0.0, 0.0, 0.0, 1.0)
				"lacher":
					v.commander(0.0, 0.0, 0.0, 0.0)
				"pause":
					s.regler(true, 1, true)
				"reprise", "x1":
					s.regler(false, 1, true)
				"x100":
					s.regler(false, 100, true)
				"coupe":
					v.moteurs[4]["actuel"] = 0.0
			k += 1
		for nom in captures:
			var c: Array = captures[nom]
			var n: int = c[0].get_frames_available()
			if n > 0:
				c[3].ajouter(c[0].get_buffer(n))
		var joue := l_structure.playing
		if joue and not joue_avant:
			departs += 1
		if joue_avant and not joue:
			arrets += 1
		joue_avant = joue
	var craquements := 0
	var lignes := PackedStringArray()
	for nom in captures:
		var c: Array = captures[nom]
		AudioServer.remove_bus_effect(c[1], c[2])
		var r: Dictionary = c[3].resultat()
		craquements += int(r["craquements"]) + int(r["non_finis"])
		lignes.append("%s : %d craquement (%.1f s écoutées)" % [nom, r["craquements"], float(r["gauche"]["echantillons"]) / AudioServer.get_mix_rate()])
	var charge: float = s.charge_fil_audio()
	_resultat(craquements == 0 and departs >= 3 and arrets >= 3, titre,
		"10 s dans le vrai fil audio : la voix des moteurs a démarré %d fois et s'est arrêtée %d fois ; %s. Charge du fil audio : %.2f %% d'un cœur." % [
			departs, arrets, "; ".join(lignes), charge * 100.0])
	_liberer(s)
	await get_tree().process_frame


# =====================================================================
# 4. CE QUI SORT VRAIMENT DES HAUT-PARLEURS
# =====================================================================
## Pour chaque couche, on mesure le son qui sort de son bus et on le compare au niveau calculé.
func _test_calibration() -> void:
	var lignes := PackedStringArray()
	var pire := 0.0
	for cas in ["structure", "rcs", "jet", "souffle"]:
		var v
		match cas:
			"structure":
				v = _vaisseau_vide()
				v.moteurs[4]["actuel"] = 1.0
			"rcs":
				v = _vaisseau_vide()
				v.commander(0.0, 0.0, 0.0, 1.0)   # roulis : les 4 propulseurs des bouts d'ailes
			"jet":
				v = _vaisseau_air(500.0, 0.0)
				v.moteurs[4]["actuel"] = 1.0
			"souffle":
				v = _vaisseau_air(1000.0, 150.0)
		var s = _son(v, true)
		# le bus où joue la couche (phase 1 : un bus par couche ; phase 2 : celui de sa voix fabriquée en direct)
		var bus: String = (s.couches[cas]["lecteur"] as AudioStreamPlayer).bus
		var i_bus := AudioServer.get_bus_index(bus)
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.5
		AudioServer.add_bus_effect(i_bus, cap)
		var i_cap := AudioServer.get_bus_effect_count(i_bus) - 1
		await get_tree().create_timer(1.7).timeout   # le son bref de départ (allumage, vanne) est fini
		cap.clear_buffer()
		var somme := 0.0
		var n := 0
		var energie := 0.0   # niveau calculé, moyenné sur le même temps (le vaisseau accélère : il varie)
		var n_e := 0
		var avec := PackedStringArray()
		# 2 s : le bruit grave du jet (résonance de la verrière à 80 Hz) varie lentement
		var fin := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < fin:
			await get_tree().process_frame
			var k := cap.get_frames_available()
			if k > 0:
				for f in cap.get_buffer(k):
					somme += f.x * f.x
					n += 1
			# toutes les couches qui jouent sur ce bus (ex. : les petits propulseurs qui tiennent le vaisseau)
			for nom in s.couches:
				var l := s.couches[nom]["lecteur"] as AudioStreamPlayer
				var joue: bool = l.playing
				if s.couches[nom].has("voix"):
					joue = joue and float(s.couches[nom]["energie"]) > 0.0   # couche cachée ou trop faible : rien
				if l.bus == bus and joue:
					energie += pow(10.0, (_niveau(s, nom) - MoteurAudio.ZERO_DBFS + s.gain) / 10.0)
					if not nom in avec:
						avec.append(nom)
			n_e += 1
		AudioServer.remove_bus_effect(i_bus, i_cap)
		var mesure := 10.0 * log(maxf(somme / maxi(n, 1), 1e-20)) / log(10.0)
		var attendu: float = 10.0 * log(maxf(energie / maxi(n_e, 1), 1e-30)) / log(10.0)
		var ecart := mesure - attendu
		pire = maxf(pire, absf(ecart))
		lignes.append("%s (%s) %.1f dB calculé, %.1f dB mesuré" % [cas, " + ".join(avec), attendu, mesure])
		_liberer(s)
		await get_tree().process_frame
	_resultat(pire < 1.5, "Ce qui sort = ce qui est calculé",
		"Son mesuré à la sortie de chaque bus (dB pleine échelle) : %s. Plus grand écart %.2f dB (tolérance 1,5 ; le grave du jet varie naturellement d’environ ±1 dB sur 2 s)." % ["; ".join(lignes), pire])
