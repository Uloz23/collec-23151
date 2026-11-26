# Monôme Héro : récapitulatif de conception pour l'intégration

Jeu de rythme façon Guitar Hero sur les chants gadz, à intégrer dans un onglet de l'appli de cartes. Il n'y a pas de lien avec la collection pour l'instant. La conception a été faite dans une autre discussion, avec un prototype jouable validé par Mathieu.

Le prototype complet tient dans `prototype_index.html` : un seul fichier HTML, Canvas 2D et Web Audio, sans aucune bibliothèque. C'est la **référence** : le reprendre tel quel plutôt que de repartir de zéro. Il fonctionne s'il est servi par HTTP avec les fichiers de ce dossier à côté (`decor_*.png`, `logo.png`, `songs/`).

## 1. Contenu du dossier

| Fichier | Rôle |
|---|---|
| `prototype_index.html` | Le jeu complet (écrans, gameplay, décors animés, monôme, progression) |
| `logo.png` | Logo « MONOME HERO » détouré, 340 px de large |
| `decor_bordels.png`, `decor_chalons.png`, `decor_boquette.png`, `decor_cluns.png`, `decor_birse.png` | Décors pixel art 360×640, 45 à 75 Ko chacun |
| `songs/<lieu>_<version>.mp3` | Audio : `court` (≈1 min 30) et `entier`, MP3 96 kb/s stéréo |
| `songs/<lieu>_<version>.json` | Partition correspondante |
| `outils/*.py` | Scripts Python (librosa) d'analyse, de découpe et de génération des partitions |

## 2. Écrans et navigation

1. **Écran titre** : logo en haut, braises qui montent, petit monôme de 13 gadz qui tourne autour du Zamat dans le décor de Bordel's. Boutons : Jouer, Meilleurs scores, Réglages.
2. **Jouer**, en trois étapes, avec un bouton Retour qui remonte d'une étape :
   - **Choix du chant** : les chants débloqués listés les uns sous les autres (nom du chant, lieu en petit dessous). S'il reste au moins un chant verrouillé, une seule case « ??? » grisée suit, avec la condition en petit (« 70 % sur <chant précédent> (courte, facile) »).
   - **Choix de la version** : Version courte / Version entière. Une version verrouillée est grisée, avec la mention « 70 % en version courte pour la débloquer ».
   - **Choix de la difficulté** : Facile / Normal / Difficile. Sous un niveau débloqué : le record et la meilleure précision. Sous un niveau verrouillé : la condition. Toucher un niveau débloqué lance la partie.
3. **Partie** : compte à rebours de 1,6 s, puis le jeu. Pause en haut à droite (ou Échap/Espace), et automatiquement si l'appli passe en arrière-plan.
4. **Fin de partie** : score, version, difficulté, précision, combo max, monôme max, détail des jugements, puis « Débloqué » avec la liste de ce qui s'ouvre, ou le rappel de l'objectif de 70 %. Boutons Rejouer et Menu (le menu revient au choix de difficulté du même chant).
5. **Meilleurs scores** : pour chaque chant, record et meilleure précision par version et par difficulté ; « Pas encore débloqué » pour les autres.
6. **Réglages** : décalage audio (de -200 à +300 ms, mémorisé), vibrations oui/non, effacer la progression (avec confirmation).

## 3. Chants, décors, progression

Ordre de progression et noms :

| # | Lieu (tabagn's) | Chant | Tempo | Coupe de la version courte |
|---|---|---|---|---|
| 1 | Bordel's | Monôme de Bordel's | 112 BPM | 0:00 → 1:43 |
| 2 | Chalon's | La cousine Lison | 144 | 0:00 → 1:22 (coupe refaite par Mathieu, fondu de 2 s) |
| 3 | Boquette | Dans les rues | 144 | 0:00 → 1:28 |
| 4 | Clun's | Monôme de Clun's | 136 | 0:00 → 1:38 |
| 5 | Birse | Monôme de Birse | 144 | 0:00 → 1:24 |

