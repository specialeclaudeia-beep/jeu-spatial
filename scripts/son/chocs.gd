extends RefCounted
## Sons brefs fabriqués EN DIRECT (moteur audio, phase 3, demande de Gwenaël du 21/11) : rien n'est enregistré.
## Pour chaque choc, ce fichier écrit la « recette » : les modes de la pièce frappée (fréquence, durée de
## résonance, force, retard), plus une bouffée de bruit ou un crissement si besoin. La classe C++ ChocsSon
## (labo-lumiere/cpp/src/chocs_son.cpp) les fait sonner dans le fil audio. Chaque choc est tiré au hasard à
## partir de sa matière : deux chocs ne sont jamais identiques (comme en vrai : on ne frappe jamais deux fois au
## même endroit, avec la même force).
##
## D'où viennent les modes (synthèse modale) : une pièce (poutre, plaque, coque) vibre à des fréquences propres,
## réparties entre f_min et f_max, chacune décalée de ±2 % (deux pièces ne sont jamais identiques). Un mode
## dure 1 / (π f perte) : l'acier sonne longtemps, le caoutchouc presque pas. Sa force dépend de :
##   - l'endroit frappé (forme du mode à cet endroit) ;
##   - la durée du contact : une force qui dure « contact » secondes (demi-sinus) ne nourrit pas les modes plus
##     rapides qu'elle. Plus le choc est rapide, plus le contact est bref (loi de Hertz : ∝ v^−1/5) : plus aigu ;
##   - la masse du mode (∝ 1/√f).
## L'intensité (0 à 1, donnée par sol_son.gd et moteurs_son.gd depuis la vitesse du choc) change donc le
## timbre ; le NIVEAU, lui, vient de l'énergie de déformation ½ m v² (idée de Gwenaël, voir sol_son.gd).
##
## Phase 4 : craquements, relâchements et tics de la coque (tension_son.gd), grains de poussière (poussiere_son.gd).
## « trajet » (m de structure jusqu'au pilote) assombrit le son : les aigus se perdent en route.
##
## Clés : matiere (aluminium, acier, caoutchouc, roche, composite, verre), perte (facteur de perte de la pièce et de ses
## attaches), rebonds [retard (s), force] (verrou qui claque deux fois, caillou qui rebondit), ticks (grains qui
## crépitent au début), souffle (gaz d'une vanne, huile d'un vérin, vers souffle_f Hz), crissement (pneu qui
## accroche et glisse, vers crissement_f Hz), attaque (s : force qui monte doucement, moteur qui s'allume).

