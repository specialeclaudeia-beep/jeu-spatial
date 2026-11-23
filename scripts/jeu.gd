extends Node3D
## Phase 1 — vol spatial réaliste.
## Un vaisseau à 5 moteurs (modèle 3D v12), une planète avec sa gravité, le cockpit et des instruments.
## La physique est dans scripts/physique/vaisseau_physique.gd ; ce script ne fait que l'afficher
## et transmettre les commandes du pilote.
##
## Affichage « à origine flottante » : le vaisseau est toujours au centre de la scène et c'est
## la planète qu'on place autour de lui. Les grandes distances restent ainsi précises.

const VaisseauPhysique = preload("res://scripts/physique/vaisseau_physique.gd")
const VieABord = preload("res://scripts/physique/vie_a_bord.gd")
const Commandes = preload("res://scripts/commandes.gd")
const EcranTouches = preload("res://scripts/ecran_touches.gd")
const LumiereJeu = preload("res://scripts/lumiere_jeu.gd")
const PiloteAuto = preload("res://scripts/physique/pilote_auto.gd")
const Cockpit = preload("res://scripts/cockpit.gd")
const EcransCockpit = preload("res://scripts/ecrans_cockpit.gd")
const Droide = preload("res://scripts/droide.gd")
const Reperes = preload("res://scripts/physique/reperes.gd")
const TrouVer = preload("res://scripts/physique/trou_de_ver.gd")
const Toile = preload("res://scripts/einstein/toile.gd")
const Atmosphere = preload("res://scripts/physique/atmosphere.gd")
const MoteurAudio = preload("res://scripts/son/moteur_audio.gd")
const ModeleVaisseau = preload("res://scripts/modele_vaisseau.gd")
const DessinVaisseau = preload("res://scripts/dessin_vaisseau.gd")
const Partie = preload("res://scripts/partie.gd")
const Plan = preload("res://scripts/atelier/plan.gd")

# =====================================================================
# CONSTANTES
# =====================================================================
const RAYON_PLANETE := 600000.0          # m (planète de test, plus petite que la Terre)
const GRAVITE_SURFACE := 9.81            # m/s² au sol
## Atmosphère : à 100 km, il reste assez d'air pour faire retomber le vaisseau en une heure (comme sur
## Terre). L'orbite de départ est donc plus haut, à 250 km : l'air y freine si peu qu'elle tient des mois.
const ALTITUDE_DEPART := 250000.0        # m
## Atelier, étape 2 : le départ « devant le hangar » (bouton Lancer de l'atelier). Endroit choisi sur la
## planète (repère de la planète, direction depuis son centre) : un des sols les moins en pente du côté
## éclairé au départ (pente 1,5° sous le vaisseau, 2 100 m d'altitude, 30° de latitude nord), le matin :
## le Soleil est à 38° au-dessus de l'horizon et monte. Le nez du vaisseau pointe à l'opposé du Soleil.
## (test « Départ devant le hangar » dans scripts/tests_atelier.gd)
const LIEU_HANGAR := Vector3(0.3635219, 0.5054473, 0.7825438)
## La planète tourne sur elle-même en 2 h (comme le labo, Q40 : jour court pour les essais). Au sol, à
## l'équateur, on file donc à 524 m/s dans l'espace : pour se poser, il faut suivre le sol.
const DUREE_JOUR := 7200.0               # s
const PAS := 1.0 / 120.0                 # s (120 calculs de physique par seconde)
const DISTANCE_RENDU_MAX := 200000.0     # au-delà, la planète est dessinée en réduction (même taille apparente)
const ALTITUDE_CALOTTE := 60000.0        # en dessous, on dessine une calotte détaillée sous le vaisseau
const DIRECTION_SOLEIL := Vector3(0.8, 0.3, 0.5)
const MODELE_EXTERIEUR := "res://modeles/vaisseau/vaisseau_exterieur.glb"
const MODELE_COCKPIT := "res://modeles/vaisseau/cockpit.glb"
const MODELE_DROIDE := "res://modeles/vaisseau/droide.glb"
const OEIL_PILOTE_DEFAUT := Vector3(0.0, 0.58, 0.38)   # remplacé par le point Oeil_pilote du modèle s'il existe
# vue extérieure : caméra qui tourne autour du vaisseau (stick droit), à cette distance du centre
const VUE_EXT_DISTANCE := 24.0
const VUE_EXT_HAUTEUR := deg_to_rad(-12.0)    # un peu au-dessus du vaisseau
const FOV_NORMAL := 75.0
const FOV_ZOOM := 25.0        # zoom pour lire les instruments (3 fois plus gros)
const ACCELERATIONS_TEMPS := [1, 10, 100, 1000, 10000, 100000, 1000000, 10000000]
## Au-delà de x100 000, le temps n'accélère autant que loin des astres (voir VaisseauPhysique.limite_temps).
const TEMPS_TOUJOURS := 100000
## Puissance des moteurs principaux (touches 7 / 8) : x1 = la vraie poussée (5 × 200 kN, ≈ 12 g).
## Plus fort, c'est un moteur imaginaire, mais toujours une vraie force : la relativité s'applique.
const FACTEURS_POUSSEE := [1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0]
# tête du pilote (stick droit) : ne touche qu'à la caméra, jamais au vaisseau
const TETE_VITESSE := 2.5                     # rad/s quand le stick est poussé à fond (environ 140°/s)
const TETE_LACET_MAX := deg_to_rad(130.0)     # jusqu'où on peut tourner la tête à gauche / à droite
const TETE_HAUT_MAX := deg_to_rad(80.0)
const TETE_BAS_MAX := deg_to_rad(50.0)
const TETE_RETOUR := 2.0                      # vitesse du retour doux vers l'avant, stick lâché
# tête qui bouge avec les forces G (étape 8 du système de lumière) : le cou est un ressort amorti.
# Assis et sanglé, la tête recule d'environ 1,5 cm par g ; au plus 8 cm.
const TETE_G_METRES_PAR_G := 0.015
const TETE_G_MAX := 0.08
const TETE_G_FREQUENCE := 1.5                 # Hz (oscillation propre du cou)
const TETE_G_AMORTI := 0.7

# =====================================================================
# ÉTAT
# =====================================================================
var vaisseau
var depart := Partie.DEPART_ORBITE   # où commence le vol (et où « recommencer » ramène)
var gaz := 0.0
var stabilisateur := false
var reperes = Reperes.new()          # Einstein A3 : un repère par système d'étoile
var trou_de_ver = TrouVer.new(reperes)   # Einstein C : le trou de ver fixe (touche W)
var toile = null                     # Einstein B : la « toile de l'espace » (touche Y)
## Einstein B : distance (centre du trou noir) du saut d'essai vers Gaia BH1 : 50 000 km, une orbite
## d'une minute. L'ombre y fait 0,08° (5 pixels) et les étoiles derrière lui bougent de façon visible.
const DISTANCE_TROU_NOIR := 5.0e7
var ordinateur = PiloteAuto.new()    # ordinateur de bord (pilote automatique)
var droide = null                    # droïde R-7 (petite IA, ordres calmes) : droide.gd
var modele_droide: Node = null
var force_cote := Vector3.ZERO       # force de côté demandée par le pilote auto (N)
var en_pause := false
var acc_temps := 1
var acc_effectif := 1                # accélération du temps réellement appliquée (le pilote auto peut la limiter)
var autopilote_actif := false        # le pilote auto calcule les ordres cette image
var aide_visible := true
var ordres := Vector3.ZERO           # tangage, lacet, roulis demandés (-1..1)
var commandes                        # touches du clavier et de la manette (modifiables, sauvegardées)
var ecran_touches: Control = null    # écran de configuration, quand il est ouvert
var image_fermeture := -1
var tete := Vector2.ZERO             # x = tête levée / baissée, y = tête tournée à gauche / à droite (radians)
var vue_interieure := true           # true = cockpit, false = vue extérieure (3e personne)
var oeil_pilote := OEIL_PILOTE_DEFAUT
var _oeil_plan := OEIL_PILOTE_DEFAUT  # l'œil du pilote dans le repère du plan (oeil_pilote = lui − centre de gravité)
var corps_vaisseau: Node3D           # le dessin du vaisseau, décalé pour que son centre de gravité soit à l'origine
# système de lumière (étape 8)
var lumiere = null                   # scripts/lumiere_jeu.gd (null : ancien affichage)
var avec_lumiere := false
var tete_g := true                   # la tête bouge avec les G (touche I)
var tete_g_pos := Vector3.ZERO       # m, repère du vaisseau
var tete_g_vit := Vector3.ZERO
var casque: CanvasLayer              # bord du casque (vue cockpit)
var lampe_ancienne: OmniLight3D
var temps_lumiere_ms := 0.0          # temps de calcul du système de lumière par image (moyenne)
var son = null                       # moteur audio (scripts/son/) : il lit la physique, ne l'écrit jamais

# calotte détaillée
var calotte_dir := Vector3.ZERO
var calotte_angle := 0.0

# =====================================================================
# NŒUDS
# =====================================================================
var pilote: Node3D
var camera: Camera3D
var exterieur: Node3D                # coque, ailes, train (visible dans les deux vues)
var cockpit: Node3D                  # intérieur du cockpit et grande verrière (vue intérieure seulement)
var modele                           # le dessin du vaisseau mis dans la pose de sa physique (modele_vaisseau.gd)
var dessin                           # modules enlevés et pièces posées dans l'atelier (dessin_vaisseau.gd)
var maillages_exterieurs: Array = [] # pour couper leurs ombres en vue cockpit
var caches_en_cockpit: Array = []    # pièces du nez (train avant, moteurs de levage) qui bouchent la vue du pilote
var lueurs: Array = []               # [nœud, matériau, propulseur de la physique, couleur faible, couleur forte, énergie min, énergie max]
var panaches: Array = []             # [nœud, matériau, propulseur de la physique, échelle de repos, axe (0,1,2), couleur faible, couleur forte]
const SHADER_PANACHE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec3 couleur = vec3(0.0, 0.25, 1.0);
uniform vec3 axe = vec3(0.0, 0.0, 1.0);
uniform float longueur = 1.5;
uniform float puissance = 0.0;
varying float d;
void vertex() { d = clamp(abs(dot(VERTEX, axe)) / max(longueur, 0.001), 0.0, 1.0); }
void fragment() { ALBEDO = couleur; ALPHA = (1.0 - d) * 0.8 * puissance; }
"""
## Le même jet dans le système de lumière (étape 8) : vraie luminance, œil du pilote, profondeur logarithmique.
const SHADER_PANACHE_LUMIERE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
#include "res://scripts/lumiere/oeil.gdshaderinc"
#include "res://scripts/lumiere/compagnon.gdshaderinc"
#include "res://scripts/lumiere/objets.gdshaderinc"
uniform vec3 couleur = vec3(0.0, 0.25, 1.0);
uniform vec3 axe = vec3(0.0, 0.0, 1.0);
uniform float longueur = 1.5;
uniform float puissance = 0.0;
uniform float luminance = 1500.0;
varying float d;
void vertex() { d = clamp(abs(dot(VERTEX, axe)) / max(longueur, 0.001), 0.0, 1.0); }
void fragment() {
	vec3 l = couleur * luminance * (1.0 - d) * 0.8 * puissance;
	ALBEDO = max(oeil_vers_ecran(l, FRAGCOORD.xy, TIME) - oeil_vers_ecran(vec3(0.0), FRAGCOORD.xy, TIME), vec3(0.0));
	DEPTH = profondeur_log(-VERTEX.z);
}
"""
## Luminances (cd/m²) de ce qui brille, pour le système de lumière : écran ordinaire, lueur d'une sortie
## de moteur à pleine poussée (métal chauffé et gaz ionisé), cœur d'un jet à pleine poussée.
const LUMINANCE_ECRAN := 120.0
const LUMINANCE_LUEUR := 4000.0
const LUMINANCE_JET := 1500.0
var pieces_cockpit                   # leviers, manche, pédales, interrupteurs, boutons, voyants (cockpit.gd)
var ecrans                           # écrans du cockpit remplis en direct (ecrans_cockpit.gd)
var clics := {}                      # actions déclenchées cette image par un clic sur le cockpit
var ordres_pilote := Vector3.ZERO    # ce que demande le pilote (le manche ne suit pas le stabilisateur)
var planete: MeshInstance3D
var calotte: MeshInstance3D
var materiau_planete: ShaderMaterial
var hud: Label
var aide: Label
var compteur: Label                  # images/s, en haut à droite
var _compteur_t := 0.0
var message: Label
var marqueur_avant: Label
var marqueur_arriere: Label
var couche_hud: CanvasLayer

