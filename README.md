# jeu-spatial
Un jeu a la première personne dans l'espace , avec un physique réaliste.

Moteur : Godot 4.7 (rendu Compatibilité). Dossier de référence du projet : `docs/dossier-jeu-spatial.md`.

Version réunie le 18/11/2026 : le vaisseau v25 (aujourd'hui modèle v27, roues arrière freinées ; cockpit détaillé, droïde R-7, pilote automatique, fait
sur le PC) avec le système de lumière (étapes 0 à 9, fait dans le cloud). Le droïde a besoin de deux
choses qui ne sont pas dans le dépôt (trop lourdes) : l'extension `addons/nobodywho` et le dossier `ia/`
(modèles Qwen3-0.6B et LFM2.5-350M). Sans elles, le jeu marche, R-7 dit seulement qu'il est hors ligne.

## Ouvrir le projet
1. Lance Godot 4.7.
2. Dans le gestionnaire de projets : **Importer**, puis choisis le fichier `project.godot` de ce dossier.
3. Appuie sur **Lecture ▶** (en haut à droite) ou **F5**.

## Commandes
Toutes les commandes se changent dans le jeu : **F2** (ou **Options** sur la manette) ouvre l'écran
de configuration. On clique sur une case (ou on la choisit avec la croix directionnelle puis Croix),
puis on appuie sur la touche, le bouton ou le stick voulu. Les réglages sont sauvegardés tout de suite
(fichier `commandes.cfg` dans le dossier de sauvegarde de Godot) et rechargés à chaque partie.
Sticks et gâchettes sont analogiques : pousser à moitié demande la moitié.

Disposition par défaut :

| Action | Clavier | Manette (PS5) |
|---|---|---|
| plus / moins de poussée | Z / S | R2 / L2 |
| couper la poussée | Espace | Croix |
| tangage (nez en haut / en bas) | flèches haut / bas | stick gauche haut / bas |
| lacet (nez à gauche / à droite) | Q / D | L1 / R1 |
| roulis (pencher à gauche / à droite) | A / E | stick gauche gauche / droite |
| stabilisateur de rotation | T | Triangle |
| pilote auto : garder le cap | K | — |
| pilote auto : s'arrêter | N | — |
| pilote auto : atterrir | L | — |
| ouvrir / replier les ailes | X | croix directionnelle haut |
| sortir / rentrer le train d'atterrissage | G | croix directionnelle bas |
| freins des roues (au sol, maintenir) | Maj | — |
| vue cockpit / vue extérieure | V | pavé tactile |
| vol vertical (décollage / atterrissage) | F | bouton micro |
| zoom pour lire les instruments (maintenir) | B | L3 (enfoncer le stick gauche) |
| pause | P | Carré |
| cacher / montrer l'aide | H | Rond |
| recommencer / remettre en orbite | R / O | Créer |
| temps ×1, ×10, ×100, ×1000, ×10 000, ×100 000 ; loin des astres ×1 million, ×10 millions | 1 2 3 4 5 6 ; 9 0 | croix directionnelle gauche / droite (moins / plus vite) |
| puissance des moteurs : moins / plus (÷10 / ×10, de ×1 à ×100 000) | 7 / 8 | — (à choisir avec F2) |
| tourner la tête, ou la caméra en vue extérieure (le vaisseau ne bouge pas) | — | stick droit (lâché : la tête revient devant) |
| regarder droit devant | C | R3 (enfoncer le stick droit) |
| projecteur du vaisseau (allumer / éteindre) | J | — (à choisir avec F2) |
| visière du casque : relevée, claire, teintée | U | — (à choisir avec F2) |
| tête qui bouge avec les G (oui / non) | I | — (à choisir avec F2) |
| toile de l'espace : la courbure d'Einstein (oui / non) | Y | — (à choisir avec F2) |
| saut d'essai vers le trou noir Gaia BH1 | M | — (à choisir avec F2) |
| saut d'essai devant le trou de ver (vers Alpha du Centaure) | W | — (à choisir avec F2) |
| tests de physique | F1 (Échap pour revenir) | Rond pour revenir |
| configurer les commandes | F2 | Options |

## Ordinateur de bord (pilote automatique)
Il pilote avec les mêmes moteurs et propulseurs que le joueur : il calcule seulement les ordres
(gaz, tangage, lacet, roulis, et une petite force de côté). Toucher une commande de pilotage,
ou couper la poussée, le désactive.
- **Garder le cap (K)** : garde le nez dans la direction qu'il avait à l'activation, même lancé en rotation.
- **S'arrêter (N)** : annule la vitesse par rapport à la planète. Près d'une planète, il passe tout
  seul en vol vertical (la tuyère tourne vers le haut) et se penche, nez en haut, pour pousser contre
  sa vitesse : il ne se retourne jamais. La vitesse verticale et la vitesse horizontale s'annulent en
  même temps (le freinage le plus court). Si le vaisseau monte, il laisse la gravité freiner la montée.
  Il finit immobile, à plat, en vol stationnaire.
