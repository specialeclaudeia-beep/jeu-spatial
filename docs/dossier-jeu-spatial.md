# Dossier de référence — Jeu spatial réaliste

État au 15/11/2026. Sources : 4 conversations avec ChatGPT (projet « jeu spacial »), puis les échanges avec Claude. Texte original de mes explications : fiche Notion « Jeu spatial réaliste » → sous-page « Archives ChatGPT ».

Légende : **Décidé** = choisi par moi · **Hypothèse** = piste pas encore démontrée · **À résoudre** = question ouverte.

---

## 1. Le jeu

**Décidé.** Simulateur d'exploration spatiale en 3D, vue à la première personne dans le cockpit d'un chasseur façon X-Wing. On passe de l'espace à l'orbite, à l'atmosphère et à la surface sans transition artificielle. Planètes générées automatiquement. Sons selon l'environnement (pas de son extérieur dans le vide : seulement ce qui passe par la structure du vaisseau).

**Décidé.** D'abord une physique qui marche, ensuite le reste. Pas de carburant (autonomie illimitée, comme dans Star Wars), mais les forces restent réalistes.

**Matériel.** Dell Inspiron 17 3793 : Intel Core i3-1005G1 (2 cœurs / 4 threads), Intel UHD Graphics (mémoire partagée), 8 Go DDR4 (une barrette, 2 emplacements, max 16 Go), SSD 512 Go. Moteur : **Godot 4.7.2**, rendu « Compatibilité ».

## 2. Feuille de route

1. Vol et physique du vaisseau (cockpit provisoire, 6 degrés de liberté, gravité) — **en cours**
2. Optimisation (n'afficher que ce qu'on voit, niveaux de détail, précision des grandes distances ; physique séparée du rendu)
3. Apparence du X-Wing (cockpit 3D, instruments, ailes animées selon la vitesse, vibrations)
4. Génération d'une planète (relief, océans, biomes), puis de plusieurs ; atmosphère et aérodynamique
5. Génération non déterministe (garder une graine reproductible pour les tests)
6. Graphismes (textures, lumière, nuages, atmosphères, océans)
7. Sons et immersion

## 3. Physique du vaisseau

**Décidé — règle « aucune physique magique ».** Le moteur physique ne modifie jamais directement la position ou l'orientation. Les forces changent la vitesse, les couples changent la rotation (couple = position × force). Dans le vide, moteurs coupés, la vitesse reste constante. L'orientation du nez et la direction du déplacement sont deux choses différentes.

- Corps rigide à 6 degrés de liberté : masse, centre de masse, inertie.
- Gravité de Newton F = G·M·m/r², calculée en permanence pour tous les corps.
- **5 moteurs arrière** (4 sur les ailes + 1 central). Chacun a sa position, sa direction, sa poussée (0–100 %) et son temps de réponse. Pour tourner, on augmente ou on réduit certains moteurs.
- Des moteurs qui poussent tous vers l'avant ne peuvent pas faire de roulis : il faut des **propulseurs d'orientation** (ou des moteurs orientables).
- Frottement de l'air seulement dans une atmosphère (densité, vitesse relative à l'air, surface, coefficient de traînée).
- Aides au pilotage possibles, mais seulement en agissant sur les moteurs et propulseurs.
- Distinguer vitesse réelle, vitesse relative (à une planète, une station) et accélération ressentie par le pilote.

## 4. Univers

**Décidé.** Galaxie construite à partir de vraies données (catalogue d'étoiles Gaia, exoplanètes de la NASA ; le projet open source Known Universe sert de référence), complétée par de la génération procédurale qui donne toujours le même résultat au même endroit (graine tirée de l'identifiant ou des coordonnées). Ne jamais présenter une planète inventée comme réelle. Données astronomiques indépendantes du moteur graphique.

**Décidé.** Chargement progressif façon Google Maps : l'espace est découpé en zones de plus en plus fines quand on s'approche. On charge le champ de vision, on prépare la périphérie et on garde une version légère du lointain. Calculs répartis sur plusieurs cœurs, sans que l'ordre des tâches change le résultat.

