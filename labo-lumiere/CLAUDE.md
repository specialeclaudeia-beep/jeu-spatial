# Labo-lumière : instructions pour Claude

Ce dossier est un petit projet Godot à part, rangé dans le dépôt du jeu
(`specialeclaudeia-beep/jeu-spatial`, dossier `labo-lumiere/`). On y construit le
« système de décomposition fractale de la lumière » de Gwenaël (étapes 2 à 9 du programme, toutes faites),
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
  Étape 6 : il ajoute la Voie lactée, l'étoile compagne et l'aberration + Doppler (voir plus bas).

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

## Étoiles, étoile compagne, grande vitesse (étape 6)
- **Catalogue** : `scripts/lumiere/etoiles_yale.bin` = Bright Star Catalogue de Yale (5e éd., domaine public,
  9 096 étoiles, les plus brillantes d'abord ; AD, Dec J2000, V, B-V en float32). Fabriqué par
  `donnees/convertir_yale.py` (dossier ignoré par Godot) depuis le JSON de brettonw/YaleBrightStarCatalog
  (le site de Harvard et le CDS ne passent pas par le proxy du cloud).
- **Repère du ciel** : Y = pôle nord céleste = axe de la planète, X = AD 0 h (`Etoiles.direction_ciel`).
  Le nœud `Etoiles` (MultiMesh, 1 carré par étoile) reste sur la caméra et tourne avec le jour
  (`Basis(Y, −angle_jour)`, comme le Soleil).
- **Dessin** (`etoiles.gdshader`) : vraie lumière d'un point (lux = 2,54e-6 × 10^(−0,4 V)), tache gaussienne
  de 0,6 px qui garde toute la lumière, halo CIE pour les brillantes (carré jusqu'à 24 px), puis
  `oeil_vers_ecran(fond + étoile) − oeil_vers_ecran(fond)` en mélange additif : l'étoile ajoute ce qu'elle
  ajoute vraiment à l'œil (rien quand l'œil est ébloui). Étoile trop faible pour l'œil → carré jeté
  dans le vertex. Profondeur : `DEPTH = 1e-7` (inversée : tout au fond) → la planète et la lune les cachent.
  Le carré est placé à `distance_dessin` = √(near × far) pour ne jamais être coupé par les plans.
- **Couleur** : B-V → température (Ballesteros 2012) → corps noir (Planck × CIE 1931 de Wyman 2013) → sRGB
  linéaire de luminance 1. `Etoiles.table_corps_noir()` = texture 256 × 1 (500 K à 2 MK), alpha =
  efficacité relative (1 au Soleil). Uniform `corps_noir` à donner au ciel ET aux étoiles.
- **Voie lactée** (`fond_galaxie`, même formule en GDScript et en shader) : 7e-5 cd/m² + bande (b ≈ 8°)
  + bulbe vers le centre (Sagittaire). Pôle et centre galactiques J2000 → globals `ciel_pole_galaxie`,
  `ciel_centre_galaxie` (tournent avec le ciel). Moyenne du ciel ≈ 1e-4 ; le posemètre garde FOND_CIEL = 2e-4.
- **Étoile compagne** (`etoile_proche.gd`, Q « deux étoiles proches ») : naine K5 (4 400 K, 0,7 R☉) à 5 UA,
  125° du Soleil (`VERS_COMPAGNE` dans labo.gd). 610 lux. Globals `compagnon_*` (`compagnon.gdshaderinc`).
  `planete.gdshader` additionne les deux lumières (fonction `eclairage`), le reste du ciel est regroupé dans
  `lux_fond`. Le posemètre C++ ne connaît qu'une étoile : `labo._posemetre_astre` l'appelle deux fois
  (2e fois avec fond 0) et additionne. Pas de halo dans l'œil pour la compagne (≈ 1/200 du Soleil) : à faire
  si besoin avec les 4 sources individuelles.
- **Ombre de l'astre lui-même** (correctif) : un astre cache ses étoiles sous l'horizon : boule de rayon
  min(rayon, 0,9999 × distance au centre) dans `planete.gdshader` (`part_etoile`, uniform `rayon_corps`) ET
  dans le posemètre C++ (même formule, calculée seulement si l'étoile est à moins de ~17° au-dessus).
  Avant, la loi du cône de petites faces éclairait des pentes en pleine nuit.
- **Grande vitesse** : global `oeil_vitesse` (fraction de c, repère d'affichage) = déplacements de l'œil + essai B.
  Mise à 0 si < 1/10 pixel. Le ciel fait l'aberration À L'ENVERS par pixel (d'où vient sa lumière au repos),
  luminance × D⁴ × eff(D·T)/eff(T), couleur du corps noir à D·T. Les étoiles : direction penchée, éclat
  × D² × eff(D·T)/eff(T). Le halo du Soleil suit `soleil_direction_vue` (oeil.gdshaderinc).
  PAS ENCORE : planète et lune non déformées à grande vitesse (et leur lumière pas décalée).

## Petite échelle jusqu'au millimètre (étape 7)
- **64 bits partout** dans `labo.gd` : le centre de la planète vu de l'œil (`rel64`, donné à
  `tampon_instances`), l'altitude (`_sol64`), le sol infranchissable, les points de vue (`_placer64`).
  Un `Vector3` de Godot est en 32 bits : à 600 km du centre, 4 cm d'erreur. À reprendre au branchement.
- **Œil jusqu'à 5 mm** (`ALTITUDE_MIN`), vitesse min 5 mm/s × molette. `NIVEAU_MAX` = 26 (rayons ≈ 1,2 mm).
- **Caméra de Godot** : elle ne supporte pas 0,2 mm → 300 km (plus rien ne s'affichait sous 3 m : culling
  faux). Son plan proche reste ≥ far × 1e-5 ; la vraie distance proche (`planete.profondeur_pres`) sert
  seulement à la profondeur logarithmique, et `planete.gdshader` met `POSITION.z = 0` (le sol n'est jamais
  coupé par les plans proche / lointain, seulement derrière l'œil). À reprendre pour tout objet dessiné
  près de l'œil au branchement (cockpit : profondeur logarithmique avec la même formule).
- **Relief** (`ArbreLumiere::octave`) : octaves 17 à 25 = cailloux (au plus un par cellule, 8 cellules
  voisines, bosse aux bords raides, `caillou()`), teinte par caillou dans `couleur_sol` ; au-delà, le grain
  du sable. Bornes : valeur entre −1,5 et 1,5 × amplitude (rayon englobant et `relief_max` × 1,5).
- **Horizon de chaque coin** (`lumiere_coin`) : 4 azimuts (est = Y × verticale, nord, ouest, sud,
  `repere_lieu`, le même dans le shader), marche à 2, 4, 8, 16 fois l'écart des coins puis ×4 jusqu'à
  60 km. À chaque pas, 6 octaves (taille de la distance) calculées pour de vrai, les plus grandes suivent
  leur pente au coin (différences finies déjà faites pour la normale), les plus petites ignorées ; courbure
  −D²/2R. Ne dépend pas du Soleil. Rangé sur 2 texels de plus par coin (5 au lieu de 3 : départ + visé,
  code 0,5 + 0,5 signe(x)√|x|, x = h/90°), glisse comme les couleurs. Shader et posemètre :
  `part_horizon` / `part_sous_horizon` = mélange des 4 valeurs (cos², sin²), bord adouci sur
  2 × (rayon apparent + 0,005 rad).
- **Coût** : éclairer ≈ 3× plus cher par morceau (cloud, 4 fils : 0,06 → 0,14-0,24 ms). Le budget de
  3 ms par image ne change pas : la planète s'affine plus lentement après un saut. Si trop lent sur le PC :
  bande de 5 octaves au lieu de 6, ou 3 pas ×2 au lieu de 4.
- `project.godot` : rien à changer (le tri des ombres de Godot râlait seulement quand le plan proche
  était minuscule ; corrigé par la règle ci-dessus).
- Points de vue : L (10) loupe 3 cm, Soleil à 12° ; G (11) descente exponentielle 1 500 km → 3 cm en 40 s.
- Pas encore : rebonds (ombres noires), ombres projetées plus fines que 4 azimuts, lune : sa rotation est
  un `Basis` 32 bits (≈ 1 cm d'erreur au sol de la lune).

## Branchement dans le jeu (étape 8)
- `scripts/lumiere/` est copié TEL QUEL dans le jeu (`scripts/lumiere/`), un test du jeu compare les md5.
  On change toujours le labo d'abord, on importe le labo (pour ses .uid), puis on recopie.
  Le jeu reçoit aussi la section `[shader_globals]` du `project.godot` du labo (à recopier si elle change).
- Nouveaux fichiers : `objets.gd` (convertit les matières du modèle Blender, posemètre du cockpit par
  rayons dans un PhysicsServer3D à part, `percer_ombre` pour la coque sous la verrière), `objet.gdshader` /
  `objet_double.gdshader` + `objet_commun.gdshaderinc` (tout l'éclairage dans `light()` : le
  DirectionalLight de Godot ne sert qu'à l'ombre, ALBEDO = 1, résultat passé par l'œil dans
  DIFFUSE_LIGHT ; passe d'ombre reconnue par `PROJECTION_MATRIX[3][3] > 0.5`), `vitre.gdshader` (reflet
  du Soleil seulement), `lampes.gdshaderinc` (2 lampes en candelas, aussi sur la planète),
  `objets.gdshaderinc` (profondeur log, lumière renvoyée par la planète). `oeil_filtre` = visière.
- Côté jeu : `scripts/lumiere_jeu.gd`. Le DirectionalLight reste TOUJOURS allumé (sinon `light()` n'est
  plus appelée et tout devient noir la nuit) ; la nuit, c'est `objets_soleil_visible` = 0.
- Coût mesuré dans le cloud : environ 8 ms par image pour la lumière (planète 1-7 ms, posemètre 2-5 ms).
- Pas encore : ombre du vaisseau sur le sol, ombres de la planète et de la compagne dans le cockpit,
  lune absente du jeu, planète qui ne tourne pas, rebonds.

## Reflets (étape 9)
- `scripts/lumiere/reflets.gd` + `reflets.gdshaderinc`. Trois sources, toutes tirées des rayons :
  1. **Carte du ciel** `ArbreLumiere.carte_ciel(camera, rotation, w, h, soleil, e, occulteur, angle)` (C++) :
     tous les rayons affichés rangés par direction vue de l'œil (longitude-latitude 64 × 32, repère
     d'affichage, u = atan2(x, −z)/2π + 0,5, v = acos(y)/π), rgb = luminance, a = part couverte (boule,
     3 × 3 directions par case) ; cases vides de l'astre = moyenne des voisines, sinon Lambert. Au-delà
     de 6 000 rayons, un sur 2…16 par morceau. Lumière d'un rayon = `eclairage_rayon` (commun avec le
     posemètre, refactorisé sans changer les résultats). Refaite une image sur 6 (`CIEL_TOUTES_LES`),
     ≈ 1-2,5 ms. `reflets.mettre_a_jour_ciel([astres du plus proche au plus lointain])` : le plus proche
     cache l'autre. Texture prémultipliée RGBAH avec mipmaps (flou des surfaces rugueuses).
  2. **Sonde du cockpit** (32 × 16, repère du vaisseau, depuis l'œil) : `objets.luminance_vue_couleur`
     (rayons PhysicsServer3D, ombre du Soleil comprise), 48 cases par image (tout refait en 11 images,
     0,3 ms). Lue avec correction de parallaxe sur une boule de 0,9 m (`reflets_rayon_sonde`).
  3. **Visière** : global `oeil_reflet_visiere` ajouté APRÈS le filtre dans `oeil_vers_ecran` : voile =
     reflet de la face intérieure (claire 9,8 %, or ≈ 55/46/28 %) × visage (albédo moyen 0,2) éclairé
     à travers la visière ((1 + devant·s)/4 du Soleil si la coque ne le cache pas + la moitié du reste).
- **Verrière** (`vitre.gdshader`) : lame d'acrylique n = 1,49, R1 de Schlick, renvoyé 2R/(1+R), transmis
  (1−R)/(1+R). Elle lit l'écran derrière elle (`hint_screen_texture`), le ramène en luminance
  (`reflets_ecran_vers_luminance`, inverse de la vision de jour), applique la transmission, ajoute le reflet,
  et renvoie `fond + œil(après) − œil(avant)` (les erreurs d'inversion s'annulent). Attention : ne pas
  nommer un uniform `ecran` (conflit avec la variable de `oeil_vers_ecran`).
- **Objets** (`objet_commun.gdshaderinc`) : reflet de l'entourage (cockpit + planète, sans les disques :
  le Soleil est déjà dans `light()`) × approximation de Karis 2014 (Fresnel moyenné GGX), flou = mipmap
  selon la rugosité ; **rebond** dans le cockpit = π × sonde très floue vue selon la normale (nul au-delà de 4 m).
- Globals ajoutés (labo ET jeu) : `oeil_reflet_visiere`, `reflets_ciel`, `reflets_cockpit` (sampler2D),
  `reflets_base` (mat3), `reflets_rayon_sonde`, `reflets_actifs`.
- Pas encore : reflets des étoiles une à une (trop faibles : Sirius reflété ≈ magnitude 2), image fantôme du
  Soleil dans la visière (reflet du disque par la face intérieure), éblouissement (halo) causé par le Soleil
  reflété dans la verrière, sonde en vue extérieure (elle se refait depuis la caméra, 11 images de retard),
  rebonds sur la planète (Q38 : ombres du sol encore noires), lune absente du jeu.

## Suite du programme (après l'étape 9) : rebonds, ombre du vaisseau au sol, sol en pente
- **Double conversion sRGB (correctif)** : dans `light()`, Godot (Compatibilité) reconvertit DIFFUSE_LIGHT en
  sRGB à la fin (`linear_to_srgb` de drivers/gles3/shaders/scene.glsl : 1,055 v^(1/2,4) − 0,055), alors
  qu'il ne le fait pas pour ALBEDO d'un « unshaded » (il le défait d'abord). Vérifié : DIFFUSE_LIGHT 0,5 →
  0,737 à l'écran. Tout ce qui passait par `light()` (vaisseau, cockpit depuis l'étape 8) était donc délavé,
  ombres grises. Toujours écrire `DIFFUSE_LIGHT = oeil_vers_lumiere_godot(...)` (oeil.gdshaderinc), jamais
  `oeil_vers_ecran` dans `light()`. Un test du labo le vérifie.
- **Rebonds (Q38)** : `rebond()` dans planete.gdshader = `ArbreLumiere::rebond_lieu` en C++ (posemètre et carte
  du ciel, via `eclairage_rayon` qui rend direct + rebond). Le sol autour, plat et éclairé, reçoit
  E × sin(hauteur de l'étoile) ; le lieu en voit F = (1 − cos penché)/2 + (1 − longueur) + ½ × moyenne
  des sin²(horizon) ; somme des rebonds 1/(1 − ρF). Pas d'ombre de relief sur le rebond. Test : `ArbreLumiere.rebond(...)`
  (méthode statique pour les tests).
- **Ombre du vaisseau sur le sol** : planete.gdshader n'est plus « unshaded » : le Soleil direct est ajouté
  dans `light()` × ATTENUATION (ombre de la seule lumière de Godot). VERTEX/NORMAL posés en fin de vertex
  (repère de la vue) : Godot y cherche l'ombre. Coût : la planète est dessinée deux fois (Godot dessine une
  lumière avec ombre dans une passe de plus). Le labo a un DirectionalLight SANS ombre (sinon light() n'est
  jamais appelée → planète noire). Jeu : ombres en 2 zones (0-20 m, 20-200 m), effacement de 160 à 200 m
  (au-delà de ~170 m, le cœur de l'ombre d'un fuselage de 1,6 m disparaît : Soleil de 0,53°). Les pièces
  « cacher_en_vue_cockpit » passent en SHADOWS_ONLY en vue cockpit (leur ombre reste au sol).
- **Sol en pente (physique du jeu)** : chaque point du train prend le sol sous lui et sa pente
  (`normale_sol`, différences de ±25 cm) ; frottement « accroché » (ressort de côté 100 kN/m, limité à
  0,5 × la poussée du sol) : le vaisseau ne glisse plus doucement sur une pente ; la roue avant roule
  librement dans l'axe. Le sol peut tourner (`omega_planete`, `angle_planete`, relief donné dans le repère
  de la planète). Constat : train arrière étroit (84 cm), ressorts souples, centre de gravité à 1,55 m :
  le vaisseau se couche dès ~3,5° de pente de côté.

## Organisation
| Chemin | Contenu |
|---|---|
| `project.godot` | Projet « Labo lumière », rendu Compatibilité, 1280×720 |
| `LISEZMOI.md` | Pour Gwenaël : quoi ouvrir, quelles touches |
| `scenes/labo.tscn` | Scène principale (planète, Soleil, caméra libre au fil des étapes) |
| `scenes/mesure.tscn` | Mesure de vitesse (créée à l'étape 2) |
| `scenes/tests.tscn` | Tests automatiques |
| `scripts/lumiere/` | Le système lui-même (`orbite.gd` : lune et retard de la lumière, étape 5 ; `etoiles.gd`, `etoile_proche.gd`, `etoiles.gdshader`, `etoiles_yale.bin` : étape 6). Ne charge RIEN en dehors de ce dossier (un test le vérifie) : il sera copié tel quel dans le jeu à l'étape 8 |
| `scripts/outils/` | Outils du labo (compteur…) |
| `scripts/tests/` | Les tests |
| `shaders/` | Programmes de la carte graphique propres au labo (`astre_essai.gdshader` = boule de secours sans C++) |
| `donnees/` | Outil de conversion du catalogue d'étoiles (ignoré par Godot) |
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