- **Atterrir (L)** : comme N, mais il descend ensuite : chute libre, puis freinage au dernier moment avec
  la poussée voulue pour arriver à 1 m/s, train sorti, et se pose à plat. Sous 400 m, il regarde le
  sol : si la pente dépasse 12° (le train en tient 24°), il va d'abord au-dessus de l'endroit assez plat
  le plus proche (jusqu'à 400 m), en restant à 60 m de haut, puis s'y pose. Il surveille la roue la plus
  basse (sur une pente, la roue côté montée touche en premier).
- **Urgence** : si le vol vertical ne peut plus éviter le sol (trop bas, descente trop rapide), il utilise
  un moment les gros moteurs, nez en haut, puis revient au vol vertical.
- **Temps accéléré** : le pilote calcule ses ordres au plus toutes les 0,04 s de temps de jeu, même à
  x1000. Il limite lui-même l'accélération du temps pendant une manœuvre (x100 au plus, x10 sous
  150 m, x1 sous 30 m) ; l'écran affiche « TEMPS x1000 (pilote auto : x100) ».

## Ce qui est simulé
- Vaisseau de 8,5 t (8 535 kg), corps rigide à 6 degrés de liberté (masse, inertie complète 3×3, couples).
  Depuis l'atelier (étape 1), le vaisseau est construit à partir de son **plan**
  (`vaisseaux/chasseur_v27.plan.json`) : la liste de ses pièces, chacune avec sa place, sa matière et sa
  masse. La masse, le centre de gravité et l'inertie sont recalculés à partir des pièces ; le rôle de
  chaque petit propulseur (tourner sur quel axe, ou glisser) est trouvé par le calcul de son couple.
- 5 moteurs arrière de 200 kN (chacun seul pousse 2,4 fois le poids ; ensemble, environ 12 g d'accélération),
  chacun à sa vraie position. 12 petits propulseurs d'orientation de 6 kN (le roulis n'est possible
  qu'avec eux) et 10 buses de 6 kN encastrées dans la coque (freiner, glisser, monter, descendre).
- Calcul automatique des poussées : on demande une poussée et une rotation, et le calcul choisit
  combien chaque propulseur pousse, d'après sa position (moteurs d'un côté plus forts que de l'autre,
  propulseurs d'orientation). Le vaisseau n'est jamais tourné directement.
- Relativité restreinte d'Einstein (étape A du programme « Einstein ») : on ne peut jamais atteindre la
  vitesse de la lumière. La physique suit la « vitesse propre » (γ·v) : le pilote sent toujours la même
  poussée, mais vue de la planète, la vitesse s'approche de c sans jamais l'atteindre. À petite vitesse,
  c'est exactement Newton. Deux horloges à l'écran : celle du pilote retarde quand il va vite (facteur γ)
  et, un tout petit peu, au fond d'un puits de gravité. Les vrais moteurs donnent 12 g (0,9 c en 43 jours
  du pilote) ; touches 7 / 8 : moteurs « imaginaires » jusqu'à ×100 000 (toujours de vraies forces, dont la
  part en plus passe par le centre de gravité). Le ciel (aberration, Doppler) suit la vraie vitesse.
  Étape A2 : planète et lune déformées par l'aberration et colorées par l'effet Doppler.
  Étapes B (gravité d'Einstein, trou noir) et C (trou de ver) : voir plus bas.
- Un repère par système d'étoile (étape A3) : le système du Soleil (la maison : planète, lune, Soleil,
  étoile compagne), Alpha du Centaure A et B (4,37 années-lumière) et Proxima du Centaure (4,25), à leur
  vraie place dans le ciel, avec leur vraie vitesse (32 km/s par rapport au Soleil). Le vaisseau compte
  toujours sa position depuis l'étoile du système où il est : ses nombres restent précis (0,03 mm à 1 UA
  d'Alpha du Centaure, au lieu de 8 m comptés depuis la maison). À mi-chemin entre deux systèmes, il passe
  dans le repère de l'autre par une transformation de Lorentz (position, heure et vitesse). Gravité de
  chaque système (étoiles, et désormais le Soleil et la compagne dans celui de la maison). Ligne REPÈRE à
  l'écran : système, étoile la plus proche, heure de la maison quand on est ailleurs. Entrer dans une
  étoile : le vaisseau brûle. Aller à Alpha du Centaure : puissance ×100 000 (touche 8), gaz à fond, temps
  ×100 000 (touche 6) : environ 25 minutes réelles (si le PC suit le rythme).
