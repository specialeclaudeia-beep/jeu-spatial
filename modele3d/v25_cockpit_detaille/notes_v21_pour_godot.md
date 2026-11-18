# Vaisseau v21 : buses de stabilisation encastrées

Fait à partir de la v20 (trains à amortisseurs, cockpit) et de la v19 (lueurs des moteurs). Leurs notes restent valables :
`../v20_trains_et_cockpit/notes_v20_pour_godot.md` et `../v19_moteurs_lumineux/notes_v19_pour_godot.md`.

## Principe
Comme sur les fusées, les petites buses sont **encastrées dans la coque** (objet `RCS_integres` : une bague et une sortie sombre, au ras de la coque).
Chaque buse souffle **perpendiculairement à la coque à l'endroit où elle est posée** : la force qu'elle donne est exactement l'opposé de ce sens, appliquée à sa position. Rien n'est « magique ».
Elles vont toujours **par paires symétriques gauche/droite** : la paire pousse le vaisseau sans le faire tourner (les petites composantes de côté s'annulent).

Avant la v21, aucun propulseur ne poussait vers l'arrière : on ne pouvait pas freiner sans se retourner.

## Nouveaux points de poussée (extras `type = rcs_translation`, `poussee_N = 6000`, `souffle_godot`, `poussee_godot`)

| Paire | Où (repère Godot) | Pousse le vaisseau vers |
|---|---|---|
| `Point_rcs_freinage_gauche/droit` | face avant du nez (±0.10, 0, -6.0) | l'arrière : **freine / recule** |
| `Point_rcs_poussee_fine_gauche/droit` | face arrière, à côté du gros moteur (±0.70, 0, 4.3) | l'avant (petites avancées précises) |
| `Point_rcs_lateral_gauche/droit` | milieu des flancs (±0.75, 0, 0) | le côté opposé |
| `Point_rcs_montee_gauche/droit` | chanfrein bas des flancs (±0.56, -0.46, 0) | le haut (en paire) |
| `Point_rcs_descente_gauche/droit` | chanfrein haut des flancs (±0.57, 0.62, 0) | le bas (en paire) |

Les valeurs exactes (avec les petites inclinaisons de la coque) sont dans les extras de chaque nœud : utiliser `poussee_godot` tel quel.
Les buses de montée et de descente sont inclinées comme la coque (environ 32°) : une seule pousse aussi un peu sur le côté, c'est normal, la paire l'annule.

Les 8 propulseurs existants du nez et de la queue (`RCS_nez_*`, `RCS_queue_*`) ont pris le même style encastré. Leurs points et leurs directions n'ont pas changé.

## Lueurs
Chaque buse a sa lueur `Lueur_rcs_<nom>` (`type = lueur`, `moteur` = nom du point), même fonctionnement que les moteurs : éteint à 0, bleu → violet.

## Pour la physique
Ajouter ces 10 points à la liste `rcs` de `vaisseau_physique.gd` avec leur `poussee_godot` : le calcul qui répartit la poussée les utilisera tout seul pour glisser, freiner et faire les petites corrections.

## Poids
Extérieur : environ 11 300 triangles. Cockpit inchangé.
