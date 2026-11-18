# Labo-lumière : instructions pour Claude

Ce dossier est un petit projet Godot à part, rangé dans le dépôt du jeu
(`specialeclaudeia-beep/jeu-spatial`, dossier `labo-lumiere/`). On y construit le
« système de décomposition fractale de la lumière » de Gwenaël (étapes 2 à 7 du programme),
avant de le brancher dans le jeu à l'étape 8.

Référence unique : le programme du système de lumière, https://claude.ai/artifact/XLupfWSmbU7wjncyd5Vkpa
(parties 2, 4, 5 et 6, et la ligne de ton étape dans la partie 7). Fiches mémoire du projet :
« programme-lumiere » (journal des étapes) et « lumiere-couleurs-reflets-oeil ».

## Règles de Gwenaël
- Toujours en français simple, sans jargon. Gwenaël n'est pas développeur : Claude fait le technique.
- Pas de question quand la réponse est sûre : faire, puis dire ce qui a été fait.
- Le système de lumière est son idée : on l'améliore, on ne le remplace jamais par une solution
  « classique » sans en discuter avec lui.
- Aucune physique magique : la lumière suit de vraies lois.
- Fini = tests automatiques ET essai de Gwenaël à l'écran. On garde toujours la dernière version qui marche.
- PC modeste (i3-1005G1, Intel UHD, 8 Go) : viser 60 images/s en 1280×720.

## Instructions Godot
- **Version et rendu** : Godot 4.7.2, rendu Compatibilité (OpenGL 3). Pas de compute shaders, pas de SSR,
  pas d'éclairage global. Au plus 8 lumières et 2 sondes de reflet par objet. Couleurs sur 8 bits, d'où le tramage.
- **Données** : GDScript typé partout. Les rayons vivent dans des tableaux compacts
  (PackedFloat32Array, PackedInt64Array). Jamais un nœud ni un objet par rayon ou par triangle.
  Les adresses de 64 bits tiennent dans un int de GDScript.
- **Calcul** : le travail lourd passe par WorkerThreadPool. Un fil de calcul ne touche jamais à l'arbre de scène.
- **Envoi** : les couleurs partent dans une Image, avec un seul `ImageTexture.update()` par image.
- **Dessin** : un MultiMesh du morceau type, et un shader qui lit la couleur dans la texture.
- **Précision** : positions calculées en 64 bits (GDScript), affichage en 32 bits. Les astres lointains
  sont donc dessinés plus près et plus petits.
- **Mesurer avant d'optimiser** : chaque scène affiche le compteur (`scripts/outils/compteur.gd`, F3) :
  images/s, millisecondes des 4 temps de la boucle, nombre de rayons. Le système range ses mesures
  dans `compteur.chrono` (`scripts/lumiere/chrono_boucle.gd` : `debut(i)` / `fin(i)`, `nb_rayons`).