- Gravité de Newton calculée en permanence (planète de test : 600 km de rayon, 9,81 m/s² au sol).
- Gravité de plusieurs astres possible (somme des attractions) et petit couple dû au gradient de gravité :
  laissé seul en orbite, le vaisseau se balance lentement autour de la direction de la planète.
- Vaisseau dessiné d'après le modèle 3D (`modeles/vaisseau/`, exporté de Blender) : les 17 propulseurs
  de la physique sont exactement aux endroits dessinés. Les ailes se replient en 2,5 s et les propulseurs
  posés dessus tournent avec elles (le calcul des poussées en tient compte). Le train sort en 3 s.
  Posé sur le ventre, le train ne peut pas sortir (le sol bloque les jambes).
- Sol : rien n'est bloqué « par magie ». Chaque roue est au bout d'une jambe à ressort-amortisseur
  (idée des points de contact d'Orbiter) : l'amortisseur s'écrase (15 cm à l'avant, 12 cm à l'arrière,
  comme sur le modèle v20) et pousse sur le vaisseau, à l'endroit de la roue. Posé, ils s'écrasent
  d'environ 5 cm, et le modèle 3D les montre écrasés (ressorts compris). Le train encaisse un posé
  jusqu'à 4 m/s ; au-delà l'amortisseur arrive en bout de course et casse. Train rentré, la coque
  (ventre, nez, queue) touche le sol : écrasé au-delà de 3 m/s. Le sol frotte et freine le glissement.
- Rouler au sol (étape 6) : au sol, le lacet tourne aussi la roue avant (jusqu'à 35° à l'arrêt, moins
  en roulant vite, comme les palonniers d'un avion : sinon un virage serré à grande vitesse ferait
  basculer le vaisseau). Depuis le modèle v27, les patins arrière sont remplacés par de vraies roues
  freinées (2,37 m l'une de l'autre). Maj serre les freins des trois roues. C'est le sol qui pousse sur
  les roues : la force ne dépasse jamais l'adhérence des pneus (0,8 × la force qui appuie). Le vaisseau
  roule droit tout seul (train tricycle, comme un avion : plus de tête-à-queue), freine en 4 m depuis
  8 m/s, et roule presque librement sans frein. Frein de parc automatique : posé, presque arrêté
  (moins de 0,3 m/s) et gaz à zéro, les freins se serrent tout seuls ; ils se desserrent quand on remet
  les gaz. Le stabilisateur (T) aide encore au sol (propulseurs + roue avant).
- Temps accéléré près du sol : x100 au plus (au sol, chaque pas est découpé en morceaux de 1/240 s pour
  les ressorts du train ; plus vite, le jeu se figeait). L'écran l'indique : « trop près du sol ».
- Ombre du vaisseau : sur le sol de la planète ET sur celui de la lune (sous 400 m) ; les montagnes de
  la lune peuvent aussi cacher le Soleil au vaisseau.