- Uniquement des remix (Mathieu a abandonné les versions a cappella). Chaque chant existe en version courte (environ un couplet et un refrain, fondu de 2 s) et entière. Les coupes sont à valider à l'oreille par Mathieu.
- **Au départ**, seul Monôme de Bordel's est ouvert, en version courte et en facile.
- **Règle de déblocage** : réussir une version **courte** avec au moins **70 %** de précision débloque, pour ce chant, la **version entière dans la même difficulté** et la **difficulté suivante en version courte**. Réussir la courte en **facile** débloque aussi le **chant suivant** (courte, facile).
- À venir : Siber's (photos du lieu des monômes manquantes), Kin (pressenti comme niveau secret « le chant oublié », débloqué à la fin), Le facteur polonais (chant d'ambiance, décor à trouver, le Pian's a été évoqué).

## 4. Gameplay

- Rendu sur un canvas virtuel de **360×640**, agrandi avec `image-rendering: pixelated` pour garder les pixels nets. Les notes et l'interface sont dessinées dans un repère 180×320 (multiplié par 2).
- **3 colonnes**, centres en x = 54 / 90 / 126 (repère 180), zones de toucher 0-72 / 72-108 / 108-180. Multitouch géré. Clavier : Q, S, D (et flèches, 1-2-3).
- **Ligne de frappe** selon le décor : y = 250 (Bordel's), 268 (Birse), 280 pour les autres (repère 180×320).
- **Temps de chute** des notes : 1,7 s en facile, 1,35 s en normal, 1,1 s en difficile.
- **Jugements** : Parfait ≤ 50 ms (300 pts), Bien ≤ 95 ms (150), Juste ≤ 140 ms (50), au-delà Raté. Multiplicateur : 1 + 1 par tranche de 10 de combo, ×4 maximum.
- **Notes longues** : il faut maintenir le doigt ou la touche ; environ 120 pts/s pendant le maintien, puis 200 à la fin, multipliés par le multiplicateur. Lâcher plus de 0,12 s avant la fin casse la note. **Jamais dans la colonne du milieu.**
- **Précision** = (Parfait + 0,7 × Bien + 0,4 × Juste) / nombre de notes.
- **Synchronisation** sur l'horloge Web Audio (`AudioContext.currentTime`), en tenant compte de `outputLatency` et du décalage réglé par le joueur.
- Effets communs : note qui éclate, étincelles en pixels, faisceau de couleur dans la colonne, cercles qui pulsent sur le tempo, secousse et vibration sur un raté. « Parfait xN » à partir de 3 d'affilée, couleur qui change tous les 3. Paliers de combo affichés à 10, 25, 50, 100 et 200.

## 5. Le monôme (élément signature)

- Chaque note réussie ajoute 1 gadz, une note longue tenue jusqu'au bout en ajoute 2. Un raté coupe le monôme en deux (la queue disparaît en petits nuages), sans jamais l'annuler.
- C'est une **chenille** : la tête ne disparaît jamais, elle avance d'un pas par temps sur un parcours fixe propre à chaque décor. Le corps suit sans jamais se croiser, et seule la longueur varie. Le monôme ne marche jamais sur le Zamat, l'emblème de Chalon's ou les pelouses.
- Les gadz sont à l'échelle des décors (25 à 45 px de haut, plus grands au premier plan), dessinés en code : tête ronde, biaude évasée avec marques de feutre, bras tendu vers l'épaule de celui de devant, jambes qui marquent le pas sur le temps. **Trois vues selon la direction de marche** : de face (visage, carnet dans la poche sur le cœur), de dos (cheveux, rectangle blanc de la bucque), de profil.
- Ils passent derrière les éléments du décor (piliers, poteaux, bidons, buis, balustrades) grâce à des calques d'occlusion découpés dans les décors.
- Compteur « Monôme : N gadz » en haut de l'écran, et monôme max à l'écran de fin.

## 6. Ambiance par décor

Commun à tous : fenêtres et arcades qui s'allument par paliers de combo, clignotent sur le temps, alternent en damier à partir de 30, changent de couleur à 50 et flashent sur le contretemps à 100. Tout s'éteint quand le combo casse.

| Lieu | Pièce maîtresse | Parcours du monôme |
|---|---|---|
| Bordel's | Le Zamat (damier 7×7) : dalles qui flashent, damier qui s'inverse, ondes depuis le centre, couleurs. 4 bidons dont les flammes s'allument avec le combo et pulsent, avec des gerbes d'étincelles | Spirale autour du Zamat, vue en plongée, garde-corps au premier plan |
| Chalon's | L'emblème au sol : s'illumine, vague sur le tapis rouge, rayons, colonne de lumière. Horloge qui s'affole à 50 | Sous les 3 ouvertures, puis boucles devant et autour de l'emblème |
| Boquette | Le clocheton : cloche qui se balance, ondes sonores, faisceaux de phare, onde de choc | Galerie derrière les piliers, puis rangées en perspective dans la cour |
| Clun's | La rosace (oculus) : vitrail 8 segments, projection colorée sur l'allée, rotation | Galerie, le long des buis, puis tour de l'allée centrale |
| Birse | La statue (satyre / Bacchus) : yeux, médaillon, raisins qui s'envolent, aura couleur vin, ondes pourpres. Ateliers avec soudure et étincelles dans les baies | Deux anneaux autour du jardin, balustrade au premier plan |

Toutes les coordonnées (fenêtres, parcours, occultations) sont dans le prototype, dans les constantes `BWIN`, `CWIN2`, `QWIN`, `KWIN`, `SWIN`, `PATH`, `BARRELS`, etc.

## 7. Format des partitions

```json
{"titre":"Monôme de Bordel's","duree":104.6,"tempo":112.35,
 "beats":[0.52, 1.05, ...],
 "notes":{"facile":[[t, colonne] ou [t, colonne, durée], ...],"normal":[...],"difficile":[...]}}
```
`t` et `durée` sont en secondes, `colonne` vaut 0, 1 ou 2. Les `beats` servent aux effets en rythme. Les partitions font 7 à 25 Ko.

Génération automatique avec `outils/generer_partition.py` (librosa) : détection du tempo et des temps, attaques par bande de fréquences (graves → colonne 1, médiums → 2, aigus → 3), densité qui suit l'énergie du morceau, notes longues seulement dans les passages soutenus et jamais au milieu. Usage : `python3 analyser_structure.py <lieu>`, puis `python3 generer_partition.py <lieu> <fin de la coupe en secondes> "<titre>"`. Les chemins des MP3 sources sont à adapter dans le dictionnaire `SONGS` en tête des deux scripts.

## 8. Ce qui reste à faire à l'intégration

- **Stockage partagé** : le prototype garde la progression et les records en `localStorage` (clés `gh_prog`, `gh_best_<lieu>_<version>_<difficulté>`, `gh_lat`, `gh_vib`). Dans l'appli, il faut les rattacher au compte du joueur et créer un **classement commun** entre les membres, par chant, version et difficulté. Éviter la triche grossière (scores impossibles).
- **Chargement** : l'audio est chargé et décodé au lancement de chaque chant, puis gardé en cache. Les décors pèsent environ 300 Ko au total.
- **Mobile** : bloquer le zoom et le défilement pendant la partie, gérer la mise en veille et le retour d'arrière-plan (pause automatique déjà présente), reprendre l'`AudioContext` sur un geste de l'utilisateur.
- **Plus tard** : Siber's, Kin, Le facteur polonais ; termes d'argadz pour les jugements (provisoires : Parfait, Bien, Juste, Raté) ; un éditeur de retouche des partitions serait utile.
