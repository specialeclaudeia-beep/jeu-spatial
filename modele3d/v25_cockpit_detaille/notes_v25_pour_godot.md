# Vaisseau v25 : cockpit détaillé

Fait à partir de la v24 (droïde, couleurs corrigées). Les notes v21 à v24 et `masses_godot.json` restent valables (copiés ici).
Seul `cockpit_v25.glb` change vraiment. L'extérieur et le droïde sont les mêmes qu'en v24.

## Nouvel objet `Cockpit_details_v25` (dans le glb du cockpit)
Il n'ajoute **aucun bouton ni interrupteur décoratif** : les commandes restent celles de `commandes_cockpit.md`.
- Siège éjectable : appui-tête rembourré avec joues, dossier et assise capitonnés, bourrelets latéraux bleu nuit avec liseré orange, rails d'éjection rivetés derrière le dossier, socle avec bandes de sécurité orange.
- Flancs : membrures rivetées, panneaux bleu nuit avec liseré orange, grilles d'aération, faisceau de 3 câbles avec colliers sous le rebord, bouteille d'oxygène à gauche, extincteur rouge à droite.
- Cloison arrière : panneaux, grilles, rivets, tuyaux.
- Plancher : plaques antidérapantes rivetées.
- Tableau de bord : cadres épais vissés autour des 3 écrans, joues latérales.
- Poignées de maintien sur les rebords de la verrière.

Cockpit : environ 7 400 triangles (2 900 avant).

## À faire dans Godot : vue dégagée depuis le cockpit
Vu du siège, le dessus du nez est presque à hauteur des yeux. Comme la coque extérieure est invisible de l'intérieur (faces simples, voulu depuis la v11), le pilote voyait à travers le nez le puits du train avant, la roue rentrée et les moteurs de levage : ça faisait un rectangle sombre devant lui.
Ces nœuds ont maintenant l'extra `cacher_en_vue_cockpit = true` :
`Puits_train_avant`, `Train_avant` (avec ses enfants), `Trappe_avant`, `Charniere_Trappe_avant`, `Puits_moteur_levage_*`, `Moteur_levage_*` (avec leurs enfants), `Charniere_Trappe_levage_*`.
**En vue cockpit, les rendre invisibles** (visible = false, avec leurs enfants), et les réafficher en vue extérieure, comme on le fait déjà pour le cockpit dans l'autre sens.

Le cadre du viseur tête haute (HUD) ajouté en v20 a aussi été retiré de `Cockpit_habillage`.
