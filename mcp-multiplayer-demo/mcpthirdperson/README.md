# Lobby multijoueur

Le projet démarre sur le menu du lobby. Le bouton **Jouer en solo** permet de
retrouver la scène de jeu existante.

Pour héberger, choisissez un pseudo, une couleur et un port UDP, puis cliquez
sur **Héberger**. Les autres joueurs renseignent l'adresse IP de l'hôte et le
même port, puis cliquent sur **Rejoindre**. Le lobby accepte quatre joueurs au
maximum, hôte compris. Chaque joueur peut modifier son profil et se déclarer
prêt. Lorsque deux à quatre joueurs sont prêts, l'hôte peut lancer la partie.
Les déplacements et les sauts sont simulés par l'hôte puis synchronisés ; les
noms et les couleurs choisis apparaissent au-dessus des personnages. Les
commandes de mouvement et de caméra sont les mêmes qu'en solo. Échap libère la
souris pour utiliser le bouton **Quitter la partie**. Si l'hôte quitte, les
autres joueurs retournent au menu.

L'hôte peut terminer la partie depuis le bouton en jeu. L'écran de résultats
affiche la durée, les joueurs encore présents et l'état du cube cible. L'hôte
peut ensuite ramener tout le monde au lobby ; tous les états « prêt » sont
réinitialisés avant une nouvelle partie. Un joueur peut aussi quitter vers le
menu ; si l'hôte quitte, la session est fermée pour tous.

Un clic gauche tire horizontalement dans la direction de la caméra. Le serveur
valide la cadence de tir, simule la balle et retire le cube cible pour tous les
joueurs lorsqu'il est touché. Les obstacles arrêtent les balles. Chaque tir
touchant un autre joueur lui enlève un point de vie. Le cube est simulé par
l'hôte et sa position est synchronisée. Le personnage s'arrête pendant son tir.

Chaque joueur dispose de trois points de vie, indiqués par une barre à l'écran.
Cinq sphères rouges apparaissent aléatoirement près du centre de l'arène ;
les toucher rend un point de vie, sans dépasser trois. Une sphère n'est pas
consommée si la vie est déjà pleine. Après la dernière collecte, une sphère
réapparaît toutes les 20 secondes jusqu'au maximum de cinq ; une nouvelle
collecte relance ce délai. En multijoueur, l'hôte décide des
dégâts, des soins et du placement des sphères pour tous.

À zéro point de vie, le personnage joue son animation de mort ; trois secondes
plus tard, il disparaît dans une explosion de particules. Le joueur reste
spectateur, avec une caméra fixe à l'endroit de son élimination, jusqu'à la fin
de la partie. L'hôte peut toujours terminer la partie et lancer une revanche.
La barre et les sphères sont aussi présentes en solo ; il n'y a pas encore
d'ennemi capable d'infliger des dégâts en solo.

Le client prédit ses déplacements et se recale sur les positions du serveur ;
les autres joueurs sont affichés avec un tampon d'interpolation de 100 ms.
Le serveur reste responsable des collisions et des tirs. Les corrections
importantes peuvent provoquer un repositionnement visible, notamment autour
du cube mobile.

Le score, les ennemis et les autres événements de combat restent à implémenter.
Rejoindre une partie déjà commencée n'est pas possible.

Sur Internet, l'hôte doit autoriser le trafic UDP dans son pare-feu et, si
nécessaire, rediriger le port UDP du routeur vers sa machine. La saisie
`127.0.0.1` ne fonctionne que sur la même machine. Aucun relais, code de salle
ou franchissement automatique de NAT n'est encore disponible.

Pour vérifier le protocole dans un seul processus Godot :

```text
godot --headless --path <projet> --script res://tests/lobby_in_process.gd
```

Le test `tests/lobby_smoke.py <chemin-vers-godot>` lance cinq processus et
vérifie notamment la connexion en moins de trois secondes, la synchronisation
des profils, le refus d'une cinquième connexion alors que quatre joueurs sont
présents, et les déconnexions. Le test du serveur plein n'est lancé qu'après
confirmation par l'hôte que les quatre joueurs sont prêts. Un délai de connexion
du cinquième joueur ne prouve pas à lui seul la cause du refus. Le test nécessite
que le système autorise les communications UDP entre processus Godot.

Exemple sous Windows, depuis le dossier du projet :

```powershell
python .\tests\lobby_smoke.py "C:\chemin\vers\Godot_console.exe"
```

Le code de sortie doit être `0`, avec `PASS` pour chaque rôle. Si les clients
ne se connectent pas à `127.0.0.1`, vérifiez les autorisations réseau de
l'exécutable Godot et les règles de pare-feu avec l'administrateur de la
machine ; ne désactivez pas globalement le pare-feu. Un problème de
communication locale doit être résolu avant de conclure sur le comportement
du jeu sur un réseau distant.

Le lancement, les déplacements, une simulation de 150 ms de retard d'entrée,
les tirs, les résultats et une revanche se vérifient avec :

```text
godot --headless --path <projet> --script res://tests/multiplayer_game_in_process.gd
godot --headless --path <projet> --script res://tests/health_solo.gd
```

### Vérification manuelle sur un réseau

Utilisez la même version du projet sur chaque poste et commencez sur un réseau
local. L'hôte communique son adresse IP locale et le port UDP choisi. Sur une
seule machine, utilisez plutôt `127.0.0.1` dans des instances distinctes.

1. Connectez trois clients, choisissez les profils et vérifiez que la liste et
   les états « prêt » sont identiques sur les quatre écrans. Essayez ensuite
   une cinquième connexion.
2. Lancez la partie et vérifiez les déplacements, sauts, marches, tirs et
   destruction du cube sur tous les écrans.
3. Terminez la partie, vérifiez les résultats, revenez au lobby et lancez une
   revanche. Vérifiez que le cube réapparaît et que personne n'est déjà prêt.
4. Déconnectez un client pendant la partie, puis testez séparément le départ
   de l'hôte : les autres clients doivent revenir au menu sans plantage.
5. Si un outil réseau externe est disponible, répétez les déplacements avec
   environ 150 ms de latence et des pertes de paquets ; vérifiez visuellement
   la fluidité et la convergence. Rétablissez ensuite les réglages réseau.

Les tests dans un seul processus ne remplacent pas ces vérifications sur des
processus ou des machines distincts, et ne garantissent pas la fluidité sur
Internet.
