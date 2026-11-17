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
- `scripts/lumiere/oeil.gd` : pupille (Moon et Spencer), adaptation de la rétine en trolands (vite à la
  lumière 0,4 s ; au noir 8 s accéléré par défaut, 300 s avec T), réponse de Naka-Rushton (k = 4,5),
  vision de nuit entre 3 et 0,003 cd/m², halo = fonction d'éblouissement CIE 146:2002.
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

## Organisation
| Chemin | Contenu |
|---|---|
| `project.godot` | Projet « Labo lumière », rendu Compatibilité, 1280×720 |
| `LISEZMOI.md` | Pour Gwenaël : quoi ouvrir, quelles touches |
| `scenes/labo.tscn` | Scène principale (planète, Soleil, caméra libre au fil des étapes) |
| `scenes/mesure.tscn` | Mesure de vitesse (créée à l'étape 2) |
| `scenes/tests.tscn` | Tests automatiques |
| `scripts/lumiere/` | Le système lui-même. Ne charge RIEN en dehors de ce dossier (un test le vérifie) : il sera copié tel quel dans le jeu à l'étape 8 |
| `scripts/outils/` | Outils du labo (compteur…) |
| `scripts/tests/` | Les tests |
| `shaders/` | Programmes de la carte graphique propres au labo (`astre_essai.gdshader`) |
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
