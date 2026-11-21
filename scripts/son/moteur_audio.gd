extends Node
## Moteur audio (phase 1) : le « chef d'orchestre ». Il écoute la physique et fait le son du cockpit.
## Il ne modifie JAMAIS la physique : il la lit (capteurs.gd), calcule ce que le pilote entend
## (moteurs_son.gd, fluides_son.gd), puis décide quoi jouer et à quel volume.
##
## Règles (plan du 21/11, réponses de Gwenaël) :
##  - on n'entend que le cockpit, jamais l'espace : l'oreille est toujours celle du pilote, même en vue
##    extérieure ; dans le vide, seul ce qui passe par la structure arrive (le cockpit, lui, est plein d'air) ;
##  - temps accéléré : son normal jusqu'à x10, silence au-delà (sauf les alarmes, quand il y en aura) ;
##  - pause, écran des touches, vaisseau écrasé : fondu au silence en 0,1 s ;
##  - 24 voix au plus : 8 couches continues + 16 sons brefs (16 lecteurs créés une fois pour toutes) ;
##  - priorités : alarmes > chocs > moteurs > air > tension > ambiance ;
##  - un son trop faible (sous −60 dB) ou caché par un autre (20 dB plus fort dans les mêmes fréquences)
##    n'est pas joué ;
##  - volume : on calcule d'abord le vrai niveau dans le cockpit (dB), puis on le ramène à ce qu'un
##    haut-parleur peut rendre. Au-delà de 95 dB, le volume monte 4 fois moins vite (sinon un réglage de
##    poussée x100 000 ferait exploser les oreilles).
##
## Bus de mixage (créés au démarrage) : Structure (vibrations) et Exterieur (passé par la verrière) vont
## dans Cockpit (petite réverbération), qui va dans Master (limiteur). Le souffle a un égaliseur à
## 10 octaves : on lui donne, bande par bande, le spectre calculé par la physique (egaliseur.gd calcule
## exactement ce qui en sort). Les jets n'en ont pas besoin : la forme de leur bruit ne change pas.

const Capteurs = preload("res://scripts/son/capteurs.gd")
const MoteursSon = preload("res://scripts/son/moteurs_son.gd")
const Fluides = preload("res://scripts/son/fluides_son.gd")
const Egaliseur = preload("res://scripts/son/egaliseur.gd")
const Synthese = preload("res://scripts/son/synthese.gd")

const CATALOGUE := "res://sons/sons.json"
const COUCHES_MAX := 8
const LECTEURS := 16
const VOIX_MAX := COUCHES_MAX + LECTEURS
const SEUIL_DB := -60.0          # dB pleine échelle : en dessous, on ne joue pas
const MASQUAGE_DB := 20.0
const FONDU_SILENCE := 0.1       # s
const FONDU_VOIX := 0.03         # s : une voix moins prioritaire qu'on interrompt
const ATTENTE_MAX := 0.06        # s : un son bref qui n'a pas trouvé de lecteur après ça est oublié
const TEMPS_MAX_SON := 10        # au-delà de x10, silence
## Échelle du volume : 107 dB dans le cockpit = pleine échelle (0 dB). Au-delà de 95 dB, compression 4:1 ;
## jamais plus fort que −2 dB pleine échelle (le limiteur du bus Master garde encore 1 dB de marge).
const ZERO_DBFS := 107.0
const GENOU := 95.0
const TAUX_COMPRESSION := 4.0
const PLAFOND := -2.0
const ATTAQUE := 0.02            # s : la compression réagit vite quand ça monte…
const RELACHE := 0.3             # s : … et revient doucement
const RELACHE_COUCHE := 0.06     # s : une couche qui baisse (jet de gaz coupé) s'éteint en ~60 ms

enum { AMBIANCE, TENSION, AIR, MOTEUR, CHOC, ALARME }

# --- branchements ---
var vaisseau = null
var pilote: Node3D = null              # nœud qui suit le vaisseau (centre de gravité à l'origine)
var camera: Camera3D = null
var oreille_scene := Vector3.ZERO      # tête du pilote dans le nœud « pilote »
var oreille := Vector3.ZERO            # la même, repère du modèle (comme la physique)
var capteurs := Capteurs.new()
var moteurs := MoteursSon.new()
var ecoute: AudioListener3D = null
var actif := false

