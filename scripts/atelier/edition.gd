extends RefCounted
## Atelier, étape 3 : l'ÉDITION du plan d'un vaisseau. Tout ce qu'on fait dans l'atelier passe par ici :
## poser une pièce toute faite, la déplacer, la régler, la supprimer (et enlever des pièces ou des modules
## du chasseur), annuler et refaire, renommer, enregistrer.
##
## On travaille sur une copie du plan (donnees, le texte du fichier) ; après chaque changement, le plan est
## relu (plan()) et l'atelier refait la physique, le dessin et le tableau ingénieur avec le même code que le
## jeu. Rien n'est écrit sur le disque avant « Enregistrer » (ou la sauvegarde automatique, ou « Lancer »).
##
## Symétrie : une pièce posée en symétrie a une jumelle, de l'autre côté du plan gauche-droite du vaisseau
## (x = 0). Les deux sont liées (« symetrique ») : déplacer, régler ou supprimer l'une fait pareil pour l'autre.
## Positions et orientations : repère du plan, dans sa pose de référence (ailes ouvertes, train rentré).

signal change

const Plan = preload("res://scripts/atelier/plan.gd")
const Catalogue = preload("res://scripts/atelier/catalogue.gd")
const Pieces = preload("res://scripts/atelier/pieces_toutes_faites.gd")

const DOSSIER := "user://vaisseaux/"
const HISTOIRE_MAX := 80                          # nombre de retours en arrière possibles
const MIROIR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))   # gauche ↔ droite (x → −x)
const SUR_L_AXE := 0.05                           # m : une pièce posée à moins de 5 cm du milieu n'a pas de jumelle
## Modules qu'on ne peut pas enlever : le jeu en a besoin (le pilote est dans le cockpit).
const MODULES_INDISPENSABLES := ["cockpit"]

var donnees := {}
var chemin := ""          # fichier où le vaisseau est enregistré (user://vaisseaux/…) ; "" = pas encore
var source := ""          # fichier d'où il a été ouvert
var modifie := false      # changé depuis le dernier enregistrement
var _passe: Array = []    # états d'avant (pour annuler)
var _futur: Array = []    # états annulés (pour refaire)
var _plan = null          # le plan relu (gardé jusqu'au prochain changement)
var _nom_source := ""     # nom du vaisseau ouvert (celui du jeu ne s'écrase pas : la copie s'appelle « … modifié »)


func _init(d: Dictionary = {}, chemin_source := "") -> void:
	donnees = d.duplicate(true)
	source = chemin_source
	chemin = chemin_source if chemin_source.begins_with(DOSSIER) else ""
	if not donnees.has("pieces"):
		donnees["pieces"] = []
	_nom_source = nom()
	# les pièces toutes faites sont refabriquées à partir de leurs réglages (si le catalogue a changé)
	for e in donnees["pieces"]:
		if e is Dictionary and e.has("modele") and Pieces.existe(String(e["modele"])):
			e["reglages"] = Pieces.reglages_complets(String(e["modele"]), e.get("reglages", {}))
			e["pieces"] = Pieces.pieces(String(e["modele"]), e["reglages"], String(e["id"]))


## Le plan relu à partir du texte actuel (scripts/atelier/plan.gd).
func plan():
	if _plan == null:
		_plan = Plan.new()
		_plan.lire_dictionnaire(donnees.duplicate(true))
		_plan.chemin = chemin if chemin != "" else source
	return _plan


func nom() -> String:
	return String(donnees.get("nom", "Vaisseau"))


# =====================================================================
# HISTOIRE : annuler / refaire
# =====================================================================
func _avant() -> void:
	_passe.append(donnees.duplicate(true))
	if _passe.size() > HISTOIRE_MAX:
		_passe.pop_front()
	_futur.clear()


func _apres() -> void:
	# le vaisseau du jeu (res://) ne peut pas être écrit : ses changements deviennent un vaisseau à toi
	if chemin == "" and source.begins_with("res://") and nom() == _nom_source:
		donnees["nom"] = _nom_source + " modifié"
	modifie = true
	_plan = null
	change.emit()


func peut_annuler() -> bool:
	return not _passe.is_empty()


func peut_refaire() -> bool:
	return not _futur.is_empty()


func annuler() -> bool:
	if _passe.is_empty():
		return false
	_futur.append(donnees)
	donnees = _passe.pop_back()
	_apres()
	return true


func refaire() -> bool:
	if _futur.is_empty():
		return false
	_passe.append(donnees)
	donnees = _futur.pop_back()
	_apres()
	return true


# =====================================================================
# LES PIÈCES DU PLAN (premier niveau)
# =====================================================================
func pieces_racine() -> Array:
	return donnees["pieces"]


