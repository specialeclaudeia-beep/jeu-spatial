extends Node
## Tests automatiques du moteur audio (phases 1 à 4). À part des tests de physique.
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
const Chocs = preload("res://scripts/son/chocs.gd")
const SolSon = preload("res://scripts/son/sol_son.gd")
const PoussiereSon = preload("res://scripts/son/poussiere_son.gd")
const CoteSon = preload("res://scripts/son/cote_son.gd")
const TensionSon = preload("res://scripts/son/tension_son.gd")
const C_LUMIERE := 299792458.0
const UA := 1.495978707e11
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
	# « -- --seul=kaiser » ne lance que les tests dont le nom contient « kaiser » (pour aller vite pendant un réglage)
	var seul := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seul="):
			seul = a.substr(7)
	for nom in ["_test_physique_intacte",
			"_test_capteurs",
			"_test_paroi",
			"_test_couche_limite",
			"_test_vide",
			"_test_jets",
			"_test_structure",
			"_test_evenements",
			"_test_temps_pause",
			"_test_voix",
			"_test_plafond",
			"_test_repetitions",
			"_test_prises_sol",
			"_test_toucher",
			"_test_rouler",
			"_test_raclage",
			"_test_verins",
			"_test_vitesse",
			"_test_cpp_niveaux",
			"_test_cpp_resonances",
			"_test_cpp_detecteur",
			"_test_chocs_niveau",
			"_test_chocs_tempete",
			"_test_vol_10_minutes",
			"_test_charges_somme",
			"_test_charges_centrifuge_pose",
			"_test_cas_de_calcul",
			"_test_kaiser_relachement",
			"_test_tics_thermiques",
			"_test_poussiere",
			"_test_phase4_en_jeu",
			"_test_cote_propulseurs"]:
		if seul == "" or seul in nom:
			call(nom)
	for nom in ["_test_cpp_en_direct", "_test_calibration"]:
		if seul == "" or seul in nom:
			await call(nom)
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
	var ouverture: Array = _vannes(s._demandes)
	v.rcs[0]["actuel"] = 0.0
	s._physics_process(PAS)   # trop tôt : la même vanne ne reclaque pas avant 70 ms
	var trop_tot: int = _vannes(s._demandes).size()
	s.mettre_a_jour(1.0 / 60.0)
	s.capteurs.temps += 0.1
	v.rcs[0]["actuel"] = 1.0
	s._physics_process(PAS)
	v.rcs[0]["actuel"] = 0.0
	s.capteurs.temps += 0.1
	s._physics_process(PAS)
	var fermeture: Array = _vannes(s._demandes)
	s.mettre_a_jour(1.0 / 60.0)
	v.moteurs[4]["actuel"] = 0.6
	v.moteurs[4]["consigne"] = 1.0
	s._physics_process(PAS)
	var allumage: Array = _vannes(s._demandes)
	var ok: bool = ouverture.size() == 1 and ouverture[0][0] == "rcs_ouverture" and trop_tot == 1 \
		and fermeture.size() == 2 and fermeture[1][0] == "rcs_fermeture" and allumage.size() == 1 and allumage[0][0] == "moteur_allumage" \
		and float(ouverture[0][1]) > 80.0 and float(ouverture[0][1]) < 92.0 and float(allumage[0][1]) > 75.0
	_resultat(ok, "Sons brefs : vannes et allumages",
		"Vanne du nez ouverte : « %s » à %.1f dB ; refermée 8 ms après : rien (%d demande) ; puis « %s ». Moteur central allumé : « %s » à %.1f dB." % [
			ouverture[0][0] if ouverture.size() else "rien", float(ouverture[0][1]) if ouverture.size() else 0.0, trop_tot,
			fermeture[1][0] if fermeture.size() > 1 else "rien", allumage[0][0] if allumage.size() else "rien", float(allumage[0][1]) if allumage.size() else 0.0])
	_liberer(s)