const SEUIL_FIN := 3e-5           # −90 dB pleine échelle (même seuil que la partie C++)
const FENETRE := 0.1              # s : le niveau d'un choc = son niveau moyen sur ses 100 premières ms
const MODES_MAX := 48
const FAMILLES := {
	# --- vannes et moteurs (les coups de la phase 1) ---
	"rcs_ouverture": {"matiere": "acier", "duree": 0.35,
		"f_min": 180.0, "f_max": 4500.0, "modes": 14, "perte": 0.012, "contact": 0.0004, "souffle": 0.5, "souffle_f": 1800.0},
	"rcs_fermeture": {"matiere": "acier", "duree": 0.25,
		"f_min": 400.0, "f_max": 6000.0, "modes": 10, "perte": 0.015, "contact": 0.0002},
	"moteur_allumage": {"matiere": "aluminium", "duree": 1.4,
		"f_min": 35.0, "f_max": 600.0, "modes": 16, "perte": 0.02, "contact": 0.004, "attaque": 0.03},
	"moteur_coupure": {"matiere": "aluminium", "duree": 1.0,
		"f_min": 30.0, "f_max": 400.0, "modes": 12, "perte": 0.03, "contact": 0.01, "attaque": 0.06},
	# --- sol (phase 3) ---
	# pneu qui touche le sol : le caoutchouc s'écrase (contact long, 3 à 8 ms : sourd), la jambe et la coque
	# vibrent en grave
	"pneu_toucher": {"matiere": "caoutchouc", 
		"duree": 0.8, "f_min": 28.0, "f_max": 900.0, "modes": 18, "perte": 0.035, "contact": 0.006},
	# le pneu qui ne tournait pas touche en roulant vite : il glisse le temps de prendre sa vitesse (« couic »)
	"pneu_crissement": {"matiere": "caoutchouc", 
		"duree": 0.35, "modes": 0, "crissement": 1.0, "crissement_f": 1050.0},
	# amortisseur en bout de course : acier contre acier, contact très bref, ça sonne
	"train_butee": {"matiere": "acier", "duree": 0.6,
		"f_min": 70.0, "f_max": 3000.0, "modes": 18, "perte": 0.006, "contact": 0.0003},
	# jambe qui se détend d'un coup (rebond, roue qui quitte le sol) : butée haute, plus douce
	"amortisseur_detente": {"matiere": "acier", "duree": 0.5,
		"f_min": 60.0, "f_max": 1500.0, "modes": 14, "perte": 0.012, "contact": 0.0015},
	# la coque qui tape le sol : panneau d'aluminium sur de la roche, avec des grains qui crépitent
	"coque_choc": {"matiere": "aluminium", 
		"duree": 0.9, "f_min": 40.0, "f_max": 2500.0, "modes": 20, "perte": 0.015, "contact": 0.001, "ticks": 14},
	# petit caillou projeté par une roue contre la coque ou la trappe
	"gravier": {"matiere": "roche", "duree": 0.1,
		"f_min": 900.0, "f_max": 7000.0, "modes": 8, "perte": 0.02, "contact": 0.00008, "rebonds": [[0.018, 0.25]]},
	# frein qui se serre (étrier) ou frein de parc
	"frein_serrage": {"matiere": "acier", "duree": 0.25,
		"f_min": 300.0, "f_max": 5000.0, "modes": 10, "perte": 0.02, "contact": 0.0004},
	# --- vérins (train, ailes, roue avant) : l'intensité = taille du vérin (roue avant 0,2 ; train 0,6 ; ailes 0,9) ---
	# départ : le distributeur s'ouvre (clic) et l'huile part d'un coup (bouffée grave)
	"verin_depart": {"matiere": "acier", "duree": 0.4,
		"f_min": 120.0, "f_max": 3000.0, "modes": 10, "perte": 0.02, "contact": 0.0005, "souffle": 0.35, "souffle_f": 600.0},
	# arrêt : le piston arrive au bout (coup sourd, amorti par l'huile)
	"verin_arret": {"matiere": "acier", "duree": 0.5,
		"f_min": 50.0, "f_max": 1200.0, "modes": 14, "perte": 0.018, "contact": 0.003},
	# verrou du train ou des ailes qui se ferme : « clac-clac » métallique (crochet puis loquet)
	"verrouillage": {"matiere": "acier", "duree": 0.4,
		"f_min": 250.0, "f_max": 5000.0, "modes": 12, "perte": 0.008, "contact": 0.0002, "rebonds": [[0.022, 0.6]]},
	# --- tension des pièces (phase 4, tension_son.gd) ---
	# craquement (émission acoustique) : une micro-rupture dure quelques microsecondes et fait sonner la pièce ;
	# composite : sec et court (« carton dur ») ; métal : rivet qui glisse d'un micron (« tink ») ; verre : tintement
	"craquement_composite": {"matiere": "composite", "duree": 0.12,
		"f_min": 350.0, "f_max": 7000.0, "modes": 14, "perte": 0.03, "contact": 0.00004, "ticks": 3},
	"craquement_metal": {"matiere": "aluminium", "duree": 0.3,
		"f_min": 500.0, "f_max": 9000.0, "modes": 12, "perte": 0.006, "contact": 0.00003, "ticks": 1},
	"craquement_verre": {"matiere": "verre", "duree": 0.3,
		"f_min": 900.0, "f_max": 10000.0, "modes": 10, "perte": 0.004, "contact": 0.00002},
	# relâchement : la charge tombe d'un coup, la pièce revient et sonne avec ses grands modes (« boum », « bong »)
	"relachement_composite": {"matiere": "composite", "duree": 0.5,
		"f_min": 45.0, "f_max": 1600.0, "modes": 16, "perte": 0.03, "contact": 0.003},
	"relachement_metal": {"matiere": "acier", "duree": 0.9,
		"f_min": 55.0, "f_max": 2500.0, "modes": 16, "perte": 0.01, "contact": 0.002},
	"relachement_verre": {"matiere": "verre", "duree": 0.7,
		"f_min": 140.0, "f_max": 3500.0, "modes": 14, "perte": 0.006, "contact": 0.0015},
	# tôle de la coque qui chauffe ou refroidit et saute d'un appui à l'autre (« tic », parfois « tic-tic »)
	"tic_thermique": {"matiere": "aluminium", "duree": 0.25,
		"f_min": 700.0, "f_max": 7000.0, "modes": 10, "perte": 0.008, "contact": 0.00008, "rebonds": [[0.006, 0.3]]},
	# --- poussière de l'espace (phase 4, poussiere_son.gd) : choc à des km/s, contact de quelques µs ---
	"poussiere_verre": {"matiere": "verre", "duree": 0.08,
		"f_min": 2000.0, "f_max": 14000.0, "modes": 8, "perte": 0.004, "contact": 0.00001},
	"poussiere_coque": {"matiere": "aluminium", "duree": 0.1,
		"f_min": 900.0, "f_max": 10000.0, "modes": 8, "perte": 0.01, "contact": 0.00002},
}
## Phase 4 : un son qui traverse la structure perd ses aigus (les vibrations rapides s'amortissent plus vite) :
## 0,3 dB par mètre et par kHz, en plus du 1 dB par mètre déjà compté dans son niveau.
const ASSOURDISSEMENT := 0.3


