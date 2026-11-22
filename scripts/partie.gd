extends RefCounted
## Ce qui passe d'un écran à l'autre : l'écran d'accueil, l'ATELIER et le JEU sont trois scènes séparées.
## Une seule est en mémoire à la fois : le jeu (planète, lumière, son) n'est chargé qu'au clic sur
## « Lancer », et il est entièrement libéré quand on revient à l'atelier (F3). Le PC garde ainsi sa mémoire
## pour ce qu'on fait.
##
## Ce qu'il faut transmettre (quel plan de vaisseau, où commence le vol) est gardé dans les métadonnées du
## moteur (Engine), qui restent quand on change de scène. Le dernier vaisseau ouvert est aussi écrit dans
## un petit fichier, pour que « Jouer » le reprenne à la partie suivante.

const SCENE_ACCUEIL := "res://scenes/accueil.tscn"
const SCENE_ATELIER := "res://scenes/atelier.tscn"
const SCENE_JEU := "res://scenes/jeu.tscn"
const FICHIER := "user://partie.cfg"
const PLAN_PAR_DEFAUT := "res://vaisseaux/chasseur_v27.plan.json"
const DOSSIERS_PLANS := ["res://vaisseaux/", "user://vaisseaux/"]

## Lieux de départ du vol.
const DEPART_HANGAR := "hangar"   # posé au sol devant le hangar (choix de Gwenaël, Q19)
const DEPART_ORBITE := "orbite"   # en orbite à 250 km (ancien départ, et mode --mesure)

const CLE := "partie"


static func _etat() -> Dictionary:
	if not Engine.has_meta(CLE):
		var d := {"plan": PLAN_PAR_DEFAUT, "depart": "", "plan_lu": false}
		Engine.set_meta(CLE, d)
	return Engine.get_meta(CLE)


## Plan du vaisseau choisi (chemin du fichier). Au premier appel : le dernier vaisseau ouvert.
static func plan_choisi() -> String:
	var e := _etat()
	if not bool(e["plan_lu"]):
		e["plan_lu"] = true
		var f := ConfigFile.new()
		if f.load(FICHIER) == OK:
			var c := String(f.get_value("partie", "dernier_plan", PLAN_PAR_DEFAUT))
			if FileAccess.file_exists(c):
				e["plan"] = c
	return String(e["plan"])


static func choisir_plan(chemin: String) -> void:
	var e := _etat()
	e["plan"] = chemin
	e["plan_lu"] = true
	var f := ConfigFile.new()
	f.load(FICHIER)
	f.set_value("partie", "dernier_plan", chemin)
	f.save(FICHIER)


## Lieu de départ du prochain vol : "" si le jeu a été lancé directement (sans l'accueil ni l'atelier).
static func depart() -> String:
	return String(_etat()["depart"])


static func choisir_depart(lieu: String) -> void:
	_etat()["depart"] = lieu


static func lancer_jeu(arbre: SceneTree, lieu := DEPART_HANGAR) -> void:
	choisir_depart(lieu)
	arbre.change_scene_to_file(SCENE_JEU)


static func aller_atelier(arbre: SceneTree) -> void:
	arbre.change_scene_to_file(SCENE_ATELIER)


static func aller_accueil(arbre: SceneTree) -> void:
	arbre.change_scene_to_file(SCENE_ACCUEIL)


## Les plans de vaisseau qu'on peut ouvrir : [{chemin, nom, pieces}] (ceux du jeu, puis les tiens).
static func plans_disponibles() -> Array:
	var liste := []
	for dossier in DOSSIERS_PLANS:
		var d := DirAccess.open(dossier)
		if d == null:
			continue
		var fichiers := Array(d.get_files())
		fichiers.sort()
		for nom in fichiers:
			if not String(nom).ends_with(".plan.json"):
				continue
			var chemin: String = dossier + nom
			var j = JSON.parse_string(FileAccess.get_file_as_string(chemin))
			if j is Dictionary and String(j.get("format", "")) == "plan-vaisseau":
				liste.append({"chemin": chemin, "nom": String(j.get("nom", nom)), "description": String(j.get("description", ""))})
	return liste