## Les demandes des vannes et des moteurs seulement (sans les craquements de la phase 4 : ici, le moteur s'allume
## d'un coup sans que le vaisseau accélère, ce qui charge vraiment son support).
func _vannes(demandes: Array) -> Array:
	return demandes.filter(func(d): return String(d[0]).begins_with("rcs") or String(d[0]).begins_with("moteur"))


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
	var apres: int = s.get_child_count() + _pilotes[0].get_child_count()
	var ok: bool = voix_max <= MoteurAudio.VOIX_MAX and voix_max > 8 and not invalide and apres == noeuds and s.joues > 50
	_resultat(ok, "Tempête de sons : 24 voix au plus",
		"5 s de vannes qui claquent sans arrêt (22 propulseurs) et de moteurs qui s'allument : au plus %d voix en même temps (limite 24 : couches + 16 chocs fabriqués en direct), %d sons brefs joués, %d écartés (trop faibles, cachés ou sans place). Aucun nœud créé en jeu : %s. Volume invalide : %s." % [
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
	# chaque choc est tiré au hasard dans sa matière : jamais deux fois le même ; plus fort = plus bref = plus aigu
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pareils := 0
	var precedent := PackedFloat32Array()
	for k in 200:
		var r := Chocs.recette("rcs_ouverture", 0.6, 1e-3, rng)
		if r["modes"] == precedent:
			pareils += 1
		precedent = r["modes"]
	var aigus := []   # part de l'énergie au-dessus de 90 Hz
	for i in [0.1, 0.9]:
		var moy := 0.0
		for k in 50:
			var p: PackedFloat64Array = Chocs.recette("pneu_toucher", i, 1e-3, rng)["parts"]
			for b in range(2, 10):
				moy += p[b] / 50.0
		aigus.append(moy)
	var ok: bool = pareils == 0 and aigus[1] > 1.2 * aigus[0]
	_resultat(ok, "Chocs : jamais deux fois le même",
		"200 vannes de suite : %d fois la même recette (attendu 0). Pneu qui touche doucement / fort : %.1f %% / %.1f %% de l'énergie au-dessus de 90 Hz (un choc rapide est plus bref, donc plus aigu : loi de Hertz)." % [
			pareils, aigus[0] * 100.0, aigus[1] * 100.0])


# =====================================================================
# 2 bis. PHASE 3 : LE SOL (prises en lecture seule, chocs par l'énergie ½ m v²)
# =====================================================================
## Vaisseau posé (ou à h m au-dessus de son posé), sans air, haut vers +X, avant vers −Z, qui roule à u m/s et
## descend à w m/s. train = false : sur le ventre.
func _vaisseau_sol(h: float, u: float, w := 0.0, train := true):
	var v = VaisseauPhysique.new()
	v.reactivite_moteurs = 1e-6
	v.gm = GM
	v.rayon_planete = R
	v.orientation = Quaternion(Vector3(0, 0, 1), -PI / 2)
	if train:
		v.sortir_train(true)
		v.train = 1.0
	v.px = R + (1.56 if train else 1.0) + h
	v.vz = -u
	v.vx = -w
	return v


## n pas de physique (1/120 s) avec le son ; renvoie les sons brefs demandés [nom, dB, …].
func _rouler(v, s, n: int, avant := Callable()) -> Array:
	var ev := []
	for i in n:
		if avant.is_valid():
			avant.call(i)
		v.pas(PAS)
		s._physics_process(PAS)
		ev.append_array(s._demandes)
		if i % 2 == 0:
			s.mettre_a_jour(1.0 / 60.0)
		else:
			s._demandes.clear()
	return ev


func _compter(ev: Array, nom: String) -> int:
	return ev.filter(func(e): return e[0] == nom).size()


func _max_db(ev: Array, nom: String) -> float:
	var m := -INF
	for e in ev:
		if e[0] == nom:
			m = maxf(m, float(e[1]))
	return m


func _test_prises_sol() -> void:
	# deux vaisseaux identiques : posé à 1,2 m/s en roulant à 40 m/s, freins, roue avant qui braque, train
	# rentré (il racle sur le ventre) ; l'un avec le son, l'autre sans
	var a = _vaisseau_sol(0.3, 40.0, 1.2)
	var b = _vaisseau_sol(0.3, 40.0, 1.2)
	var s = _son(b)
	for i in 120 * 8:
		var t := i * PAS
		for v in [a, b]:
			v.commander(0.0, 0.0, 0.0, 0.0)
			v.braquage_consigne = sin(t * 1.7)
			v.frein = 1.0 if t > 2.0 and t < 3.0 else (0.4 if t > 3.0 else 0.0)
			if i == 120 * 5:
				v.sortir_train(false)
			v.pas(PAS)
		s._physics_process(PAS)
		if i % 2 == 0:
			s.mettre_a_jour(1.0 / 60.0)
	var ea := _etat_physique(a)
	var eb := _etat_physique(b)
	ea.append_array([a.braquage, a.train, a.frein_parc, a.vitesse_impact])
	eb.append_array([b.braquage, b.train, b.frein_parc, b.vitesse_impact])
	var ecarts := 0
	for k in ea.size():
		if ea[k] != eb[k]:
			ecarts += 1
	_resultat(ecarts == 0 and s.joues > 3, "Sol : la physique ne change pas",
		"8 s au sol (posé à 1,2 m/s en roulant à 40 m/s, freins, roue avant qui braque, train rentré : la coque racle), un vaisseau avec le son, un sans : %d valeurs sur %d différentes (attendu 0). Sons brefs joués : %d." % [
			ecarts, ea.size(), s.joues])
	_liberer(s)


func _test_toucher() -> void:
	var niveaux := []
	var lignes := PackedStringArray()
	var ok := true
	for w in [0.5, 1.0]:
		var v = _vaisseau_sol(0.05, 60.0, w)
		var s = _son(v)
		var ev := _rouler(v, s, 120)
		var n_t := _compter(ev, "pneu_toucher")
		var n_c := _compter(ev, "pneu_crissement")
		niveaux.append(_max_db(ev, "pneu_toucher"))
		ok = ok and n_t >= 2 and n_c >= 1 and not v.ecrase
		lignes.append("%.1f m/s : %d pneus qui touchent (le plus fort %.1f dB), %d crissements" % [w, n_t, niveaux[-1], n_c])
		_liberer(s)
	var ecart: float = niveaux[1] - niveaux[0]
	ok = ok and absf(ecart - 6.02) < 1.0
	_resultat(ok, "Posé : les pneus touchent et crissent",
		"Posé en roulant à 60 m/s : %s. Deux fois plus vite = 4 fois plus d'énergie (½ m v²) : %+.1f dB (attendu +6,0)." % [
			" ; ".join(lignes), ecart])


func _test_rouler() -> void:
	var r := {}
	for cas in ["10", "40", "frein", "bloque", "cote"]:
		var v = _vaisseau_sol(0.0, 40.0 if cas != "10" else 10.0)
		if cas == "cote":
			v.vy = 4.0   # il glisse de côté : les pneus dérapent
		var s = _son(v)
		var frein := 0.0
		match cas:
			"frein":
				frein = 0.4
			"bloque":
				frein = 1.0
		var der_max := [-INF]
		_rouler(v, s, 60, func(i: int) -> void:
			v.frein = frein
			der_max[0] = maxf(der_max[0], float(s.sol.niveaux["derapage"])))
		r[cas] = [float(s.sol.niveaux["roulage"]), float(s.sol.niveaux["frein"]), der_max[0], s.sol.vitesse_roulage]
		_liberer(s)
	var ecart: float = r["40"][0] - r["10"][0]
	var v_ratio: float = r["40"][3] / r["10"][3]
	var attendu := 25.0 * log(v_ratio) / log(10.0)
	var ok: bool = absf(ecart - attendu) < 1.0 and r["10"][2] == -INF and r["40"][1] == -INF and r["frein"][1] > 50.0 \
		and r["bloque"][2] > 60.0 and r["cote"][2] > 60.0
	_resultat(ok, "Rouler, freiner, déraper",
		"Roulement à %.1f m/s : %.1f dB ; à %.1f m/s : %.1f dB (%+.1f, loi en 25 log v : %+.1f). Freins à 40 %% : frein %.1f dB, dérapage %s. Freins à fond (roues bloquées) : dérapage %.1f dB. Glisse de côté à 4 m/s : dérapage %.1f dB." % [
			r["10"][3], r["10"][0], r["40"][3], r["40"][0], ecart, attendu, r["frein"][1], str(r["frein"][2]), r["bloque"][2], r["cote"][2]])


func _test_raclage() -> void:
	var v = _vaisseau_sol(0.1, 20.0, 0.8, false)
	var s = _son(v)
	var ev := _rouler(v, s, 90)
	var racle: float = s.sol.niveaux["raclage"]
	var n := _compter(ev, "coque_choc")
	var ok: bool = n >= 1 and racle > 70.0 and not v.ecrase
	_resultat(ok, "Sur le ventre : la coque tape et racle",
		"Train rentré, posé à 0,8 m/s en avançant à 20 m/s : %d chocs de la coque (le plus fort %.1f dB), raclage %.1f dB." % [n, _max_db(ev, "coque_choc"), racle])
	_liberer(s)


func _test_verins() -> void:
	var v = _vaisseau_vide()
	v.sortir_train(true)
	var s = _son(v)
	var ev := []
	var bouge := -INF
	for i in 120 * 4:
		v.pas(PAS)
		s._physics_process(PAS)
		ev.append_array(s._demandes)
		if i % 2 == 0:
			s.mettre_a_jour(1.0 / 60.0)
			if i == 120:
				bouge = s.sol.niveaux["verins"]
		else:
			s._demandes.clear()
	var arret: float = s.sol.niveaux["verins"]
	var ok: bool = _compter(ev, "verin_depart") == 1 and _compter(ev, "verin_arret") == 1 and _compter(ev, "verrouillage") == 1 \
		and bouge > 50.0 and arret == -INF and v.train == 1.0
	_resultat(ok, "Vérins : le train qui sort",
		"Sortie du train (3 s) : départ %d, arrêt %d, verrou %d (attendu 1, 1, 1) ; pompe et huile pendant la course %.1f dB, après : %s." % [
			_compter(ev, "verin_depart"), _compter(ev, "verin_arret"), _compter(ev, "verrouillage"), bouge, str(arret)])
	_liberer(s)


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
	# 500 µs (3 % d'une image) : depuis la phase 4, la charge de chaque pièce est calculée 120 fois par seconde
	# (≈ 80 µs par image) ; le cloud varie lui-même de ±50 µs d'un essai à l'autre
	_resultat(us < 500.0, "Léger : temps de calcul du son",
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
## Les chocs fabriqués en direct : le niveau demandé sort (100 premières ms), puis le silence.
func _test_chocs_niveau() -> void:
	var titre := "Chocs fabriqués en direct : le niveau demandé sort"
	if not _cpp(titre) or not ClassDB.class_exists("ChocsSon"):
		_resultat(false, titre, "classe C++ ChocsSon absente")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var pire := 0.0
	var lignes := PackedStringArray()
	var fin_ok := true
	for famille in Chocs.FAMILLES:
		var c = ClassDB.instantiate("ChocsSon")
		c.taux = TAUX
		var pb = c.instantiate_playback()
		pb.start(0.0)
		var r := Chocs.recette(famille, 0.6, 1e-3, rng)   # −30 dB pleine échelle
		c.frapper(r["modes"], r["options"])
		var b: PackedVector2Array = _mixer(pb, int(0.1 * TAUX), null, true)
		var e := 0.0
		for f in b:
			e += f.x * f.x
		var ecart := _db(e / b.size() / 1e-3)
		pire = maxf(pire, absf(ecart))
		_mixer(pb, int((float(r["duree"]) + 0.02) * TAUX))
		var fini: bool = c.est_silencieux()
		fin_ok = fin_ok and fini and int(c.mesures()["non_finis"]) == 0
		lignes.append("%s %+.2f" % [famille, ecart])
	_resultat(pire < 1.0 and fin_ok, titre,
		"14 familles demandées à −30 dB (moyenne des 100 premières ms), écart en dB : %s. Plus grand écart %.2f dB (tolérance 1). Tous finis et silencieux après leur durée calculée : %s." % [
			", ".join(lignes), pire, _oui(fin_ok)])


## Tempête de chocs : 40 par seconde pendant 10 s ; 16 à la fois au plus, rien d'invalide, et léger.
func _test_chocs_tempete() -> void:
	var titre := "Tempête de chocs : 16 à la fois, léger"
	if not ClassDB.class_exists("ChocsSon"):
		_resultat(false, titre, "classe C++ ChocsSon absente")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var c = ClassDB.instantiate("ChocsSon")
	c.taux = TAUX
	var pb = c.instantiate_playback()
	pb.start(0.0)
	var familles: Array = Chocs.FAMILLES.keys()
	for i in 10 * 60:
		for k in 2 if i % 3 != 0 else 0:
			var f: String = familles[rng.randi() % familles.size()]
			var g := Chocs.panoramique(Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-5, 5)), Vector3.ZERO)
			var r := Chocs.recette(f, rng.randf(), pow(10.0, rng.randf_range(-40.0, -15.0) / 10.0), rng, g.x, g.y, float(rng.randi() % 5))
			c.frapper(r["modes"], r["options"])
		_mixer(pb, TAUX / 60)
	var m: Dictionary = c.mesures()
	var ok: bool = int(m["actifs_max"]) <= 16 and int(m["non_finis"]) == 0 and float(m["charge"]) < 0.03 and int(m["joues"]) > 300
	_resultat(ok, titre,
		"10 s, 40 chocs par seconde (toutes les familles, toutes les forces) : %d joués, au plus %d en même temps (limite 16), %d remplacés par un plus important, %d perdus ; %d valeur invalide ; crête %.2f. Coût : %.2f %% d'un cœur du processeur (cloud)." % [
			m["joues"], m["actifs_max"], m["voles"], m["refuses"], m["non_finis"], m["crete"], float(m["charge"]) * 100.0])


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
	# budget 2,5 % d'un cœur : 1,9 à 2,0 % mesurés sans le côté des sons (le cloud varie d'un jour à l'autre),
	# + 0,1 % pour le côté (phase 4)
	_resultat(craquements == 0 and invalides == 0 and secondes_son > 300.0 and charge < 0.025, titre,
		"600 s de vol (vide, près du sol, 25 km à Mach 3 ; gaz coupés et remis net, vannes, pause, x10, x100) : %s ; son audible %.0f s. %d valeur invalide. Coût de la partie C++ : %.2f %% d'un cœur du processeur (budget 2,5 %%). Calculé en %.0f s." % [
			"; ".join(lignes), secondes_son, invalides, charge * 100.0, duree])
	_liberer(s)


## En vrai, dans le fil audio de Godot : les voix démarrent, s'arrêtent, repartent (moteur, pause, x100).
func _test_cpp_en_direct() -> void:
	var titre := "Son en direct : démarrer, couper, reprendre sans clic"
	if not _cpp(titre):
		return
	var v = _vaisseau_vide()
	var s = _son(v, true)
	if s.lecteur_chocs != null:
		s.lecteur_chocs.bus = "Alarmes"   # les claquements voulus (vannes) à part
	# les tests d'avant ont laissé des lecteurs de chocs qui sonnaient encore ; ils disparaissent à l'image
	# suivante (coupés net) : on attend qu'ils soient partis avant d'écouter
	for k in 4:
		await get_tree().process_frame
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
		lignes.append("%s : %d craquement (%.1f s écoutées%s)" % [nom, r["craquements"], float(r["gauche"]["echantillons"]) / AudioServer.get_mix_rate(),
			", le premier à %.2f s" % float(r["gauche"]["premier_clic"]) if int(r["craquements"]) > 0 and r["gauche"].has("premier_clic") else ""])
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


# =====================================================================
# 4. PHASE 4 : TENSION DES PIÈCES, POUSSIÈRE DE L'ESPACE
# =====================================================================
## Toutes les masses du modèle prises comme une seule « pièce » : ce qu'il faut pour les faire suivre le vaisseau
## (d'Alembert) doit retomber sur les forces du dehors (moteurs, propulseurs, air), à 0,1 % près.
func _test_charges_somme() -> void:
	var v = _vaisseau_air(3000.0, 200.0)
	var s = _son(v)
	var ch = s.tension.charges
	var pire := 0.0
	var ref := 0.0
	for i in 360:
		var t := i * PAS
		v.commander(0.8, 0.6 * sin(t * 3.0), 0.2 * sin(t * 1.7), 0.5 * sin(t * 2.3))
		v.pas(PAS)
		s._physics_process(PAS)
		if i < 120:
			continue
		var c = s.capteurs
		var dehors := Vector3.ZERO
		for k in c.nombre:
			dehors += c.directions[k] * c.forces[k]
		for f in c.air_f:
			dehors += f
		var besoin := Vector3.ZERO
		for e in ch.modele.tous:
			var r: Vector3 = (e[1] as Vector3) - c.centre_gravite
			besoin += (c.acceleration + c.alpha.cross(r) + c.omega.cross(c.omega.cross(r))) * float(e[0])
		pire = maxf(pire, (besoin - dehors).length())
		ref = maxf(ref, dehors.length())
	var ecart := pire / maxf(ref, 1.0)
	_resultat(ecart < 0.001, "Charges : la somme retombe sur les forces de la physique",
		"2 s de vol dans l'air, gaz à 80 %%, manche qui bouge : les %d masses du modèle (%.0f kg) suivent le vaisseau avec exactement les forces du dehors (moteurs, propulseurs, air sur 9 surfaces) : écart au pire %.3f %% (limite 0,1 %%)." % [
			ch.modele.tous.size(), ch.modele.masse_totale, ecart * 100.0])
	_liberer(s)


## Deux cas qu'on calcule à la main : le vaisseau qui tourne sur lui-même (chaque aile tire sur son emplanture
## avec m ω² r) et le vaisseau posé (le train porte le poids, 86 % sur les roues arrière).
func _test_charges_centrifuge_pose() -> void:
	var v = _vaisseau_vide()
	v.omega = Vector3(0.0, TAU, 0.0)   # 1 tour par seconde autour de l'axe vertical
	var s = _son(v)
	_images(s, 3)
	var ch = s.tension.charges
	var pire := 0.0
	for i in 8:   # les 4 ailes et leurs réacteurs
		var c: Vector3 = ch.centres[i]
		var attendu: Vector3 = -Vector3(c.x, 0.0, c.z) * (float(ch.masses[i]) * TAU * TAU)
		pire = maxf(pire, (ch.force[i] - attendu).length() / attendu.length())
	var f_aile: float = ch.force[0].length()
	_liberer(s)
	# posé, moteurs coupés : 3 s pour se poser bien à plat
	var p = _vaisseau_sol(0.0, 0.0)
	var s2 = _son(p)
	for i in 360:
		p.commander(0.0, 0.0, 0.0, 0.0)
		p.pas(PAS)
		s2._physics_process(PAS)
	var ch2 = s2.tension.charges
	var jambes := [ch2.noms.find("jambe avant"), ch2.noms.find("jambe arrière gauche"), ch2.noms.find("jambe arrière droit")]
	var porte := 0.0
	var arriere := 0.0
	var m_jambes := 0.0
	for k in 3:
		var f: float = -(ch2.force[jambes[k]] as Vector3).y   # le sol pousse la roue vers le haut, l'attache la retient
		porte += f
		m_jambes += float(ch2.masses[jambes[k]])
		if k > 0:
			arriere += f
	var attendu_porte: float = (p.masse - m_jambes) * 9.81
	var part := arriere / porte
	var ok := pire < 1e-6 and absf(porte / attendu_porte - 1.0) < 0.03 and absf(part - 0.86) < 0.03
	_resultat(ok, "Charges : force centrifuge et vaisseau posé",
		"Vaisseau qui tourne à 1 tour/s : chaque aile tire sur son emplanture avec m ω² r (%.0f kN pour l'aile haut gauche), écart au calcul à la main %.7f. Posé : les 3 jambes portent %.0f kN (poids moins les jambes : %.0f kN), dont %.0f %% sur les deux roues arrière (centre de gravité près d'elles : attendu 86 %%)." % [
			f_aile / 1000.0, pire, porte / 1000.0, attendu_porte / 1000.0, part * 100.0])
	_liberer(s2)


## Les cas de calcul (la résistance supposée de chaque pièce) : chaque pièce atteint 1 / 1,5 = 0,67 dans son
## pire cas ; pleine poussée normale (x1) = 1 / (1,5 × 1,25) = 0,53 pour les supports des réacteurs des ailes (le
## moteur central, plus lourd, est plutôt dimensionné par l'atterrissage à 3 m/s : il reste au-dessous).
func _test_cas_de_calcul() -> void:
	var v = _vaisseau_vide()
	var s = _son(v)
	_images(s, 2)
	var ch = s.tension.charges
	var cas: Dictionary = ch.cas_de_calcul(s.capteurs)
	var t_max := PackedFloat64Array()
	t_max.resize(ch.n)
	t_max.fill(0.0)
	var pire_cas := []
	for i in ch.n:
		pire_cas.append("")
	for nom in cas:
		ch.charger(cas[nom])
		for i in ch.n:
			var t: float = ch.taux_de(ch.force[i], ch.moment[i], ch.limite_f[i], ch.limite_m[i])
			if t > t_max[i]:
				t_max[i] = t
				pire_cas[i] = nom
	var au_max := 0
	var depasse := false
	for i in ch.n:
		if absf(t_max[i] - 1.0 / 1.5) < 1e-6:
			au_max += 1
		depasse = depasse or t_max[i] > 1.0 / 1.5 + 1e-6
	# vraie pleine poussée (x1), dans le vide
	for i in 120:
		v.commander(1.0, 0.0, 0.0, 0.0)
		v.pas(PAS)
		s._physics_process(PAS)
	var central: float = ch.taux[ch.noms.find("moteur central")]
	var reacteur: float = ch.taux[ch.noms.find("réacteur haut gauche")]
	var lignes := PackedStringArray()
	for i in ch.n:
		lignes.append("%s %s" % [ch.noms[i], pire_cas[i]])
	_resultat(au_max >= 12 and not depasse and absf(reacteur - 1.0 / 1.875) < 0.01 and central < 1.0 / 1.875 + 0.01,
		"Charges : la résistance de chaque pièce",
		"%d pièces sur %d arrivent à 0,67 de la rupture dans leur pire cas (les autres sont tenues par le minimum de 3 g), aucune au-delà. Pire cas : %s. Pleine poussée x1 : support du réacteur haut gauche à %.3f de la rupture (attendu 1 / 1,875 = 0,533), du moteur central à %.3f (au plus 0,533)." % [
			au_max, ch.n, ", ".join(lignes), reacteur, central])
	_liberer(s)


## Effet Kaiser : une pièce craque quand la charge dépasse ce qu'elle a déjà connu (au départ : l'épreuve, 0,67 de
## la rupture), pas quand on refait la même chose (sauf un peu le composite très chargé : effet Felicity) ; relâchement : charge qui tombe d'un coup (moteurs coupés net),
## mais pas en 0,3 s. Pleine poussée normale (x1) : aucun craquement.
func _test_kaiser_relachement() -> void:
	var v = _vaisseau_vide()
	var s = _son(v)
	_images(s, 2)
	# poussée x1,5 : au-delà de l'épreuve (pleine poussée normale x1 = 0,53 de la rupture, sous l'épreuve à 0,67 : muet)
	var etapes := [["1re poussée", 1.0, 1.5], ["coupé", 0.0, 1.5], ["2e poussée, pareille", 1.0, 1.5], ["coupé", 0.0, 1.5],
		["poussée 20 % plus forte", 1.0, 1.8], ["coupé", 0.0, 1.8]]
	var craq := []
	var dus := []
	var rel := []
	var niveaux := []
	for e in etapes:
		v.regler_poussee(float(e[2]))
		var ev := []
		var dus_avant: int = s.tension.craquements_dus
		for i in 240:
			v.commander(float(e[1]), 0.0, 0.0, 0.0)
			v.pas(PAS)
			s._physics_process(PAS)
			ev.append_array(s._demandes)
			s._demandes.clear()
		craq.append(ev.filter(func(d): return String(d[0]).begins_with("craquement")).size())
		dus.append(s.tension.craquements_dus - dus_avant)
		rel.append(ev.filter(func(d): return String(d[0]).begins_with("relachement")).size())
		var m := -INF
		for d in ev:
			if String(d[0]).begins_with("craquement"):
				m = maxf(m, float(d[1]))
		niveaux.append(m)
	# moteurs qui suivent en 0,3 s (comme dans le jeu) : la charge descend trop doucement pour un relâchement
	var w = VaisseauPhysique.new()
	var s2 = _son(w)
	var rel_doux := 0
	var craq_x1 := 0
	var craq_x1_avant := 0
	for i in 600:
		w.commander(1.0 if i < 360 else 0.0, 0.0, 0.0, 0.0)
		w.pas(PAS)
		s2._physics_process(PAS)
		rel_doux += s2._demandes.filter(func(d): return String(d[0]).begins_with("relachement")).size()
		craq_x1 += s2.tension.craquements_dus - craq_x1_avant
		craq_x1_avant = s2.tension.craquements_dus
		s2._demandes.clear()
	var ok: bool = craq[0] >= 10 and dus[2] * 3 <= dus[0] and dus[4] > 2 * dus[2] and craq[4] >= 5 and rel[1] >= 8 and rel_doux == 0 \
		and craq_x1 == 0
	_resultat(ok, "Craquements : effet Kaiser, relâchements",
		"Poussée x1 : %d craquements (attendu 0, sous l'épreuve). Poussée x1,5 : %d craquements (%d joués, le plus fort %.0f dB) ; refaite pareille : %d (la structure se souvient : %d joués) ; 20 %% plus forte : %d (%d joués, %.0f dB). Moteurs coupés net : %d relâchements ; coupés en 0,3 s comme dans le jeu : %d (attendu 0)." % [
			craq_x1, dus[0], craq[0], niveaux[0], dus[2], craq[2], dus[4], craq[4], niveaux[4], rel[1], rel_doux])
	_liberer(s)
	_liberer(s2)


## De quel côté vient chaque propulseur (demande de Gwenaël) : la partie C++ partage l'énergie entre les oreilles
## comme demandé, sans clic quand ça change ; un petit propulseur au bout de l'aile gauche s'entend nettement à
## gauche ; un réacteur de l'aile gauche (1,6 m sur le côté mais 3,6 m derrière : 25° seulement) un peu à gauche,
## surtout dans les aigus (l'ombre de la tête), celui de droite à droite, les deux ensemble au milieu ; tête tournée
## vers l'arrière : les côtés s'inversent ; dans le jeu, la voix « structure » sort plus fort à gauche.
func _test_cote_propulseurs() -> void:
	var titre := "Côté des propulseurs : gauche, droite, tête qui tourne"
	if not _cpp(titre):
		return
	# 1. partie C++ seule : 80 % à gauche, puis 20 %, d'un coup
	var flux = ClassDB.instantiate("SyntheSon")
	flux.taux = TAUX
	var e := PackedFloat32Array()
	e.resize(30)
	var tot := 0.0
	for j in 30:
		var f := Resonances.centre(j)
		e[j] = Synthese.spectre("structure", f) * f
		tot += e[j]
	for j in 30:
		e[j] *= 1e-3 / tot
	flux.regler_bandes(e)
	var w := PackedFloat32Array()
	w.resize(30)
	w.fill(0.8)
	flux.regler_gauche(w)
	var pb = flux.instantiate_playback()
	pb.start(0.0)
	_mixer(pb, TAUX)
	var a = ClassDB.instantiate("AnalyseSon")
	_mixer(pb, TAUX * 10, a)
	var r: Dictionary = a.resultat()
	var g8 := _db(float(r["gauche"]["energie"]) / 1.6e-3)
	var d8 := _db(float(r["droite"]["energie"]) / 0.4e-3)
	w.fill(0.2)
	flux.regler_gauche(w)
	a.remettre()
	_mixer(pb, TAUX * 2, a)
	var r2: Dictionary = a.resultat()
	var clics: int = int(r2["gauche"]["craquements"]) + int(r2["droite"]["craquements"])
	var cpp_ok := absf(g8) < 0.3 and absf(d8) < 0.5 and clics == 0
	# 2. le calcul : réacteur de l'aile gauche seul, de droite seul, les deux
	var v = _vaisseau_vide()
	var s = _son(v)
	s.hors_ligne = true
	_images(s, 2)
	var c = s.capteurs
	var i_g := -1
	var i_d := -1
	for i in c.nombre:
		if c.types[i] == Capteurs.TYPE_RCS:
			continue
		if c.positions[i].x < -1.0 and (i_g < 0 or c.positions[i].x < c.positions[i_g].x):
			i_g = i
		if c.positions[i].x > 1.0 and (i_d < 0 or c.positions[i].x > c.positions[i_d].x):
			i_d = i
	var i_bout := -1   # petit propulseur au bout d'une aile gauche (bien de côté)
	for i in c.nombre:
		if c.types[i] == Capteurs.TYPE_RCS and c.positions[i].x < -3.0:
			i_bout = i
	for i in c.nombre:
		c.forces[i] = 6000.0 if i == i_bout else 0.0
	s.moteurs.calculer(c, s.oreille, PackedFloat64Array())
	var bout: float = s.moteurs.cote_rcs[5]     # octave de 1 kHz (là où souffle une petite buse)
	var parts := {}
	for cas in [["gauche", [i_g], Basis.IDENTITY], ["droite", [i_d], Basis.IDENTITY], ["les deux", [i_g, i_d], Basis.IDENTITY],
			["gauche, tête vers l'arrière", [i_g], Basis(Vector3.UP, PI)]]:
		for i in c.nombre:
			c.forces[i] = c.poussee_reference if i in cas[1] else 0.0
		s.moteurs.tete = cas[2]
		s.moteurs.calculer(c, s.oreille, PackedFloat64Array())
		parts[cas[0]] = s.moteurs.cote_structure.duplicate()
	s.moteurs.tete = Basis.IDENTITY
	var aigu_g: float = parts["gauche"][7]       # octave de 4 kHz
	var grave_g: float = parts["gauche"][1]      # octave de 62 Hz
	var aigu_d: float = parts["droite"][7]
	var deux: float = parts["les deux"][7]
	var tourne: float = parts["gauche, tête vers l'arrière"][7]
	var dos: float = parts["gauche"][CoteSon.OCTAVES + 9]            # 16 kHz, moteur derrière le pilote
	var devant: float = parts["gauche, tête vers l'arrière"][CoteSon.OCTAVES + 9]
	var calc_ok: bool = i_g >= 0 and i_d >= 0 and i_bout >= 0 and aigu_g > 0.7 and grave_g > 0.52 and grave_g < aigu_g \
		and absf(aigu_d - (1.0 - aigu_g)) < 0.01 and absf(deux - 0.5) < 0.02 and tourne < 0.3 and dos < 0.8 and devant > 0.99 \
		and bout > 0.8
	# 3. dans le chef d'orchestre : réacteur gauche seul pendant 0,5 s, puis ce qui sort de la voix « structure »
	for i in c.nombre:
		c.forces[i] = c.poussee_reference if i == i_g else 0.0
	for k in 30:
		s.mettre_a_jour(1.0 / 60.0)
	var vd: Dictionary = s.voix_directes["structure"]
	var pg: PackedFloat32Array = vd.get("parts_gauche", PackedFloat32Array())
	var pb2 = vd["flux"].instantiate_playback()
	pb2.start(0.0)
	_mixer(pb2, TAUX / 2)
	var a2 = ClassDB.instantiate("AnalyseSon")
	_mixer(pb2, TAUX * 2, a2)
	var r3: Dictionary = a2.resultat()
	var ecart := _db(float(r3["gauche"]["energie"]) / float(r3["droite"]["energie"]))
	var jeu_ok := pg.size() == 30 and absf(pg[22] - aigu_g) < 0.03 and ecart > 1.0
	_resultat(cpp_ok and calc_ok and jeu_ok, titre,
		"Partie C++ : 80 %% à gauche demandé → gauche %+.2f dB, droite %+.2f dB de l'attendu ; passé d'un coup à 20 %% : %d clic. Petit propulseur au bout de l'aile gauche : %.0f %% de l'énergie à gauche à 1 kHz. Réacteur de l'aile gauche seul : %.0f %% de l'énergie à gauche à 4 kHz (ombre de la tête), %.0f %% à 62 Hz ; aile droite seule : %.0f %% à gauche ; les deux : %.0f %% ; tête tournée vers l'arrière : %.0f %% (les côtés s'inversent). Moteur derrière le pilote : aigus à 16 kHz × %.2f (tête tournée : × %.2f). Dans le jeu (voix structure) : %.0f %% à gauche à 4 kHz, la voie gauche sort %.1f dB plus fort que la droite." % [
			g8, d8, clics, 100.0 * bout, 100.0 * aigu_g, 100.0 * grave_g, 100.0 * aigu_d, 100.0 * deux, 100.0 * tourne, dos, devant,
			100.0 * (pg[22] if pg.size() == 30 else 0.0), ecart])
	_liberer(s)


## La coque qui refroidit de 2 degrés par seconde tique (un tic par 1,5 degré) ; qui bouge à peine, rien.
func _test_tics_thermiques() -> void:
	var v = _vaisseau_vide()
	var s = _son(v)
	var comptes := []
	for vitesse in [-2.0, -0.01]:
		v.temperature_nez = 600.0
		var n := 0
		for i in 120 * 30:
			v.temperature_nez += vitesse * PAS
			v.temps_univers += PAS
			s._physics_process(PAS)
			n += s._demandes.filter(func(d): return d[0] == "tic_thermique").size()
			s._demandes.clear()
		comptes.append(n)
	var ok: bool = comptes[0] >= 25 and comptes[0] <= 55 and comptes[1] == 0
	_resultat(ok, "Tics de la coque qui refroidit",
		"Nez qui refroidit de 2 °C par seconde pendant 30 s (60 °C) : %d tics (attendu environ 40, un par 1,5 °C) ; qui bouge de 0,01 °C par seconde : %d (attendu 0)." % comptes)
	_liberer(s)


## Une « photo » fabriquée pour la poussière : vitesse, sens du vol, endroit.
func _photo_lieu(vitesse: float, etoile: float, astre := INF, rayon := 0.0, sens := Vector3(0, 0, -1)) -> Capteurs:
	var c := Capteurs.new()
	c.vitesse = vitesse
	c.gamma = 1.0 / sqrt(1.0 - pow(vitesse / C_LUMIERE, 2.0))
	c.direction = sens
	c.dist_etoile = etoile
	c.dist_astre = astre
	c.rayon_astre = rayon
	c.temps_physique = PAS
	return c


## Fait tourner la poussière n secondes ; renvoie [grains joués un par un, dont audibles (> 47 dB), le plus fort, verrière].
func _grains(p, c: Capteurs, secondes: float) -> Array:
	var joues := 0
	var audibles := 0
	var fort := -INF
	var verre := 0
	for i in int(secondes * 120.0):
		p.detecter(c, Jeu.OEIL_PILOTE_DEFAUT, PAS)
		for e in p.evenements:
			joues += 1
			if float(e[1]) > 47.0:
				audibles += 1
			if e[0] == "poussiere_verre":
				verre += 1
			fort = maxf(fort, float(e[1]))
		p.evenements.clear()
	p.calculer(c)
	return [joues, audibles, fort, verre]


func _test_poussiere() -> void:
	var p := PoussiereSon.new()
	# orbite basse (250 km au-dessus d'une planète de 600 km, à 1 UA de l'étoile)
	var orbite := _grains(p, _photo_lieu(2040.0, UA, R + 250000.0, R), 300.0)
	# entre les étoiles, de plus en plus vite
	var souffles := []
	var par_seconde := []
	for b in [0.2, 0.5, 0.9]:
		var g := _grains(p, _photo_lieu(b * C_LUMIERE, INF), 20.0)
		souffles.append(p.niveau)
		par_seconde.append(float(g[0]) / 20.0)
	var monte: bool = souffles[1] > souffles[0] + 5.0 and souffles[2] > souffles[1] + 5.0 and souffles[2] > 55.0
	var g1: float = p.gamma_moins_un   # à 0,9 c
	var einstein := absf(g1 - (1.0 / sqrt(1.0 - 0.81) - 1.0)) < 1e-6
	# de face ou à reculons (0,5 c) : la verrière, devant, reçoit le vent de face
	var face := _grains(p, _photo_lieu(0.5 * C_LUMIERE, INF), 30.0)
	var dos := _grains(p, _photo_lieu(0.5 * C_LUMIERE, INF, INF, 0.0, Vector3(0, 0, 1)), 30.0)
	# Campbell : à 0,01 c, tous les grains sont trop faibles pour s'entendre seuls : le souffle est leur somme ;
	# 2 fois plus de temps par seconde (temps x2) = 2 fois plus de grains = +3,01 dB
	var lent := _photo_lieu(0.01 * C_LUMIERE, UA)
	_grains(p, lent, 1.0)
	var l1: float = p.niveau
	lent.temps_physique = 2.0 * PAS
	var g2 := _grains(p, lent, 1.0)
	var campbell: float = p.niveau - l1
	# dans l'air (100 km d'altitude environ) : les grains brûlent avant d'arriver
	var air := _photo_lieu(0.5 * C_LUMIERE, UA)
	air.densite = 1.0e-6
	air.temperature = 200.0
	var dans_air := _grains(p, air, 2.0)
	var ok: bool = orbite[1] >= 3 and orbite[1] <= 40 and monte and einstein and par_seconde.max() <= 30.5 \
		and face[3] >= 3 * maxi(dos[3], 1) and absf(campbell - 3.01) < 0.05 and g2[0] == 0 and dans_air[0] == 0 and p.niveau == -INF
	_resultat(ok, "Poussière et gaz de l'espace",
		"Orbite basse : %d grains entendus en 5 min (le plus fort %.0f dB). Entre les étoiles, souffle continu à 0,2 / 0,5 / 0,9 c : %.0f / %.0f / %.0f dB, grains joués un par un : %.1f / %.1f / %.1f par s (au plus 30). Énergie d'Einstein à 0,9 c : (γ − 1) = %.4f, %.2f fois ½ v². Verrière à 0,5 c : %d grains de face, %d à reculons. Campbell : temps x2 = %+.2f dB (attendu +3,01). Dans l'air : %d grain, silence (%s)." % [
			orbite[1], orbite[2], souffles[0], souffles[1], souffles[2], par_seconde[0], par_seconde[1], par_seconde[2],
			g1, g1 / (0.5 * 0.81), face[3], dos[3], campbell, dans_air[0], str(p.niveau)])


## Tout ensemble dans le chef d'orchestre : charges sans valeur invalide, 24 voix au plus, craquements joués,
## couches « tension » et « poussiere » qui arrivent à leur voix.
func _test_phase4_en_jeu() -> void:
	var v = _vaisseau_vide()
	var s = _son(v)
	s.hors_ligne = true
	v.regler_poussee(1.6)   # au-delà de l'épreuve, pour que la structure craque
	_images(s, 2)
	var voix_max := 0
	var invalide := false
	var tension_max := -INF
	var craq_joues := 0
	for i in 120 * 8:
		var t := i * PAS
		v.commander(1.0 if int(t) % 2 == 0 else 0.0, sin(t * 2.0), 0.0, cos(t * 1.3))
		v.pas(PAS)
		s.capteurs.temps = t
		s._physics_process(PAS)
		if i % 2 == 0:
			var avant: int = s.joues
			var demandes: int = s._demandes.filter(func(d): return String(d[0]).begins_with("craquement")).size()
			s.mettre_a_jour(1.0 / 60.0)
			if demandes > 0 and s.joues > avant:
				craq_joues += 1
			voix_max = maxi(voix_max, s.voix_actives())
			tension_max = maxf(tension_max, _niveau(s, "tension"))
		for x in s.tension.charges.taux:
			invalide = invalide or is_nan(x) or is_inf(x)
	# la poussière à 0,9 c, donnée à la main
	s.poussiere.detecter(_photo_lieu(0.9 * C_LUMIERE, INF), s.oreille, PAS)
	s.mettre_a_jour(1.0 / 60.0)
	var pous: float = _niveau(s, "poussiere")
	var ok: bool = not invalide and voix_max <= 24 and craq_joues > 0 and tension_max > 40.0 and absf(pous - s.poussiere.niveau) < 0.01 \
		and pous > 50.0
	_resultat(ok, "Phase 4 dans le chef d'orchestre",
		"8 s de poussées x1,6 coupées et remises, manche qui bouge : charges sans valeur invalide (%s), au plus %d voix (limite 24), craquements joués dans %d images, chant de la structure jusqu'à %.0f dB. Poussière à 0,9 c : couche à %.1f dB (calculé %.1f dB)." % [
			_oui(not invalide), voix_max, craq_joues, tension_max, pous, s.poussiere.niveau])
	_liberer(s)