static func existe(famille: String) -> bool:
	return FAMILLES.has(famille)


## La recette d'un choc de la famille, à l'intensité i (0..1), pour un niveau moyen voulu (carré moyen sur les
## 100 premières ms, pleine échelle = 1). Renvoie {modes (n × 4 nombres), options (11 nombres, voir chocs_son.h),
## parts (énergie de chaque octave, somme 1), duree (s, jusqu'à −90 dB)}.
static func recette(famille: String, i: float, carre_moyen: float, rng: RandomNumberGenerator, gauche := 1.0, droite := 1.0,
		priorite := 0.0, trajet := 0.0) -> Dictionary:
	var p: Dictionary = FAMILLES[famille]
	i = clampf(i, 0.0, 1.0)
	var k := clampf(i, 0.05, 1.0) / 0.5
	var contact: float = float(p.get("contact", 0.0005)) * pow(k, -0.2)   # loi de Hertz
	var attaque: float = p.get("attaque", 0.0)
	var duree: float = float(p["duree"]) * (0.75 + 0.5 * i)
	var modes := PackedFloat32Array()
	var parts := PackedFloat64Array()
	parts.resize(10)
	var ms := 0.0                  # carré moyen sur 100 ms, avant mise à l'échelle
	var nb: int = p.get("modes", 0)
	var f_min: float = p.get("f_min", 100.0)
	var f_max: float = p.get("f_max", 1000.0)
	var perte: float = p.get("perte", 0.02)
	var point := rng.randf_range(0.15, 0.85)   # endroit frappé
	var base := []                 # [f, tau, a]
	var a2_tot := 0.0
	for m in nb:
		var f := f_min * pow(f_max / f_min, (m + rng.randf_range(0.1, 0.9)) / nb) * rng.randf_range(0.98, 1.02)
		var tau := 1.0 / (PI * f * perte * rng.randf_range(0.8, 1.25))
		var forme := absf(sin(PI * (m + 1) * point))
		var tc := f * contact
		var choc := 1.0 if absf(1.0 - 4.0 * tc * tc) < 1e-6 else absf(cos(PI * tc) / (1.0 - 4.0 * tc * tc))
		var montee := 1.0 / sqrt(1.0 + pow(TAU * f * attaque, 2.0))
		var a := forme * choc * montee / sqrt(f) * rng.randf_range(0.6, 1.0) * _assourdi(f, trajet)
		base.append([f, minf(tau, duree), a])
		a2_tot += a * a
	var a_ref := sqrt(a2_tot / maxi(nb, 1)) if nb > 0 else 1.0
	for b in base:
		_mode(modes, parts, b[0], b[1], b[2], rng.randf_range(0.0, 0.0006))
	var croise := 0.0   # rebonds : le même mode refrappé s'ajoute à lui-même (en phase ou non) : terme croisé
	for r in p.get("rebonds", []):
		var d := float(r[0]) * rng.randf_range(0.85, 1.15)
		for bm in base:
			_mode(modes, parts, bm[0], bm[1], float(bm[2]) * float(r[1]), d)
			var tau: float = bm[1]
			if d < FENETRE:
				croise += float(bm[2]) * float(bm[2]) * float(r[1]) * cos(TAU * float(bm[0]) * d) * exp(d / tau) \
					* tau * 0.5 * (exp(-2.0 * d / tau) - exp(-2.0 * FENETRE / tau))
	# grains qui crépitent (roche, poussière) : chacun un tout petit mode aigu très amorti
	var ticks := int(round(float(p.get("ticks", 0)) * (0.3 + i)))
	for t in ticks:
		var f_t := rng.randf_range(2500.0, 7000.0)
		_mode(modes, parts, f_t, 0.0006, a_ref * rng.randf_range(0.5, 2.0) * _assourdi(f_t, trajet), rng.randf_range(0.0, 0.15))
	var options := PackedFloat32Array()
	options.resize(11)
	options[0] = maxf(attaque, 0.0003)
	# bouffée de bruit (gaz, huile) : variance 1 dans la partie C++, enveloppe (1 − e^(−t/2 ms)) e^(−t/30 ms)
	var souffle: float = float(p.get("souffle", 0.0)) * (0.5 + i)
	var e_bruit := 0.0
	if souffle > 0.0:
		options[1] = souffle * a_ref * 3.0
		options[2] = p.get("souffle_f", 1500.0)
		options[3] = 0.002
		options[4] = 0.03
		e_bruit = options[1] * options[1] * _integrale(func(t: float) -> float: return pow((1.0 - exp(-t / 0.002)) * exp(-t / 0.03), 2.0))
		parts[_octave(options[2])] += e_bruit
	# crissement : son presque pur + harmoniques + un peu de bruit
	if float(p.get("crissement", 0.0)) > 0.0:
		var f0: float = float(p["crissement_f"]) * rng.randf_range(0.85, 1.15) * (0.9 + 0.2 * i)
		options[5] = 1.0
		options[6] = f0
		options[7] = duree
		var e := (1.0 + 0.35 * 0.35 + 0.15 * 0.15) * 0.5 + 0.36
		var e_c := e * _integrale(func(t: float) -> float: return pow((1.0 - exp(-t / 0.004)) * pow(maxf(1.0 - t / duree, 0.0), 1.5), 2.0))
		e_bruit += e_c
		parts[_octave(f0)] += e_c
	for m in modes.size() / 4:
		var tau := float(modes[4 * m + 1])
		var a := float(modes[4 * m + 2])
		var d := float(modes[4 * m + 3])
		if d < FENETRE:
			var e := tau * 0.5 * (1.0 - exp(-2.0 * (FENETRE - d) / tau))
			if attaque > 0.001 and d < attaque:
				# force qui monte doucement (demi-cosinus sur « attaque » s) : on retire ce qu'elle enlève
				var t_a := attaque
				var tau_m := tau
				e -= _integrale_sur(func(t: float) -> float: return (1.0 - pow(0.5 - 0.5 * cos(PI * t / t_a), 2.0)) * exp(-2.0 * t / tau_m), t_a, 24)
			ms += a * a * 0.5 * e / FENETRE
	ms += (e_bruit + croise) / FENETRE
	# mise à l'échelle : le niveau moyen voulu
	var echelle := sqrt(carre_moyen / maxf(ms, 1e-30))
	var fin := 0.0
	for m in modes.size() / 4:
		modes[4 * m + 2] *= echelle
		var a := absf(modes[4 * m + 2])
		if a > SEUIL_FIN:
			fin = maxf(fin, modes[4 * m + 3] + modes[4 * m + 1] * log(a / SEUIL_FIN))
	options[1] *= echelle
	options[5] *= echelle
	if options[1] > 0.0:
		fin = maxf(fin, 0.03 * log(maxf(options[1], SEUIL_FIN) / SEUIL_FIN))
	if options[5] > 0.0:
		fin = maxf(fin, options[7])
	options[8] = gauche
	options[9] = droite
	options[10] = priorite
	var tot := 0.0
	for e in parts:
		tot += e
	for b in 10:
		parts[b] /= maxf(tot, 1e-30)
	return {"modes": modes, "options": options, "parts": parts, "duree": fin}


