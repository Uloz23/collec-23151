# Jeux de la Collec' 23-151

Chaque jeu vit dans son dossier `jeux/<id>/` et n'est chargé que quand un joueur l'ouvre
depuis l'onglet « Jeux ». L'identifiant `<id>` est celui de la ligne du jeu dans l'admin (onglet Jeux).

## Brancher un jeu

`jeux/<id>/jeu.js` :

```js
Collec.jeu("<id>", {
  start(api, root) { /* dessine le jeu dans root (plein écran sous la barre « Quitter ») */ },
  stop() { /* arrête les minuteurs, les sons… (appelé quand on quitte) */ }
});
```

Voir `jeux/demo/jeu.js` pour un exemple complet.

## Ce que fournit `api`

| | |
|---|---|
| `api.game` | `{ id, name, settings }` (réglages de l'admin, sans les récompenses) |
| `api.pseudo`, `api.isTest` | le joueur |
| `api.cards()`, `api.owned(id, version?)` | toutes les cartes publiées, nombre d'exemplaires possédés |
| `api.cardEl(carte, version)`, `api.backEl()` | dessin d'une carte et du dos |
| `api.audio()` | l'AudioContext de l'appli, ou `null` si le son est coupé |
| `api.muted()`, `api.sfx` | état du son, petits sons de l'appli |
| `api.asset(chemin)` | fichier du dépôt : `jeux/<id>/<chemin>` (code, images) |
| `api.media(chemin)` | fichier du stockage Supabase : `medias/jeux/<id>/<chemin>` (sons, gros fichiers) |
| `api.submit(piste, score, précision?, détails?)` | enregistre une partie ; renvoie `{ record, best, previous, rank, boosters, reasons, test }` |
| `api.bests()` | mes records : `{ piste: { score, accuracy, plays, at } }` |
| `api.board(piste, nombre?)` | classement d'une piste |
| `api.progress.get()`, `api.progress.set(données)` | progression libre du joueur (débloquages…), 20 ko max |
| `api.toast(texte)`, `api.quit()` | message bref, fermer le jeu |

## Pistes

Une « piste » est un texte libre qui sépare les records, avec `/` entre les niveaux,
par exemple `bordels/remix/entier/difficile`. Dans La fam's, elle s'affiche « bordels · remix · entier · difficile ».

## Comptes test

Un compte test peut jouer aux jeux en état « test », mais rien n'est enregistré
(ni score, ni progression, ni récompense).
