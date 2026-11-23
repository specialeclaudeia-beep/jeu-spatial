# Mesure la CABINE du cockpit v27 (atelier, étape 8) sur le modèle 3D (modele3d/v27_roues_arriere/cockpit_v27.glb) :
#   1. le VOLUME D'AIR : l'intérieur est découpé en petits cubes de 2 cm ; les parois (baignoire, verrière, cadre,
#      habillage, détails du tableau de bord) sont « épaissies » d'un cube pour boucher les petits jours entre deux
#      pièces du modèle, puis l'air est rempli de proche en proche depuis la place du pilote ; on rend la moitié de
#      l'épaississement, et on enlève le pilote et son siège ;
#   2. le RAYON DE COURBURE de chaque paroi sous pression : la paroi est coupée en 10 tranches le long du vaisseau,
#      un cercle est ajusté sur chaque tranche (moindres carrés, pondérés par la surface), et on garde la tranche la
#      plus plate (le plus grand rayon : c'est là que la contrainte σ = p·R/e est la plus forte).
# Les nombres sont recopiés dans outils/plan/composer_plan_v27.py (section « vie » du plan).
# Lancement : python outils/plan/cabine_cockpit_v27.py   (depuis le dossier du projet ; Python 3 + numpy ;
# environ 5 minutes : le remplissage est fait en Python simple)
import json, os, struct, sys
import numpy as np

ICI = os.path.dirname(os.path.abspath(__file__))
PROJET = os.path.dirname(os.path.dirname(ICI))
MODELE = os.path.join(PROJET, "modele3d", "v27_roues_arriere", "cockpit_v27.glb")
PAROIS = ["Cockpit_interieur", "Cockpit_verriere", "Cockpit_cadre"]
AUTOUR = ["Cockpit_details", "Cockpit_habillage", "Cockpit_details_v25"]   # prennent aussi de la place
PAS = 0.02                       # m, côté des petits cubes
PLACE_PILOTE = (0.0, 0.5, 0.3)   # m, un point dans l'air de la cabine (au-dessus du siège)
VOLUME_PILOTE = 0.08             # m³ : 85 kg à 1 060 kg/m³ (densité moyenne du corps humain)
VOLUME_SIEGE = 0.10              # m³ : siège éjectable (assise, dossier, coussins, environ 0,5 × 0,5 × 0,4 m)


def lire_glb(chemin):
    b = open(chemin, "rb").read()
    assert b[:4] == b"glTF"
    n = struct.unpack("<I", b[12:16])[0]
    js = json.loads(b[20:20 + n])
    off = 20 + n
    ln = struct.unpack("<I", b[off:off + 4])[0]
    return js, b[off + 8:off + 8 + ln]


def accesseur(js, binc, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    comp = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}[a["componentType"]]
    nc = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    debut = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    pas = bv.get("byteStride", comp[1] * nc)
    sortie = np.zeros((a["count"], nc))
    for k in range(a["count"]):
        s = debut + k * pas
        sortie[k] = struct.unpack("<" + comp[0] * nc, binc[s:s + comp[1] * nc])
    return sortie