# =====================================================================
# DÉMARRAGE
# =====================================================================
## Mesure de vitesse (lancer avec « -- --mesure ») : sans synchro écran, 10 s en vue cockpit puis 10 s
## en vue extérieure ; écrit les images par seconde (moyenne et pire) et le temps de la lumière, puis quitte.
var _mesure := {}


func _mesurer(delta: float) -> void:
	if _mesure.is_empty():
		return
	_mesure.t += delta
	var phase: int = _mesure.phase
	if _mesure.t < 3.0:
		return    # on laisse l'œil et le jeu se stabiliser
	if _mesure.n == 0 and son != null:
		son.remettre_mesures_fil_audio()   # sons fabriqués en direct (C++) : on mesure cette phase seulement
	_mesure.n += 1
	_mesure.somme += delta
	_mesure.pire = maxf(_mesure.pire, delta)
	_mesure.lumiere += temps_lumiere_ms
	var vp := get_viewport().get_viewport_rid()
	_mesure.gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_mesure.dessin_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	_mesure.jeu += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_mesure.physique += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if son != null:
		_mesure.son += son.ms_par_image
	if avec_lumiere:
		for k in lumiere.ms_parties:
			_mesure.parties[k] = _mesure.parties.get(k, 0.0) + lumiere.ms_parties[k]
	if _mesure.t >= 13.0:
		var nom: String = PHASES_MESURE[phase]
		var ligne := "MESURE %s : %.0f images/s en moyenne, pire image %.1f ms, lumière %.1f ms par image" % [
			nom, _mesure.n / _mesure.somme, _mesure.pire * 1000.0, _mesure.lumiere / _mesure.n]
		var detail := PackedStringArray()
		for k in _mesure.parties:
			detail.append("%s %.1f" % [k, _mesure.parties[k] / _mesure.n])
		ligne += "\n   détail (ms) : " + ", ".join(detail)
		ligne += "\n   carte graphique %.1f ms, préparation du dessin %.1f ms, scripts %.1f ms, physique %.1f ms, son %.2f ms, fenêtre %s" % [
			_mesure.gpu / _mesure.n, _mesure.dessin_cpu / _mesure.n, _mesure.jeu / _mesure.n, _mesure.physique / _mesure.n,
			_mesure.son / _mesure.n, str(get_viewport().get_visible_rect().size)]
		if son != null and son.synthese_directe:
			# fabriqué dans le fil audio de Godot, à côté des images : part d'un cœur du processeur
			ligne += "\n   son fabriqué en direct (C++, fil audio, 3 voix et 16 chocs à pleine charge) : %.2f %% d'un cœur" % (son.charge_fil_audio() * 100.0)
		print(ligne)
		_mesure.texte += ligne + "\n"
		if phase + 1 < PHASES_MESURE.size():
			_mesure.merge({"phase": phase + 1, "t": 0.0, "n": 0, "somme": 0.0, "pire": 0.0, "lumiere": 0.0, "parties": {},
				"gpu": 0.0, "dessin_cpu": 0.0, "jeu": 0.0, "physique": 0.0, "son": 0.0}, true)
			_phase_mesure(phase + 1)
		else:
			var f := FileAccess.open("user://mesure.txt", FileAccess.WRITE)
			if f:
				f.store_string(_mesure.texte)
			get_tree().quit()


const PHASES_MESURE := ["vue cockpit", "vue extérieure", "vue extérieure sans ombres",
	"vue extérieure, image à 70 %", "vue extérieure, carte d'ombre 4096 (ancien réglage)",
	"vue extérieure, carte d'ombre 1024", "vue cockpit, image à 70 %"]
# [cockpit, ombres, échelle de l'image, taille de la carte d'ombre] pour chaque phase
const REGLAGES_MESURE := [[true, true, 1.0, 2048], [false, true, 1.0, 2048], [false, false, 1.0, 2048],
	[false, true, 0.7, 2048], [false, true, 1.0, 4096], [false, true, 1.0, 1024], [true, true, 0.7, 2048]]


func _phase_mesure(phase: int) -> void:
	var r: Array = REGLAGES_MESURE[phase]
	vue_interieure = r[0]
	_appliquer_vue()
	if avec_lumiere and lumiere.lumiere_soleil:
		lumiere.lumiere_soleil.shadow_enabled = r[1]
	get_viewport().scaling_3d_scale = r[2]
	RenderingServer.directional_shadow_atlas_set_size(r[3], true)


func _ready() -> void:
	if "--mesure" in OS.get_cmdline_user_args():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		_mesure = {"phase": 0, "t": 0.0, "n": 0, "somme": 0.0, "pire": 0.0, "lumiere": 0.0, "parties": {}, "texte": "",
			"gpu": 0.0, "dessin_cpu": 0.0, "jeu": 0.0, "physique": 0.0, "son": 0.0}
		call_deferred("_debut_mesure")
	else:
		# Synchronisation « adaptative » : à 60 i/s, l'image attend l'écran (pas de déchirure) ; en dessous,
		# elle part tout de suite au lieu d'attendre l'image suivante de l'écran (sinon 50 i/s tombent à 30-45).
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
	commandes = Commandes.new()
	commandes.charger()      # réglages de la dernière partie (sinon : disposition par défaut)
	commandes.appliquer()
	# le vaisseau : construit à partir de son plan (celui choisi dans l'atelier, sinon le chasseur de départ)
	var plan = Plan.par_defaut()
	var chemin_plan := Partie.plan_choisi()
	# « -- --mesure --plan <fichier> » : mesurer la vitesse avec un autre vaisseau (atelier, étape 5)
	var args := OS.get_cmdline_user_args()
	var k_plan := args.find("--plan")
	if k_plan >= 0 and k_plan + 1 < args.size():
		chemin_plan = args[k_plan + 1]
	if chemin_plan != Plan.PLAN_PAR_DEFAUT:
		var autre = Plan.new()
		if autre.charger(chemin_plan):
			plan = autre
		else:
			push_warning("Plan « %s » illisible : chasseur de départ. %s" % [chemin_plan, "; ".join(autre.erreurs)])
	vaisseau = VaisseauPhysique.new(plan)
	# lancé depuis l'atelier ou l'accueil : devant le hangar ; lancé tout seul (ou --mesure) : en orbite
	if Partie.depart() == Partie.DEPART_HANGAR and _mesure.is_empty():
		depart = Partie.DEPART_HANGAR
	vaisseau.gm = GRAVITE_SURFACE * RAYON_PLANETE * RAYON_PLANETE
	vaisseau.rayon_planete = RAYON_PLANETE
	vaisseau.omega_planete = TAU / DUREE_JOUR
	vaisseau.atmosphere = Atmosphere.new(RAYON_PLANETE, vaisseau.omega_planete)
	vaisseau.placer_en_orbite(ALTITUDE_DEPART)
	_creer_pilote_et_cockpit()
	_brancher_lumiere()
	vaisseau.trou_de_ver = trou_de_ver
	reperes.preparer(vaisseau)   # après la lune : ajoute la gravité du Soleil et de la compagne
	if depart == Partie.DEPART_HANGAR:
		_poser_devant_hangar()   # après le relief et les astres : il se pose sur le vrai sol
	_creer_hud()
	_appliquer_vue()
	droide = Droide.new()
	add_child(droide)
	droide.installer(self, couche_hud, modele_droide)
	# le son du cockpit (phase 1) : il lit la physique après chaque pas, sans jamais la modifier
	son = MoteurAudio.new()
	son.name = "Son"
	add_child(son)
	son.installer(vaisseau, pilote, camera, oeil_pilote)


## Départ « devant le hangar » : posé sur ses roues, à l'arrêt, nez à l'opposé du Soleil du départ.
func _poser_devant_hangar() -> void:
	vaisseau.poser_au_sol(LIEU_HANGAR, -LumiereJeu.VERS_SOLEIL.normalized())
	gaz = 0.0


## Étape 8 : le système de lumière (vrai Soleil, planète en rayons, œil du pilote). Sans sa partie C++,
## le jeu garde son ancien affichage (planète lisse, Soleil de Godot).
func _brancher_lumiere() -> void:
	lumiere = LumiereJeu.new()
	lumiere.name = "Lumiere"
	add_child(lumiere)
	avec_lumiere = lumiere.preparer(camera, RAYON_PLANETE, vaisseau.gm)
	if not avec_lumiere:
		lumiere.queue_free()
		lumiere = null
		_creer_environnement()
		_creer_planete()
		_appliquer_vue()
		return
	lumiere.ajouter_objets(exterieur, pilote, true)
	lumiere.ajouter_objets(cockpit, pilote)
	toile = Toile.new()
	lumiere.add_child(toile)
	_brillances_dans_lumiere()
	# La coque passe au-dessus du cockpit, sous la verrière : elle ne doit pas lui faire d'ombre.
	var vitre := cockpit.find_child("Cockpit_verriere", true, false) as MeshInstance3D
	var coque := exterieur.find_child("Fuselage", true, false) as MeshInstance3D
	if vitre and coque:
		var b: AABB = lumiere.objets.boite(vitre, pilote)
		b = b.grow(0.05)
		b.position.y -= 0.6
		b.size.y += 1.6
		lumiere.objets.percer_ombre(coque, b, pilote)
	if lampe_ancienne:
		lampe_ancienne.queue_free()   # remplacée par la vraie lampe du système
		lampe_ancienne = null
	# le sol de la physique suit le relief de la planète dessinée
	vaisseau.relief = lumiere.hauteur_sol_planete   # (la physique fait elle-même la rotation de la planète)
	# la petite lune attire aussi le vaisseau (elle bouge : sa position est recalculée à chaque pas)
	if lumiere.lune:
		vaisseau.ajouter_astre_mobile("lune", lumiere.gm_lune(), lumiere.position_lune, LumiereJeu.RAYON_LUNE)
		# grandes distances : près de la lune, on compte depuis elle (on peut s'y poser)
		var lune_planete = lumiere.lune
		reperes.configurer_lune(lumiere.orbite, LumiereJeu.RAYON_LUNE, lumiere.gm_lune(), vaisseau.gm,
			func(p: PackedFloat64Array) -> float: return lune_planete.hauteur_sol(p))
	_creer_casque()
	_appliquer_vue()


