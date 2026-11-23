# Écrit le PLAN du chasseur v27 (vaisseaux/chasseur_v27.plan.json) à partir de :
#   - outils/plan/masses_pieces_v27.json : masse, centre et inertie propre de chaque pièce du modèle Blender
#     (écrit par outils/plan/extraire_masses_blender.py) ;
#   - la description du vaisseau qui était écrite « en dur » dans scripts/physique/vaisseau_physique.gd et
#     scripts/physique/aerodynamique.gd jusqu'à l'atelier, étape 1 (moteurs, propulseurs, ailes, train,
#     plaques d'air), recopiée ici À L'IDENTIQUE : le vaisseau se comporte comme avant.
# Lancement : python outils/plan/composer_plan_v27.py  (depuis le dossier du projet ; Python 3 seul suffit)
#
# Le plan est écrit dans sa POSE DE RÉFÉRENCE : ailes ouvertes, train rentré, vol normal (tuyère droite,
# moteurs de levage rentrés). Repère de Godot : −Z = avant, +Y = haut, +X = droite, mètres.
import json, math, os, re

ICI = os.path.dirname(os.path.abspath(__file__))
PROJET = os.path.dirname(os.path.dirname(ICI))
MASSES = os.path.join(ICI, "masses_pieces_v27.json")
ANCIEN_JSON = os.path.join(PROJET, "modele3d", "v27_roues_arriere", "masses_godot.json")
SORTIE = os.path.join(PROJET, "vaisseaux", "chasseur_v27.plan.json")

MATIERES = {   # noms du modèle Blender → matières du catalogue (scripts/atelier/catalogue.gd)
    "composite fibre de carbone (ailes)": "composite_carbone",
    "alliage aluminium-lithium (coque, trappes)": "aluminium_lithium",
    "titane (tuyères, moteur, carters chauds)": "titane",
    "acier haute résistance (trains d'atterrissage)": "acier",
    "verre aluminosilicate feuilleté (verrière)": "verre_aluminosilicate",
    "aluminium (habillage du cockpit)": "aluminium",
}
# pièces mobiles du modèle Blender → articulation du plan (le premier ancêtre trouvé l'emporte)
ARTICULATION_DE = {
    "Charniere_haut_gauche": "aile_haut_gauche", "Charniere_haut_droit": "aile_haut_droit",
    "Charniere_bas_gauche": "aile_bas_gauche", "Charniere_bas_droit": "aile_bas_droit",
    "Pivot_tuyere_centrale": "tuyere",
    "Moteur_levage_gauche": "verin_levage_gauche", "Moteur_levage_droit": "verin_levage_droit",
}

# MODULES (atelier, étape 3) : le chasseur est découpé en morceaux qu'on choisit (et qu'on enlève) d'un seul
# coup dans l'atelier : une aile avec son réacteur, ses propulseurs et ses plaques d'air ; le canon avec ses
# munitions ; un propulseur avec sa buse… Chaque pièce porte le nom de son module (« module »).
MODULES = {
    "fuselage": "Fuselage et coque",
    "cockpit": "Cockpit",
    "aile_haut_gauche": "Aile haut gauche", "aile_haut_droit": "Aile haut droite",
    "aile_bas_gauche": "Aile bas gauche", "aile_bas_droit": "Aile bas droite",
    "moteur_central": "Moteur central et tuyère",
    "moteurs_levage": "Moteurs de levage",
    "canons": "Canons",
    "equipements": "Équipements de bord",
    "droide": "Droïde et son logement",
    "train_avant": "Train avant",
    "train_arriere_gauche": "Train arrière gauche", "train_arriere_droit": "Train arrière droit",
    "buses": "Buses encastrées",
}
for _p in ("nez_haut", "nez_bas", "nez_gauche", "nez_droit", "queue_haut", "queue_bas", "queue_gauche", "queue_droit"):
    MODULES["rcs_" + _p] = "Propulseur " + _p.replace("_", " ")