- **C++ (décidé à l'étape 2)** : mesure sur le PC = choisir 9 ms + éclairer 7 ms en GDScript avec fils
  (budget 2 + 3). Gwenaël a choisi le C++ (GDExtension) pour ces DEUX temps ; l'envoi, le dessin et le reste
  restent en GDScript/shader. Résultats : `mesures/resultats-pc.md`, scène `scenes/mesure.tscn`.
- **Pas de `class_name`** : on charge les scripts avec `preload`, pour que rien n'entre en conflit
  avec les classes du jeu le jour du branchement.

## Soleil et œil (étape 3)
- `scripts/lumiere/soleil.gd` : Soleil réel (1 UA, rayon 6,957e8 m, 126 600 lux, éclat 1,86e9 cd/m², bord
  assombri 60 %), positions en 64 bits (`PackedFloat64Array`), part visible du disque derrière une sphère
  (recouvrement de deux disques = pénombre).
- `scripts/lumiere/oeil.gd` : pupille (Moon et Spencer), adaptation de la rétine en trolands (lumière
  2 s, d'où un vrai éblouissement blanc en sortant du noir ; au noir 8 s accéléré par défaut, 300 s avec T), réponse de Naka-Rushton (k = 4,5),
  vision de nuit entre 3 et 0,003 cd/m², halo = fonction d'éblouissement CIE 146:2002.
  Le disque du Soleil ne compte qu'à 3 % dans l'adaptation (`PART_DISQUE_ADAPTATION` dans labo.gd) :
  sinon tout l'écran noircit face au Soleil, effet « paupières qui se ferment » refusé par Gwenaël le 18/11.
  `luminance_scene()` = « posemètre » (aujourd'hui 16 × 9 directions dans labo.gd ; à l'étape 4 ce
  seront les rayons qui donneront ces mesures, sans coût en plus).
- `scripts/lumiere/oeil.gdshaderinc` : à inclure dans TOUT programme de dessin. Chaque programme calcule
  une vraie luminance (cd/m²), ajoute `oeil_voile(direction, TIME)`, puis `ALBEDO = oeil_vers_ecran(...)`.
- Réglages globaux des shaders : section `[shader_globals]` de `project.godot` (à recopier dans le jeu
  à l'étape 8). Le processeur les met à jour à chaque image.
- **Rendu Compatibilité : aucune conversion vers sRGB pour nos programmes** (vérifié : `ALBEDO = 0.5` sort
  à 0,502 à l'écran). `oeil_vers_ecran` fait donc lui-même la conversion sRGB. Garder
  `Environment.tonemap_mode = LINEAR` et pas de glow.
- `scripts/lumiere/ciel.gdshader` : ciel (lueur de fond 2e-4 cd/m², disque solaire, couronne de Baumbach).
  Les étoiles arrivent à l'étape 6.

## Planète en rayons et partie C++ (étape 4)
- **Partie C++** (GDExtension) : classe `ArbreLumiere`, sources dans `cpp/src/` (dossier ignoré par Godot,
  `.gdignore`), bibliothèques compilées dans `scripts/lumiere/bin/` (`lumiere.gdextension` + .dll Windows
  + .so Linux, debug ET release : l'éditeur et F5 prennent la version debug). godot-cpp = branche
  **master** (api_version=4.7), pas le tag 4.5. Compilation dans le cloud :
  `git clone --depth 1 https://github.com/godotengine/godot-cpp` puis, dans `cpp/` :
  `scons godot_cpp=<chemin> api_version=4.7 platform=windows use_mingw=yes target=template_debug`
  (et `template_release`, et `platform=linux` pour les tests du cloud ; mingw : paquet
  `g++-mingw-w64-x86-64-posix`, scons par pip). La DLL est liée en statique : rien à installer sur le PC.
- **Dans le cloud** : la première importation sans écran (`--headless --import` sur un `.godot` vide)
  plante à la FERMETURE dès qu'une classe C++ est enregistrée (bug de Godot en mode sans écran ;
  l'éditeur normal s'ouvre bien, vérifié avec un écran virtuel). Lancer l'importation deux fois.
- **Arbre** : 20 faces d'icosaèdre, ×4 par niveau, adresse 64 bits (1 de tête + 5 bits + 2 bits/niveau).
  Un morceau = triangle coupé 3 fois (64 rayons, 45 coins). Coins par milieux successifs ramenés sur la
  sphère (mêmes opérations chez les voisins → mêmes nombres). Relief : un coin a les détails de son
  niveau de NAISSANCE (−2) → un coin ne change jamais de hauteur. Couper à 8 px par rayon, fusionner à 6.
- **Choisir** : file de priorité (le plus gros à l'écran est coupé d'abord, avec un facteur de vue en biais
  sqrt(max(|cos|, 0,2))), budget = places − 24 ; tri par l'horizon et le champ de vue. Un parent reste
  affiché tant que ses 4 enfants ne sont pas calculés. Cache : 12 000 morceaux, on garde les 9 000 plus récents.
- **Éclairer** : par paquets de 8 sur les fils de calcul, au plus 96 morceaux et 3 ms par image
  (`budget_eclairer_ms` dans `planete.gd`) ; le reste attend l'image suivante.
- **Lumière sur les COINS partagés** (pas par rayon) : albédo, direction moyenne et couleur de départ rangés
  sur les 45 coins, calculés seulement à partir de la direction du coin et de son niveau de naissance →
  deux morceaux voisins ont les mêmes nombres sur leur bord, et la carte graphique fond d'un coin à l'autre.
- **Glissement** : un enfant né d'une coupe part de la forme et des couleurs de son parent
  (`depart`) et glisse en 0,5 s vers les siennes (`cible`) ; le shader mélange selon l'heure d'arrivée
  (INSTANCE_CUSTOM.x). **Jupes** : petits murs sous les bords des morceaux, contre les fentes entre niveaux.
- **Étalement** : la direction moyenne (longueur L) = cône de petites faces de demi-angle b,
  cos b = 2L − 1 ; lumière = moyenne de max(cos, 0) sur le cône (jamais de lumière côté nuit).
  Même loi dans `planete.gdshader` et dans le posemètre C++.
- **Profondeur logarithmique** dans `planete.gdshader` (DEPTH) : à reprendre pour tout objet dessiné avec
  la planète au branchement (étape 8). ATTENTION : Godot 4.7 en Compatibilité utilise une profondeur
  INVERSÉE (1 = près, 0 = loin) : `DEPTH = 1.0 - log(...)`, sinon la face cachée passe devant.
- **Posemètre** : `ArbreLumiere.posemetre()` range la lumière des rayons affichés dans 16 × 9 cases.
- **Rotation** (jour 2 h) : faite en faisant tourner le Soleil autour de la planète (l'œil tourne avec le sol).
  `tampon_instances()` accepte déjà une vraie rotation pour l'étape 8.
- **Mesure sur le PC** : `Godot_v4.7.2-stable_win64_console.exe --path labo-lumiere -- --mesure`
  → `mesures/resultats-planete-pc.md`.
- Pas encore fait : rebonds de lumière (Q38).

## Lune, éclipses et retard de la lumière (étape 5)
- **Lune** (Q42) : 2e `Planete` (rayon 150 km, graine 23, 512 places, éclairer 48 morceaux / 1,5 ms),
  à 6 000 km du centre. `preparer(rayon, graine, places)`. Elle a sa propre rotation
  (`planete.rotation_astre`, envoyée à `tampon_instances` ; l'œil et les axes de la caméra passent dans
  son repère avec la transposée). Elle montre toujours la même face à la planète.
- **Orbite** (`scripts/lumiere/orbite.gd`) : vraie gravité de Newton, orbite circulaire de Kepler
  (masse de la planète = boule de roche 3 000 kg/m³ → un tour en 60 h, 174 m/s). Repère FIXE (qui ne
  tourne pas) ; le labo travaille dans le repère de la planète, qui tourne : passage par une rotation de
  −angle_jour autour de Y (`_vers_planete`). Plan de l'orbite = contient la direction du Soleil
  → une éclipse de Soleil et une de lune à chaque tour.
- **Retard de la lumière** : `orbite.retard(t, oeil)` résout |p(t − r) − œil| = c r (6 tours) ;
  la lune est dessinée là où elle ÉTAIT (`position_vue`). Le Soleil ne bouge pas dans le repère fixe :
  sa lumière a 8 min 19 s de retard (affiché) mais sa direction ne change pas. Effets minuscules ici
  (lune : 20 ms, 3,5 m), ils compteront pour les étoiles proches et les grandes vitesses (étape 6).
- **Éclipses avec pénombre** : chaque astre a un « occulteur » (l'autre astre). Dans `planete.gdshader`,
  la part visible du disque solaire est calculée AUX COINS (recouvrement de deux disques, même formule
  que `soleil.gd` et la partie C++), uniform `occulteur` (centre par rapport à la caméra, rayon en w).
  Dans la partie C++, `posemetre(..., occulteur, soleil_angle)` fait de même rayon par rayon, et
  `couverture()` donne la part de chaque case couverte par l'astre (pour mettre la lune devant la planète
  case par case dans `labo._poser`). Pour l'œil : part visible = vp + vl − 1 (deux occulteurs).
- **Temps accéléré** : V (×1, ×10, ×100, ×1000) agit sur la rotation et l'orbite (`temps_astres`), PAS
  sur l'œil ni sur le glissement (horloge `temps`).
- Points de vue : 6 éclipse totale vue du sol (matin, Soleil à 35°), 7 ombre de la lune vue d'orbite,
  8 éclipse de lune (la lune au bord de l'ombre de la planète, vue à 500 km).
- Pas encore fait : lumière de la planète sur la lune (et inversement) = rebonds Q38 ; la lune côté nuit
  est donc noire.

## Organisation
| Chemin | Contenu |
|---|---|
| `project.godot` | Projet « Labo lumière », rendu Compatibilité, 1280×720 |
| `LISEZMOI.md` | Pour Gwenaël : quoi ouvrir, quelles touches |
| `scenes/labo.tscn` | Scène principale (planète, Soleil, caméra libre au fil des étapes) |
| `scenes/mesure.tscn` | Mesure de vitesse (créée à l'étape 2) |
| `scenes/tests.tscn` | Tests automatiques |
| `scripts/lumiere/` | Le système lui-même (`orbite.gd` : lune et retard de la lumière, étape 5). Ne charge RIEN en dehors de ce dossier (un test le vérifie) : il sera copié tel quel dans le jeu à l'étape 8 |
| `scripts/outils/` | Outils du labo (compteur…) |
| `scripts/tests/` | Les tests |
| `shaders/` | Programmes de la carte graphique propres au labo (`astre_essai.gdshader` = boule de secours sans C++) |
| `cpp/` | Sources C++ de `ArbreLumiere` (étape 4), ignorées par Godot |
| `scripts/lumiere/bin/` | Partie C++ compilée (Windows + Linux) |
| `addons/godot_ai/` | Copié depuis le jeu sur le PC, pas dans le dépôt (`.gitignore`) |

## Tests automatiques
- Dans le cloud : télécharger Godot 4.7.2 pour Linux dans le dossier temporaire du fil
  (`https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`), puis
  `godot --headless --path labo-lumiere res://scenes/tests.tscn --quit-after 3000`
  (code de sortie 0 = tout passe, 1 = un échec ; dernière ligne « RÉSULTAT : x / y tests réussis »).
- Capture d'écran : `xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path labo-lumiere`
  avec un petit script `-s` qui charge la scène, attend ~90 images et enregistre `get_viewport().get_texture().get_image()`.
- Après chaque changement, lancer aussi les tests du jeu pour vérifier que rien n'est cassé :
  `godot --headless --path . res://scenes/tests.tscn --quit-after 4000` (depuis la racine du dépôt).

## Sur le PC de Gwenaël
- Dossier : `Documents\jeu spacial\labo-lumiere`. Les sessions sur le PC n'ont pas GitHub :
  elles déposent un patch dans les fichiers du projet Claude, et un fil dans le cloud le fusionne.
- Godot AI : Godot ouvert sur le labo, puis une session Remote Control, qui donne les outils
  Godot AI (lire la scène, la lancer, lire les erreurs). Si la session démarre pendant que le serveur
  Godot AI se prépare (plus de 30 s), arrêter la session et la relancer.

## À ne pas faire
- Ne pas toucher au jeu depuis le labo, sauf à l'étape 8. Le jeu ignore ce dossier tout seul
  (Godot saute tout sous-dossier qui contient son propre `project.godot`, vérifié à l'étape 0).
- Garder une version qui marche : une branche par fil, une demande de fusion en brouillon,
  fusion sur main seulement après l'essai validé par Gwenaël.
