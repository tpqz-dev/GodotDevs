# Prototype de sculpture

Première phase : sphère de 30 000 triangles, vue 3D et pinceau Standard. Ouvrir ce dossier dans
Godot 4.7 et lancer le projet avec F5 (ou `godot --path <dossier>`).

- Clic gauche et déplacement : ajouter du volume.
- Alt + clic gauche : retirer du volume.
- Maj + clic gauche et déplacement : lisser temporairement la surface.
  Maj prend priorité sur Alt lorsque les deux touches sont maintenues.
- Maintenir S et déplacer la souris horizontalement : modifier la taille du
  pinceau (droite : agrandir ; gauche : réduire). Le mouvement ne sculpte pas.
- Clic milieu et déplacement : tourner autour du modèle.
- Maj + clic milieu : déplacer la vue. Molette : zoom. F : recadrer.
- Maj + F : afficher ou masquer le maillage triangulé.
- Ctrl + Z : annuler un trait complet. Ctrl + Y ou Ctrl + Maj + Z :
  rétablir. Les boutons « Annuler » et « Rétablir » font de même.
- « Ouvrir OBJ » (Ctrl + O) charge un maillage ; « Enregistrer OBJ »
  (Ctrl + S) écrit la géométrie sculptée dans un fichier OBJ. Une ouverture
  remplace la sculpture et vide l'historique après confirmation. L'écrasement
  d'un fichier existant est confirmé par le sélecteur.
- L'import prend en charge les faces polygonales et les indices OBJ négatifs,
  puis triangule les faces. Les sommets non utilisés, les faces dégénérées et
  les arêtes non-manifold ou d'orientation incohérente sont refusés. Limites :
  fichier de 64 Mio, 500 000 sommets et 500 000 triangles. Les normales sont
  recalculées ; matériaux, textures, UV et groupes ne sont pas conservés.
  Les sommets distincts ne sont pas fusionnés à l'import.
- OBJ sauvegarde uniquement le maillage, pas l'historique, les paramètres
  de pinceau, la symétrie ni la vue. Une confirmation est demandée avant de
  fermer si la géométrie a changé depuis le dernier enregistrement.
- La limite mémoire de l'historique est réglable dans le panneau (64 Mio par
  défaut) ; les actions les plus anciennes sont supprimées lorsque nécessaire.
  Une nouvelle sphère efface l'historique après confirmation. L'historique
  ne persiste pas après fermeture.
- « Symétrie X » reproduit les coups de pinceau de l'autre côté du plan
  X = 0, y compris pour creuser et lisser. Elle est désactivée au démarrage
  et ne rend pas symétriques les déformations déjà réalisées.
- Les curseurs règlent le rayon et l'intensité ; « Nouvelle sphère » remet
  le modèle à zéro après confirmation si la sculpture a été modifiée.

Le prototype ne sauvegarde pas encore de projet complet. Les autres pinceaux,
les symétries Y et Z, les masques, la subdivision et l'import/export STL
ne sont pas encore implémentés. La géométrie est traitée sur le processeur ;
les traits peuvent présenter des ralentissements,
particulièrement lorsque le maillage est affiché. La prise en charge des
tablettes reste à évaluer.

Test automatisé :

```powershell
godot --headless --path <dossier> --script res://tests/prototype_test.gd
godot --headless --path <dossier> --script res://tests/history_test.gd
godot --headless --path <dossier> --script res://tests/brush_size_test.gd
godot --headless --path <dossier> --script res://tests/obj_test.gd
```

Pour vérifier le rendu des faces avec une fenêtre et un GPU :

```powershell
godot --path <dossier> --script res://tests/face_render_test.gd
```
