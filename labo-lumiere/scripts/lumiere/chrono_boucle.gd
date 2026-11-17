extends RefCounted
## Chronomètre des 4 temps de la boucle d'une image du système de lumière :
## 0 choisir (couper / fusionner les triangles), 1 éclairer (calculer les rayons),
## 2 envoyer (couleurs vers la carte graphique), 3 dessiner.
## Le système appelle debut(i) / fin(i) autour de chaque temps ; le compteur (F3) affiche le résultat.
## Ce fichier fait partie du système : il ne dépend de rien d'autre, pour être copié tel quel
## dans le jeu à l'étape 8.

const CHOISIR := 0
const ECLAIRER := 1
const ENVOYER := 2
const DESSINER := 3
const NOMS: PackedStringArray = ["choisir", "éclairer", "envoyer", "dessiner"]

## Budget visé par temps, en millisecondes (programme, partie 5). Des objectifs, pas des mesures.
const BUDGET_MS: PackedFloat64Array = [2.0, 3.0, 1.0, 8.0]

## Part de la nouvelle mesure dans la moyenne lissée (0,1 = lissage sur une dizaine d'images).
const LISSAGE := 0.1

var derniers_ms := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])   # dernière mesure de chaque temps
var moyennes_ms := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])   # moyenne lissée de chaque temps
var nb_rayons: int = 0                                          # rayons actifs (mis par le système)

var _debuts_us := PackedInt64Array([0, 0, 0, 0])
var _deja_mesure: Array[bool] = [false, false, false, false]


## Démarre le chronomètre du temps i.
func debut(i: int) -> void:
	_debuts_us[i] = Time.get_ticks_usec()


## Arrête le chronomètre du temps i et renvoie la durée en millisecondes.
func fin(i: int) -> float:
	var ms := float(Time.get_ticks_usec() - _debuts_us[i]) / 1000.0
	enregistrer(i, ms)
	return ms


## Range une durée mesurée ailleurs (par exemple le temps de dessin donné par Godot).
func enregistrer(i: int, ms: float) -> void:
	ms = maxf(ms, 0.0)
	derniers_ms[i] = ms
	if _deja_mesure[i]:
		moyennes_ms[i] = lerpf(moyennes_ms[i], ms, LISSAGE)
	else:
		moyennes_ms[i] = ms
		_deja_mesure[i] = true


## Somme des moyennes des 4 temps.
func total_ms() -> float:
	var t := 0.0
	for m in moyennes_ms:
		t += m
	return t


## Vrai si le temps i dépasse son budget.
func depasse(i: int) -> bool:
	return moyennes_ms[i] > BUDGET_MS[i]