## La pièce de premier niveau qui a cet id (vide si aucune).
func element(id: String) -> Dictionary:
	for e in donnees["pieces"]:
		if e is Dictionary and String(e.get("id", "")) == id:
			return e
	return {}


func est_ajout(id: String) -> bool:
	var e := element(id)
	return not e.is_empty() and e.has("modele")


## Les pièces toutes faites posées (ensembles avec un modèle), dans l'ordre du plan.
func ajouts() -> Array:
	return (donnees["pieces"] as Array).filter(func(e): return e is Dictionary and e.has("modele"))


## Les modules du chasseur : {clé: {"nom": …, "ids": [pièces de premier niveau]}} (dans l'ordre du plan).
func modules() -> Dictionary:
	var noms: Dictionary = donnees.get("modules", {})
	var d := {}
	for e in donnees["pieces"]:
		if not e is Dictionary or e.has("modele") or not e.has("module"):
			continue
		var m := String(e["module"])
		if not d.has(m):
			d[m] = {"nom": String(noms.get(m, m)), "ids": []}
		(d[m]["ids"] as Array).append(String(e["id"]))
	return d


func nom_module(cle: String) -> String:
	return String((donnees.get("modules", {}) as Dictionary).get(cle, cle))


# =====================================================================
# PLACE ET ORIENTATION D'UNE PIÈCE TOUTE FAITE
# =====================================================================
## Transformation d'un ensemble (repère du plan) : position, rotation, miroir.
static func xf_de(e: Dictionary) -> Transform3D:
	var b := Catalogue.rotation(e.get("rotation_deg", [0.0, 0.0, 0.0]))
	if bool(e.get("miroir_x", false)):
		b = b * MIROIR
	return Transform3D(b, Catalogue.vecteur(e.get("position", [0.0, 0.0, 0.0])))


## Écrit une transformation dans un ensemble (une orientation « en miroir » devient rotation + miroir_x).
static func ecrire_xf(e: Dictionary, xf: Transform3D) -> void:
	var b := xf.basis.orthonormalized()
	var miroir := b.determinant() < 0.0
	if miroir:
		b = b * MIROIR
	var eu := b.get_euler()
	e["position"] = [snappedf(xf.origin.x, 0.0001), snappedf(xf.origin.y, 0.0001), snappedf(xf.origin.z, 0.0001)]
	e["rotation_deg"] = [snappedf(rad_to_deg(eu.x), 0.001), snappedf(rad_to_deg(eu.y), 0.001), snappedf(rad_to_deg(eu.z), 0.001)]
	for i in 3:
		if absf(float(e["rotation_deg"][i])) < 0.0005:
			e["rotation_deg"][i] = 0.0
	if miroir:
		e["miroir_x"] = true
	else:
		e.erase("miroir_x")


## La même place, de l'autre côté (gauche ↔ droite).
static func miroir(xf: Transform3D) -> Transform3D:
	return Transform3D(MIROIR * xf.basis, MIROIR * xf.origin)


## Le nom de la pièce (ou de l'articulation) qui est de l'autre côté : « Aile_haut_gauche » ↔
## « Aile_haut_droit », « Aileron_g » ↔ « Aileron_d ». Pour une pièce toute faite : sa jumelle. S'il n'y
## en a pas (pièce du milieu, comme le fuselage), le même nom.
func nom_miroir(id: String) -> String:
	if id == "":
		return ""
	var e := element(id)
	if not e.is_empty() and e.has("symetrique") and not element(String(e["symetrique"])).is_empty():
		return String(e["symetrique"])
	var candidats := []
	for paire in [["gauche", "droite"], ["gauche", "droit"]]:
		if id.contains(paire[0]):
			candidats.append(id.replace(paire[0], paire[1]))
		if id.contains(paire[1]):
			candidats.append(id.replace(paire[1], paire[0]))
	if id.ends_with("_g"):
		candidats.append(id.trim_suffix("_g") + "_d")
	if id.ends_with("_d"):
		candidats.append(id.trim_suffix("_d") + "_g")
	var p = plan()
	for c in candidats:
		if not element(c).is_empty() or p.articulations.has(c) or _a_piece(p, c):
			return c
	return id


static func _a_piece(p, id: String) -> bool:
	for q in p.pieces:
		if q["id"] == id:
			return true
	return false


func _numero_libre(prefixe: String) -> int:
	var n := 1
	var pris := {}
	for e in donnees["pieces"]:
		if e is Dictionary:
			pris[String(e.get("id", ""))] = true
	while pris.has("%s_%d" % [prefixe, n]):
		n += 1
	return n