- Vue cockpit (caméra à l'œil du pilote) ou vue extérieure (caméra qui tourne autour du vaisseau) ;
  l'intérieur du cockpit n'est affiché qu'en vue cockpit.
- Lueurs des moteurs (modèle v19/v20) : chaque sortie s'allume selon la VRAIE poussée de son moteur
  (éteinte à 0, bleue à faible puissance, violette à pleine puissance), avec un jet de lumière dont la
  longueur suit la poussée.
- Vol vertical (F) : deux moteurs de levage de 37,5 kN sortent du ventre à l'avant (trappes puis vérin),
  puis la tuyère du moteur central tourne vers le bas (4 s en tout). Les gaz poussent alors vers le haut,
  au plus 211 kN sans faire basculer le vaisseau (il pèse 84 kN au sol) : de quoi décoller et se poser
  à la verticale. Tout vient de la poussée réelle des moteurs, à leur vraie place.
- Cockpit fonctionnel : levier des gaz (et ses 8 voyants), manche et pédales suivent les commandes ;
  interrupteurs (train, ailes, stabilisateur, couper les gaz) et boutons (temps, pause, vue, aide,
  commandes, remettre en orbite, poignée rouge pour recommencer) bougent quand on les actionne, et on
  peut aussi cliquer dessus à la souris. Les 5 écrans affichent en direct : radar des astres (position,
  distance), état du vaisseau, vitesses / altitude / G, temps, orbite. En vue cockpit, le texte en
  surimpression est caché : tout est sur les écrans.
- **Système de lumière** (étape 8, copié du labo `labo-lumiere/`) : vrai Soleil (environ 127 000 lux),
  planète dessinée en rayons avec son relief (le vaisseau se pose sur ce relief), étoiles réelles, étoile
  compagne, ombres du vaisseau dans le cockpit. L'œil du pilote s'habitue à la lumière comme un vrai œil
  (la nuit, la lampe du cockpit s'allume seule). Casque et visière (touche U), projecteur (J), tête qui
  bouge de quelques centimètres sous les G (I). Si la partie C++ manque, le jeu reprend l'ancien affichage.
  Étape 9 : reflets de la verrière et de la visière (loi de Fresnel), du cockpit, de la planète et du
  Soleil ; les métaux reflètent leur entourage et la lumière rebondit dans le cockpit.
  Vaisseau v25 : écrans, voyants, lueurs et jets des moteurs passent aussi par la lumière (vraie
  luminance en cd/m², vue par l'œil). En vue extérieure, pas de visière (la caméra n'est pas dans le casque).
- **Gravité d'Einstein** (programme Einstein, étape B) : la gravité n'est plus une force mais la courbure de
  l'espace-temps (solution exacte de Schwarzschild pour chaque astre). Le vaisseau suit le chemin le plus droit
  de cet espace courbé : à petite vitesse et loin des trous noirs c'est Newton, près d'un astre dense les
  orbites tournent (avance du périhélie), la lumière est déviée deux fois plus que selon Newton, le temps
  ralentit (ligne EINSTEIN des instruments). Vrai trou noir : Gaia BH1 (9,27 Soleils, à 1 560 années-lumière,
  avec son étoile jumelle du Soleil) ; touche M = saut d'essai en orbite à 50 000 km. Près de lui, le ciel est
  vraiment courbé : ombre noire, étoiles repoussées, deux images de chaque étoile, anneau d'Einstein (calcul
  des rayons à l'envers, `scripts/physique/lentille.gd`). L'étoile jumelle éblouit l'œil comme le Soleil : pour
  voir les étoiles courbées, il faut que l'œil s'habitue au noir (sans casque, cockpit à l'ombre). Touche Y :
  la « toile de l'espace », l'entonnoir de Flamm (vraie forme de l'espace autour de l'astre), exagéré quand il
  est trop petit pour être vu (le facteur est affiché), couleur = ralentissement du temps. Passer l'horizon du
  trou noir : on ne revient pas (R pour recommencer).
- **Trou de ver fixe** (programme Einstein, étape C) : un trou de ver d'Ellis (celui d'Interstellar, gorge de
  1 km de rayon) relie un point à 20 000 km de la planète à Alpha du Centaure (à 1,25 UA de son étoile A).
  Il n'attire rien (pas de gravité) : seul l'espace est courbé. Le vaisseau y suit le chemin le plus droit, et ce
  chemin peut passer par la gorge : on ressort 4,37 années-lumière plus loin, avec la même vitesse. Passé à côté,
  il est dévié exactement comme la lumière. Touche W = saut d'essai à 30 km de la gorge, nez vers elle : mettre
  les gaz. Dans la gorge, on voit le ciel d'en face (Alpha du Centaure A au centre quand on est dans l'axe),
  autour, notre ciel déformé et un anneau brillant (la lumière qui a tourné autour de la gorge). Angles de la
  lumière calculés exactement en C++ (intégrales elliptiques, `TrouDeVer`, 0,4 ms quand l'œil bouge).
- **Atmosphère** : la planète a un air comme celui de la Terre (même gravité au sol), calculé avec l'atmosphère
  type de 1976 ; sa gravité baisse plus vite en montant (planète 10 fois plus petite), donc son air monte un peu
  plus haut. L'air tourne avec la planète. Tout passe par de vraies forces, chacune à son endroit
  (`scripts/physique/aerodynamique.gd`) : les 4 ailes (3 bandes chacune, mesurées sur le modèle), les 2 dérives,
  le fuselage (de face, de travers, nez effilé), le train sorti. Portance et traînée changent avec la vitesse
  du son (Mach), l'angle, et l'air très rare de la haute altitude. Ailes en X : le vaisseau est stable en
  tangage, presque neutre en lacet (le stabilisateur T aide). Le nez chauffe à la rentrée (loi de
  Sutton-Graves, rayonnement de la coque) : la température est affichée (ligne COQUE), et la coque rougeoie.
  Dans l'air épais, le temps accéléré est limité (les pas de calcul doivent rester courts). L'orbite de départ
  est à 250 km (à 100 km, l'air la ferait retomber en une heure). Ciel dans le système de lumière
  (`scripts/lumiere/atmosphere.gdshaderinc`) : ciel bleu, aube et coucher orangés, Soleil rouge à l'horizon,
  brume sur le sol lointain, liseré bleu de la planète vue de l'orbite, étoiles atténuées ; le vaisseau reçoit
  un Soleil filtré par l'air et la lumière bleue du ciel.
- Pas de carburant.
- Marqueurs : (o) = direction où l'on va, (x) = direction d'où l'on vient.

## Son (phase 1 du moteur audio)
Un casque est conseillé. On n'entend **que le cockpit**, jamais l'espace : le cockpit est plein d'air
(pressurisé), et les sons du dehors n'y arrivent qu'en faisant vibrer la coque et la verrière. Le son ne fait
que **lire** la physique, il ne la change jamais (un test le vérifie). Tout est calculé, rien n'est enregistré.
- **Dans le vide** : seul ce qui passe par la structure arrive. Grondement des moteurs (son énergie suit la force
  au carré, il perd 1 dB par mètre de structure et 6 dB à l'emplanture d'une aile) ; souffle des petits
  propulseurs ; claquement de leurs vannes quand elles s'ouvrent et se ferment ; « coup » d'un moteur qui
  s'allume ou se coupe (plusieurs variantes, jamais deux fois la même de suite).
- **Dans l'air**, en plus : le bruit des jets (loi de Lighthill : il suit la puissance du jet et la densité de
  l'air ; plus fort derrière le jet que devant ; en vol, le son remonte mal le vent, et plus du tout au-delà de
  Mach 1) et le **souffle** de l'air sur la coque (remous de la couche limite : modèle de Goody, énergie de
  Farabee et Casarella ; air lisse et presque muet à basse vitesse ou très haut ; rien quand l'air est trop rare).
  Tout passe par la paroi (loi de masse : elle arrête bien les aigus ; sa résonance vers 80 Hz fait gronder).
- **Volume** : on calcule le vrai niveau dans le cockpit (en dB), puis 107 dB = plein volume. Au-delà de 95 dB, le
  volume monte 4 fois moins vite (une poussée x100 000 ne fait pas exploser les oreilles).
- **Temps accéléré** : son normal jusqu'à x10, silence au-delà. Pause, écran des touches, vaisseau écrasé :
  silence en 0,1 s. En vue extérieure, on entend toujours le cockpit.
- 24 voix au plus (8 sons continus + 16 sons brefs), un son trop faible ou caché par un autre n'est pas joué.
  Calcul du son : environ 0,2 ms par image (ligne « son » du mode `--mesure`).
- Fichiers : `scripts/son/` (`moteur_audio.gd` = le chef d'orchestre, `capteurs.gd` = le seul qui lit la
  physique, `moteurs_son.gd`, `fluides_son.gd`, `sol_son.gd`, `chocs.gd`, `egaliseur.gd` = l'égaliseur de Godot
  refait en calcul pour que le volume soit exact, `synthese.gd` = fabrication des boucles), `sons/` (boucles de secours).
- Refabriquer les sons (même graine = même son) :
  `godot --headless --path . --script res://outils/generateur_sons.gd`
- Tests du son : `godot --headless --path . res://scenes/tests_son.tscn`
- Extraits à écouter, sans lancer le jeu :
  `godot --headless --path . --script res://outils/extraits_son.gd -- <dossier>`

## Son (phase 2 : sons fabriqués en direct)
- Les sons continus (grondement des moteurs, souffle des petits propulseurs, souffle de l'air, bruit des jets) ne
  sont plus des boucles enregistrées : la partie C++ (`SyntheSon`, dans `labo-lumiere/cpp/src/synthe_son.cpp`) les
  fabrique **en direct** dans le fil audio de Godot, 48 000 fois par seconde. Le son ne se répète donc jamais, et sa
  couleur suit exactement le spectre calculé par la physique, dans 30 tiers d'octave (25 Hz à 20 kHz).
- Deux voix : **structure** (moteurs + petits propulseurs, par les panneaux du cockpit) et **air** (souffle + jets, par
  la verrière). 60 fois par seconde, `moteur_audio.gd` leur donne l'énergie voulue dans chaque bande ; le C++ y glisse
  doucement par blocs de 5 ms (jamais de marche d'escalier, donc pas de craquement). Le niveau qui sort = le niveau
  calculé (test, à 0,3 dB près).
- **Résonances des panneaux** (`scripts/son/resonances.gd`) : en grave, le plancher, les parois, le tableau de bord
  et la cloison arrière (aluminium de 2 à 3 mm) vibrent à leurs fréquences propres (plaques de Kirchhoff, perte
  1 %). Les 32 plus graves sont de petits résonateurs : ils mettent un peu de temps à monter et à s'éteindre, comme
  une vraie tôle. Plus haut (au-delà de ~300 Hz), elles se chevauchent et le son redevient un bruit lisse.
- Le grondement monte un peu en fréquence avec la poussée (comme la boucle de la phase 1 ; vrai modèle du moteur :
  phase 6), avec un léger battement de 2 à 10 Hz.
- Coût : environ 1 % d'un cœur du processeur (ligne « son fabriqué en direct » du mode `--mesure`).
- Tests : niveaux et couleur exacts, résonances, détecteur de craquements, **10 minutes de vol sans un seul
  craquement** (vide, sol, haute altitude, gaz coupés net, vannes, pause, x10, x100), et démarrages / arrêts dans le
  vrai fil audio.
- Ancienne version (boucles de la phase 1), en secours ou pour comparer : lancer avec `-- --son-boucles`
  (aussi pour l'outil des extraits). Sans la partie C++, le jeu reprend tout seul les boucles.

## Son (phase 3 : le sol, les chocs, les vannes, les vérins)
- **Tous les sons brefs sont fabriqués en direct** (demande de Gwenaël) : plus aucun fichier enregistré. Pour
  chaque choc, `scripts/son/chocs.gd` écrit la « recette » de la pièce frappée (ses fréquences propres, leur durée
  de résonance, leur force, les rebonds), et la partie C++ `ChocsSon` (`labo-lumiere/cpp/src/chocs_son.cpp`) la fait
  sonner dans le fil audio. 16 chocs à la fois au plus ; plein, le moins important s'éteint en 30 ms. Deux chocs
  ne sont jamais identiques (endroit frappé, pièce, force tirés à chaque fois).
- **Chocs par l'énergie** (idée de Gwenaël) : ce qui frappe a une masse et une vitesse ; la pièce frappée absorbe
  l'énergie ½ m v² en se déformant, et une part repart en son : +10 dB quand l'énergie est 10 fois plus grande. La
  matière donne le timbre (caoutchouc sourd, acier qui sonne, aluminium de la coque, roche) ; la vitesse donne la
  durée du contact (loi de Hertz : plus vite = plus bref = plus aigu).
- **Au sol** (« prises » ajoutées dans `_forces_sol`, en lecture seule : la physique ne change pas, un test le
  vérifie) : pneu qui touche (et crisse s'il ne tournait pas), amortisseur en bout de course ou qui se détend,
  coque qui tape et qui racle, cailloux projetés par les roues, roulement des pneus (grave qui monte avec la
  vitesse), dérapage (crissement vers 1 kHz), freins (frottement, disque qui chante), clic des freins.
- **Vérins** : train, ailes, roue avant, tuyères : départ, pompe qui siffle et huile qui coule pendant la course,
  arrêt, verrou qui claque au bout (« clac-clac »).
- Vannes des petits propulseurs et allumage / coupure des moteurs : mêmes sons qu'avant, maintenant fabriqués
  en direct.
- 3 voix continues (structure, air, sol) + 16 chocs. Coût au pire (tout à pleine charge, `--mesure`) : environ
  2,5 % d'un cœur du processeur dans le cloud ; GDScript : environ 0,2 ms par image.
- Sans la partie C++ (ou avec `-- --son-boucles`) : pas de sons brefs ni de sons du sol, seulement les boucles.
- Extraits à écouter : `outils/extraits_son.gd` (extraits 5 à 7 : se poser et freiner, train et ailes, sur le ventre).

## Son (phase 4 : la tension des pièces, la poussière de l'espace, le côté des sons)
- **Charges de chaque pièce** (`scripts/son/charges.gd`, 120 fois par seconde, lecture seule) : 16 attaches (ailes,
  réacteurs, moteur central, dérives, jambes du train, verrière, nez), avec les vraies forces de la physique
  (principe de d'Alembert : moteurs, air, sol, gravité de marée, rotation). La résistance de chaque pièce vient des
  cas de calcul des avions (ressource à 9 g, pleine poussée x1,25, posé à 3 m/s, cabine à 1,33 fois sa pression…)
  × 1,5. Pleine poussée normale : 0,53 de la rupture pour les supports des réacteurs.
- **Craquements** (`scripts/son/tension_son.gd`, émission acoustique) : une pièce craque quand sa charge dépasse
  tout ce qu'elle a déjà connu (effet Kaiser). Chaque pièce a été « éprouvée » à 0,67 de sa rupture avant le premier
  vol : un vaisseau en bon état ne craque donc qu'en surcharge (moteurs x10, atterrissage plus dur que 3 m/s, air trop
  dense à trop grande vitesse). Aussi : relâchements (charge qui tombe d'un coup), tics de la coque qui chauffe ou
  refroidit (un tic par 1,5 degré), et « chant » de la structure quand la charge varie.
- **Poussière et gaz de l'espace** (`scripts/son/poussiere_son.gd`, idée de Gwenaël) : vrais grains (flux de Grün près
  du Soleil, grains de l'espace entre les étoiles), vent solaire, gaz entre les étoiles, et un nuage inventé autour de
  la planète. Chaque grain a sa masse et sa vitesse ; l'énergie (γ − 1) m c² devient du son sur la verrière ou la
  coque. En orbite : de rares « tic » ; à 0,5 c : une pluie ; à 0,9 c : un souffle continu et quelques gros coups.
- **Côté des sons** (`scripts/son/cote_son.gd`, demande de Gwenaël) : chaque moteur, chaque petit propulseur et
  chaque pièce qui chante a sa place. Le son arrive par la coque, depuis le point de fixation : les parois de son côté
  vibrent plus fort, la tête fait de l'ombre à l'autre oreille dans les aigus, un son venu de derrière perd un peu
  d'aigus. La partie C++ donne à chaque tiers d'octave sa part à gauche. Si le pilote tourne la tête, le son reste
  à sa place dans le cockpit. Les sons brefs aussi.
- Extraits à écouter : 8 à 16 (virage serré, montée hors de l'air, coque qui refroidit, orbite, 0,5 c, 0,9 c,
  propulseur gauche puis droite, moteurs x10, atterrissage dur).

## Son (phase 5 : l'air en détail)
Tout est dans `scripts/son/air_son.gd` ; la physique n'est que lue (nouvelles « prises » en lecture seule dans
`aerodynamique.gd` : angle d'attaque, vitesse, surface et corde de chaque bande d'aile et de chaque dérive, part
« molécules isolées » de l'air).
- **Le train qui siffle** : derrière chaque jambe, l'air se détache en tourbillons à f = 0,2 × U / D (Strouhal) ; la
  force qui va et vient rayonne comme un petit haut-parleur (loi de Curle, coefficients mesurés en soufflerie selon le
  nombre de Reynolds : sifflement pur à petite vitesse, souffle grave après la « crise de traînée »). Les roues font
  un souffle plus grave. Son pur dans la voix air (il tremble un peu).
- **Les trappes qui grondent** : au-dessus d'un puits ouvert, l'air ondule et résonne aux fréquences de Rossiter
  (puits de 1 m à 100 m/s : 37 et 85 Hz). Puits du train et des moteurs de levage.
- **Tremblement transsonique** (Mach 0,75 à 1,3) : le choc va et vient sur les ailes qui portent, ~9 fois par
  seconde (balancement au hasard) ; il passe par l'emplanture, donc on l'entend du côté de l'aile qui tremble.
- **Décrochage** : au-delà de ~15°, chaque bande d'aile décroche avec SON air (en roulis, une seule aile peut décrocher :
  on l'entend de son côté).
- **Onde de choc sur la verrière** (au-delà de Mach 1,1, rentrée) : le petit décollement d'air devant la verrière bat ;
  une coque chaude épaissit la couche d'air, le grondement devient plus grave.
- **Fondu vers le silence** : tout s'efface avec la part « fluide » de l'air (la même que la physique). Les molécules
  isolées ne s'entendent pas (calculé : moins d'un milliardième de newton sur 1 m² de coque).
- Réglages à valider à l'écoute : chemin par la structure des ailes (−25 dB), double paroi sous le ventre (−15 dB).
- Extraits à écouter : 17 à 21 (train qui sort, transsonique, décrochage puis aile gauche, Mach 2, rentrée).

## Son (phase 6 : l'intérieur des moteurs ioniques)
Un **modèle inventé, pour le son seulement** (`scripts/son/ionique_son.gd`) : la physique ne connaît que la poussée
de chaque moteur ; il n'y a ni carburant ni pièce en plus. On donne au vaisseau un petit « intérieur » de moteur à plasma
façon Star Wars (jet de 3 000 m/s), qui suit de vraies lois là où elles existent :
- **Le réacteur qui bourdonne** (derrière le pilote) : 110 Hz et ses harmoniques (le fer des transformateurs s'allonge
  deux fois par période). Un peu au repos, plus fort quand les moteurs tirent (2,3 GW pour les cinq à fond : ½ F v
  ÷ 65 %), et un peu plus grave (−3 %) ; il creuse un instant quand on remet les gaz, remonte quand on coupe.
- **Les bobines qui sifflent** : pour pousser plus fort, il faut un champ plus fort (B ∝ √poussée) ; l'onduleur suit le
  courant, les bobines vibrent au double : un sifflement qui monte avec √poussée (2,4 kHz à fond, levage plus aigu).
  Chaque moteur a le sien, réglé à quelques millièmes près : ils battent doucement entre eux. Le champ part AVANT la
  poussée (0,12 s) ; à la coupure, le courant s'écoule en 0,9 s : le sifflement redescend en glissant.
- **La chambre à plasma qui gronde** : le gaz s'ionise par vagues (« respiration » des propulseurs de Hall,
  √(v_gaz × v_ions) / 2πL ≈ 190 Hz). Les parois chauffent en quelques secondes : le grondement monte lentement (×1,4)
  et redescend quand le moteur refroidit. Le grondement large des moteurs (phase 1) suit la même hauteur.
- **Allumage détaillé** : « clac » du contacteur (il rebondit), sifflement qui part du grave, puis « whoomp » du plasma
  avec ses étincelles et sa bouffée de gaz ~40 ms après ; à la coupure, le contacteur se rouvre quand le champ est
  retombé (avec un petit arc).
- Chaque son garde son côté (moteur d'aile gauche à gauche, réacteur au milieu derrière) : la partie C++ donne
  maintenant un côté à chacun de ses 24 sons purs (`SyntheSon.regler_raies`). Un son pur qui tombe sur une résonance
  d'un panneau du cockpit sonne plus fort (`Resonances.reponse`).
- Le modèle avance au rythme de la physique (rien en pause, ×10 en temps accéléré). Niveaux réglés « à l'oreille ».
- Extraits à écouter : 22 à 26 (allumage puis coupure, paliers de poussée, aile gauche puis droite, chambre qui
  chauffe, vol vertical).

## Organisation
- `scripts/physique/vaisseau_physique.gd` : toute la physique (indépendante de l'affichage). Elle ne connaît
  que des lois : le vaisseau lui-même vient de son plan.
- `scripts/atelier/` : le plan d'un vaisseau (`plan.gd` : lecture, vérification, sous-ensembles, masse,
  centre de gravité, inertie) et le catalogue des matières et des types de pièces (`catalogue.gd`).
  `vaisseaux/` : les plans (celui du chasseur de départ). `outils/plan/` : comment refaire le plan à
  partir du modèle Blender. `scripts/tests_atelier.gd` : ses tests (`res://scenes/tests_atelier.tscn`).
- `scripts/physique/atmosphere.gd` et `aerodynamique.gd` : l'air de la planète et ce qu'il fait au vaisseau.
- `scripts/physique/reperes.gd` : les systèmes d'étoile, leurs repères et les transformations de Lorentz entre eux.
- `scripts/physique/lentille.gd` : Einstein B, la lumière courbée par un trou noir (tables pour le ciel et les étoiles).
- `scripts/einstein/toile.gd` : Einstein B, la « toile de l'espace » (touche Y).
- `scripts/physique/trou_de_ver.gd` : Einstein C, le trou de ver (trajet du vaisseau, lumière, touche W) ; calcul de la lumière en C++ (`labo-lumiere/cpp/src/trou_de_ver.cpp`).
- `scripts/jeu.gd` : affichage (modèle 3D, vues, animation des ailes et du train), instruments.
- `modeles/vaisseau/` : le vaisseau (`vaisseau_exterieur.glb`), le cockpit (`cockpit.glb`) et les positions
  des propulseurs. Pour une nouvelle version du modèle, il suffit de remplacer ces fichiers (mêmes noms).
- `scripts/commandes.gd` : touches du clavier et de la manette (disposition par défaut, sauvegarde).
- `scripts/ecran_touches.gd` : l'écran de configuration des commandes (F2).
- `scripts/lumiere/` : le système de lumière, copie exacte de `labo-lumiere/scripts/lumiere/` (un test le vérifie : on le change dans le labo, puis on recopie).
- `scripts/lumiere_jeu.gd` : branche le système dans le jeu (Soleil, planète, lampes, visière, posemètre de l'œil).
- `scripts/tests_physique.gd` : les tests automatiques (F1).
- `scripts/son/`, `sons/`, `outils/` : le son (voir « Son » plus haut) ; `scripts/tests_son.gd` : ses tests.
- `shaders/` : surface de la planète et ciel étoilé.
