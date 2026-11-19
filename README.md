# jeu-spatial
Un jeu a la première personne dans l'espace , avec un physique réaliste.

Moteur : Godot 4.7 (rendu Compatibilité). Dossier de référence du projet : `docs/dossier-jeu-spatial.md`.

Version réunie le 18/11/2026 : le vaisseau v25 (cockpit détaillé, droïde R-7, pilote automatique, fait
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
| temps ×1, ×10, ×100, ×1000, ×10 000, ×100 000 | 1 2 3 4 5 6 | croix directionnelle gauche / droite (moins / plus vite) |
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
- Vaisseau de 10 t, corps rigide à 6 degrés de liberté (masse, inertie, couples).
- 5 moteurs arrière de 200 kN (chacun seul pousse 2 fois le poids ; ensemble, 10 g d'accélération),
  chacun à sa vraie position. 12 petits propulseurs d'orientation de 6 kN (le roulis n'est possible
  qu'avec eux).
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
  Pas encore : gravité d'Einstein (étape B), trou de ver (étape C).
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
  au plus 132 kN sans faire basculer le vaisseau (il pèse 98 kN au sol) : de quoi décoller et se poser
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

## Organisation
- `scripts/physique/vaisseau_physique.gd` : toute la physique (indépendante de l'affichage).
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
- `shaders/` : surface de la planète et ciel étoilé.