# =====================================================================
# OPÉRATIONS (chacune peut être annulée)
# =====================================================================
## Pose une pièce toute faite. xf : sa place (repère du plan) ; fixe_a : la pièce sur laquelle elle est
## posée ; articulation : la pièce mobile qu'elle suit (aile…) ; symetrie : poser aussi sa jumelle de
## l'autre côté. Renvoie les ids des pièces posées.
func ajouter(modele: String, reglages: Dictionary, xf: Transform3D, fixe_a := "", articulation := "", symetrie := false) -> Array:
	if not Pieces.existe(modele):
		return []
	_avant()
	var r := Pieces.reglages_complets(modele, reglages)
	var jumelle := symetrie and absf(xf.origin.x) > SUR_L_AXE
	var n := _numero_libre(modele)
	var id := "%s_%d" % [modele, n]
	var e := _nouvel_ensemble(id, modele, r, xf, fixe_a, articulation)
	e["nom"] = _nom_ajout(modele, n, xf.origin.x if jumelle else 0.0)
	pieces_racine().append(e)
	var ids := [id]
	if jumelle:
		var id2 := "%s_%d" % [modele, _numero_libre(modele)]
		var e2 := _nouvel_ensemble(id2, modele, r, miroir(xf), nom_miroir(fixe_a), nom_miroir(articulation))
		e2["nom"] = _nom_ajout(modele, n, -xf.origin.x)
		e["symetrique"] = id2
		e2["symetrique"] = id
		pieces_racine().append(e2)
		ids.append(id2)
	_apres()
	return ids


func _nouvel_ensemble(id: String, modele: String, r: Dictionary, xf: Transform3D, fixe_a: String, articulation: String) -> Dictionary:
	var e := {"id": id, "type": "ensemble", "modele": modele, "nom": Pieces.nom(modele), "reglages": r.duplicate()}
	ecrire_xf(e, xf)
	if fixe_a != "":
		e["fixe_a"] = fixe_a
	if articulation != "":
		e["articulation"] = articulation
	e["pieces"] = Pieces.pieces(modele, r, id)
	return e


static func _nom_ajout(modele: String, n: int, x: float) -> String:
	var cote := ""
	if x < -SUR_L_AXE:
		cote = " gauche"
	elif x > SUR_L_AXE:
		cote = " droite"
	return "%s %d%s" % [Pieces.nom(modele), n, cote]


## Déplace (et tourne) une pièce toute faite ; sa jumelle suit, de l'autre côté.
func placer(id: String, xf: Transform3D, fixe_a := "", articulation := "") -> void:
	var e := element(id)
	if e.is_empty() or not e.has("modele"):
		return
	_avant()
	_poser(e, xf, fixe_a, articulation)
	var j := element(String(e.get("symetrique", "")))
	if not j.is_empty():
		_poser(j, miroir(xf), nom_miroir(fixe_a), nom_miroir(articulation))
	_apres()


func _poser(e: Dictionary, xf: Transform3D, fixe_a: String, articulation: String) -> void:
	ecrire_xf(e, xf)
	if fixe_a != "":
		e["fixe_a"] = fixe_a
	else:
		e.erase("fixe_a")
	if articulation != "":
		e["articulation"] = articulation
	else:
		e.erase("articulation")


## Change la place sans changer la fixation (réglage à la main des coordonnées dans la fiche).
func deplacer_a_la_main(id: String, xf: Transform3D) -> void:
	var e := element(id)
	if e.is_empty():
		return
	placer(id, xf, String(e.get("fixe_a", "")), String(e.get("articulation", "")))


## Change un réglage (poussée, dimension, matière…) ; la jumelle prend le même.
func regler(id: String, cle: String, valeur) -> void:
	var e := element(id)
	if e.is_empty() or not e.has("modele"):
		return
	var modele := String(e["modele"])
	var r: Dictionary = (e.get("reglages", {}) as Dictionary).duplicate()
	r[cle] = valeur
	r = Pieces.reglages_complets(modele, r)
	if r == e.get("reglages", {}):
		return
	_avant()
	for x in [e, element(String(e.get("symetrique", "")))]:
		if (x as Dictionary).is_empty():
			continue
		x["reglages"] = r.duplicate()
		x["pieces"] = Pieces.pieces(modele, r, String(x["id"]))
	_apres()