## Ce qui brille dans le modèle v25 (écrans, voyants, lueurs et jets des moteurs) passe aussi par le
## système de lumière : une vraie luminance (cd/m²) vue par l'œil du pilote, et la même profondeur
## logarithmique que le reste (sinon ces pièces passeraient devant ou derrière la coque au hasard).
func _brillances_dans_lumiere() -> void:
	# écrans : l'image dessinée devient la lumière qu'ils émettent (≈ 120 cd/m², un écran ordinaire)
	for nom in ecrans.ecrans:
		var mi := ecrans.ecrans[nom]["mesh"] as MeshInstance3D
		var m := mi.get_surface_override_material(0) as ShaderMaterial
		if m == null:
			continue
		m.set_shader_parameter("tex_emission", (ecrans.ecrans[nom]["viewport"] as SubViewport).get_texture())
		m.set_shader_parameter("tex_albedo", null)
		m.set_shader_parameter("albedo_lin", Vector3(0.02, 0.02, 0.02))   # verre sombre
		m.set_shader_parameter("emission_couleur", Vector3.ONE)
		m.set_shader_parameter("emission_luminance", LUMINANCE_ECRAN)
	# voyants : ils reprennent leurs nouvelles matières pour s'allumer et s'éteindre
	pieces_cockpit.rebrancher_matieres()
	# lueurs des sorties de moteurs : matière du système, sa luminance suit la vraie poussée
	var sh_objet: Shader = load("res://scripts/lumiere/objet.gdshader")
	for l in lueurs:
		var m := ShaderMaterial.new()
		m.shader = sh_objet
		m.set_shader_parameter("albedo_lin", Vector3.ZERO)
		m.set_shader_parameter("emission_luminance", 0.0)
		(l[0] as MeshInstance3D).material_override = m
		l[1] = m
	# jets : lumière ajoutée devant ce qu'il y a derrière, vue par l'œil
	var sh_jet := Shader.new()
	sh_jet.code = SHADER_PANACHE_LUMIERE
	for pa in panaches:
		var ancien := pa[1] as ShaderMaterial
		var m := ShaderMaterial.new()
		m.shader = sh_jet
		m.set_shader_parameter("axe", ancien.get_shader_parameter("axe"))
		m.set_shader_parameter("longueur", ancien.get_shader_parameter("longueur"))
		(pa[0] as MeshInstance3D).material_override = m
		pa[1] = m


## Bord du casque, vu de l'intérieur : la visière ne laisse voir qu'un grand ovale, le reste est l'intérieur
## sombre du casque. (La couleur de la visière, elle, passe par l'œil : oeil_filtre.)
func _creer_casque() -> void:
	casque = CanvasLayer.new()
	casque.layer = 0
	add_child(casque)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, 2.0);
	p.x *= 0.80;
	p.y *= 1.10;
	float d = length(p);
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(1.02, 1.22, d) * 0.97);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	casque.add_child(r)


func _creer_environnement() -> void:
	var ciel := Sky.new()
	var mat_ciel := ShaderMaterial.new()
	mat_ciel.shader = load("res://shaders/etoiles.gdshader")
	ciel.sky_material = mat_ciel
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = ciel
	# aucune lumière d'ambiance : seul le Soleil éclaire (le vrai noir de l'espace)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var soleil := DirectionalLight3D.new()
	soleil.light_energy = 1.3
	add_child(soleil)
	soleil.basis = Basis.looking_at(-DIRECTION_SOLEIL.normalized(), Vector3.UP)


func _creer_planete() -> void:
	materiau_planete = ShaderMaterial.new()
	materiau_planete.shader = load("res://shaders/planete.gdshader")
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	planete = MeshInstance3D.new()
	planete.mesh = sphere
	planete.material_override = materiau_planete
	add_child(planete)
	calotte = MeshInstance3D.new()
	calotte.material_override = materiau_planete
	calotte.visible = false
	add_child(calotte)


func _creer_pilote_et_cockpit() -> void:
	pilote = Node3D.new()           # suit l'orientation du vaisseau ; centre de gravité à l'origine
	add_child(pilote)
	# le modèle 3D est exporté de Blender dans le même repère que la physique (-Z avant, +Y haut) ;
	# il est décalé pour que son centre de gravité soit au centre de la scène (le vaisseau tourne autour)
	var corps := Node3D.new()
	corps.position = -vaisseau.centre_gravite
	pilote.add_child(corps)
	corps_vaisseau = corps
	exterieur = (load(MODELE_EXTERIEUR) as PackedScene).instantiate()
	corps.add_child(exterieur)
	cockpit = (load(MODELE_COCKPIT) as PackedScene).instantiate()
	corps.add_child(cockpit)
	# droïde (modèle v24) : posé au fond de son logement, seule la tête dépasse
	var logement := exterieur.find_child("Point_droide", true, false) as Node3D
	if logement != null and ResourceLoader.exists(MODELE_DROIDE):
		modele_droide = (load(MODELE_DROIDE) as PackedScene).instantiate()
		logement.add_child(modele_droide)
	# ailes, train, trappes, moteurs de levage, tuyère, amortisseurs : le même code que l'atelier
	modele = ModeleVaisseau.new(exterieur, vaisseau)
	# vaisseau fait dans l'atelier : modules enlevés cachés, chaque pièce du plan dessinée (même code que
	# l'atelier) ; dans le jeu, les pièces posées de même matière sont FUSIONNÉES (moins d'appels de dessin
	# pour la carte graphique : étape 5)
	dessin = DessinVaisseau.new(exterieur, modele, modele_droide)
	dessin.construire(vaisseau.plan, vaisseau, true)
	_trouver_lueurs()
	var oeil := cockpit.find_child("Oeil_pilote", true, false) as Node3D
	if oeil != null:
		oeil_pilote = oeil.position
	_oeil_plan = oeil_pilote
	oeil_pilote -= vaisseau.centre_gravite   # la caméra est placée par rapport au centre de gravité
	for m in exterieur.find_children("*", "GeometryInstance3D", true, false):
		maillages_exterieurs.append(m)
	for n in exterieur.find_children("*", "Node3D", true, false):
		var e = n.get_meta("extras", {})
		if e is Dictionary and bool(e.get("cacher_en_vue_cockpit", false)):
			caches_en_cockpit.append(n)

	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 50000.0
	pilote.add_child(camera)
	camera.make_current()

	# petite lampe du cockpit (une vraie source de lumière, pour lire les instruments la nuit)
	var lampe := OmniLight3D.new()
	lampe.position = oeil_pilote + Vector3(0, 0.3, -0.6)
	lampe.light_color = Color(1.0, 0.75, 0.45)
	lampe.light_energy = 0.25
	lampe.omni_range = 2.0
	cockpit.add_child(lampe)
	lampe_ancienne = lampe
	pieces_cockpit = Cockpit.new(cockpit)
	ecrans = EcransCockpit.new(cockpit, self)
	_appliquer_vue()
	_animer_modele()


