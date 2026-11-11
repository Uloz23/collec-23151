// Cartes du prototype : données + textes d'effet.
// prom : année de prom's (le .onscrit = 226). fx : codes d'effet lus par le moteur.
(function (root) {
const G = (id, name, prom, fx, text, extra = {}) => ({ id, name, type: "Gadz", rar: extra.rar || "gadz", cost: 0, prom, fx, text, ...extra });
const C = (id, name, type, rar, cost, fx, text, extra = {}) => ({ id, name, type, rar, cost, fx, text, ...extra });

const CARTES = [
  G(1, "Ni'K'ra", 226, ["conscrit"], "Quand Ni'K'ra est tuyssé, il rapporte 2 points (bonus compris). Après 3 tuyssages, Ni'K'ra ne peut plus être tuyssé, mais donne 2 ressources.", { rar: "mythique", conscrit: true }),
  G(2, "Kort", 225, ["draw_on_tuysse"], "Quand Kort tuysse, pioche 1 carte."),
  G(3, "SkoÝ'k", 224, ["res_lineage"], "SkoÝ'k donne 1 ressource de plus si son conscrit ou son ancien est en jeu."),
  G(4, "B&rlioz", 223, ["next_prom_bonus"], "Quand B&rlioz tuysse un Gadz de la prom's qui suit, +1 point."),
  G(5, "R&vol", 222, ["arrive_res"], "À l'arrivée de R&vol, gagne 1 ressource pour ce tour."),
  G(6, "Fe'i'2", 221, ["protect_older"], "Fe'i'2 ne peut pas être visé par les Manip' adverses tant que tu as un Gadz plus ancien en jeu."),
  G(7, "Sali'c'mi", 220, ["keep_ready"], "Quand Sali'c'mi tuysse, le Gadz tuyssé reste dégagé."),
  G(8, "Pordo", 219, ["return_hand"], "Si Pordo devait quitter la zone de manip', Pordo retourne en main à la place."),
  G(9, "Si&ledr|'s", 218, ["res2:Chant"], "Si&ledr|'s peut donner 2 ressources pour jouer un Chant."),
  G(10, "Äk'o", 217, ["arrive_look3"], "À l'arrivée d'Äk'o, regarde les 3 cartes du dessus de ta pioche, garde-en 1 et remets les autres dessous."),
  G(11, "A'i'k'n'fla'i", 216, ["tuyssed_ready"], "Quand A'i'k'n'fla'i est tuyssé, A'i'k'n'fla'i ne s'engage pas."),
  G(12, "Chot²", 215, ["res_untap"], "Quand Chot² donne de la ressource, dégage un autre de tes Gadz (une fois par tour)."),
  G(13, "O'buch&", 214, ["next_prom_bonus"], "Quand O'buch& tuysse un Gadz de la prom's qui suit, +1 point."),
  G(14, "N'chon", 213, ["arrive_draw"], "À l'arrivée de N'chon, pioche 1 carte."),
  G(15, "Di'v§m&ti&", 212, ["res2:Trad's"], "Di'v§m&ti& peut donner 2 ressources pour jouer une Trad's."),
  G(16, "Uloz²", 211, ["res_lineage"], "Uloz² donne 1 ressource de plus si son conscrit ou son ancien est en jeu."),
  G(17, "Niwi", 210, ["leave_draw2"], "Quand Niwi quitte la zone de manip', pioche 2 cartes."),
  G(18, "Omor&", 209, ["arrive_untap"], "À l'arrivée d'Omor&, dégage un autre de tes Gadz."),
  G(19, "G²", 208, ["protect_older"], "G² ne peut pas être visé par les Manip' adverses tant que tu as un Gadz plus ancien en jeu."),
  G(20, "Chto²ch", 207, ["res2:Manip'"], "Chto²ch peut donner 2 ressources pour jouer une Manip'."),
  G(21, "Ur", 206, ["haste_first"], "Tant qu'Ur est en jeu, le premier Gadz que tu poses chaque tour peut tuysser tout de suite."),
  G(22, "Presk", 205, ["arrive_draw_lineage"], "À l'arrivée de Presk, si son conscrit ou son ancien est en jeu, pioche 1 carte."),
  G(23, "V'n'ga", 204, ["next_prom_bonus"], "Quand V'n'ga tuysse un Gadz de la prom's qui suit, +1 point."),
  G(24, "2'Chit", 203, ["arrive_draw"], "À l'arrivée de 2'Chit, pioche 1 carte."),
  G(25, "K'rtapus", 202, ["keep_ready"], "Quand K'rtapus tuysse, le Gadz tuyssé reste dégagé."),
  G(26, "Soron", 200, ["arrive_res"], "À l'arrivée de Soron, gagne 1 ressource pour ce tour."),
  G(27, "Ben", 199, ["draw_on_tuysse"], "Quand Ben tuysse, pioche 1 carte."),
  G(74, "Spar", 198, ["res_lineage"], "Spar donne 1 ressource de plus si son conscrit ou son ancien est en jeu."),
  G(28, "Bo²mbo", 197, ["res2:Tabagn's"], "Bo²mbo peut donner 2 ressources pour jouer un Tabagn's."),
  G(75, "Cir'c'", 197, ["arrive_look3"], "À l'arrivée de Cir'c', regarde les 3 cartes du dessus de ta pioche, garde-en 1 et remets les autres dessous."),
  G(76, "Satur", 197, ["static_next_prom"], "Tant que Satur est en jeu, tes tuyssages entre prom's qui se suivent rapportent +1 point."),
  G(29, "Epi", 196, ["tuyssed_ready"], "Quand Epi est tuyssé, Epi ne s'engage pas."),
  G(30, "Ast'R'X", 196, ["res_untap"], "Quand Ast'R'X donne de la ressource, dégage un autre de tes Gadz (une fois par tour)."),
  G(31, "Sergey", 194, ["arrive_young_res"], "À l'arrivée de Sergey, gagne 1 ressource par Gadz plus jeune que Sergey dans ta zone."),
  G(32, "Äk", 193, ["decade_bonus"], "Les tuyssages d'Äk rapportent +1 point par tranche de 10 prom's d'écart, au lieu du bonus habituel."),
  G(33, "K'psul's", 185, ["tuysse_ready"], "La première fois que K'psul's tuysse chaque tour, K'psul's ne s'engage pas."),
  // Proches : payants, hors limite, donnent de la ressource, ne tuyssent pas
  G(69, "Vic", 211, ["protect_partner"], "Za d'Uloz². Tant que Vic est en jeu, Uloz² ne peut pas être visé par les Manip' adverses.", { proche: "Za", partner: "Uloz²", cost: 1 }),
  G(70, "Guillaume", 219, ["partner_draw"], "Zon de Pordo. Quand Pordo tuysse, pioche 1 carte.", { proche: "Zon", partner: "Pordo", cost: 1 }),

  // Tabagn's
  C(34, "Bordel's", "Tabagn's", "mythique", 4, ["tab_bordels"], "Au début de ton tour, marque 1 point, ou 2 si tu as au moins 5 Gadz en zone de manip'."),
  C(35, "Boquette", "Tabagn's", "commune", 2, ["tab_cost:Chant"], "Tes Chants coûtent 1 de moins."),
  C(36, "Siber's", "Tabagn's", "commune", 2, ["tab_cost:Manip'"], "Tes Manip' coûtent 1 de moins."),
  C(37, "KIN", "Tabagn's", "commune", 2, ["tab_kin"], "Quand un de tes Gadz quitte la zone de manip', pioche 1 carte."),
  C(38, "P3", "Tabagn's", "peu-commune", 3, ["tab_p3"], "Les Gadz que tu poses peuvent tuysser tout de suite."),
  C(39, "Clun's", "Tabagn's", "commune", 2, ["tab_cost:Trad's"], "Tes Trad's coûtent 1 de moins."),
  C(40, "Chalon's", "Tabagn's", "commune", 2, ["tab_chalons"], "Le premier de tes Gadz qui tuysse chaque tour pioche 1 carte."),
  C(41, "Birse", "Tabagn's", "commune", 3, ["tab_birse"], "Au début de ton tour, si tu as moins de Gadz que l'adversaire, pioche 1 carte."),

  // Chants
  C(42, "Monome de Bordel's", "Chant", "mythique", 3, ["monome_all"], "Tous tes Gadz, même engagés, forment un monôme : chacun tuysse le suivant, du plus ancien au plus jeune.", { tab: "Bordel's" }),
  C(43, "Monome de Birse", "Chant", "peu-commune", 1, ["monome:3", "after_draw"], "Monôme de 3 Gadz : le plus ancien tuysse le 2e, qui tuysse le 3e. Puis pioche 1 carte.", { tab: "Birse" }),
  C(44, "Monome de Clun's", "Chant", "peu-commune", 2, ["monome:4"], "Monôme de jusqu'à 4 Gadz : chacun tuysse le suivant, du plus ancien au plus jeune.", { tab: "Clun's" }),
  C(45, "Dans les rues", "Chant", "peu-commune", 1, ["monome:3", "after_point"], "Monôme de 3 Gadz : le plus ancien tuysse le 2e, qui tuysse le 3e. +1 point au total.", { tab: "Boquette" }),
  C(46, "La cousine Lison", "Chant", "peu-commune", 1, ["monome:3", "last_ready"], "Monôme de 3 Gadz : le plus ancien tuysse le 2e, qui tuysse le 3e. Le dernier reste dégagé.", { tab: "Chalon's" }),
  C(47, "Le facteur Polonais", "Chant", "peu-commune", 1, ["draw_per_gadz"], "Défausse 1 carte de ta main. Pioche 1 carte par Gadz dans ta zone de manip' (3 maximum).", { defausse: 1 }),
  C(48, "Hymne des Gadzarts", "Chant", "rare", 1, ["hymne"], "Ce tour-ci, chaque tuyssage rapporte +1 point, y compris ceux déjà faits."),
  C(49, "Monome de Siber's", "Chant", "peu-commune", 1, ["monome:3", "first_ready"], "Monôme de 3 Gadz : le plus ancien tuysse le 2e, qui tuysse le 3e. Le premier ne s'engage pas.", { tab: "Siber's" }),
  C(50, "Le Clocheton", "Chant", "rare", 1, ["clocheton"], "Chacun de tes Gadz encore dégagé s'engage et te fait marquer 1 point."),

  // Trad's
  C(51, "Pian's", "Trad's", "rare", 1, ["draw:1", "untap:1"], "Défausse 1 carte de ta main. Pioche 1 carte et dégage 1 de tes Gadz.", { defausse: 1 }),
  C(52, "Zamat", "Trad's", "commune", 1, ["zamat"], "Regarde les 3 cartes du dessus de ta pioche, prends-en 1 et mets les autres dessous. Ce tour-ci, GGT coûte 1 de moins."),
  C(53, "Week's Fam's", "Trad's", "rare", 3, ["weeks_fams"], "Pose jusqu'à 2 Gadz depuis ta main ou ton K'jib. Ils peuvent tuysser tout de suite."),
  C(54, "Crap's", "Trad's", "commune", 1, ["craps"], "Choisis un Gadz adverse : jusqu'à la fin de son prochain tour, il ne peut ni tuysser ni être tuyssé."),
  C(55, "Gorgu", "Trad's", "rare", 1, ["gorgu"], "Ce tour-ci, chacun de tes Gadz donne 2 ressources au lieu d'1."),
  C(56, "Monome", "Trad's", "commune", 1, ["pts_per_chant"], "Marque 1 point par Chant dans ton K'jib (4 maximum)."),
  C(57, "Zag", "Trad's", "peu-commune", 2, ["zag_pts"], "Tenue réglementaire : marque 3 points si tu as au moins 5 Gadz dans ta zone de manip'."),
  C(58, "Patator", "Trad's", "commune", 1, ["patator"], "Défausse 1 carte de ta main (elle sert de patate). Renvoie un Gadz adverse sur le dessus de la pioche de son propriétaire.", { defausse: 1 }),
  C(59, "Biaude", "Trad's", "commune", 1, ["biaude_pts"], "Au boulot : marque 1 point par carte que tu as engagée pour de la ressource ce tour (3 maximum)."),
  C(60, "Carn's", "Trad's", "commune", 1, ["draw:2"], "Défausse 1 carte de ta main. Pioche 2 cartes.", { defausse: 1 }),
  C(61, "Gala des Fignos", "Trad's", "rare", 3, ["gala"], "Coûte 1 de moins par Gadz de ta zone tuyssé ce tour. Marque 2 points par Gadz de ta zone tuyssé ce tour."),
  C(62, "La Rochefouc's", "Trad's", "mythique", 3, ["rochefoucs"], "Le fondateur : marque 2 points par tuyssage fait ce tour, puis dégage tous tes Gadz."),
  C(63, "Bandes", "Trad's", "commune", 1, ["untap:2"], "Défausse 1 carte de ta main. Dégage jusqu'à 2 de tes Gadz.", { defausse: 1 }),
  C(64, "Gnassage", "Trad's", "commune", 0, ["gnassage"], "Défausse 1 carte de ta main. Au début de ton prochain tour, gagne 3 ressources.", { defausse: 1 }),
  C(65, "GGT", "Trad's", "peu-commune", 1, ["ggt"], "Ce tour-ci, un de tes Gadz peut tuysser 2 Gadz plus jeunes au lieu d'un seul, et ses tuyssages rapportent +1 point."),
  C(66, "Week's P3", "Trad's", "rare", 1, ["weeks_p3"], "Chaque joueur remet sa main dans sa pioche, mélange et repioche autant de cartes. Toi, tu en pioches 1 de plus et tu marques 1 point."),
  C(67, "CP", "Trad's", "peu-commune", 2, ["cp"], "Choisis un de tes Gadz : jusqu'à la fin de la partie, il gagne aussi l'effet d'un autre de tes Gadz en jeu."),
  C(68, "La 23-151", "Trad's", "mythique", 0, ["pts_x"], "Coût X : marque X points, sans dépasser le nombre de Gadz dans ta zone de manip'.", { costX: true }),
  C(73, "Pin's Trad's", "Trad's", "commune", 1, ["pins_pts"], "Défausse 1 carte de ta main. Marque 1 point par Trad's dans ton K'jib (4 maximum).", { defausse: 1 }),

  // Carte provisoire pour tester une « remise à zéro » (pas encore dans la Collec')
  C(900, "Vacances d'été", "Trad's", "rare", 4, ["vacances"], "Le tabagn's se vide : tous les Gadz, Za et Zon des deux joueurs retournent dans la pioche de leur propriétaire, qui la mélange.", { provisoire: true }),

  // Manip' (jouables à tout moment)
  C(71, "Sandwich Couscous", "Manip'", "commune", 0, ["sandwich"], "Défausse 1 carte de ta main. Engage un de tes Gadz dégagés : il donne 2 ressources de plus.", { defausse: 1 }),
  C(72, "Jetplack's de fam's", "Manip'", "rare", 2, ["jetplacks"], "Engage jusqu'à 2 Gadz adverses."),
];
const PAR_ID = Object.fromEntries(CARTES.map(c => [c.id, c]));
const api = { CARTES, PAR_ID };
if (typeof module !== "undefined") module.exports = api; else root.Cartes = api;
})(this);