## Supprime des pièces de premier niveau (une pièce toute faite part avec sa jumelle) ou des modules entiers
## du chasseur (« module:clé »). Les pièces qui étaient posées dessus restent (elles ne touchent plus rien).
func supprimer(ids: Array) -> int:
	var a_enlever := {}
	var mods := modules()
	for id in ids:
		var s := String(id)
		if s.begins_with("module:"):
			if MODULES_INDISPENSABLES.has(s.trim_prefix("module:")):
				continue
			for i in mods.get(s.trim_prefix("module:"), {}).get("ids", []):
				a_enlever[i] = true
			continue
		var e := element(s)
		if e.is_empty() or MODULES_INDISPENSABLES.has(String(e.get("module", ""))):
			continue
		a_enlever[s] = true
		if e.has("symetrique"):
			a_enlever[String(e["symetrique"])] = true
	if a_enlever.is_empty():
		return 0
	_avant()
	var reste := []
	for e in donnees["pieces"]:
		if e is Dictionary and a_enlever.has(String(e.get("id", ""))):
			continue
		reste.append(e)
	donnees["pieces"] = reste
	# une jumelle dont l'autre a disparu devient une pièce seule
	for e in reste:
		if e is Dictionary and e.has("symetrique") and a_enlever.has(String(e["symetrique"])):
			e.erase("symetrique")
	_apres()
	return a_enlever.size()


## Délie une pièce de sa jumelle (elles deviennent deux pièces indépendantes).
func separer_symetrie(id: String) -> void:
	var e := element(id)
	if e.is_empty() or not e.has("symetrique"):
		return
	_avant()
	var j := element(String(e["symetrique"]))
	e.erase("symetrique")
	if not j.is_empty():
		j.erase("symetrique")
	_apres()


func renommer(nouveau: String) -> void:
	nouveau = nouveau.strip_edges()
	if nouveau == "" or nouveau == nom():
		return
	_avant()
	donnees["nom"] = nouveau
	_apres()


# =====================================================================
# FICHIERS
# =====================================================================
## « Chasseur v27 modifié » → « chasseur_v27_modifie » (nom de fichier sans accents ni espaces).
static func nom_fichier(t: String) -> String:
	var s := t.to_lower()
	for paire in [["àâä", "a"], ["éèêë", "e"], ["îï", "i"], ["ôö", "o"], ["ùûü", "u"], ["ç", "c"], ["ÿ", "y"]]:
		for ch in String(paire[0]):
			s = s.replace(ch, paire[1])
	var sortie := ""
	for ch in s:
		sortie += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while sortie.contains("__"):
		sortie = sortie.replace("__", "_")
	sortie = sortie.strip_edges().trim_prefix("_").trim_suffix("_").left(48)
	return sortie if sortie != "" else "vaisseau"


## Texte du fichier : JSON lisible, listes de nombres sur une seule ligne.
func texte() -> String:
	var t := JSON.stringify(donnees, "\t", false)
	var re := RegEx.new()
	re.compile("\\[\\s*(-?[0-9][-0-9.eE+]*(?:,\\s*-?[0-9][-0-9.eE+]*)*)\\s*\\]")
	var sortie := ""
	var debut := 0
	for m in re.search_all(t):
		sortie += t.substr(debut, m.get_start() - debut)
		var nombres := PackedStringArray()
		for x in m.get_string(1).split(","):
			nombres.append(x.strip_edges())
		sortie += "[" + ", ".join(nombres) + "]"
		debut = m.get_end()
	return sortie + t.substr(debut)


## Enregistre une COPIE du vaisseau (« … (copie) ») dans un nouveau fichier ; l'original reste.
func enregistrer_copie(dossier := DOSSIER) -> Error:
	_avant()
	donnees["nom"] = nom() + " (copie)"
	chemin = ""
	_plan = null
	return enregistrer(dossier)


## Enregistre le vaisseau dans user://vaisseaux/<nom>.plan.json. Renommer puis enregistrer renomme le
## fichier ; un autre vaisseau qui a déjà ce nom n'est jamais écrasé (le nouveau prend « _2 », « _3 »…).
func enregistrer(dossier := DOSSIER) -> Error:
	DirAccess.make_dir_recursive_absolute(dossier)
	var base := dossier + nom_fichier(nom())
	var nouveau := base + ".plan.json"
	var k := 2
	while FileAccess.file_exists(nouveau) and nouveau != chemin:
		nouveau = "%s_%d.plan.json" % [base, k]
		k += 1
	donnees["format"] = Plan.FORMAT
	donnees["version"] = Plan.VERSION
	var f := FileAccess.open(nouveau, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(texte() + "\n")
	f.close()
	if chemin != "" and chemin != nouveau and chemin.begins_with(dossier) and FileAccess.file_exists(chemin):
		DirAccess.remove_absolute(chemin)   # le vaisseau a été renommé : l'ancien fichier part
		Plan._textes.erase(chemin)
	chemin = nouveau
	Plan._textes.erase(nouveau)
	modifie = false
	if _plan != null:
		_plan.chemin = chemin
	return OK