# --- état du jeu (donné par jeu.gd à chaque image) ---
var pause := false
var acc_temps := 1
var vue_interieure := true

# --- mixage ---
var couches := {}       # nom → {lecteur, ref_dbfs, parts (énergie par octave de la boucle), eq, niveau, lisse, priorite}
var voix: Array = []    # lecteurs des sons brefs : {lecteur, priorite, debut, fondu, volume, ref}
var coups := {}         # nom → [{stream, ref_dbfs, parts}]
var _recents := {}      # nom → dernières variantes jouées
var _demandes: Array = []   # sons brefs en attente : [nom, niveau (dB), position, priorite, âge]
var fondu := 0.0        # 0 = silence, 1 = son normal
var gain := 0.0         # dB : réduction de la compression (≤ 0)
var souffle := {}       # dernier calcul du souffle (fluides_son.gd)
var _transm := PackedFloat64Array()
var _z_ext := -1.0
var _rng := RandomNumberGenerator.new()
var ms_par_image := 0.0     # temps de calcul du son par image (moyenne glissante)
var _us_physique := 0
var joues := 0              # sons brefs lancés depuis le début
var oublies := 0            # sons brefs écartés (trop faibles, cachés, pas de lecteur)


## À appeler une fois, après la création du vaisseau et du nœud « pilote ».
## oeil : position de la tête du pilote dans le nœud « pilote » (comme la caméra du cockpit).
func installer(v, noeud_pilote: Node3D, cam: Camera3D, oeil: Vector3) -> void:
	vaisseau = v
	pilote = noeud_pilote
	camera = cam
	oreille_scene = oeil
	capteurs.lire(vaisseau, 0.0)
	oreille = oeil + capteurs.centre_gravite
	_rng.seed = 7
	preparer_bus()
	_charger_sons()
	ecoute = AudioListener3D.new()
	ecoute.name = "OreillePilote"
	pilote.add_child(ecoute)
	ecoute.position = oreille_scene
	ecoute.make_current()
	for i in LECTEURS:
		var l := AudioStreamPlayer3D.new()
		l.name = "Voix%d" % i
		l.bus = "Structure"
		l.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		l.attenuation_filter_cutoff_hz = 20500.0
		l.panning_strength = 0.5   # vibrations de la structure : on devine d'où ça vient, sans plus
		l.max_db = 24.0
		l.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		pilote.add_child(l)
		voix.append({"lecteur": l, "priorite": AMBIANCE, "debut": 0.0, "fondu": -1.0, "volume": -80.0})
	actif = true


## Bus de mixage (une seule fois par partie : ils restent d'une scène à l'autre).
static func preparer_bus() -> void:
	if AudioServer.get_bus_index("Cockpit") >= 0:
		return
	var master := AudioServer.get_bus_index("Master")
	var limiteur := AudioEffectHardLimiter.new()
	limiteur.ceiling_db = -1.0
	AudioServer.add_bus_effect(master, limiteur)
	var cockpit := _nouveau_bus("Cockpit", "Master")
	# petite pièce, parois dures et garnitures : réverbération courte (~0,15 s), discrète
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.08
	reverb.damping = 0.7
	reverb.spread = 1.0
	reverb.hipass = 0.15
	reverb.dry = 1.0
	reverb.wet = 0.08
	reverb.predelay_msec = 4.0
	reverb.predelay_feedback = 0.0
	AudioServer.add_bus_effect(cockpit, reverb)
	_nouveau_bus("Structure", "Cockpit")
	_nouveau_bus("Exterieur", "Cockpit")
	AudioServer.add_bus_effect(_nouveau_bus("Souffle", "Exterieur"), AudioEffectEQ10.new())
	_nouveau_bus("Jet", "Exterieur")
	_nouveau_bus("Alarmes", "Master")


static func _nouveau_bus(nom: String, vers: String) -> int:
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, nom)
	AudioServer.set_bus_send(i, vers)
	return i