## Vue cockpit : on voit l'intérieur ; la coque ne fait pas d'ombre dans le cockpit (sinon il serait
## tout noir). Vue extérieure : le cockpit est caché, la coque fait de nouveau ses ombres.
func _appliquer_vue() -> void:
	cockpit.visible = vue_interieure
	for n in caches_en_cockpit:
		if avec_lumiere:
			# Système de lumière : ces pièces restent là pour leur ombre sur le sol, mais on ne les
			# dessine pas en vue cockpit (elles boucheraient la vue du pilote).
			(n as Node3D).visible = true
			var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if vue_interieure else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			for m in (n as Node).find_children("*", "GeometryInstance3D", true, false):
				(m as GeometryInstance3D).cast_shadow = mode
			if n is GeometryInstance3D:
				(n as GeometryInstance3D).cast_shadow = mode
		else:
			(n as Node3D).visible = not vue_interieure
	# en vue cockpit, les informations sont sur les écrans du tableau de bord ; dehors, en surimpression
	if hud != null:
		hud.visible = not vue_interieure
	if compteur != null:
		compteur.visible = vue_interieure   # dehors, le tableau a sa propre ligne IMAGES/S
	tete = Vector2.ZERO
	if casque:
		casque.visible = vue_interieure and lumiere.visiere != 0
	if avec_lumiere:
		lumiere.vue_interieure = vue_interieure
		# système de lumière : la coque fait toujours ses ombres (la verrière, jamais : on voit à travers)
		for m in maillages_exterieurs:
			var nom := String((m as Node).name).to_lower()
			var vitre := nom.contains("verriere") and not nom.contains("cadre")
			if (m as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and not vitre:
				continue   # pièce du nez cachée en vue cockpit (voir plus haut) : elle garde son ombre
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if vitre else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if vitre:
				# la verrière vue de dehors (opaque, teintée) : en vue cockpit, c'est la vitre du cockpit qu'on voit
				(m as Node3D).visible = not vue_interieure
		return
	var ombre := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if vue_interieure else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for m in maillages_exterieurs:
		(m as GeometryInstance3D).cast_shadow = ombre
	tete = Vector2.ZERO


## Ailes et train : le modèle suit exactement l'état de la physique (mêmes angles que le calcul des poussées).
## Étape 7 : les pièces mobiles posées dans l'atelier aussi (dessin.poser) ; et quand une pièce mobile
## emmène sa masse, le centre de gravité se déplace dans le vaisseau : le dessin (et l'œil du pilote) se
## décalent d'autant, puisque la scène tourne autour du centre de gravité.
func _animer_modele() -> void:
	dessin.poser(vaisseau)
	if corps_vaisseau != null:
		corps_vaisseau.position = -vaisseau.centre_gravite
	oeil_pilote = _oeil_plan - vaisseau.centre_gravite


## Modèle v19 : lueurs et jets des moteurs.
func _trouver_lueurs() -> void:
	# n° du moteur de la physique pour chaque point de poussée du modèle
	var num := {}
	for m in vaisseau.moteurs:
		num["Point_moteur_" + String(m["nom"]).replace(" ", "_")] = m
	# pièces posées dans l'atelier : leurs lueurs et jets disent quel moteur de la physique ils montrent
	var par_id := {}
	for t in vaisseau.moteurs + vaisseau.rcs:
		par_id[String(t["id"])] = t
	for n in exterieur.find_children("*", "MeshInstance3D", true, false):
		var e = n.get_meta("extras", {})
		if not (e is Dictionary):
			continue
		var i = num.get(e.get("moteur", ""))
		if i == null and e.has("id_physique"):
			i = par_id.get(String(e["id_physique"]))
		if i == null and String(e.get("moteur", "")).begins_with("Point_rcs_"):
			# petite buse : on prend le propulseur de la physique le plus proche de la lueur
			# (les noms haut/bas des buses du nez sont inversés dans le modèle, la position ne trompe pas)
			var d_min := 0.1
			for t in vaisseau.rcs:
				var d: float = ((t["position"] as Vector3) - (n as Node3D).position).length()
				if t["aile"] == "" and d < d_min:
					d_min = d
					i = t
		if i == null:
			continue
		var faible := _couleur(e.get("couleur_faible", [0.0, 0.25, 1.0]))
		var forte := _couleur(e.get("couleur_forte", [0.55, 0.0, 1.0]))
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if e.get("type", "") == "lueur":
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color.BLACK
			mi.material_override = mat
			lueurs.append([mi, mat, i, faible, forte, float(e.get("energie_min", 1.0)), float(e.get("energie_max", 4.0))])
		elif e.get("type", "") == "panache":
			var mat := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = SHADER_PANACHE
			mat.shader = sh
			var axe := {"X": 0, "Y": 1, "Z": 2}.get(String(e.get("axe_longueur_godot", "Z")), 2) as int
			var v_axe := Vector3.ZERO
			v_axe[axe] = 1.0
			mat.set_shader_parameter("axe", v_axe)
			mat.set_shader_parameter("longueur", float(e.get("longueur_max_m", 1.5)))
			mi.material_override = mat
			var repos := Vector3.ONE   # dans le glb, les jets sont exportés écrasés (moteurs coupés)
			panaches.append([mi, mat, i, repos, axe, faible, forte])
			mi.visible = false


static func _couleur(a) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return Color(0.0, 0.25, 1.0)


## Lueurs et jets : ils suivent la VRAIE poussée de chaque moteur (pas la commande des gaz).
func _animer_lueurs() -> void:
	for l in lueurs:
		var p: float = clampf(float(l[2]["actuel"]), 0.0, 1.0)
		if float(l[2]["poussee_max"]) <= 0.0:
			p = 0.0
		var lum := lerpf(float(l[5]), float(l[6]), p) / float(l[6])
		if l[1] is ShaderMaterial:
			# système de lumière : vraie luminance
			var c := (l[3] as Color).lerp(l[4], p).srgb_to_linear()
			var mat_l := l[1] as ShaderMaterial
			mat_l.set_shader_parameter("emission_couleur", Vector3(c.r, c.g, c.b))
			mat_l.set_shader_parameter("emission_luminance", 0.0 if p < 0.01 else LUMINANCE_LUEUR * lum)
			continue
		var mat: StandardMaterial3D = l[1]
		if p < 0.01:
			mat.albedo_color = Color.BLACK
		else:
			mat.albedo_color = (l[3] as Color).lerp(l[4], p) * lum
	for pa in panaches:
		var p: float = clampf(float(pa[2]["actuel"]), 0.0, 1.0)
		if float(pa[2]["poussee_max"]) <= 0.0:
			p = 0.0
		var mi: MeshInstance3D = pa[0]
		mi.visible = p >= 0.01
		if mi.visible:
			var sc: Vector3 = pa[3]
			sc[pa[4]] = maxf(p, 0.001)
			mi.scale = sc
			var mat: ShaderMaterial = pa[1]
			var cj := (pa[5] as Color).lerp(pa[6], p)
			if avec_lumiere:
				cj = cj.srgb_to_linear()
				mat.set_shader_parameter("luminance", LUMINANCE_JET)
			mat.set_shader_parameter("couleur", cj)
			mat.set_shader_parameter("puissance", 1.0)


## Amortisseurs et ressorts : ils s'écrasent comme dans la physique ; les roues tournent en roulant.
func _animer_amortisseurs(delta: float) -> void:
	modele.amortir(vaisseau, delta)


func _label(taille: int, couleur := Color(0.75, 0.95, 0.8)) -> Label:
	var l := Label.new()
	var police := SystemFont.new()
	police.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	l.add_theme_font_override("font", police)
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _creer_hud() -> void:
	var couche := CanvasLayer.new()
	couche_hud = couche
	add_child(couche)
	hud = _label(15)
	hud.position = Vector2(16, 12)
	couche.add_child(hud)
	# compteur d'images/s, en haut à droite, visible dans les deux vues
	compteur = _label(14, Color(0.8, 0.85, 1.0))
	compteur.anchor_left = 1.0
	compteur.anchor_right = 1.0
	compteur.offset_left = -300
	compteur.offset_right = -16
	compteur.offset_top = 12
	compteur.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	couche.add_child(compteur)
	aide = _label(14, Color(0.8, 0.85, 1.0))
	aide.anchor_top = 1.0
	aide.anchor_bottom = 1.0
	aide.offset_left = 16
	aide.offset_top = -268
	couche.add_child(aide)
	_ecrire_aide()
	message = _label(28, Color(1.0, 0.45, 0.4))
	message.anchor_left = 0.5
	message.anchor_right = 0.5
	message.anchor_top = 0.3
	message.offset_left = -300
	message.offset_right = 300
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	couche.add_child(message)
	marqueur_avant = _label(22, Color(0.5, 1.0, 0.5))
	marqueur_avant.text = "(o)"
	couche.add_child(marqueur_avant)
	marqueur_arriere = _label(22, Color(1.0, 0.6, 0.4))
	marqueur_arriere.text = "(x)"
	couche.add_child(marqueur_arriere)

func _ecrire_aide() -> void:
	var c = commandes
	aide.text = (
		"%s : plus de poussée   %s : moins   %s : couper la poussée\n" % [c.resume("gaz_plus"), c.resume("gaz_moins"), c.resume("couper_gaz")]
		+ "Tangage %s      Lacet %s\n" % [_paire("tangage_haut", "tangage_bas"), _paire("lacet_gauche", "lacet_droite")]
		+ "Roulis %s\n" % _paire("roulis_gauche", "roulis_droite")
		+ "Pilote auto : %s garder le cap   %s s'arrêter   %s atterrir (une touche de pilotage le coupe)\n" % [c.resume("pilote_cap"), c.resume("pilote_arret"), c.resume("pilote_atterrir")]
		+ "%s : stabilisateur   %s : pause   Temps : %s %s %s %s %s %s, loin des astres %s %s, ou %s / %s\n" % [c.resume("stabilisateur"), c.resume("pause"), c.resume("temps_x1"), c.resume("temps_x10"), c.resume("temps_x100"), c.resume("temps_x1000"), c.resume("temps_x10000"), c.resume("temps_x100000"), c.resume("temps_x1000000"), c.resume("temps_x10000000"), c.resume("temps_moins"), c.resume("temps_plus")]
		+ "Puissance des moteurs (relativité) : %s moins   %s plus\n" % [c.resume("poussee_moins"), c.resume("poussee_plus")]
		+ "%s : remettre en orbite   %s : recommencer (%s)   %s : retour à l'atelier   %s : tests   %s : cacher l'aide\n" % [c.resume("remettre_orbite"), c.resume("recommencer"), "devant le hangar" if depart == Partie.DEPART_HANGAR else "en orbite", c.resume("atelier"), c.resume("tests"), c.resume("aide")]
		+ "%s : ailes   %s : train d'atterrissage   %s : vol vertical   %s : vue cockpit / extérieure   %s : vanne de la cabine (vider l'air)\n" % [c.resume("ailes"), c.resume("train"), c.resume("vol_vertical"), c.resume("vue"), c.resume("vanne_cabine")]
		+ "Au sol : le lacet tourne aussi la roue avant   %s (maintenir) : freins des roues (frein de parc automatique à l'arrêt, gaz à zéro)\n" % c.resume("frein")
		+ "Tourner la tête (ou la caméra) : %s   %s : regarder droit devant   %s (maintenir) : zoom\n" % [_aide_tete(), c.resume("regard_centre"), c.resume("zoom")]
		+ "%s : projecteur   %s : casque et visière   %s : tête qui bouge avec les G\n" % [c.resume("phares"), c.resume("visiere"), c.resume("tete_g")]
		+ "Einstein : %s toile de l'espace (courbure)   %s saut d'essai vers le trou noir Gaia BH1   %s trou de ver vers Alpha du Centaure\n" % [c.resume("toile"), c.resume("trou_noir"), c.resume("trou_de_ver")]
		+ "Dans le cockpit, on peut aussi cliquer sur les boutons et les interrupteurs\n"
		+ "Entrée : parler au droïde R-7 (ordres calmes : train, ailes, pilote auto, questions)\n"
		+ "%s : configurer les commandes (clavier et manette)" % c.resume("ecran_touches"))

## « stick droit » si les 4 directions de la tête sont sur le stick droit, sinon la liste.
func _aide_tete() -> String:
	var noms := ["regard_gauche", "regard_droite", "regard_haut", "regard_bas"]
	var tout_stick_droit := true
	for n in noms:
		var m: String = commandes.liaisons[n]["manette"]
		if not (m.begins_with("a:%d:" % JOY_AXIS_RIGHT_X) or m.begins_with("a:%d:" % JOY_AXIS_RIGHT_Y)):
			tout_stick_droit = false
	if tout_stick_droit and noms.all(func(n): return commandes.liaisons[n]["clavier"] == ""):
		return "stick droit"
	var morceaux := PackedStringArray()
	for n in noms:
		morceaux.append(commandes.resume(n))
	return ", ".join(morceaux)


## « Flèche haut / Flèche bas (manette : Stick gauche ↑ haut / Stick gauche ↓ bas) »
func _paire(a: String, b: String) -> String:
	var l: Dictionary = commandes.liaisons
	var txt := "%s / %s" % [Commandes.nom_lisible(l[a]["clavier"]), Commandes.nom_lisible(l[b]["clavier"])]
	if l[a]["manette"] != "" or l[b]["manette"] != "":
		txt += " (%s / %s)" % [Commandes.nom_lisible(l[a]["manette"]), Commandes.nom_lisible(l[b]["manette"])]
	return txt

# =====================================================================
# COMMANDES DU PILOTE
# =====================================================================
## Appuis simples (boutons, touches). On interroge Godot à chaque image : ça marche pareil
## pour une touche, un bouton de manette ou même un stick si le joueur en choisit un.
func _lire_boutons() -> void:
	if ecran_touches != null or Engine.get_process_frames() == image_fermeture or (droide != null and droide.ecrit):
		clics.clear()
		return
	if _appui("ecran_touches"):
		_ouvrir_ecran_touches()
		clics.clear()
		return
	if _appui("temps_x1"): acc_temps = ACCELERATIONS_TEMPS[0]
	if _appui("temps_x10"): acc_temps = ACCELERATIONS_TEMPS[1]
	if _appui("temps_x100"): acc_temps = ACCELERATIONS_TEMPS[2]
	if _appui("temps_x1000"): acc_temps = ACCELERATIONS_TEMPS[3]
	if _appui("temps_x10000"): acc_temps = ACCELERATIONS_TEMPS[4]
	if _appui("temps_x100000"): acc_temps = ACCELERATIONS_TEMPS[5]
	if _appui("temps_x1000000"): acc_temps = ACCELERATIONS_TEMPS[6]
	if _appui("temps_x10000000"): acc_temps = ACCELERATIONS_TEMPS[7]
	if _appui("poussee_plus"): _changer_poussee(1)
	if _appui("poussee_moins"): _changer_poussee(-1)
	if _appui("temps_plus"):
		acc_temps = ACCELERATIONS_TEMPS[mini(ACCELERATIONS_TEMPS.find(acc_temps) + 1, ACCELERATIONS_TEMPS.size() - 1)]
	if _appui("temps_moins"):
		acc_temps = ACCELERATIONS_TEMPS[maxi(ACCELERATIONS_TEMPS.find(acc_temps) - 1, 0)]
	if _appui("couper_gaz"):
		gaz = 0.0
		ordinateur.activer(PiloteAuto.AUCUN, vaisseau)
	if _appui("pilote_cap"):
		ordinateur.activer(PiloteAuto.AUCUN if ordinateur.mode == PiloteAuto.CAP else PiloteAuto.CAP, vaisseau)
	if _appui("pilote_arret"):
		ordinateur.activer(PiloteAuto.AUCUN if ordinateur.mode == PiloteAuto.ARRET else PiloteAuto.ARRET, vaisseau)
	if _appui("pilote_atterrir"):
		ordinateur.activer(PiloteAuto.AUCUN if ordinateur.mode == PiloteAuto.ATTERRIR else PiloteAuto.ATTERRIR, vaisseau)
	if _appui("stabilisateur"): stabilisateur = not stabilisateur
	if _appui("ailes"): vaisseau.ouvrir_ailes(vaisseau.ailes_consigne < 0.5)
	if _appui("train"): vaisseau.sortir_train(vaisseau.train_consigne < 0.5)
	if _appui("vol_vertical"): vaisseau.passer_vol_vertical(vaisseau.vertical_consigne < 0.5)
	if _appui("vanne_cabine") and vaisseau.vie != null: vaisseau.vie.ouvrir_vanne(not vaisseau.vie.vanne_ouverte)
	if _appui("vue"):
		vue_interieure = not vue_interieure
		_appliquer_vue()
	if _appui("pause"): en_pause = not en_pause
	if _appui("tete_g"):
		tete_g = not tete_g
	if toile != null and _appui("toile"):
		toile.visible = not toile.visible
	if _appui("trou_noir"):
		ordinateur.activer(PiloteAuto.AUCUN, vaisseau)
		gaz = 0.0
		acc_temps = 1
		reperes.aller_trou_noir(vaisseau, DISTANCE_TROU_NOIR)
	if _appui("trou_de_ver"):
		ordinateur.activer(PiloteAuto.AUCUN, vaisseau)
		gaz = 0.0
		acc_temps = 1
		trou_de_ver.aller(vaisseau, ALTITUDE_DEPART)
	if avec_lumiere and _appui("phares"):
		lumiere.projecteur = not lumiere.projecteur
	if avec_lumiere and _appui("visiere"):
		lumiere.changer_visiere()
		casque.visible = vue_interieure and lumiere.visiere != 0
	if _appui("aide"):
		aide_visible = not aide_visible
		aide.visible = aide_visible
	var recommencer := _appui("recommencer")
	var orbite := _appui("remettre_orbite")
	if orbite or recommencer:
		ordinateur.activer(PiloteAuto.AUCUN, vaisseau)
		gaz = 0.0
		acc_temps = 1
		reperes.revenir_maison(vaisseau)
		if recommencer and depart == Partie.DEPART_HANGAR:
			_poser_devant_hangar()   # recommencer : on repart d'où on est parti
		else:
			vaisseau.placer_en_orbite(ALTITUDE_DEPART)
	if _appui("atelier"):
		Partie.aller_atelier(get_tree())   # le jeu est libéré, l'atelier rechargé
		clics.clear()
		return
	clics.clear()
	if Input.is_action_just_pressed("tests"):
		get_tree().change_scene_to_file("res://scenes/tests.tscn")


## Puissance des moteurs principaux : un cran de plus (+1) ou de moins (-1) dans FACTEURS_POUSSEE.
func _changer_poussee(sens: int) -> void:
	var i_p: int = maxi(FACTEURS_POUSSEE.find(vaisseau.facteur_poussee), 0)
	i_p = clampi(i_p + sens, 0, FACTEURS_POUSSEE.size() - 1)
	vaisseau.regler_poussee(FACTEURS_POUSSEE[i_p])


## Vrai si l'action vient d'être demandée (touche, manette ou clic sur le cockpit).
## La pièce correspondante du cockpit s'enfonce alors un instant.
func _appui(action: String) -> bool:
	if Input.is_action_just_pressed(action) or clics.has(action):
		pieces_cockpit.appuyer(action)
		return true
	return false


## Clic gauche en vue cockpit : on cherche la commande visée (bouton, interrupteur, poignée).
func _unhandled_input(e: InputEvent) -> void:
	if not vue_interieure or ecran_touches != null:
		return
	if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var pos := (e as InputEventMouseButton).position
		var action: String = pieces_cockpit.action_sous_rayon(camera.project_ray_origin(pos), camera.project_ray_normal(pos))
		if action != "":
			clics[action] = true
			get_viewport().set_input_as_handled()


func _ouvrir_ecran_touches() -> void:
	ecran_touches = EcranTouches.new()
	ecran_touches.commandes = commandes
	ecran_touches.ferme.connect(_fermer_ecran_touches)
	couche_hud.add_child(ecran_touches)


func _fermer_ecran_touches() -> void:
	ecran_touches = null
	image_fermeture = Engine.get_process_frames()   # pour ne pas rouvrir l'écran avec le même appui
	_ecrire_aide()


## Tourner la tête dans le cockpit (stick droit). Stick lâché : la tête revient doucement droit devant.
func _bouger_tete(delta: float) -> void:
	if ecran_touches != null or (droide != null and droide.ecrit):
		return
	if Input.is_action_just_pressed("regard_centre"):
		tete = Vector2.ZERO
	var dx := Input.get_axis("regard_bas", "regard_haut")
	var dy := Input.get_axis("regard_droite", "regard_gauche")
	if dx == 0.0 and dy == 0.0:
		tete = tete.lerp(Vector2.ZERO, minf(1.0, TETE_RETOUR * delta))
	else:
		tete.x = clampf(tete.x + dx * TETE_VITESSE * delta, -TETE_BAS_MAX, TETE_HAUT_MAX)
		if vue_interieure:
			tete.y = clampf(tete.y + dy * TETE_VITESSE * delta, -TETE_LACET_MAX, TETE_LACET_MAX)
		else:
			tete.y = wrapf(tete.y + dy * TETE_VITESSE * delta, -PI, PI)   # dehors : on peut faire le tour
	# zoom (maintenir) : le champ de vision se resserre pour lire les écrans du tableau de bord
	var fov_voulu := FOV_ZOOM if Input.is_action_pressed("zoom") else FOV_NORMAL
	camera.fov = lerpf(camera.fov, fov_voulu, minf(1.0, 10.0 * delta))
	if vue_interieure:
		camera.position = oeil_pilote + tete_g_pos
		camera.rotation = Vector3(tete.x, tete.y, 0.0)
	else:
		# caméra derrière le vaisseau, qui tourne autour de lui ; elle regarde toujours son centre
		var b := Basis.from_euler(Vector3(clampf(VUE_EXT_HAUTEUR - tete.x, -1.5, 1.5), tete.y, 0.0))
		camera.position = b * Vector3(0, 0, VUE_EXT_DISTANCE)
		camera.basis = b


## Lit le clavier et la manette. Sticks et gâchettes sont analogiques : à moitié = la moitié.
func _lire_ordres(delta: float) -> void:
	var ecrit: bool = droide != null and droide.ecrit   # on parle au droïde : clavier ignoré
	var t := 0.0 if ecrit else Input.get_axis("tangage_bas", "tangage_haut")
	var l := 0.0 if ecrit else Input.get_axis("lacet_droite", "lacet_gauche")
	var r := 0.0 if ecrit else Input.get_axis("roulis_droite", "roulis_gauche")
	ordres_pilote = Vector3(t, l, r)
	# étape 6 (sol) : les palonniers du lacet tournent aussi la roue avant ; Maj serre les freins des roues
	vaisseau.braquage_consigne = l
	vaisseau.frein = 0.0 if ecrit else Input.get_action_strength("frein")
	# la poussée monte ou descend d'autant plus vite qu'on appuie fort (Z / S ou gâchettes R2 / L2)
	if not ecrit:
		gaz += 0.5 * delta * (Input.get_action_strength("gaz_plus") - Input.get_action_strength("gaz_moins"))
	gaz = clampf(gaz, 0.0, 1.0)
	force_cote = Vector3.ZERO
	# Pilote automatique : dès que le joueur touche aux commandes, il reprend la main.
	# (ses ordres sont calculés dans _physics_process, par petits morceaux de temps : en temps
	# accéléré, il garde ainsi le contrôle)
	autopilote_actif = false
	if ordinateur.mode != PiloteAuto.AUCUN:
		if t != 0.0 or l != 0.0 or r != 0.0 or (not ecrit and (Input.is_action_pressed("gaz_plus") or Input.is_action_pressed("gaz_moins"))):
			ordinateur.activer(PiloteAuto.AUCUN, vaisseau)
		else:
			autopilote_actif = true
			return
	# Stabilisateur : sur chaque axe non commandé, il allume les propulseurs qui freinent la rotation.
	# Il n'agit QUE par les propulseurs (aucune rotation imposée directement).
	# En temps accéléré, l'ordre dure plus longtemps (PAS × acc_temps) : le stabilisateur en tient compte.
	if stabilisateur:
		var s: Vector3 = vaisseau.ordres_stabilisateur(PAS * acc_effectif)
		if t == 0.0: t = s.x
		if l == 0.0:
			l = s.y
			# Au sol, il tourne aussi la roue avant (par son vérin, comme un pilote qui corrige au palonnier) :
			# avec les roues arrière (v27), le vaisseau roule déjà droit ; T aide encore à grande vitesse.
			if vaisseau.au_sol:
				vaisseau.braquage_consigne = s.y
		if r == 0.0: r = s.z
	ordres = Vector3(t, l, r)

# =====================================================================
# SIMULATION
# =====================================================================
func _physics_process(delta: float) -> void:
	if en_pause or vaisseau.ecrase or ecran_touches != null:
		return
	# Einstein A3 : plus près d'un autre système d'étoile ? On passe dans son repère.
	if reperes.verifier(vaisseau) and autopilote_actif:
		ordinateur.activer(PiloteAuto.AUCUN, vaisseau)   # le pilote auto ne connaît que la planète
	if vaisseau.ecrase:
		return
	acc_effectif = temps_permis(acc_temps)
	_lire_ordres(delta)
	if autopilote_actif:
		# Le pilote auto calcule ses ordres au plus toutes les 0,04 s de temps de jeu, même en temps
		# accéléré (sinon un seul ordre durerait jusqu'à 8 s à x1000). Il limite lui-même l'accélération
		# du temps quand c'est dangereux (près du sol).
		acc_effectif = mini(acc_effectif, ordinateur.limite_temps(vaisseau))
		var duree: float = PAS * acc_effectif
		var n_ap: int = maxi(1, ceili(duree / ordinateur.periode_controle(vaisseau)))
		var dt_ap: float = duree / n_ap
		for i in n_ap:
			ordinateur.calculer(vaisseau, dt_ap)
			gaz = ordinateur.gaz
			force_cote = ordinateur.force_cote
			ordres = ordinateur.ordres
			vaisseau.commander(gaz, ordres.x, ordres.y, ordres.z, force_cote)
			vaisseau.pas(dt_ap)
			if vaisseau.ecrase:
				break
		return
	vaisseau.commander(gaz, ordres.x, ordres.y, ordres.z, force_cote)
	if acc_effectif == 1:
		vaisseau.pas(PAS)
	else:
		# au-delà de x1000, plus de petits pas (au plus 8 s chacun à x100 000) pour rester précis
		var n: int = mini(acc_effectif, 25) if acc_effectif <= 1000 else 100
		var dt: float = PAS * acc_effectif / n
		for i in n:
			vaisseau.pas(dt)


## Grandes distances : accélération du temps vraiment appliquée. Jusqu'à x100 000, comme demandé.
## Au-delà, seulement loin des astres : en une image, le vaisseau ne doit pas faire plus de 5 % du chemin
## qui le sépare d'un astre (sinon il pourrait sauter par-dessus une planète, ou mal suivre une orbite).
## Rien de magique : le temps passe plus vite, la physique est la même (des pas plus longs).
func temps_permis(acc: int) -> int:
	# Près du sol, la physique découpe chaque pas en morceaux de 1/240 s (ressorts du train) : à x1000,
	# cela faisait plus de 2 000 calculs par image et le jeu se figeait (plusieurs secondes par image).
	# Le temps est donc limité à x100 près du sol (une journée de la planète passe encore en 72 s).
	# (en orbite, une image à x10 millions fait 830 s de chemin : on prend alors la plus grande
	# accélération dont le pas ne s'approche pas du sol, les autres limites s'appliquent ensuite)
	_limite_sol = false
	if acc > TEMPS_MAX_SOL and vaisseau.pres_du_sol(pas_physique(acc)):
		var ok_sol := TEMPS_MAX_SOL
		for a in ACCELERATIONS_TEMPS:
			if a > TEMPS_MAX_SOL and a < acc and not vaisseau.pres_du_sol(pas_physique(a)):
				ok_sol = a
		_limite_sol = ok_sol == TEMPS_MAX_SOL
		acc = ok_sol
	# Atmosphère : dans l'air épais, les pas de calcul doivent rester courts (voir pas_max_air).
	var pas_air: float = vaisseau.pas_max_air()
	_limite_air = false
	if pas_air < INF:
		var ok := 1
		for a in ACCELERATIONS_TEMPS:
			if a <= acc and pas_physique(a) <= maxf(pas_air, PAS):
				ok = a
		_limite_air = ok < acc
		acc = ok
	if acc <= TEMPS_TOUJOURS:
		return acc
	var maxi_acc: float = vaisseau.limite_temps(0.05) / PAS
	var permis := TEMPS_TOUJOURS
	for a in ACCELERATIONS_TEMPS:
		if a <= acc and a > permis and a <= maxi_acc:
			permis = a
	return permis

var _limite_air := false
var _limite_sol := false
const TEMPS_MAX_SOL := 100   # accélération du temps permise près du sol (voir temps_permis)
var _vent_chaleur := Vector3.ZERO


## Atmosphère : l'air autour du vaisseau, ce qu'il lui fait, la chaleur du nez.
func _ligne_air() -> String:
	var v = vaisseau
	var t_nez := "COQUE (nez)   %.0f °C" % (v.temperature_nez - 273.15)
	if v.temperature_nez > v.t_limite_coque:
		t_nez += "  TROP CHAUD (une vraie coque fondrait)"
	if v.densite_air <= 0.0:
		return "AIR           aucun (vide)      " + t_nez
	var a = v.aero
	var p := float(v.atmosphere.etat(v.distance_centre() - v.rayon_planete)[2])
	var txt := "AIR           %s kg/m³  %s  %.0f °C   Mach %.2f   pression du vent %s" % [_petit(v.densite_air),
		_pression_txt(p), v.temperature_air - 273.15, a.mach, _pression_txt(a.pression_dyn)]
	txt += "\n              portance %s   traînée %s   incidence %+.1f°   chaleur reçue %s/m²      %s" % [_force_txt(a.portance),
		_force_txt(a.trainee), rad_to_deg(a.incidence), _puissance_txt(v.flux_nez), t_nez]
	return txt


static func _pression_txt(p: float) -> String:
	if p >= 1000.0:
		return "%s kPa" % _nombre(p / 1000.0, 1)
	return "%s Pa" % _petit(p)


static func _puissance_txt(w: float) -> String:
	var a := absf(w)
	if a >= 1.0e6:
		return "%s MW" % _nombre(w / 1.0e6, 2)
	if a >= 1000.0:
		return "%s kW" % _nombre(w / 1000.0, 1)
	return "%.0f W" % w


## Durée de chaque petit pas de physique pour une accélération du temps (voir _physics_process).
static func pas_physique(a: int) -> float:
	if a == 1:
		return PAS
	var n: int = mini(a, 25) if a <= 1000 else 100
	return PAS * a / n


# =====================================================================
# AFFICHAGE
# =====================================================================
func _debut_mesure() -> void:
	if son != null and son.synthese_directe:
		son.banc = true   # coût du son fabriqué en direct à pleine charge (inaudible)
	_phase_mesure(0)


## Résolution automatique : si la carte graphique met plus de 15 ms par image (pas de 60 i/s possible),
## l'image 3D est calculée un peu plus petite (jusqu'à 70 %) puis agrandie à l'écran ; dès qu'il reste
## de la marge, elle remonte vers 100 %. Le texte (instruments, aide) reste toujours net.
const RESOLUTION_MIN := 0.7
const GPU_TROP := 15.0    # ms
const GPU_MARGE := 13.5   # ms
var echelle_image := 1.0
var _gpu_lisse := 0.0
var _resolution_t := 0.0


func _regler_resolution(delta: float) -> void:
	if not _mesure.is_empty():
		return
	var vp := get_viewport().get_viewport_rid()
	if _resolution_t == 0.0:
		RenderingServer.viewport_set_measure_render_time(vp, true)
	_gpu_lisse = lerpf(_gpu_lisse, RenderingServer.viewport_get_measured_render_time_gpu(vp), 0.1)
	_resolution_t += delta
	if _resolution_t < 0.5:
		return
	_resolution_t = 0.0001
	var avant := echelle_image
	var lent := Engine.get_frames_per_second() < 57.0
	if _gpu_lisse > GPU_TROP and lent:
		echelle_image = maxf(RESOLUTION_MIN, echelle_image - 0.05)
	elif echelle_image < 1.0 and _gpu_lisse * pow((echelle_image + 0.05) / echelle_image, 2.0) < GPU_MARGE:
		# remonte seulement si l'image un peu plus grande tiendrait encore large dans le temps
		echelle_image = minf(1.0, echelle_image + 0.05)
	if echelle_image != avant:
		get_viewport().scaling_3d_scale = echelle_image


func _process(delta: float) -> void:
	_mesurer(delta)
	_regler_resolution(delta)
	_lire_boutons()
	if son != null:
		son.regler(en_pause or ecran_touches != null, acc_effectif, vue_interieure)
	# (près de la lune, les axes de la physique tournent avec elle : on dessine dans ceux de la maison)
	pilote.basis = reperes.base_affichage() * Basis(vaisseau.orientation)
	_suivre_g(delta)
	_bouger_tete(delta)
	_animer_modele()
	_animer_lueurs()
	_animer_amortisseurs(delta)
	_mettre_a_jour_cockpit(delta)
	if avec_lumiere:
		_placer_lumiere(delta)
	else:
		_placer_planete()
	if hud != null and hud.visible:   # caché en vue cockpit : inutile de recomposer ses 20 lignes à chaque image
		_mettre_a_jour_hud()
	_mettre_a_jour_message()
	_compteur_t += delta
	if compteur and _compteur_t >= 0.25:
		_compteur_t = 0.0
		compteur.text = "%d images/s   image 3D à %d %%" % [roundi(Engine.get_frames_per_second()), roundi(echelle_image * 100.0)]
	_placer_marqueurs()


## La tête du pilote, sur son cou (ressort amorti), recule quand le vaisseau accélère : on sent les G.
## Elle ne touche qu'à la caméra, jamais à la physique du vaisseau.
func _suivre_g(delta: float) -> void:
	var cible := Vector3.ZERO
	if tete_g and not en_pause:
		cible = cible_tete_g(pilote.basis.inverse() * vaisseau.acceleration_ressentie)
	var r := pas_tete_g(tete_g_pos, tete_g_vit, cible, delta)
	tete_g_pos = r[0]
	tete_g_vit = r[1]


## Où la tête irait, à l'équilibre, sous l'accélération ressentie a_local (m/s², repère du vaisseau) :
## à l'opposé de l'accélération (on est poussé dans le siège), 1,5 cm par g, au plus 8 cm.
static func cible_tete_g(a_local: Vector3) -> Vector3:
	return (-a_local / VaisseauPhysique.G0 * TETE_G_METRES_PAR_G).limit_length(TETE_G_MAX)


## Un pas du cou (ressort amorti) : renvoie [position, vitesse].
static func pas_tete_g(pos: Vector3, vit: Vector3, cible: Vector3, delta: float) -> Array:
	var w := TAU * TETE_G_FREQUENCE
	var dt := minf(delta, 0.05)
	vit += (w * w * (cible - pos) - 2.0 * TETE_G_AMORTI * w * vit) * dt
	pos += vit * dt
	return [pos.limit_length(TETE_G_MAX), vit]


## Étape 8 : l'affichage est centré sur l'œil (la caméra reste à l'origine, comme dans le labo) ; la
## position de l'œil par rapport à la planète est calculée en 64 bits (centre du vaisseau + œil).
func _placer_lumiere(delta: float) -> void:
	var oeil_local := camera.position
	var decalage := pilote.basis * oeil_local
	pilote.position = -decalage
	var decalage_physique := Basis(vaisseau.orientation) * oeil_local   # axes de la physique (lune : les siens)
	var oeil64 := PackedFloat64Array([vaisseau.px + float(decalage_physique.x), vaisseau.py + float(decalage_physique.y),
		vaisseau.pz + float(decalage_physique.z)])
	# Einstein A3 : la lumière compte depuis la maison (la planète, sa lune, le Soleil y sont). Loin
	# d'elle, l'œil y est placé à quelques mètres près : seules des étoiles lointaines en dépendent.
	var oeil_sys := oeil64.duplicate()
	var ev: Array = reperes.vers_maison(reperes.courant, vaisseau.temps_univers, oeil64)
	var vm := reperes.vitesse_maison(vaisseau)
	oeil64 = ev[1]
	reperes.regler_lumiere(lumiere, oeil64, ev[0])
	var gaz_moteurs := 0.0
	for m in vaisseau.moteurs:
		gaz_moteurs += float(m["actuel"])
	gaz_moteurs /= maxf(vaisseau.moteurs.size(), 1)
	var t0 := Time.get_ticks_usec()
	lumiere.angle_planete = reperes.angle_planete_maison(vaisseau, ev[0])
	lumiere.temps_astres = ev[0]
	lumiere.mettre_a_jour(delta, oeil64, Vector3(vm[0], vm[1], vm[2]), pilote.basis,
		oeil_local, gaz_moteurs)
	# Atmosphère : la coque chauffée par l'air brille (le côté qui fait face à l'air)
	if vaisseau.atmosphere != null and vaisseau.vitesse_air > 1.0:
		_vent_chaleur = Vector3(vaisseau.vx, vaisseau.vy, vaisseau.vz) - vaisseau.vitesse_sol(vaisseau.px, vaisseau.py, vaisseau.pz)
	lumiere.regler_chaleur(vaisseau.temperature_nez, _vent_chaleur)
	# Einstein B : lumière courbée près d'un trou noir, et la toile de l'espace
	reperes.regler_lentille(lumiere, oeil_sys)
	trou_de_ver.regler_lumiere(lumiere, oeil_sys, vaisseau)
	if toile != null and toile.visible:
		var l := Vector3(vaisseau.py * vaisseau.vz - vaisseau.pz * vaisseau.vy, vaisseau.pz * vaisseau.vx - vaisseau.px * vaisseau.vz,
			vaisseau.px * vaisseau.vy - vaisseau.py * vaisseau.vx)
		if l.length() < 1e-6 * vaisseau.distance_centre() * maxf(vaisseau.vitesse(), 1e-3) or l.length() == 0.0:
			l = Vector3.UP
		var ba := reperes.base_affichage()   # axes de la physique → axes du dessin (près de la lune)
		var pv := ba * Vector3(vaisseau.px, vaisseau.py, vaisseau.pz)
		toile.mettre_a_jour(ba * Vector3(-oeil_sys[0], -oeil_sys[1], -oeil_sys[2]), PackedFloat64Array([pv.x, pv.y, pv.z]),
			vaisseau.gm, _rayon_astre_principal(), ba * l)
	temps_lumiere_ms = lerpf(temps_lumiere_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.05)
## Rayon de l'astre au centre du système (0 pour un trou noir : toute sa masse est en un point).
func _rayon_astre_principal() -> float:
	if reperes.a_la_maison():
		return vaisseau.rayon_planete
	var e0: Dictionary = reperes.systemes[reperes.courant]["etoiles"][0]
	return 0.0 if e0.get("trou_noir", false) else float(e0["rayon"])


## Les pièces du cockpit suivent les commandes, et les écrans affichent l'état du vol.
func _mettre_a_jour_cockpit(delta: float) -> void:
	pieces_cockpit.mettre_a_jour({
		"gaz": gaz, "tangage": ordres_pilote.x, "lacet": ordres_pilote.y, "roulis": ordres_pilote.z,
		"train": vaisseau.train_consigne, "ailes": vaisseau.ailes_consigne, "stabilisateur": stabilisateur,
	}, delta)
	ecrans.mettre_a_jour(_infos_cockpit(), delta, vue_interieure)


func _infos_cockpit() -> Dictionary:
	var vers_vaisseau := Basis(vaisseau.orientation).inverse()
	var astres := []
	# planète : position de son centre vue depuis le vaisseau, distance jusqu'à la surface
	var p := vers_vaisseau * Vector3(-vaisseau.px, -vaisseau.py, -vaisseau.pz)
	if reperes.sur_lune:
		astres.append({"nom": "Lune", "position": p, "distance": vaisseau.altitude(), "principal": true})
	elif reperes.a_la_maison():
		astres.append({"nom": "Planète", "position": p, "distance": vaisseau.altitude(), "principal": true})
	else:
		var e0: Dictionary = reperes.systemes[reperes.courant]["etoiles"][0]
		astres.append({"nom": String(e0["nom"]), "position": p, "distance": vaisseau.distance_centre() - float(e0["rayon"]), "principal": true})
	for a in vaisseau.autres_astres:
		var q := vers_vaisseau * Vector3(float(a["x"]) - vaisseau.px, float(a["y"]) - vaisseau.py, float(a["z"]) - vaisseau.pz)
		astres.append({"nom": String(a["nom"]), "position": q, "distance": q.length()})
	var rcs_actifs := 0
	for t in vaisseau.rcs:
		if float(t["actuel"]) > 0.01:
			rcs_actifs += 1
	var moteurs := []
	for m in vaisseau.moteurs:
		moteurs.append(float(m["actuel"]))
	return {
		"vitesse": vaisseau.vitesse(), "v_horiz": vaisseau.vitesse_horizontale(), "v_vert": vaisseau.vitesse_verticale(),
		"altitude": vaisseau.altitude(), "g": vaisseau.acceleration_ressentie.length() / VaisseauPhysique.G0,
		"rotation": vaisseau.omega * (180.0 / PI), "gaz": gaz, "moteurs": moteurs, "rcs_actifs": rcs_actifs,
		"ailes": vaisseau.ailes, "ailes_txt": _etat(vaisseau.ailes, vaisseau.ailes_consigne, "ouvertes", "repliées"),
		"train": vaisseau.train, "train_txt": _etat(vaisseau.train, vaisseau.train_consigne, "sorti", "rentré"),
		"vertical": vaisseau.vertical, "vertical_txt": _etat(vaisseau.vertical, vaisseau.vertical_consigne, "ACTIF", "arrêt"),
		"stabilisateur": stabilisateur, "temps": acc_effectif, "pause": en_pause, "vue_interieure": vue_interieure,
		"orbite": vaisseau.orbite(), "au_sol": vaisseau.au_sol, "ecrase": vaisseau.ecrase, "astres": astres,
		"cabine": _infos_cabine(),
	}


## Étape 8 : ce que l'écran SYSTÈME montre de la cabine (vide : pas de cabine).
func _infos_cabine() -> Dictionary:
	var vie = vaisseau.vie
	if vie == null:
		return {}
	return {"pression": vie.pression_cabine(), "consigne": vie.consigne, "ppo2": vie.ppo2_cabine(), "fuite": vie.fuite(),
		"trou": vie.surface_trous_cabine(), "vanne": vie.vanne_ouverte, "conscience": vie.temps_conscience,
		"reserve": (vie.reserve_o2 + vie.reserve_n2) / maxf(float(vie.analyse["survie"]["oxygene_kg"]) + float(vie.analyse["survie"]["azote_kg"]), 1e-9)
			if vie.a_survie else 0.0}


func _placer_planete() -> void:
	if not reperes.a_la_maison():   # la planète est restée dans son système d'étoile
		planete.visible = false
		calotte.visible = false
		return
	var px: float = vaisseau.px
	var py: float = vaisseau.py
	var pz: float = vaisseau.pz
	var d := sqrt(px * px + py * py + pz * pz)
	var s := minf(1.0, DISTANCE_RENDU_MAX / d)   # réduction : même taille apparente, plus près
	planete.position = Vector3(-px * s, -py * s, -pz * s)
	planete.scale = Vector3.ONE * (RAYON_PLANETE * s)
	camera.far = maxf(1000.0, (d + RAYON_PLANETE) * s * 1.05)

	var alt := d - RAYON_PLANETE
	if alt < ALTITUDE_CALOTTE:
		var dir := Vector3(px / d, py / d, pz / d)
		var angle := clampf(acos(clampf(RAYON_PLANETE / d, -1.0, 1.0)) * 1.3, 0.003, 0.6)
		var a_refaire := calotte.mesh == null
		if not a_refaire:
			a_refaire = dir.angle_to(calotte_dir) > calotte_angle * 0.15 or angle / calotte_angle > 1.4 or angle / calotte_angle < 0.7
		if a_refaire:
			_construire_calotte(dir, angle)
		calotte.visible = true
		planete.visible = false
		calotte.position = Vector3(
			(calotte_dir.x * RAYON_PLANETE - px) * s,
			(calotte_dir.y * RAYON_PLANETE - py) * s,
			(calotte_dir.z * RAYON_PLANETE - pz) * s)
		calotte.scale = Vector3.ONE * s
	else:
		calotte.visible = false
		planete.visible = true


## Morceau de sphère très détaillé sous le vaisseau (la sphère entière serait trop grossière près du sol).
func _construire_calotte(c: Vector3, angle: float) -> void:
	var n := 64
	var u := c.cross(Vector3.UP)
	if u.length() < 0.1:
		u = c.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := c.cross(u)
	var t := tan(angle)
	var sommets := PackedVector3Array()
	var normales := PackedVector3Array()
	var indices := PackedInt32Array()
	for j in n + 1:
		for i in n + 1:
			var a := (float(i) / n * 2.0 - 1.0) * t
			var b := (float(j) / n * 2.0 - 1.0) * t
			var d := (c + u * a + v * b).normalized()
			sommets.append((d - c) * RAYON_PLANETE)
			normales.append(d)
	for j in n:
		for i in n:
			var k := j * (n + 1) + i
			# sens des triangles : face avant vers l'extérieur (vers le pilote). Dans l'autre sens,
			# Godot voyait l'envers, retournait la normale et la calotte restait noire (invisible).
			indices.append_array([k, k + n + 1, k + 1, k + 1, k + n + 1, k + n + 2])
	var tableaux := []
	tableaux.resize(Mesh.ARRAY_MAX)
	tableaux[Mesh.ARRAY_VERTEX] = sommets
	tableaux[Mesh.ARRAY_NORMAL] = normales
	tableaux[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tableaux)
	calotte.mesh = m
	calotte_dir = c
	calotte_angle = angle


## Nombre avec des espaces entre les milliers : 12 345,6.
static func _nombre(x: float, decimales := 0) -> String:
	var t := String.num(absf(x), decimales) if decimales > 0 else str(int(round(absf(x))))
	var entier := t.get_slice(".", 0)
	var reste := t.get_slice(".", 1) if t.contains(".") else ""
	if decimales > 0 and reste == "":
		reste = "0".repeat(decimales)
	var groupes := ""
	while entier.length() > 3:
		groupes = " " + entier.right(3) + groupes
		entier = entier.left(entier.length() - 3)
	return ("-" if x < 0.0 else "") + entier + groupes + ("," + reste if reste != "" else "")


static func _vitesse_txt(v: float, signe := false) -> String:
	var s := "+" if signe and v >= 0.0 else ""
	if absf(v) < 10000.0:
		return s + _nombre(v, 1) + " m/s"
	return s + _nombre(v / 1000.0, 0) + " km/s"


## Fraction de la vitesse de la lumière : assez de chiffres pour voir s'approcher de 1 sans l'atteindre.
static func _fraction_c(b: float) -> String:
	if b < 0.999:
		return String.num(b, 6 if b < 0.001 else 4).replace(".", ",")
	# 0,999 999… : on compte les 9
	var d := clampi(int(ceil(-log(1.0 - b) / log(10.0))) + 2, 4, 15)
	return String.num(b, d).replace(".", ",")


static func _gamma_txt(g: float) -> String:
	if g < 1.001:
		return String.num(g, 9).replace(".", ",")
	if g < 100.0:
		return String.num(g, 3).replace(".", ",")
	return _nombre(g)


static func _force_txt(f: float) -> String:
	if f < 1e6:
		return _nombre(f / 1000.0) + " kN"
	if f < 1e9:
		return _nombre(f / 1e6, 1) + " MN"
	return _nombre(f / 1e9, 1) + " GN"


## Durée lisible : « 2 ans 41 j 03:12:45 ».
static func _duree(s: float) -> String:
	var an := 365.25 * 86400.0
	var t := ""
	var reste := maxf(s, 0.0)
	if reste >= an:
		var n := int(floor(reste / an))
		t += "%d an%s " % [n, "s" if n > 1 else ""]
		reste -= n * an
	if reste >= 86400.0 or t != "":
		var j := int(floor(reste / 86400.0))
		t += "%d j " % j
		reste -= j * 86400.0
	var hh := int(floor(reste / 3600.0))
	var mm := int(floor(fmod(reste, 3600.0) / 60.0))
	var ss := fmod(reste, 60.0)
	return t + "%02d:%02d:%04.1f" % [hh, mm, ss]


## Petit écart de temps : en microsecondes, secondes… ou comme _duree.
static func _duree_courte(s: float) -> String:
	var a := absf(s)
	if a < 1e-6:
		return "%.1f ns" % (s * 1e9)
	if a < 1e-3:
		return "%.1f µs" % (s * 1e6)
	if a < 1.0:
		return "%.1f ms" % (s * 1e3)
	if a < 60.0:
		return "%.2f s" % s
	return _duree(s)


func _distance(m: float) -> String:
	if absf(m) >= 10000.0:
		return "%.1f km" % (m / 1000.0)
	return "%.0f m" % m


func _etat(valeur: float, consigne: float, plein: String, vide: String) -> String:
	if valeur == consigne:
		return plein if valeur >= 1.0 else vide
	return "en mouvement (%d %%)" % int(round(valeur * 100.0))


## « HG », « C », « G »… pour les moteurs du chasseur ; le nom de la pièce pour un moteur posé dans l'atelier.
static func _nom_court_moteur(mo: Dictionary) -> String:
	var noms := {"moteur_haut_gauche": "HG", "moteur_haut_droit": "HD", "moteur_bas_gauche": "BG", "moteur_bas_droit": "BD",
		"moteur_central": "C", "moteur_levage_gauche": "G ", "moteur_levage_droit": "D "}
	var id := String(mo["id"])
	if noms.has(id):
		return String(noms[id])
	# moteur posé dans l'atelier : son nom, raccourci (« Moteur ionique 1 droite » → « ion.1 D »)
	var nom := String(mo.get("nom_ajout", id.get_slice("/", 0)))
	for r in [["Moteur ionique ", "ion."], ["Moteur de levage ", "lev."], [" droite", " D"], [" gauche", " G"]]:
		nom = nom.replace(r[0], r[1])
	return nom


func _barre(x: float) -> String:
	var n := int(round(clampf(x, 0.0, 1.0) * 10.0))
	return "#".repeat(n) + ".".repeat(10 - n)


func _mettre_a_jour_hud() -> void:
	var o: Dictionary = vaisseau.orbite()
	var orbite_txt := ""
	if vaisseau.au_sol:
		orbite_txt = "posé au sol"
	elif o["apo"] == INF:
		orbite_txt = "trajectoire d'évasion (périapside %s)" % _distance(o["peri"])
	else:
		orbite_txt = "périapside %s   apoapside %s" % [_distance(o["peri"]), _distance(o["apo"])]
	var w: Vector3 = vaisseau.omega * (180.0 / PI)
	var m: Array = vaisseau.moteurs
	var lignes := PackedStringArray()
	lignes.append("IMAGES/S      %d   (%.1f ms par image)   image 3D à %d %%" % [roundi(Engine.get_frames_per_second()), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), roundi(echelle_image * 100.0)])
	lignes.append("VITESSE       %s   (verticale %s   horizontale %s)   par rapport au sol %s (horizontale %s)" % [_vitesse_txt(vaisseau.vitesse()), _vitesse_txt(vaisseau.vitesse_verticale(), true), _vitesse_txt(vaisseau.vitesse_horizontale()), _vitesse_txt(vaisseau.vitesse_par_rapport_au_sol().length()), _vitesse_txt(vaisseau.vitesse_horizontale_sol())])
	lignes.append("RELATIVITÉ    %s c   γ = %s   rapidité %.4f" % [_fraction_c(vaisseau.beta()), _gamma_txt(vaisseau.gamma()), vaisseau.rapidite()])
	lignes.append("HORLOGES      pilote %s   univers %s   (le pilote a %s de moins)" % [_duree(vaisseau.temps_pilote), _duree(vaisseau.temps_univers), _duree_courte(vaisseau.temps_univers - vaisseau.temps_pilote)])
	lignes.append(_ligne_repere())
	lignes.append(_ligne_einstein())
	lignes.append("ALTITUDE      %s" % _distance(vaisseau.altitude()))
	lignes.append("ORBITE        %s" % orbite_txt)
	lignes.append(_ligne_air())
	lignes.append(_ligne_cabine())
	lignes.append("RESSENTI      %.2f g" % (vaisseau.acceleration_ressentie.length() / VaisseauPhysique.G0))
	lignes.append("GAZ           %s %3d %%" % [_barre(gaz), int(round(gaz * 100.0))])
	# moteurs : ceux du plan, quels qu'ils soient (l'atelier peut en enlever ou en ajouter)
	var principaux := PackedStringArray()
	var levage := PackedStringArray()
	for mo in m:
		var b := "%s %s" % [_nom_court_moteur(mo), _barre(mo["actuel"])]
		if String(mo.get("role", "")) == "levage":
			levage.append(b)
		else:
			principaux.append(b)
	for k in range(0, maxi(principaux.size(), 1), 3):
		lignes.append(("MOTEURS       " if k == 0 else "              ") + ("  ".join(principaux.slice(k, k + 3)) if principaux.size() > 0 else "aucun"))
	lignes.append("LEVAGE        " + ("  ".join(levage) if levage.size() > 0 else "aucun"))
	lignes.append("ROTATION      tangage %+.1f°/s   lacet %+.1f°/s   roulis %+.1f°/s" % [w.x, w.y, w.z])
	lignes.append("AILES         %s      TRAIN %s      VUE %s" % [_etat(vaisseau.ailes, vaisseau.ailes_consigne, "ouvertes", "repliées"),
		_etat(vaisseau.train, vaisseau.train_consigne, "sorti", "rentré"), "cockpit" if vue_interieure else "extérieure"])
	lignes.append("VOL VERTICAL  %s   (tuyère %.0f°)" % [_etat(vaisseau.vertical, vaisseau.vertical_consigne, "activé", "désactivé"), vaisseau.angle_tuyere()])
	lignes.append("PUISSANCE     x%s   poussée max %s (%s g)%s" % [_nombre(vaisseau.facteur_poussee), _force_txt(vaisseau.poussee_avant_max), _nombre(vaisseau.poussee_avant_max / vaisseau.masse / VaisseauPhysique.G0, 1), "   (vrais moteurs)" if vaisseau.facteur_poussee == 1.0 else "   (moteurs imaginaires)"])
	lignes.append("PILOTE AUTO   %s" % ordinateur.nom_mode())
	var temps_txt := "x%s" % _nombre(acc_temps)
	if acc_effectif < acc_temps:
		var permis := temps_permis(acc_temps)
		if acc_effectif < permis:
			temps_txt += " (pilote auto : x%s)" % _nombre(acc_effectif)
		elif _limite_sol and acc_effectif == TEMPS_MAX_SOL:
			temps_txt += " (x%s : trop près du sol pour aller plus vite)" % _nombre(acc_effectif)
		elif _limite_air:
			temps_txt += " (x%s : l'air est trop épais pour aller plus vite)" % _nombre(acc_effectif)
		else:
			temps_txt += " (x%s : %s trop proche)" % [_nombre(acc_effectif), vaisseau.astre_limitant]
	lignes.append("STABILISATEUR %s      TEMPS %s%s" % ["activé" if stabilisateur else "désactivé", temps_txt, "   (PAUSE)" if en_pause else ""])
	if avec_lumiere:
		lignes.append(lumiere.infos())
		lignes.append("TÊTE          %s (déplacement %.1f cm)      calcul de la lumière %.1f ms par image" % ["bouge avec les G" if tete_g else "fixe", tete_g_pos.length() * 100.0, temps_lumiere_ms])
	hud.text = "\n".join(lignes)


