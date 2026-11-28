# Collec' 23-151 : fiche du projet

À lire en premier par toute conversation qui reprend le travail sur ce dépôt.
Elle résume l'organisation, les règles décidées avec Mathieu et la façon de travailler.

## Qui, quoi

- **Mathieu** (bucque **Uloz²**), gadzarts de Bordel's, fam's 23-151, promo 211. Prof de maths, débutant en programmation :
  lui expliquer simplement, en français, sans jargon. C'est lui qui lance les mises à jour SQL dans Supabase.
- **Collec' 23-151** : appli web de cartes à collectionner pour un petit cercle autour de la fam's
  (boosters, album, versions, échanges, jeux). Lancée pour le week's fam's de novembre 2026.
- Respecter l'argadz de Bordel's (voir plus bas) : on « fait partie » d'une fam's, P1 n'existe pas (c'est le .onscrit),
  P2 = ancien, P3 = 3e génération… Pas de « période sombre » (fusion 23-151-33) dans les contenus.

## Organisation du travail

- **Une seule conversation modifie le code à un moment donné** (pas de modifications en parallèle).
  Une conversation par chantier (la Collec', Monome Hero, un nouveau jeu…), l'une après l'autre.
- La réflexion sur les nouveaux jeux se fait dans des discussions à part, qui fournissent un récapitulatif (ex. `jeux/rythme/CONCEPTION.md`).
- **Ne jamais mettre en ligne un prototype de jeu pour les joueurs** sans son accord : passer par l'état « test » des jeux.
- Toujours `git pull --rebase` avant de pousser. Messages de commit en français.
- Après une mise à jour SQL : donner le fichier à Mathieu (et le texte en ligne s'il est sur téléphone), avec ce qu'il doit voir
  (« Mise à jour n° X installée »). Une mise à jour doit être **relançable sans danger** et ne pas dépendre d'une mise à jour
  non installée (piège déjà rencontré : la n° 12 n'était pas installée ; la n° 19 inclut désormais `_variant`).

## Hébergement

- Site statique sur GitHub Pages : https://uloz23.github.io/collec-23151/ (dépôt `Uloz23/collec-23151`, branche `main`).
  Les déploiements peuvent rester bloqués : vérifier avec `gh run list -R Uloz23/collec-23151`.
- Base **Supabase** (Postgres, RLS, fonctions `security definer`, stockage `medias`, pg_cron, fonction Edge `notifs` pour les notifications).
  Adresse et clé publique dans `config.js`. Les secrets (clé VAPID privée, secret du cron) sont **uniquement dans Supabase**, jamais dans le dépôt.
- Ne jamais demander de mot de passe à Mathieu. Son adresse e-mail est privée : ne pas la transmettre à un service extérieur sans son accord.
- `sw.js` : service worker sans cache pour les fichiers du site (pas besoin de vider le cache), notifications.

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | L'appli des joueurs : connexion par pseudo et code, boosters, album, La fam's (classement, échanges, recherche de version, propositions), onglet Jeux |
| `admin.html` | Administration : joueurs (cadeaux, god packs, test, testeur jeux, droit d'offrir), cartes, import, réglages, propositions, bilan, stats, jeux |
| `carte.js`, `carte.css` | Dessin des cartes, partagé par l'appli, l'admin (aperçu) et le duel. Fabrique `window.CarteRendu(ctx)` |
| `jeux/` | Les jeux (voir `jeux/README.md` pour brancher un jeu) |
| `duel.html`, `jeu/` | Prototype du jeu de cartes (page cachée, mis en pause ; une refonte « plus fun » est envisagée) |
| `maj-N-*.sql` | Mises à jour de la base, dans l'ordre |
| `supabase/functions/notifs` | Envoi des notifications sur téléphone |

## Règles de la collection

- Raretés : gadz, commune, peu-commune, rare, mythique. Versions : normale, brillante, full art (`textless`), dorée,
  et **Maître** (`maitre`, gagnée dans Monome Hero, seulement pour 5 cartes Chant).
- Les boosters sont tirés **côté serveur** (`open_booster`), selon les « slots » des réglages (JSON de l'admin).
- **God packs** : au moins une dorée et une full art, communes et peu communes forcément dorées ou full art.
  Ceux qui ont le droit d'offrir (et l'admin) peuvent garantir que le prochain booster d'un joueur sera un god pack, avec un message ou en discrétion.
- **Cartes hors-série** (case dans l'admin) : jamais dans les boosters ni les échanges, section à part dans l'album, hors des totaux.
- **Version Maître** et hors-série : non échangeables, hors du classement des collections.
- Échanges : par groupes de rareté (réglage), dorées et full art libres entre elles, même version obligatoire (réglage).
- Carte dépubliée : invisible et hors classement, mais conservée par ses propriétaires.
- **Compte test** : tout débloqué, invisible des autres, et **sans trace** (rien n'est enregistré ; sa réserve revient à l'identique en repassant en normal).
- **Testeur jeux** : joueur normal qui voit aussi les jeux en état « test ».
- Cartes Gadz : génération Pn (P1 = .onscrit, P2 = Ancien), case Viscrit, plusieurs fam's possibles ; « // » dans un nom force un retour à la ligne.
- Police **Zagots** (`assets/zagots.ttf`) : Ä/ä = Za, Ö/ö = Zi, | = AM stylisé, Ý ou Þ = Pi, § = t transposée, & = é.

## Jeux

- Onglet **« À venir »** (icône ?) qui n'affiche que « Tu verras » tant qu'aucun jeu n'est ouvert à tous ; devient « Jeux » ensuite.
  Les comptes test et testeurs voient les jeux en test.
- États d'un jeu (admin, onglet Jeux) : désactivé, à venir, test, ouvert à tous. **Aucune récompense tant qu'un jeu est en test.**
  Le jour de l'ouverture : « Tout remettre à zéro », puis « Ouvert à tous ».
- Records, classements, progression et récompenses passent par le socle (`maj-21` et suivantes) ; voir `jeux/README.md`.

### Monome Hero (`jeux/rythme/`)

- Prototype d'origine repris tel quel dans `jeux/rythme/index.html`, chargé dans un cadre par `jeu.js`. Conception : `jeux/rythme/CONCEPTION.md`.
- 5 chants (Bordel's, Chalon's, Boquette, Clun's, Birse), version courte (coupes refaites par Mathieu, fondu de 2 s) et entière,
  facile / normal / difficile, plus « très difficile » (versions entières, pour le chant de la semaine).
- Partitions générées avec les scripts de `jeux/rythme/outils/` (librosa). Pas de notes longues en facile (retirées par le jeu).
- Déblocages : 70 % en version courte ouvre la version entière de la même difficulté, la difficulté suivante (courte et entière),
  et en facile le chant suivant. En état test, tous les chants sont ouverts en courte facile (sans être enregistré).
- Le monôme garde toujours sa tête ; les gadz arrivent en marchant et repartent en se dispersant.
- Récompenses : 1 booster par version réussie à 70 % (30 au total, sans plafond) ; **version Maître** d'une carte Chant quand ses 6 versions sont à 90 % ;
  carte hors-série pour un sans-faute sur les 30 versions (`fc_card` dans les réglages du jeu) ;
  **chant de la semaine** : extrait d'une minute tiré chaque lundi, 80 % = 1 booster, meilleur score = 5 boosters dont un god pack (ex aequo tous gagnants, sans l'afficher).
- Menus : Jouer (choix puis Valider), Chant de la semaine, Classements (chant → version → les 3 difficultés), Ma progression (précision, rang, sans-faute), Réglages.
  Touche retour du téléphone : pause en partie, remonte les menus.
- Pistes : `chant/version/difficulté` (ex. `bordels/court/facile`), `semaine/AAAA-MM-JJ` pour le chant de la semaine.
- Pièges connus : certains téléphones renvoient une latence audio absurde (ignorée) ; Opera GX bloquait sur `navigator.vibrate` (vibrations seulement sur écran tactile).

## Mises à jour SQL

| N° | Fichier | Contenu |
|---|---|---|
| 1 | maj-1-offrir | Droit d'offrir des boosters depuis l'appli |
| 2 | maj-2-voir-albums | Voir l'album des autres |
| 3 | maj-3-compte-test | Comptes test |
| 4 | maj-4-proches | Cartes de proches d'un gadz |
| 5 | maj-5-couleurs | Couleurs des illustrations sans photo |
| 6 | maj-6-cadeau | Booster gratuit entre joueurs |
| 7 | maj-7-reinitialiser | Remise à zéro de comptes |
| 8 | maj-8-echanges | Échanges |
| 9 | maj-9-groupes-echange | Groupes de rareté pour les échanges |
| 10 | maj-10-bilan | Bilan admin |
| 11 | maj-11-stats | Stats admin |
| 12 | maj-12-variantes-rarete | Multiplicateur de versions par rareté |
| 13 | maj-13-propositions | Propositions de cartes |
| 14 | maj-14-notifications | Notifications sur téléphone |
| 15 | maj-15-cartes-masquees | Cartes dépubliées hors classement |
| 16 | maj-16-chercher-version | « Qui a cette version ? » |
| 17 | maj-17-echanges-dorees | Dorées et full art échangeables entre elles |
| 18 | maj-18-viscrits | Case Viscrit |
| 19 | maj-19-god-packs | God packs renforcés, god pack garanti à offrir |
| 20 | maj-20-test-sans-trace | Mode test sans trace |
| 21 | maj-21-jeux | Socle des jeux |
| 22 | maj-22-monome-hero | Réglages de Monome Hero, records de la fam's |
| 23 | maj-23-testeurs-jeux | Testeurs de jeux |
| 24 | maj-24-remise-a-zero-jeu | Remise à zéro d'un jeu |
| 25 | maj-25-recompenses-monome-hero | Récompenses, chant de la semaine, version Maître, hors-série |
| 26 | maj-26-rangs-jeux | Rang dans la fam's par piste |

La prochaine mise à jour sera la **n° 27**.

## Tester

- Appli et jeux : serveur local (`python3 -m http.server`) + Playwright, en remplaçant `supabase.js` par un faux client qui renvoie des données de test.
  Le jeu Monome Hero expose `window.__mhDbg` (grow, shrink, combo, photo…) pour les essais automatiques.
- SQL : Postgres local avec des tables simplifiées, pour vérifier les fonctions avant de les donner à Mathieu.
- Toujours vérifier la syntaxe des scripts (`node --check`) et regarder des captures avant de pousser.

## Idées en attente

- Jeu de cartes (duel) : à repenser pour qu'il soit plus fun.
- Cartes « rarissimes » (acier gravé, dédicace façon Zagot's) : pour une grosse mise à jour du jeu de cartes.
- Beer pong : idée de jeu à réfléchir.
- Chant de Kin, Siber's, Le facteur polonais : à ajouter à Monome Hero quand Mathieu aura les éléments.