func _charger_sons() -> void:
	var f := FileAccess.open(CATALOGUE, FileAccess.READ)
	if f == null:
		push_warning("Son : catalogue %s introuvable" % CATALOGUE)
		return
	var cat = JSON.parse_string(f.get_as_text())
	if not (cat is Dictionary):
		return
	var b: Dictionary = cat["boucles"]
	_couche("structure", "structure", b, "Structure", MOTEUR)
	_couche("rcs", "rcs", b, "Structure", MOTEUR)
	_couche("jet", "jet_moteur", b, "Jet", MOTEUR)
	_couche("jet_rcs", "jet_rcs", b, "Jet", MOTEUR)
	_couche("souffle", "souffle", b, "Souffle", AIR)
	for nom in cat["coups"]:
		var liste := []
		for v in cat["coups"][nom]:
			liste.append({"stream": load(v["fichier"]), "ref_dbfs": float(v["rms_dbfs"]), "parts": PackedFloat64Array(v["bandes"])})
		coups[nom] = liste
		_recents[nom] = []


func _couche(nom: String, boucle: String, catalogue: Dictionary, bus: String, priorite: int) -> void:
	if couches.size() >= COUCHES_MAX or not catalogue.has(boucle):
		return
	var infos: Dictionary = catalogue[boucle]
	var l := AudioStreamPlayer.new()
	l.name = "Couche_" + nom
	l.stream = load(infos["fichier"])
	l.bus = bus
	add_child(l)
	var eq: AudioEffectEQ10 = null
	var m_eq := PackedFloat64Array()
	var i_bus := AudioServer.get_bus_index(bus)
	if i_bus >= 0 and AudioServer.get_bus_effect_count(i_bus) > 0:
		eq = AudioServer.get_bus_effect(i_bus, 0) as AudioEffectEQ10
	if eq != null:
		# ce que l'égaliseur de Godot fait vraiment à cette boucle (une fois pour toutes)
		var forme: String = Synthese.BOUCLES[boucle]["spectre"]
		m_eq = Egaliseur.matrice(func(f: float) -> float: return Synthese.spectre(forme, f), AudioServer.get_mix_rate())
	couches[nom] = {"lecteur": l, "ref_dbfs": float(infos["rms_dbfs"]), "parts": PackedFloat64Array(infos["bandes"]),
		"eq": eq, "m_eq": m_eq, "niveau": -INF, "lisse": -INF, "priorite": priorite, "bandes_db": PackedFloat64Array(),
		"volume": -80.0}


## L'état du jeu, à donner à chaque image.
func regler(en_pause: bool, acceleration: int, vue_cockpit: bool) -> void:
	pause = en_pause
	acc_temps = acceleration
	vue_interieure = vue_cockpit


## Le son est-il permis maintenant ? (sinon : fondu au silence)
func son_permis() -> bool:
	return not pause and acc_temps <= TEMPS_MAX_SON and not capteurs.ecrase


func _physics_process(delta: float) -> void:
	if not actif:
		return
	var t0 := Time.get_ticks_usec()
	capteurs.lire(vaisseau, delta)
	if son_permis():
		moteurs.detecter(capteurs, oreille)
		for e in moteurs.evenements:
			_demandes.append([e[0], e[1], e[2], CHOC if String(e[0]).begins_with("choc") else MOTEUR, 0.0])
	moteurs.evenements.clear()
	_us_physique += Time.get_ticks_usec() - t0


func _process(delta: float) -> void:
	if not actif:
		return
	var t0 := Time.get_ticks_usec()
	mettre_a_jour(delta)
	var us := Time.get_ticks_usec() - t0 + _us_physique
	_us_physique = 0
	ms_par_image = lerpf(ms_par_image, us / 1000.0, 0.05)