func _mettre_a_jour_message() -> void:
	var cabine := _alarme_cabine()
	if vaisseau.avale:
		message.text = "TOMBÉ DANS LE TROU NOIR\n(l'horizon est franchi : rien n'en ressort, pas même la lumière)\nR pour recommencer"
	elif vaisseau.ecrase:
		message.text = "ÉCRASÉ (impact à %.0f m/s)\nR pour recommencer" % vaisseau.vitesse_impact
	elif vaisseau.au_sol:
		message.text = ("Posé (impact à %.1f m/s)" % vaisseau.vitesse_impact if vaisseau.vitesse_impact >= 0.05 else "Posé") \
			+ ("\n" + cabine if cabine != "" else "")
	else:
		message.text = cabine


## Atelier, étape 8 : la cabine (scripts/physique/vie_a_bord.gd). Une paroi qui cède reste écrite 8 s.
var _alerte_cabine := ""
var _alerte_cabine_fin := 0


func _alarme_cabine() -> String:
	var vie = vaisseau.vie
	if vie == null:
		return ""
	for e in vie.evenements:
		_alerte_cabine = String(e)
		_alerte_cabine_fin = Time.get_ticks_msec() + 8000
	vie.evenements.clear()
	var lignes := PackedStringArray()
	if _alerte_cabine != "" and Time.get_ticks_msec() < _alerte_cabine_fin:
		lignes.append(_alerte_cabine)
	var p: float = vie.pression_cabine()
	if vie.inconscient():
		lignes.append("PILOTE INCONSCIENT : PAS ASSEZ D'OXYGÈNE")
	elif vie.temps_conscience < INF:
		lignes.append("HYPOXIE : perte de connaissance dans %d s" % ceili(vie.temps_conscience))
	if p < VieABord.LIMITE_ARMSTRONG:
		lignes.append("CABINE VIDE (%s) : l'eau du corps bout" % _pression_txt(p))
	elif vie.fuite():
		lignes.append("FUITE DE LA CABINE : %s ouverts, cabine à %s" % [_surface_trou(vie.surface_trous_cabine()), _pression_txt(p)])
	if vie.vanne_ouverte:
		lignes.append("VANNE DE LA CABINE OUVERTE (%s pour la fermer)" % commandes.resume("vanne_cabine"))
	return "\n".join(lignes)


