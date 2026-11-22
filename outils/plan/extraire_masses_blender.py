# Extrait du modèle Blender la MASSE, le CENTRE et l'INERTIE PROPRE de chaque pièce qui pèse
# (propriété « masse_kg » des objets), pour le plan du vaisseau (vaisseaux/chasseur_v27.plan.json).
#
# Lancement (Blender 5.3, ou le module bpy de Python) :
#   blender -b --python outils/plan/extraire_masses_blender.py -- modele3d/v27_roues_arriere/vaisseau_v27.blend outils/plan/masses_pieces_v27.json
#   (ou : python outils/plan/extraire_masses_blender.py <fichier.blend> <sortie.json> avec « pip install bpy »)
# Puis : python outils/plan/composer_plan_v27.py
#
# Méthode : chaque pièce modélisée est une COQUE MINCE de masse uniforme sur sa surface (les masses du
# modèle sont « surface × épaisseur équivalente × densité ») : on additionne la contribution de chaque
# triangle (second moment exact d'un triangle uniforme). Les équipements (objets vides « Masse_* ») sont
# des masses en un point. Coordonnées converties dans le repère de Godot : (x, z, −y).
import bpy, sys, json, bmesh
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
fichier_blend, sortie = args[0], args[1]
bpy.ops.wm.open_mainfile(filepath=fichier_blend)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()


def g(v):  # Blender -> Godot
    return (v[0], v[2], -v[1])


res = {}
for o in bpy.data.objects:
    if "masse_kg" not in o.keys() or o.get("type") == "droide":
        continue   # l'objet « Droide » est la copie du droïde déjà compté par « Masse_droide »
    m = float(o["masse_kg"])
    if m <= 0.0:
        continue   # boutons, voyants : dessin seulement
    ancetres = []
    p = o.parent
    while p is not None:
        ancetres.append(p.name)
        p = p.parent
    entree = {"masse": m, "matiere": o.get("matiere", ""), "ancetres": ancetres,
              "description": o.get("description", "")}
    if o.type == 'MESH':
        oe = o.evaluated_get(dg)
        me = oe.to_mesh()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        W = o.matrix_world
        A = 0.0
        S = [0.0] * 3
        Q = [[0.0] * 3 for _ in range(3)]
        for f in bm.faces:
            pts = [g(W @ v.co) for v in f.verts]
            a = ((Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[0]))).length * 0.5
            if a <= 0:
                continue
            A += a
            s = [pts[0][k] + pts[1][k] + pts[2][k] for k in range(3)]
            for i in range(3):
                S[i] += a * s[i] / 3.0
            # second moment d'un triangle uniforme : a/12 · (Σ pᵢ pᵢᵀ + (Σ pᵢ)(Σ pᵢ)ᵀ)
            for i in range(3):
                for j in range(3):
                    Q[i][j] += a / 12.0 * (sum(pts[t][i] * pts[t][j] for t in range(3)) + s[i] * s[j])
        bm.free()
        oe.to_mesh_clear()
        if A == 0:
            c = list(g(W.translation))
            ic = [[0.0] * 3 for _ in range(3)]
        else:
            c = [S[i] / A for i in range(3)]
            cov = [[Q[i][j] / A - c[i] * c[j] for j in range(3)] for i in range(3)]
            tr = cov[0][0] + cov[1][1] + cov[2][2]
            # tenseur d'inertie autour du centre de la pièce : m · (tr(C)·1 − C)
            ic = [[m * ((tr if i == j else 0.0) - cov[i][j]) for j in range(3)] for i in range(3)]
        entree.update({"forme": "coque", "centre": c, "inertie": ic, "surface_m2": A})
    else:
        entree.update({"forme": "point", "centre": list(g(o.matrix_world.translation)),
                       "inertie": [[0.0] * 3 for _ in range(3)], "surface_m2": 0.0})
    res[o.name] = entree

with open(sortie, "w", encoding="utf-8") as f:
    json.dump({"source": fichier_blend.replace("\\", "/"), "repere": "Godot (x, y = haut, z = arrière)",
               "pieces": res}, f, indent=1, ensure_ascii=False, sort_keys=True)
print("pièces :", len(res), "masse :", round(sum(r["masse"] for r in res.values()), 1), "kg")