## Une image du chef d'orchestre (60 fois par seconde).
func mettre_a_jour(delta: float) -> void:
	# 1. silence demandé ? fondu de 0,1 s
	fondu = move_toward(fondu, 1.0 if son_permis() else 0.0, delta / FONDU_SILENCE)
	var fondu_db := 20.0 * log(maxf(fondu, 1e-4)) / log(10.0)
	# 2. ce que le pilote entend, en dB dans le cockpit
	var c := capteurs
	var z_ext := c.densite * Fluides.vitesse_son(c.temperature) if c.densite > 0.0 else 0.0
	if c.densite <= 0.0:
		_transm = PackedFloat64Array()
		_z_ext = -1.0
	elif absf(z_ext - _z_ext) > 0.002 * z_ext or _transm.is_empty():
		# passage par la paroi : il dépend un peu de l'air du dehors (refait quand il change de 0,2 %)
		_transm = Fluides.transmissions(z_ext)
		_z_ext = z_ext
	moteurs.calculer(c, oreille, _transm)
	var mach := c.vitesse_air / Fluides.vitesse_son(c.temperature) if c.densite > 0.0 else 0.0
	souffle = Fluides.souffle(c.densite, c.temperature, c.vitesse_air, mach, c.temperature_coque, _transm) if c.densite > 0.0 \
		else {"niveau": -INF, "bandes": PackedFloat64Array(), "q": 0.0, "p_paroi": 0.0, "turbulent": 0.0, "fluide": 0.0}
	_poser("structure", moteurs.niveau_structure, delta)
	_poser("rcs", moteurs.niveau_rcs, delta)
	_poser("jet", moteurs.niveau_jet, delta)
	_poser("jet_rcs", moteurs.niveau_jet_rcs, delta)
	_poser("souffle", float(souffle["niveau"]), delta)
	# 3. compression : du vrai niveau total au volume des haut-parleurs
	var total := _somme_db(couches.values().map(func(k): return float(k["lisse"])))
	var cible := 0.0
	if total > -INF:
		cible = minf(sortie(total), PLAFOND) - (total - ZERO_DBFS)
		cible = minf(cible, 0.0)
	var tau := ATTAQUE if cible < gain else RELACHE
	gain += (cible - gain) * clampf(delta / tau, 0.0, 1.0)
	# 4. chaque couche : volume, égaliseur, silence si trop faible ou cachée
	for nom in couches:
		_jouer_couche(nom, fondu_db)
	if couches.has("structure"):
		# le grondement « monte en régime » avec la poussée (invention pour le son, à revoir en phase 6)
		(couches["structure"]["lecteur"] as AudioStreamPlayer).pitch_scale = 0.9 + 0.25 * sqrt(clampf(moteurs.regime, 0.0, 1.5))
	# 5. sons brefs
	_servir_demandes(delta, fondu_db)
	_faire_fondre(delta)
	# 6. l'oreille suit la tête du pilote en vue cockpit ; dehors, elle reste à sa place, tête droite
	if ecoute:
		if vue_interieure and camera != null and camera.get_parent() == pilote:
			ecoute.transform = camera.transform
		else:
			ecoute.transform = Transform3D(Basis.IDENTITY, oreille_scene)


## Niveau de sortie (dB pleine échelle) pour un niveau x (dB dans le cockpit), avant le plafond.
static func sortie(x: float) -> float:
	if x <= GENOU:
		return x - ZERO_DBFS
	return GENOU - ZERO_DBFS + (x - GENOU) / TAUX_COMPRESSION


## Niveau cible d'une couche ; il monte tout de suite, il descend en ~60 ms (pas de marches audibles).
func _poser(nom: String, niveau: float, delta: float) -> void:
	if not couches.has(nom):
		return
	var k: Dictionary = couches[nom]
	k["niveau"] = niveau
	var l: float = k["lisse"]
	if niveau >= l or l == -INF:
		l = niveau
	else:
		var bas := maxf(niveau, -40.0)
		l = l + (bas - l) * clampf(delta / RELACHE_COUCHE, 0.0, 1.0)
		if niveau == -INF and l < -30.0:
			l = -INF
	k["lisse"] = l
	# part de chaque octave (pour le masquage et l'égaliseur)
	var bdb := PackedFloat64Array()
	bdb.resize(10)
	var parts: PackedFloat64Array = k["parts"]
	var spectre := PackedFloat64Array()
	if nom == "souffle":
		spectre = souffle.get("bandes", PackedFloat64Array())
	elif nom == "jet":
		spectre = moteurs.bandes_jet
	elif nom == "jet_rcs":
		spectre = moteurs.bandes_jet_rcs
	var tot := 0.0
	for e in spectre:
		tot += e
	for b in 10:
		var part: float = spectre[b] / tot if tot > 0.0 else parts[b]
		bdb[b] = l + 10.0 * log(maxf(part, 1e-12)) / log(10.0) if l > -INF else -INF
	k["bandes_db"] = bdb