static func _surface_trou(s: float) -> String:
	return ("%s cm²" % _nombre(s * 1.0e4, 1 if s < 1.0e-3 else 0)) if s < 0.1 else ("%s m²" % _nombre(s, 2))


## La ligne CABINE du tableau : pression, oxygène, réserves, fuite, vanne, pilote.
func _ligne_cabine() -> String:
	var vie = vaisseau.vie
	if vie == null:
		return "CABINE        aucune (pas de cabine sous pression)"
	var txt := "CABINE        %s (consigne %s)   oxygène %s   réserves %s kg d'oxygène + %s kg d'azote%s" % [_pression_txt(vie.pression_cabine()),
		_pression_txt(vie.consigne), _pression_txt(vie.ppo2_cabine()), _nombre(vie.reserve_o2, 1), _nombre(vie.reserve_n2, 1),
		("   recycleur en marche" if vie.recycleur else "   recycleur arrêté") if vie.a_survie else "   pas de système de survie"]
	var suite := PackedStringArray()
	if vie.fuite():
		suite.append("FUITE %s (%s kg/s)" % [_surface_trou(vie.surface_trous_cabine()), _petit(vie.debit_fuite)])
	if vie.vanne_ouverte:
		suite.append("VANNE OUVERTE")
	if vie.autonomie() < INF:
		suite.append("réserves vides dans %s" % _duree_courte(vie.autonomie()))
	if vie.temps_conscience < INF:
		suite.append("pilote : conscience %d s" % ceili(vie.temps_conscience))
	if vie.force.length() > 0.01:
		suite.append("l'air qui s'échappe pousse le vaisseau de %s" % _force_txt(vie.force.length()))
	if not suite.is_empty():
		txt += "\n              " + "   ".join(suite)
	return txt