PREFIXES_MODULE = [   # début du nom de la pièce → module (le premier qui convient)
    ("Cockpit", "cockpit"), ("Ecran", "cockpit"), ("Levier", "cockpit"), ("Manche", "cockpit"),
    ("Pedale", "cockpit"), ("Poignee", "cockpit"), ("Verriere", "cockpit"), ("Masse_pilote", "cockpit"),
    ("Canons", "canons"), ("Masse_canons", "canons"),
    ("Moteur_central", "moteur_central"), ("Masse_moteur_central", "moteur_central"), ("Tuyere", "moteur_central"),
    ("moteur_central", "moteur_central"),
    ("Moteur_levage", "moteurs_levage"), ("moteur_levage", "moteurs_levage"), ("Masse_moteurs_levage", "moteurs_levage"),
    ("Puits_moteur_levage", "moteurs_levage"), ("Trappe_levage", "moteurs_levage"),
    ("Masse_avionique", "equipements"), ("Masse_survie", "equipements"), ("Masse_droide", "droide"),
    ("Emplacement_droide", "droide"),
    ("Jambe_avant", "train_avant"), ("Fourche_avant", "train_avant"), ("Roue_avant", "train_avant"),
    ("roue_avant", "train_avant"), ("Trappe_avant", "train_avant"), ("Puits_train_avant", "train_avant"),
    ("RCS_integres", "buses"), ("buse_", "buses"),
]


def module_de(p, rcs_points):
    """Module d'une pièce du chasseur."""
    id_ = p["id"]
    art = p.get("articulation", "")
    if art.startswith("aile_"):
        return art
    for cote in ("gauche", "droit"):
        if id_.endswith("arriere_" + cote) and not id_.startswith("coque_"):
            return "train_arriere_" + cote
    if id_.startswith("rcs_"):
        return id_
    if id_.startswith("RCS_") and id_ != "RCS_integres":
        # le dessin de chaque propulseur : le plus proche (les noms haut / bas du nez sont inversés dans le
        # modèle Blender, la position ne trompe pas)
        c = p["centre"]
        return min(rcs_points, key=lambda k: sum((a - b) ** 2 for a, b in zip(rcs_points[k], c)))
    for debut, m in PREFIXES_MODULE:
        if id_.startswith(debut):
            return m
    return "fuselage"


# ---------------------------------------------------------------------------------------------------
# Ailes (anciennes constantes AILES) : charnière parallèle à l'axe avant-arrière (axe Z), angle en
# degrés autour de +Z, de « replié » (commande 0) à « ouvert » (commande 1).
AILES = {
    "haut_gauche": ((-0.6, 0.0, 0.0), 0.0, -22.249),
    "haut_droit": ((0.6, 0.0, 0.0), 0.0, 22.249),
    "bas_gauche": ((-0.6, 0.0, 0.0), -180.0, -157.751),
    "bas_droit": ((0.6, 0.0, 0.0), 180.0, 157.751),
}


def rz(deg, v):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return (c * v[0] - s * v[1], s * v[0] + c * v[1], v[2])


def sur_aile(nom, p_charniere, d_charniere=None):
    """Point (et direction) donnés dans le repère de la charnière (ancien code) → repère du vaisseau, ailes ouvertes."""
    ch, _, ouvert = AILES[nom]
    q = rz(ouvert, p_charniere)
    p = (ch[0] + q[0], ch[1] + q[1], ch[2] + q[2])
    return (p, rz(ouvert, d_charniere)) if d_charniere is not None else p


def r(v, n=7):
    return [round(float(x), n) + 0.0 for x in v]


AVANT, HAUT, BAS, GAUCHE, DROITE = (0, 0, -1), (0, 1, 0), (0, -1, 0), (-1, 0, 0), (1, 0, 0)

# LA VIE À BORD (atelier, étape 8 : scripts/physique/vie_a_bord.gd). Volume d'air et rayons des parois mesurés sur
# le modèle 3D du cockpit par outils/plan/cabine_cockpit_v27.py. Les parois qui tiennent la pression : la vitre
# intérieure de la verrière (la vitre extérieure, « Verriere », protège du froid et des chocs ; l'air entre les deux
# communique avec le dehors), la baignoire du cockpit (plancher, flancs, tableau de bord) et le cadre de la
# verrière. « normale » : vers où part l'air si la paroi casse (la verrière s'envole vers le haut ; la baignoire
# est dans le fuselage : l'air s'y répand de tous les côtés, il ne pousse pas le vaisseau). « dessins » : les pièces
# qui dessinent la même paroi vue du dehors (l'atelier les colore avec elle). Réserves dans le
# système de survie (Masse_survie, 250 kg : air, eau, refroidissement) : 20 kg d'oxygène, 30 kg d'azote.
VIE = {
    "pression_kpa": 101.325,
    "recycleur": True,
    "cabine": {
        "nom": "cabine du pilote", "volume_m3": 3.6,
        "parois": [
            {"piece": "Cockpit_verriere", "nom": "verrière", "rayon_m": 0.731, "normale": [0.0, 1.0, 0.0],
             "surface_m2": 7.053, "centre": [0.0, 0.730663, -0.32763], "dessins": ["Verriere"]},
            {"piece": "Cockpit_interieur", "nom": "baignoire du cockpit", "rayon_m": 0.952, "normale": [0.0, 0.0, 0.0],
             "surface_m2": 26.3268, "centre": [0.0, -0.165991, -0.392151]},
            {"piece": "Cockpit_cadre", "nom": "cadre de la verrière", "rayon_m": 0.825, "normale": [0.0, 1.0, 0.0],
             "surface_m2": 1.9948, "centre": [0.0, 0.73473, -0.256098], "dessins": ["Verriere_cadre"]},
        ],
    },
    "survie": {"piece": "Masse_survie", "oxygene_kg": 20.0, "azote_kg": 30.0},
    "soutes": [],
}