func _jouer_couche(nom: String, fondu_db: float) -> void:
	var k: Dictionary = couches[nom]
	var l := k["lecteur"] as AudioStreamPlayer
	var niveau: float = k["lisse"]
	var dbfs := niveau - ZERO_DBFS + gain + fondu_db
	var audible := niveau > -INF and dbfs > SEUIL_DB and not _masquee(nom)
	if not audible:
		if l.playing:
			l.stop()
		k["volume"] = -80.0
		return
	var realise: float = k["ref_dbfs"]
	var eq: AudioEffectEQ10 = k["eq"]
	if eq != null:
		# égaliseur : chaque octave reçoit l'écart entre le spectre voulu et celui de la boucle
		var bdb: PackedFloat64Array = k["bandes_db"]
		var parts: PackedFloat64Array = k["parts"]
		var g_max := -INF
		var g := PackedFloat64Array()
		g.resize(10)
		for b in 10:
			g[b] = bdb[b] - (niveau + 10.0 * log(maxf(parts[b], 1e-12)) / log(10.0))
			g_max = maxf(g_max, g[b])
		for b in 10:
			var gb := clampf(g[b] - g_max, -60.0, 0.0)
			eq.set_band_gain_db(b, gb)
			g[b] = pow(10.0, gb / 20.0)
		# ce qui sort vraiment (les bandes de Godot se recouvrent : egaliseur.gd)
		realise += 10.0 * log(maxf(Egaliseur.energie(k["m_eq"], g), 1e-12)) / log(10.0)
	var vol := dbfs - realise
	k["volume"] = vol
	l.volume_db = vol
	if not l.playing:
		var d := (l.stream as AudioStreamWAV).get_length() if l.stream is AudioStreamWAV else 0.0
		l.play(_rng.randf() * d)   # départ au hasard dans la boucle


## Une couche est cachée si, dans toutes les octaves où elle compte, une autre est 20 dB plus forte.
func _masquee(nom: String) -> bool:
	var a: PackedFloat64Array = couches[nom]["bandes_db"]
	var lvl: float = couches[nom]["lisse"]
	if a.size() != 10:
		return false
	for b in 10:
		if a[b] < lvl - 10.0:
			continue   # octave qui compte peu pour cette couche
		var cachee := false
		for autre in couches:
			if autre == nom:
				continue
			var o: PackedFloat64Array = couches[autre]["bandes_db"]
			if o.size() == 10 and o[b] > a[b] + MASQUAGE_DB:
				cachee = true
				break
		if not cachee:
			return false
	return true


func _servir_demandes(delta: float, fondu_db: float) -> void:
	var restent := []
	for d in _demandes:
		d[4] += delta
		var nom: String = d[0]
		if not coups.has(nom) or fondu < 0.999:
			oublies += 1
			continue
		var niveau: float = d[1]
		var dbfs := niveau - ZERO_DBFS + gain + fondu_db
		var variantes: Array = coups[nom]
		var choix := _choisir(nom)
		var v: Dictionary = variantes[choix]
		if dbfs < SEUIL_DB or _coup_cache(niveau, v["parts"]):
			oublies += 1
			continue
		var i := _voix_libre(int(d[3]))
		if i < 0:
			if d[4] < ATTENTE_MAX:
				restent.append(d)   # une voix est en train de s'éteindre pour lui : on réessaie
			else:
				oublies += 1
			continue
		_retenir(nom, choix)
		var vx: Dictionary = voix[i]
		var l := vx["lecteur"] as AudioStreamPlayer3D
		l.stream = v["stream"]
		l.position = (d[2] as Vector3) - capteurs.centre_gravite
		var vol: float = dbfs - float(v["ref_dbfs"]) + _rng.randf_range(-1.0, 1.0)
		l.volume_db = vol
		l.pitch_scale = pow(2.0, _rng.randf_range(-0.4, 0.4) / 12.0)   # ±0,4 demi-ton : deux coups ne sont jamais identiques
		l.play()
		vx["priorite"] = d[3]
		vx["debut"] = capteurs.temps
		vx["fondu"] = -1.0
		vx["volume"] = vol
		joues += 1
	_demandes = restent


