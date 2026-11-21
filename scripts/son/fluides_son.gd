extends RefCounted
## Sons de l'air (moteur audio, phase 1) : ce que le pilote entend de l'air, à travers la coque.
##
## On n'entend que le cockpit (choix de Gwenaël, 21/11) : le cockpit est plein d'air (pressurisé), et les
## sons du dehors n'y arrivent qu'en faisant vibrer la paroi (verrière + coque). Ce fichier ne lit que des
## nombres (densité, température, vitesse de l'air) : il ne touche jamais à la physique du vaisseau.
##
## Le souffle : l'air qui frotte sur la coque forme une fine couche de remous collée à elle (la « couche
## limite »). Ses remous font trembler la pression sur la paroi, environ 0,6 % de la pression du vent : c'est
## ce tremblement qui fait vibrer la verrière, et la verrière qui fait vibrer l'air du cockpit.
##  - force des remous : frottement de l'air sur la paroi (lois classiques d'une plaque plane) ;
##  - couleur (part de chaque fréquence) : modèle de Goody (2004), qui suit des mesures en soufflerie ;
##  - énergie totale : loi de Farabee et Casarella (1991) ;
##  - passage par la paroi : loi de masse (une paroi lourde laisse mal passer les aigus) avec la première
##    résonance d'un panneau de verrière ;
##  - air laminaire (lisse, sans remous, à petite vitesse ou dans l'air très fin) : presque silencieux ;
##  - air trop rare (molécules isolées, haute altitude) : plus de fluide, plus de souffle.