def plan():
    masses = json.load(open(MASSES, encoding="utf-8"))["pieces"]
    ancien = json.load(open(ANCIEN_JSON, encoding="utf-8"))
    pieces = []

    # 1. Pièces qui pèsent : structures du modèle Blender (coques minces) et équipements (masses en un point)
    for nom in sorted(masses):
        m = masses[nom]
        art = ""
        for a in m["ancetres"]:
            if a in ARTICULATION_DE:
                art = ARTICULATION_DE[a]
                break
        centre = m["centre"]
        if m["forme"] == "point":
            if nom.startswith("Masse_reacteur_aile_") and max(abs(x) for x in centre) < 1e-6:
                # les 4 objets vides des réacteurs d'aile du .blend sont mal rattachés à leur aile (ils sont tous
                # à l'origine) : on reprend leur vraie place, celle du calcul des masses de Blender
                centre = ancien["equipements"][nom]["position_godot"]
            p = {"id": nom, "type": "masse", "masse_kg": m["masse"], "centre": r(centre, 6),
                 "note": m.get("description", "")}
        else:
            i = m["inertie"]
            p = {"id": nom, "type": "structure", "matiere": MATIERES[m["matiere"]], "masse_kg": m["masse"],
                 "centre": r(centre, 6),
                 "inertie_propre": r([i[0][0], i[1][1], i[2][2], i[0][1], i[0][2], i[1][2]], 4),
                 "surface_m2": round(m["surface_m2"], 4)}
        if art:
            p["articulation"] = art
        pieces.append(p)

    # 2. Moteurs principaux (ordre conservé : le jeu, le son et les tests les connaissent par leur rang)
    def moteur(id_, nom, point, direction, poussee, role, art="", **reste):
        p = {"id": id_, "type": "moteur", "nom": nom, "point": r(point), "direction": r(direction),
             "poussee_n": poussee, "role": role}
        if art:
            p["articulation"] = art
        p.update(reste)
        pieces.append(p)

    for cote_aile, x in (("haut_gauche", -1.12), ("haut_droit", 1.12), ("bas_gauche", 1.12), ("bas_droit", -1.12)):
        p, d = sur_aile(cote_aile, (x, 0.0, 4.0), AVANT)
        moteur("moteur_" + cote_aile, cote_aile.replace("_", " "), p, d, 200000.0, "principal", "aile_" + cote_aile)
    moteur("moteur_central", "central", (0.0, 0.0, 4.25 + 0.8), AVANT, 200000.0, "principal", "tuyere")
    for cote, x in (("gauche", -0.27), ("droit", 0.27)):
        # haut du vérin (y = −0,03) + sortie du moteur sous son vérin (−0,37), vérin rentré
        moteur("moteur_levage_" + cote, "levage " + cote, (x, -0.03 - 0.37, -3.0), HAUT, 37500.0, "levage",
               "verin_levage_" + cote, seulement_sorti=True)

    # 3. Petits propulseurs : leur rôle (tourner sur quel axe, ou glisser) n'est PAS écrit : la physique le
    #    trouve en calculant leur couple autour du centre de gravité.
    def propulseur(id_, nom, point, direction, art="", **reste):
        p = {"id": id_, "type": "propulseur", "nom": nom, "point": r(point), "direction": r(direction),
             "poussee_n": 6000.0}
        if art:
            p["articulation"] = art
        p.update(reste)
        pieces.append(p)

    propulseur("rcs_nez_bas", "nez bas", (0, -0.26, -5.2), HAUT)
    propulseur("rcs_queue_haut", "queue haut", (0, 1.01, 4.0), BAS)
    propulseur("rcs_nez_haut", "nez haut", (0, 0.2, -5.2), BAS)
    propulseur("rcs_queue_bas", "queue bas", (0, -1.01, 4.0), HAUT)
    propulseur("rcs_nez_droit", "nez droit", (0.29, 0, -5.2), GAUCHE)
    propulseur("rcs_queue_gauche", "queue gauche", (-0.91, 0, 4.0), DROITE)
    propulseur("rcs_nez_gauche", "nez gauche", (-0.29, 0, -5.2), DROITE)
    propulseur("rcs_queue_droit", "queue droit", (0.91, 0, 4.0), GAUCHE)
    for cote_aile, x in (("haut_droit", 5.35), ("bas_gauche", 5.35), ("haut_gauche", -5.35), ("bas_droit", -5.35)):
        p, d = sur_aile(cote_aile, (x, 0.24, 1.475), HAUT)
        propulseur("rcs_bout_aile_" + cote_aile, "bout aile " + cote_aile.replace("_", " "), p, d, "aile_" + cote_aile)
    buses = [  # buses encastrées dans la coque (modèle v21, extras poussee_godot)
        ("freinage_gauche", (-0.10, 0.0, -6.0), (0.0, 0.0, 1.0)),
        ("freinage_droit", (0.10, 0.0, -6.0), (0.0, 0.0, 1.0)),
        ("poussee_fine_gauche", (-0.70, 0.0, 4.3), (0.0, 0.0, -1.0)),
        ("poussee_fine_droit", (0.70, 0.0, 4.3), (0.0, 0.0, -1.0)),
        ("lateral_gauche", (-0.75, 0.0, 0.0), (0.997, 0.0, 0.083)),
        ("lateral_droit", (0.75, 0.0, 0.0), (-0.997, 0.0, 0.083)),
        ("montee_gauche", (-0.5622, -0.4635, 0.0), (0.847, 0.529, 0.052)),
        ("montee_droit", (0.5622, -0.4635, 0.0), (-0.833, 0.521, 0.187)),
        ("descente_gauche", (-0.5667, 0.6163, 0.0), (0.842, -0.526, 0.119)),
        ("descente_droit", (0.5667, 0.6163, 0.0), (-0.84, -0.526, 0.135)),
    ]
    for nom, point, direction in buses:
        propulseur("buse_" + nom, nom.replace("_", " "), point, direction, encastre=True)

    # 4. Train d'atterrissage (bas de chaque roue, train sorti, amortisseurs détendus) et points de la coque
    pieces.append({"id": "roue_avant", "type": "roue", "nom": "roue avant", "point": [0.0, -1.6, -4.4],
                   "course_m": 0.15, "raideur_n_m": 250000.0, "amorti_n_s_m": 30000.0, "rayon_m": 0.18,
                   "orientable_deg": 35.0, "vitesse_braquage_deg_s": 60.0, "freinee": True, "choc_max_m_s": 2.0})
    for cote, x in (("gauche", -1.184), ("droit", 1.184)):
        pieces.append({"id": "roue_arriere_" + cote, "type": "roue", "nom": "roue arrière " + cote,
                       "point": [x, -1.6, 2.4], "course_m": 0.12, "raideur_n_m": 700000.0, "amorti_n_s_m": 80000.0,
                       "rayon_m": 0.18, "freinee": True, "choc_max_m_s": 2.0})
    for id_, point in (("ventre_avant_gauche", (-0.9, -1.0, -2.5)), ("ventre_avant_droit", (0.9, -1.0, -2.5)),
                       ("ventre_arriere_gauche", (-0.9, -1.0, 2.5)), ("ventre_arriere_droit", (0.9, -1.0, 2.5)),
                       ("nez", (0.0, -0.2, -5.6)), ("queue", (0.0, 0.0, 5.4))):
        pieces.append({"id": "coque_" + id_, "type": "contact_coque", "point": list(point)})

    # 5. Plaques d'air : 3 bandes par aile (anciennes BANDES : x du milieu dans le repère de la charnière,
    #    corde, envergure de la bande, z du quart avant de la corde), puis les 2 dérives
    bandes = [(1.0, 3.1, 2.0, 1.68), (2.85, 2.1, 1.7, 1.83), (4.55, 1.9, 1.7, 1.73)]
    for nom in ("haut_gauche", "haut_droit", "bas_gauche", "bas_droit"):
        gauche, haut = nom.endswith("gauche"), nom.startswith("haut")
        signe = -1.0 if gauche != (not haut) else 1.0
        for k, (x, corde, env, zq) in enumerate(bandes):
            p, n = sur_aile(nom, (x * signe, 0.0, zq), HAUT)
            pieces.append({"id": "air_aile_%s_%d" % (nom, k + 1), "type": "surface_air", "point": r(p),
                           "normale": r(n), "surface_m2": round(corde * env, 6), "allongement": 4.8, "corde_m": corde,
                           "biplan": True, "groupe": "aile_" + nom, "articulation": "aile_" + nom})
    for cote, x in (("gauche", -0.62), ("droite", 0.62)):
        pieces.append({"id": "air_derive_" + cote, "type": "surface_air", "point": [x, 1.2, 3.0],
                       "normale": [1.0, 0.0, 0.0], "surface_m2": 1.2, "allongement": 1.4, "groupe": "derive_" + cote})

    rcs_points = {p["id"]: p["point"] for p in pieces if p["id"].startswith("rcs_") and not p["id"].startswith("rcs_bout")}
    for p in pieces:
        p["module"] = module_de(p, rcs_points)

    articulations = []
    for nom, (ch, replie, ouvert) in AILES.items():
        articulations.append({"id": "aile_" + nom, "type": "charniere", "nom": "aile " + nom.replace("_", " "),
                              "commande": "ailes", "point": list(ch), "axe": [0.0, 0.0, 1.0],
                              "angle_0_deg": replie, "angle_1_deg": ouvert, "modele_3d": "Charniere_" + nom})
    articulations.append({"id": "tuyere", "type": "tuyere_anneaux", "nom": "tuyère orientable du moteur central",
                          "commande": "vertical", "phase": [0.4, 1.0], "pivot": [0.0, 0.0, 4.25], "axe": [1.0, 0.0, 0.0],
                          "anneaux_m": [0.26, 0.26, 0.28], "angle_1_deg": 90.0, "modele_3d": "Pivot_tuyere_centrale"})
    for cote in ("gauche", "droit"):
        articulations.append({"id": "verin_levage_" + cote, "type": "verin", "nom": "vérin du moteur de levage " + cote,
                              "commande": "vertical", "phase": [0.0, 0.4], "course": [0.0, -0.32, 0.0],
                              "modele_3d": "Moteur_levage_" + cote})

    return {
        "format": "plan-vaisseau", "version": 1,
        "nom": "Chasseur v27",
        "description": "Chasseur à 4 ailes en X (modèle v27, roues arrière freinées), 5 moteurs arrière de 200 kN, "
                       "2 moteurs de levage, 12 propulseurs d'orientation et 10 buses encastrées.",
        "modele_3d": "modele3d/v27_roues_arriere/vaisseau_v27.blend",
        "pose_reference": "ailes ouvertes, train rentré, vol normal (tuyère droite, moteurs de levage rentrés)",
        "commandes": {
            "ailes": {"nom": "ouverture des ailes", "duree_s": 2.5, "depart": 1.0, "reference": 1.0},
            "train": {"nom": "train d'atterrissage", "duree_s": 3.0, "depart": 0.0, "reference": 0.0},
            "vertical": {"nom": "vol vertical", "duree_s": 4.0, "depart": 0.0, "reference": 0.0},
        },
        "modules": MODULES,
        "articulations": articulations,
        "coque": {"longueur_m": 10.3, "rayon_nez_m": 0.3, "capacite_thermique_j_m2_k": 25000.0, "emissivite": 0.85,
                  "temperature_limite_k": 1900.0, "raideur_n_m": 1500000.0, "amorti_n_s_m": 60000.0,
                  "choc_max_m_s": 3.0},
        "air": {"fuselage": {"centre": [0.0, 0.09, -0.5], "surface_face_m2": 3.34, "surface_cote_m2": 13.07,
                             "surface_dessus_m2": 12.68},
                "nez": {"point": [0.0, 0.0, -1.46], "section_max_m2": 2.8},
                "train": {"point": [0.0, -1.3, -1.0], "surface_m2": 0.9}},
        "vie": VIE,
        "pieces": pieces,
    }


if __name__ == "__main__":
    d = plan()
    os.makedirs(os.path.dirname(SORTIE), exist_ok=True)
    texte = json.dumps(d, indent="\t", ensure_ascii=False)
    # listes de nombres (positions, directions, inertie) sur une seule ligne : plus lisible
    texte = re.sub(r"\[\s*(-?[0-9][-0-9.eE+]*(?:,\s*-?[0-9][-0-9.eE+]*)*)\s*\]",
                   lambda m: "[" + ", ".join(x.strip() for x in m.group(1).split(",")) + "]", texte)
    with open(SORTIE, "w", encoding="utf-8") as f:
        f.write(texte + "\n")
    m = sum(p.get("masse_kg", 0.0) for p in d["pieces"])
    print("plan écrit :", SORTIE, "-", len(d["pieces"]), "pièces,", round(m, 1), "kg")