## Un son bref est caché si, dans sa plus forte octave, les couches continues sont 20 dB plus fortes.
func _coup_cache(niveau: float, parts: PackedFloat64Array) -> bool:
	var b_max := 0
	for b in 10:
		if parts[b] > parts[b_max]:
			b_max = b
	var e := 0.0
	for nom in couches:
		var o: PackedFloat64Array = couches[nom]["bandes_db"]
		if o.size() == 10 and o[b_max] > -INF:
			e += pow(10.0, o[b_max] / 10.0)
	if e <= 0.0:
		return false
	return niveau + 10.0 * log(parts[b_max]) / log(10.0) < 10.0 * log(e) / log(10.0) - MASQUAGE_DB


## Variante au hasard parmi celles qui n'ont pas été jouées récemment.
func _choisir(nom: String) -> int:
	var n: int = coups[nom].size()
	var recents: Array = _recents[nom]
	var permis := []
	for k in n:
		if not recents.has(k):
			permis.append(k)
	if permis.is_empty():
		return _rng.randi_range(0, n - 1)
	return permis[_rng.randi_range(0, permis.size() - 1)]


func _retenir(nom: String, k: int) -> void:
	var recents: Array = _recents[nom]
	recents.append(k)
	var garder := mini(8, coups[nom].size() - 1)
	while recents.size() > garder:
		recents.pop_front()


## Un lecteur libre ; sinon, la voix la moins prioritaire (puis la plus ancienne) commence à s'éteindre.
## Renvoie -1 si rien n'est libre tout de suite.
func _voix_libre(priorite: int) -> int:
	var victime := -1
	for i in voix.size():
		var v: Dictionary = voix[i]
		var l := v["lecteur"] as AudioStreamPlayer3D
		if not l.playing and float(v["fondu"]) < 0.0:
			return i
		if float(v["fondu"]) >= 0.0:
			continue   # déjà en train de s'éteindre
		if int(v["priorite"]) <= priorite:
			if victime < 0 or int(v["priorite"]) < int(voix[victime]["priorite"]) \
					or (int(v["priorite"]) == int(voix[victime]["priorite"]) and float(v["debut"]) < float(voix[victime]["debut"])):
				victime = i
	if victime >= 0:
		voix[victime]["fondu"] = FONDU_VOIX
	return -1


func _faire_fondre(delta: float) -> void:
	for v in voix:
		var l := v["lecteur"] as AudioStreamPlayer3D
		if float(v["fondu"]) >= 0.0:
			v["fondu"] = float(v["fondu"]) - delta
			if float(v["fondu"]) <= 0.0:
				l.stop()
				v["fondu"] = -1.0
			else:
				l.volume_db = float(v["volume"]) + 20.0 * log(float(v["fondu"]) / FONDU_VOIX) / log(10.0)
		elif l.playing and fondu < 1.0:
			l.volume_db = float(v["volume"]) + 20.0 * log(maxf(fondu, 1e-4)) / log(10.0)
		if fondu <= 0.0 and l.playing:
			l.stop()


## Nombre de voix qui jouent en ce moment (couches + sons brefs).
func voix_actives() -> int:
	var n := 0
	for nom in couches:
		if (couches[nom]["lecteur"] as AudioStreamPlayer).playing:
			n += 1
	for v in voix:
		if (v["lecteur"] as AudioStreamPlayer3D).playing:
			n += 1
	return n


static func _somme_db(niveaux: Array) -> float:
	var e := 0.0
	for x in niveaux:
		if x > -INF:
			e += pow(10.0, x / 10.0)
	return 10.0 * log(e) / log(10.0) if e > 0.0 else -INF