const GAMMA := 1.4
const R_AIR := 287.05             # J/(kg·K)
const P_REF := 2.0e-5             # Pa : 0 dB (seuil de l'oreille)
## Le cockpit : air à 1 atmosphère et 20 °C.
const CABINE_RHO := 1.204         # kg/m³
const CABINE_SON := 343.2         # m/s
const Z_CABINE := CABINE_RHO * CABINE_SON   # « impédance » de l'air : sa résistance à vibrer (Pa·s/m)
## La paroi entre le pilote et le dehors, surtout la verrière en verre feuilleté (343 kg, ~12 mm).
const PAROI_MASSE := 30.0         # kg/m²
const PAROI_F0 := 80.0            # Hz : première résonance d'un panneau d'environ 1 m (estimation)
const PAROI_PERTE := 0.1          # le film du verre feuilleté, les joints et les garnitures amortissent bien
const DISTANCE_NEZ := 4.5         # m : du nez à la verrière (longueur de la couche limite)
## Dans un petit cockpit, le son rebondit sur les parois : environ 2 fois plus d'énergie qu'en champ libre.
const GAIN_CABINE_DB := 3.0
const LONGUEUR := 10.3            # m : longueur du vaisseau (régime moléculaire, comme aerodynamique.gd)
## Les 10 bandes d'octave de l'égaliseur de Godot ; chacune est calculée sur 3 tiers d'octave.
const BANDES := [31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
const TIERS := [0.7937, 1.0, 1.2599]                 # 2^(-1/3), 1, 2^(1/3)
const LARGEUR_TIERS := 0.2316                        # largeur d'un tiers d'octave / sa fréquence centrale


## Viscosité de l'air (loi de Sutherland), Pa·s.
static func viscosite(t: float) -> float:
	return 1.458e-6 * pow(t, 1.5) / (t + 110.4)


static func vitesse_son(t: float) -> float:
	return sqrt(GAMMA * R_AIR * maxf(t, 1.0))


## Part de l'air qui se comporte encore comme un fluide (1 = fluide, 0 = molécules isolées). Même loi que
## la physique (aerodynamique.gd, nombre de Knudsen : libre parcours des molécules / taille du vaisseau).
static func part_fluide(rho: float) -> float:
	if rho <= 0.0:
		return 0.0
	var kn := 6.63e-8 * 1.225 / rho / LONGUEUR
	return 1.0 - clampf((log(kn) / log(10.0) + 1.0) / 2.0, 0.0, 1.0)


## Paroi poussée par une pression p (des deux côtés il y a de l'air : z_ext dehors, Z_CABINE dedans).
## Renvoie le rapport pression dans le cockpit / pression qui pousse la paroi (« pression bloquée »).
## Paroi = masse + ressort (sa résonance PAROI_F0) + amortissement : au-dessus de la résonance, la masse
## domine et chaque octave plus aiguë passe 2 fois moins bien (loi de masse, −6 dB par octave).
static func transmission(f: float, z_ext: float) -> float:
	var w := TAU * f
	var w0 := TAU * PAROI_F0
	var raideur := PAROI_MASSE * w0 * w0
	var x := w * PAROI_MASSE - raideur / w
	var r := raideur * PAROI_PERTE / w
	var a := z_ext + Z_CABINE + r
	return Z_CABINE / sqrt(a * a + x * x)


## Les 30 valeurs (10 octaves × 3 tiers) du carré de la transmission, pour l'air du dehors donné.
static func transmissions(z_ext: float) -> PackedFloat64Array:
	var t := PackedFloat64Array()
	t.resize(30)
	for b in 10:
		for k in 3:
			var tr := transmission(BANDES[b] * TIERS[k], z_ext)
			t[b * 3 + k] = tr * tr
	return t


## Couche limite au niveau de la verrière (plaque plane turbulente ; air compressible par la méthode de la
## « température de référence » d'Eckert). t_paroi : température de la coque (K) ; sans elle, la paroi est
## prise à la température de l'air arrêté contre elle.
## Renvoie [frottement τ (Pa), épaisseur δ (m), vitesse de frottement u_τ (m/s), viscosité ν (m²/s),
## nombre de Reynolds, part turbulente 0..1].
static func couche_limite(rho: float, t: float, u: float, mach: float, t_paroi := -1.0) -> Array:
	var t_w := t_paroi if t_paroi > 0.0 else t * (1.0 + 0.178 * mach * mach)
	var t_ref := maxf(t * (1.0 + 0.032 * mach * mach + 0.58 * (t_w / t - 1.0)), 0.5 * t)
	var rho_ref := rho * t / t_ref
	var nu := viscosite(t_ref) / rho_ref
	var re := maxf(u * DISTANCE_NEZ / nu, 10.0)
	var lg := log(re) / log(10.0)
	var turbulent := smoothstep(5.5, 6.0, lg)          # transition entre 300 000 et 1 000 000
	var cf := pow(maxf(2.0 * lg - 0.65, 1.0), -2.3)    # frottement local turbulent (White)
	var delta := 0.37 * DISTANCE_NEZ * pow(re, -0.2)
	var tau := cf * 0.5 * rho_ref * u * u
	return [tau, delta, sqrt(tau / rho_ref), nu, re, turbulent]


## Spectre de Goody (forme), x = ω·δ / U.
static func goody(x: float, c3: float) -> float:
	return 3.0 * x * x / (pow(pow(x, 0.75) + 0.5, 3.7) + pow(c3 * x, 7.0))


## Le souffle dans le cockpit. rho, t : air du dehors ; u : vitesse par rapport à l'air ; mach ;
## t_paroi : température de la coque (K, −1 si inconnue) ; transm : transmissions() pour cet air.
## Renvoie {niveau (dB dans le cockpit), bandes (énergie Pa² par octave), tiers (la même par tiers d'octave),
## q (pression du vent, Pa), p_paroi (Pa efficaces sur la paroi), turbulent, fluide}.
static func souffle(rho: float, t: float, u: float, mach: float, t_paroi: float, transm: PackedFloat64Array) -> Dictionary:
	var bandes := PackedFloat64Array()
	bandes.resize(10)
	var tiers := PackedFloat64Array()   # les mêmes, par tiers d'octave (pour la partie C++, phase 2)
	tiers.resize(30)
	var res := {"niveau": -INF, "bandes": bandes, "tiers": tiers, "q": 0.5 * rho * u * u, "p_paroi": 0.0,
		"turbulent": 0.0, "fluide": part_fluide(rho)}
	var r := remous(rho, t, u, mach, t_paroi)
	if r.is_empty():
		return res
	res["p_paroi"] = sqrt(float(r["p2"]))
	res["turbulent"] = r["turbulent"]
	var total := 0.0
	var cabine := pow(10.0, GAIN_CABINE_DB / 10.0)
	for b in 10:
		var e := 0.0
		for k in 3:
			var f: float = BANDES[b] * TIERS[k]
			var et := densite_remous(f, r) * f * LARGEUR_TIERS * transm[b * 3 + k] * cabine
			tiers[b * 3 + k] = et
			e += et
		bandes[b] = e
		total += e
	res["niveau"] = 10.0 * log(maxf(total, 1e-30) / (P_REF * P_REF)) / log(10.0)
	return res


## Les remous de la couche limite sur la paroi : {p2 (Pa², toutes fréquences), k_f (dx/df), c3, norme,
## turbulent} ; vide si pas de souffle (vide, air arrêté, molécules isolées).
static func remous(rho: float, t: float, u: float, mach: float, t_paroi := -1.0) -> Dictionary:
	var fluide := part_fluide(rho)
	if rho <= 0.0 or u < 0.5 or t <= 0.0 or fluide <= 0.0:
		return {}
	var cl := couche_limite(rho, t, u, mach, t_paroi)
	var tau: float = cl[0]
	var delta: float = cl[1]
	var u_tau: float = cl[2]
	var nu: float = cl[3]
	# énergie des remous sur la paroi (Farabee et Casarella) : p² = τ² (6,5 + 1,86 ln(Re_τ / 333))
	var re_tau := maxf(u_tau * delta / nu, 333.0)
	var p2 := tau * tau * (6.5 + 1.86 * log(re_tau / 333.0))
	# air laminaire : remous ~ 40 dB plus faibles ; molécules isolées : plus de fluide
	p2 *= (float(cl[5]) + (1.0 - float(cl[5])) * 1.0e-4) * fluide
	# forme du spectre : Goody, normalisée pour que la somme sur toutes les fréquences fasse p²
	var r_t := u_tau * u_tau * delta / (u * nu)
	var c3 := 1.1 * pow(maxf(r_t, 1.0), -0.57)
	return {"p2": p2, "k_f": TAU * delta / u, "c3": c3, "norme": p2 / integrale_goody(c3), "turbulent": cl[5]}


static var _c3_connu := -1.0
static var _integrale_connue := 1.0


## ∫ Goody dx (x de 10⁻³ à 10⁴, pas logarithmique : ∫ G dx = ∫ G·x d(ln x)). Gardée tant que c3 bouge peu.
static func integrale_goody(c3: float) -> float:
	if absf(c3 - _c3_connu) > 1.0e-4 * c3:
		var integrale := 0.0
		for k in 36:
			var x := pow(10.0, -3.0 + k * 7.0 / 35.0)
			integrale += goody(x, c3) * x
		_integrale_connue = integrale * 7.0 / 35.0 * log(10.0)
		_c3_connu = c3
	return _integrale_connue


## Densité d'énergie des remous sur la paroi à la fréquence f (Pa² par Hz), pour remous().
static func densite_remous(f: float, r: Dictionary) -> float:
	var k_f: float = r["k_f"]
	return goody(f * k_f, float(r["c3"])) * k_f * float(r["norme"])


## Forme du souffle qui sert à fabriquer sa boucle (vol à 150 m/s au niveau de la mer, à travers la
## paroi) : l'égaliseur n'a ensuite que de petites corrections à faire, qu'il fait bien.
## r : remous_reference() (calculé une fois).
static func forme_souffle(f: float, r: Dictionary) -> float:
	var tr := transmission(f, 1.225 * 340.3)
	return densite_remous(f, r) * tr * tr


static func remous_reference() -> Dictionary:
	return remous(1.225, 288.15, 150.0, 150.0 / 340.3)