## Einstein A3 : dans quel système d'étoile on est, l'étoile la plus proche, l'heure de la maison.
func _ligne_repere() -> String:
	var e: Array = reperes.etoile_proche(vaisseau)
	var t_m := reperes.heure_maison(vaisseau)
	var txt := "REPÈRE        système %s   %s à %s" % [reperes.nom_courant(), e[0], _distance_etoile(float(e[1]) - float(e[2]))]
	if not reperes.a_la_maison():
		txt += "   heure de la maison %s   (vitesse vue du Soleil %s)" % [_duree(t_m), _vitesse_txt(_norme(reperes.vitesse_maison(vaisseau)))]
	return txt


## Einstein B : de combien le temps ralentit ici (gravité seule), la marée, la toile, le trou noir.
func _ligne_einstein() -> String:
	var n: float = vaisseau.rythme_gravite()
	var ralenti := 1.0 - n
	var txt := "EINSTEIN      temps ici : "
	if ralenti < 0.01:
		txt += "%s par jour de moins que loin de tout" % _duree_courte(ralenti * 86400.0)
	else:
		txt += "%s fois plus lent que loin de tout" % _nombre(1.0 / maxf(n, 1e-9), 3 if n > 0.01 else 0)
	txt += "   marée %s m/s² par mètre" % _petit(vaisseau.maree())
	if toile != null and toile.visible:
		txt += "   toile : courbure %s" % ("à sa vraie grandeur" if toile.exageration <= 1.0 else "exagérée x%s" % _nombre(toile.exageration))
	var d_trou := trou_de_ver.distance_gorge(vaisseau)
	if d_trou < 1.0e9:
		txt += "\n              trou de ver vers %s : gorge (rayon %s) à %s%s, %d passage%s" % [trou_de_ver.nom_en_face(),
			_distance_courte(TrouVer.A), _distance_courte(d_trou), ("   lumière à travers (table %.1f ms)" % trou_de_ver.table_ms) if trou_de_ver.lumiere_active else "",
			trou_de_ver.traversees, "s" if trou_de_ver.traversees > 1 else ""]
	elif lumiere != null and lumiere.lentille_active:
		txt += "\n              trou noir : ombre de %s° vue d'ici (lumière courbée, table %.1f ms)" % [_petit(rad_to_deg(lumiere.lentille.ombre)), lumiere.lentille_ms]
	return txt