def matrice(n):
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    m = np.eye(4)
    t = n.get("translation", [0, 0, 0])
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    s = n.get("scale", [1, 1, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m[:3, :3] = r * np.array(s)
    m[:3, 3] = t
    return m


def maillages(chemin):
    """Triangles (repère du modèle) de chaque objet nommé du fichier glTF."""
    js, binc = lire_glb(chemin)
    res = {}

    def visiter(i, parent):
        n = js["nodes"][i]
        m = parent @ matrice(n)
        if "mesh" in n:
            tris = []
            for pr in js["meshes"][n["mesh"]]["primitives"]:
                v = accesseur(js, binc, pr["attributes"]["POSITION"])
                idx = accesseur(js, binc, pr["indices"]).astype(int).ravel() if "indices" in pr else np.arange(len(v))
                vw = (m[:3, :3] @ v.T).T + m[:3, 3]
                tris.append(vw[idx].reshape(-1, 3, 3))
            res[n.get("name", str(i))] = np.concatenate(tris)
        for c in n.get("children", []):
            visiter(c, m)

    for r in js["scenes"][js.get("scene", 0)]["nodes"]:
        visiter(r, np.eye(4))
    return res


def dilater(x):
    z = x.copy()
    z[1:] |= x[:-1]; z[:-1] |= x[1:]
    z[:, 1:] |= x[:, :-1]; z[:, :-1] |= x[:, 1:]
    z[:, :, 1:] |= x[:, :, :-1]; z[:, :, :-1] |= x[:, :, 1:]
    return z


def volume_air(tris, h, graine):
    v = tris.reshape(-1, 3)
    bas = v.min(0) - 3 * h
    taille = np.ceil((v.max(0) + 3 * h - bas) / h).astype(int) + 1
    mur = np.zeros(taille, bool)
    for a, b, c in tris:   # chaque triangle est semé de points tous les demi-cubes
        l = max(np.linalg.norm(b - a), np.linalg.norm(c - a), np.linalg.norm(c - b))
        n = int(np.ceil(l / (h * 0.5))) + 1
        u, w = np.meshgrid(np.linspace(0, 1, n), np.linspace(0, 1, n))
        k = (u + w) <= 1.0
        p = a + np.outer(u[k], b - a) + np.outer(w[k], c - a)
        i = np.floor((p - bas) / h).astype(int)
        mur[i[:, 0], i[:, 1], i[:, 2]] = True
    murs = dilater(mur)
    g = tuple(np.floor((np.array(graine) - bas) / h).astype(int))
    assert not murs[g], "la place du pilote est dans une paroi"
    air = np.zeros(taille, bool)
    air[g] = True
    while True:
        z = dilater(air) & ~murs
        if z.sum() == air.sum():
            break
        air = z
    fuit = air[0].any() or air[-1].any() or air[:, 0].any() or air[:, -1].any() or air[:, :, 0].any() or air[:, :, -1].any()
    couche = (dilater(air) & murs & ~mur).sum()
    return (air.sum() + 0.5 * couche) * h ** 3, fuit


def rayon_paroi(t, tranches=10):
    a, b, c = t[:, 0], t[:, 1], t[:, 2]
    aire = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    g = (a + b + c) / 3
    zs = np.linspace(g[:, 2].min(), g[:, 2].max(), tranches + 1)
    rayons = []
    for z0, z1 in zip(zs[:-1], zs[1:]):
        k = (g[:, 2] >= z0) & (g[:, 2] < z1)
        if aire[k].sum() < 0.02 * aire.sum():
            continue
        q = g[k][:, :2]
        w = np.sqrt(aire[k])
        m = np.stack([2 * q[:, 0], 2 * q[:, 1], np.ones(len(q))], 1)
        s = np.linalg.lstsq(m * w[:, None], (q[:, 0] ** 2 + q[:, 1] ** 2) * w, rcond=None)[0]
        rayons.append(float(np.sqrt(s[2] + s[0] ** 2 + s[1] ** 2)))
    return max(rayons), float(aire.sum())


if __name__ == "__main__":
    m = maillages(MODELE)
    for nom in PAROIS:
        r, s = rayon_paroi(m[nom])
        print("%-20s surface %.4f m²   rayon de la tranche la plus plate %.3f m" % (nom, s, r))
    tris = np.concatenate([m[n] for n in PAROIS + AUTOUR if n in m])
    v, fuit = volume_air(tris, PAS, PLACE_PILOTE)
    assert not fuit, "l'air sort par un trou du modèle : le calcul ne voit pas une cabine fermée"
    net = v - VOLUME_PILOTE - VOLUME_SIEGE
    print("air entre les parois %.3f m³ ; sans le pilote et son siège %.3f m³ → %.1f m³" % (v, net, net))
    sys.exit(0)