## Ce qui reste d'un mode de fréquence f après « trajet » mètres de structure (amplitude).
static func _assourdi(f: float, trajet: float) -> float:
	return pow(10.0, -ASSOURDISSEMENT * trajet * f / 20000.0) if trajet > 0.0 else 1.0


static func _mode(modes: PackedFloat32Array, parts: PackedFloat64Array, f: float, tau: float, a: float, retard: float) -> void:
	if modes.size() >= 4 * MODES_MAX:
		return
	modes.append(f)
	modes.append(tau)
	modes.append(a)
	modes.append(retard)
	parts[_octave(f)] += a * a * tau


## Octave (0 à 9, centres 31,25 Hz à 16 kHz) qui contient f.
static func _octave(f: float) -> int:
	return clampi(int(floor(log(maxf(f, 1.0) / 31.25) / log(2.0) + 0.5)), 0, 9)


## ∫ g(t) dt de 0 à 100 ms (méthode du point milieu, 200 pas).
static func _integrale(g: Callable) -> float:
	return _integrale_sur(g, FENETRE, 200)


static func _integrale_sur(g: Callable, duree: float, pas: int) -> float:
	var s := 0.0
	var dt := duree / pas
	for k in pas:
		s += float(g.call((k + 0.5) * dt))
	return s * dt


## Gains gauche et droit (même puissance totale) pour un son qui vient de « pos » (repère du modèle), oreille en
## « oreille ». force = 0,5 : on devine d'où ça vient, sans plus (vibrations de la structure).
static func panoramique(pos: Vector3, oreille: Vector3, force := 0.5) -> Vector2:
	var d := pos - oreille
	var p := clampf(d.x / maxf(d.length(), 0.3), -1.0, 1.0) * force
	var angle := (p + 1.0) * PI * 0.25
	return Vector2(cos(angle), sin(angle)) * sqrt(2.0)
