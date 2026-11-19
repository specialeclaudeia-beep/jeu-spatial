import bpy, bmesh, sys, math
from mathutils import Vector, Matrix
src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=src)
R = 0.18          # rayon de roue (même roue que l'avant)
DX = 0.14         # roue décalée vers l'extérieur du bout de jambe (fusée)
DZ = 0.06         # axe 6 cm au-dessus du bout de jambe (bas de roue = bas de l'ancien patin)
roue_av = bpy.data.objects["Roue_avant"]
ACIER = "acier haute résistance (trains d'atterrissage)"

def cyl_x(bm, x0, x1, y, z, r, seg, mat):
    vs0=[]; vs1=[]
    for i in range(seg):
        a=2*math.pi*i/seg
        vs0.append(bm.verts.new((x0, y+r*math.cos(a), z+r*math.sin(a))))
        vs1.append(bm.verts.new((x1, y+r*math.cos(a), z+r*math.sin(a))))
    fs=[]
    for i in range(seg):
        j=(i+1)%seg
        fs.append(bm.faces.new((vs0[i],vs0[j],vs1[j],vs1[i])))
    fs.append(bm.faces.new(list(reversed(vs0)))); fs.append(bm.faces.new(vs1))
    for f in fs: f.material_index=mat
def boite(bm, c, d, mat):
    r=bmesh.ops.create_cube(bm, size=1.0)
    for v in r['verts']:
        v.co = Vector((c[0]+v.co.x*d[0], c[1]+v.co.y*d[1], c[2]+v.co.z*d[2]))
    for f in {f for v in r['verts'] for f in v.link_faces}: f.material_index=mat

for cote, s in (("gauche",-1.0),("droit",1.0)):
    pied = bpy.data.objects["Pied_arriere_"+cote]
    mats = [m.name for m in pied.data.materials]
    MC, SB, OR = mats.index("Metal_clair"), mats.index("Sombre"), mats.index("Orange")
    bm = bmesh.new()
    boite(bm, (0,0,0.01), (0.15,0.17,0.17), MC)                 # rotule du bout de jambe
    boite(bm, (s*0.05,0,DZ*0.5), (0.08,0.12,0.12), MC)          # fusée
    cyl_x(bm, 0.0, s*(DX+0.085), 0, DZ, 0.04, 16, MC)           # axe de roue
    xd = s*(DX-0.065-0.015)
    cyl_x(bm, xd-0.008, xd+0.008, 0, DZ, 0.13, 24, SB)          # disque de frein
    boite(bm, (xd, -0.02, DZ+0.125), (0.05,0.09,0.05), OR)      # étrier de frein
    cyl_x(bm, s*(DX+0.07), s*(DX+0.095), 0, DZ, 0.055, 12, MC)  # écrou de roue
    if s < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("Fusee_arriere_"+cote)
    bm.to_mesh(me); bm.free()
    for m in pied.data.materials: me.materials.append(m)
    old = pied.data; pied.data = me
    if old.users == 0: bpy.data.meshes.remove(old)
    pied["type"] = "fusee_a_plat"
    pied["masse_kg"] = 41.7
    pied["note"] = "fusee de la roue arriere (axe, disque et etrier de frein), reste parallele a la coque (biellette) : rotation = inverse de celle de la jambe"
    # la roue : même maillage que la roue avant, axe X, sur l'axe de la fusée
    roue = bpy.data.objects.new("Roue_arriere_"+cote, roue_av.data.copy())
    roue.data.name = "Roue_arriere_"+cote
    for c in pied.users_collection: c.objects.link(roue)
    roue.parent = pied
    roue.matrix_parent_inverse = Matrix.Identity(4)
    roue.location = (s*DX, 0.0, DZ)
    roue["type"] = "roue"; roue["axe"] = "X"; roue["rayon_m"] = R
    roue["matiere"] = ACIER; roue["masse_kg"] = 30.0
    roue["note"] = "roue arriere freinee (touche Maj), tourne autour de son axe X en roulant"
    roue["cacher_en_vue_cockpit"] = True
    bpy.context.view_layer.update()
    vs=[roue.matrix_world@v.co for v in roue.data.vertices]
    print(cote, "roue rentree", [round(min(v[i] for v in vs),3) for i in range(3)], [round(max(v[i] for v in vs),3) for i in range(3)])

# vérification train sorti : on fait tourner les jambes comme dans le jeu
bpy.context.view_layer.update()
import copy
for cote in ("gauche","droit"):
    tr = bpy.data.objects["Train_arriere_"+cote]; pied = bpy.data.objects["Pied_arriere_"+cote]
    ax = Vector(tr["axe_blender"]).normalized()
    q0 = tr.rotation_quaternion.copy(); p0 = pied.rotation_quaternion.copy()
    from mathutils import Quaternion
    q = Quaternion(ax, math.radians(-90.0))   # essai d'un sens ; on garde celui qui met la roue en bas
    for sg in (-1, 1):
        q = Quaternion(ax, math.radians(90.0*sg))
        tr.rotation_quaternion = q0 @ q
        bpy.context.view_layer.update()
        # pied parallèle à la coque
        pw = pied.matrix_world
        pied.matrix_world = Matrix.Translation(pw.translation)
        bpy.context.view_layer.update()
        roue = bpy.data.objects["Roue_arriere_"+cote]
        vs=[roue.matrix_world@v.co for v in roue.data.vertices]
        print(cote, sg, "roue sortie", [round(min(v[i] for v in vs),3) for i in range(3)], [round(max(v[i] for v in vs),3) for i in range(3)])
        tr.rotation_quaternion = q0; pied.rotation_quaternion = p0
        bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