static func _petit(x: float) -> String:
	if x == 0.0:
		return "0"
	if absf(x) >= 0.01 and absf(x) < 100000.0:
		return ("%.3f" % x) if absf(x) < 10.0 else (("%.1f" % x) if absf(x) < 1000.0 else ("%.0f" % x))
	var e := floori(log(absf(x)) / log(10.0))
	return "%.2f·10^%d" % [x / pow(10.0, e), e]


static func _norme(p: PackedFloat64Array) -> float:
	return sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2])


## Distance entre étoiles : en UA, puis en années-lumière.
func _distance_etoile(d: float) -> String:
	if d < 1.0e10:
		return _distance(d)
	if d < 0.05 * Reperes.ANNEE_LUMIERE:
		return "%.3f UA" % (d / Reperes.UA)
	return "%.3f années-lumière" % (d / Reperes.ANNEE_LUMIERE)


## Marqueurs de direction du mouvement : (o) = où l'on va, (x) = d'où l'on vient.
func _placer_marqueurs() -> void:
	var v := Vector3(vaisseau.vx, vaisseau.vy, vaisseau.vz)
	if vaisseau.altitude() < 20000.0:
		v = vaisseau.vitesse_par_rapport_au_sol()   # près du sol, c'est le mouvement par rapport au sol qui compte
	if v.length() < 0.5:
		marqueur_avant.visible = false
		marqueur_arriere.visible = false
		return
	v = v.normalized()
	_placer_un(marqueur_avant, v)
	_placer_un(marqueur_arriere, -v)


func _placer_un(l: Label, dir: Vector3) -> void:
	var cible := camera.global_position + dir * 100.0
	if camera.is_position_behind(cible):
		l.visible = false
		return
	l.visible = true
	l.position = camera.unproject_position(cible) - l.size * 0.5


static func _distance_courte(d: float) -> String:
	if d < 1000.0:
		return "%d m" % roundi(d)
	if d < 1.0e7:
		return "%.1f km" % (d / 1000.0)
	return "%d km" % roundi(d / 1000.0)