**Hypothèse.** Univers qui évolue : naissance, vie et mort des étoiles (supernovas cohérentes avec le type d'étoile), selon un calendrier déterministe.

**Hypothèse (plus tard).** Couche séparée de relativité : lumière déviée par la gravité, décalage de couleur, retard de propagation, sans exagérer les effets.

## 5. Mon système de lumière (idée originale)

**Décidé — réalisme physique d'abord.** Le vide n'est jamais éclairé artificiellement : toute lumière visible a une vraie source (vrai noir de l'espace, ombres et éclipses naturelles). Une planète n'émet pas de lumière directe : elle renvoie celle de son étoile.

**Le cône.** Chaque astre visible (une étoile, ou la face éclairée d'une planète) a un cône de calcul. Sa base est l'astre, son sommet est au loin, et son axe pointe toujours vers le joueur. Au sommet, on ne voit qu'un point lumineux ; dans le cône, on voit de plus en plus de détails en s'approchant ; hors du cône, on ne voit rien. Le cône sert à réduire progressivement la taille sous laquelle on voit l'astre : c'est la perspective.

**La fractale de rayons.** Chaque rayon (une couleur + une énergie) est composé de rayons plus petits, qui fonctionnent exactement comme lui, sans limite théorique. Exemple de la forêt : un arbre, puis des arbres et de la neige, puis une forêt à côté d'une plaine, puis la mer… En s'éloignant, les enfants fusionnent dans leur parent ; en s'approchant, le parent redonne ses enfants. Le calcul part du joueur pour remonter vers la source.

**Décidé — triangles au lieu d'hexagones.** Les hexagones ne forment pas une fractale exacte (7 hexagones ne font pas un hexagone). On utilise des triangles : un icosaèdre dont chaque triangle se coupe en 4. La forme ne se voit pas à l'écran, elle sert seulement aux calculs.

**Règles retenues.**
- Longueur du cône : nombre de rayons × diamètre = distance (d = N × D). Elle correspond exactement à la perspective réelle.
- Portée selon la luminosité : d_visible = d × √(F / F_référence). C'est la vraie loi en 1/distance².
- Fusion : on additionne l'énergie des enfants et on fait la moyenne de leurs couleurs (moyenne pondérée par l'énergie, en couleurs linéaires).
- Graduation de 0 à 1 entre deux niveaux : les enfants commencent avec la couleur du parent puis prennent la leur peu à peu (pas de saut).
- Au-delà de la limite, les anciens détails disparaissent ; il suffit de se rapprocher pour les revoir (les données des enfants ne sont pas détruites).
- Une planète n'active des rayons que sur sa face éclairée.
- Astre très lumineux mais petit : le rayon peut s'étendre et se subdiviser selon la puissance (compromis C), sans casser d = N × D.
- On ne calcule que les rayons qui peuvent arriver jusqu'aux yeux du joueur, y compris après réflexion.
- Retard de la lumière selon la distance (on voit l'état passé de la source).
- Réflexion selon le matériau (couleur, rugosité, métal, orientation).
- Lissage des couleurs entre rayons voisins à l'affichage seulement (le calcul reste un rayon = une couleur).

**À résoudre.** Direction des rayons fusionnés ; modèle de réflexion et nombre de rebonds ; plusieurs sources de lumière ; seuil de visibilité ; temps de propagation.

**Banc d'essai (navigateur, PC).** https://claude.ai/artifact/7RTivTLhf6TDjpeZyELo2m — tests réussis : portée ×2 pour une source 4 fois plus lumineuse ; près du sol environ 21 000 triangles au lieu de 1 400 milliards ; détails qui apparaissent 7,5 fois plus en douceur avec la fusion progressive ; lumière totale conservée à moins de 3 % (moins de 0,7 % dès le niveau 2).

## 6. État du projet Godot (phase 1)

Dossier : `Documents\jeu spacial`. Fonctionne sur mon PC (testé le 15/11/2026).
- Vaisseau de 10 t, 5 moteurs de 40 kN à leur vraie position, 12 propulseurs d'orientation de 1,5 kN.
- Planète de test : 600 km de rayon, 9,81 m/s² au sol. Départ en orbite à 100 km.
- Cockpit provisoire, instruments (vitesse, altitude, orbite, g ressentis, moteurs), stabilisateur (T) qui n'agit que par les propulseurs, accélération du temps ×1 à ×1000.
- 9 tests de physique (F1) : inertie, poussée centrée et décentrée, orbite stable, précision, moment cinétique, roulis, chute libre, calcul de l'orbite.
- Pas encore : atmosphère, terrain détaillé, vrai modèle du vaisseau.

## 7. Projets open source repérés (à étudier, pas à copier)
- Orbiter — https://github.com/orbitersim/orbiter
- Spacecraft Control System Simulation — https://github.com/KVHorn/Spacecraft-Control-System-Simulation
- DaScient/flight — https://github.com/DaScient/flight
- Spaceflight Dynamics Framework — https://github.com/gerd-lrt-dev/spaceflight-dynamics-framework

Une description de dépôt n'est pas une preuve : vérifier le code, les tests et les résultats.
