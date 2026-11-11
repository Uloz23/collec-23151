// Moteur du jeu : règles, effets, IA. Fonctionne dans le navigateur et dans Node (simulations).
(function (root) {
const { CARTES, PAR_ID } = typeof module !== "undefined" ? require("./cartes.js") : root.Cartes;

const TYPES_RES = ["Chant", "Trad's", "Manip'", "Tabagn's"];
function rngFrom(seed) { let a = seed >>> 0 || 1; return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

// ---------------- Construction de deck ----------------
// Deck aléatoire légal : 30 cartes, 2 exemplaires max, 13 à 15 Gadz (proches compris)
function deckAleatoire(R, opts = {}) {
  const pool = CARTES.filter(c => !(opts.exclure || []).includes(c.id));
  const gadz = pool.filter(c => c.type === "Gadz"), autres = pool.filter(c => c.type !== "Gadz");
  const pick = (list, n) => { const out = [], cnt = {}; let guard = 0; while (out.length < n && guard++ < 5000) { const c = list[Math.floor(R() * list.length)]; if ((cnt[c.id] || 0) >= 2) continue; cnt[c.id] = (cnt[c.id] || 0) + 1; out.push(c.id); } return out; };
  // Une bonne part de Gadz (16 à 18) et au plus 2 Tabagn's
  const nG = opts.nG != null ? opts.nG : 16 + Math.floor(R() * 3), nT = opts.nT != null ? opts.nT : Math.floor(R() * 3);
  const tabs = autres.filter(c => c.type === "Tabagn's"), reste = autres.filter(c => c.type !== "Tabagn's");
  const t = []; while (t.length < nT) { const c = tabs[Math.floor(R() * tabs.length)]; if (!t.includes(c.id)) t.push(c.id); }
  return [...pick(gadz, nG), ...t, ...pick(reste, 30 - nG - t.length)];
}

// ---------------- Partie ----------------
function nouvellePartie(opts) {
  const R = rngFrom(opts.seed || (Date.now() & 0xffffff));
  const g = {
    R, opts: { cible: 23, arrivee: "A", penalite: 5, ...opts },
    tour: 0, actif: 0, fini: false, gagnant: null, log: [], uid: 1,
    joueurs: [0, 1].map(i => ({
      i, nom: opts.noms ? opts.noms[i] : (i ? "IA" : "Toi"), points: 0,
      pioche: [], main: [], zone: [], tab: null, kjib: [],
      pool: { any: 0 }, gadzPose: false, tempo: {}, prochain: {}, stats: { tuysse: 0, ptsTuysse: 0, ptsCartes: 0, remel: 0, joues: {} },
    })),
  };
  g.joueurs.forEach((p, i) => {
    p.pioche = melanger(g, (opts.decks[i] || deckAleatoire(R)).map(id => inst(g, id, i)));
    // Main de départ : 5 cartes, au moins 1 Gadz (non proche)
    const k = p.pioche.findIndex(c => c.def.type === "Gadz" && !c.def.proche);
    if (k >= 0) p.main.push(p.pioche.splice(k, 1)[0]);
    while (p.main.length < 5 && p.pioche.length) p.main.push(p.pioche.shift());
  });
  g.actif = opts.premier != null ? opts.premier : (R() < .5 ? 0 : 1);
  g.premier = g.actif;
  // Compensation du second joueur
  const sec = g.joueurs[1 - g.actif], comp = (g.opts.compensation || "carte+point").split("+");
  if (comp.includes("carte")) piocher(g, sec, 1);
  if (comp.includes("ressource")) sec.prochain.res = 1;
  if (comp.includes("point")) sec.points = 1;
  if (comp.includes("point2")) sec.points = 2;
  if (comp.includes("gadz")) sec.extraPose = true;
  debutTour(g);
  return g;
}
function inst(g, id, owner) { return { uid: g.uid++, def: PAR_ID[id], owner, engage: false, arrive: -1, haste: false, tuysseCnt: 0, tuysseMax: 1, tuysseDuTour: false, recus: 0, pinsBonus: 0, biaude: -1, crap: -1, extraFx: [], untapUsed: false, viaTuysse: false }; }
function melanger(g, a) { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(g.R() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }
const adv = (g, p) => g.joueurs[1 - p.i];
const fx = c => [...c.def.fx, ...c.extraFx];
const a = (c, code) => fx(c).some(f => f === code || f.startsWith(code + ":"));
const vrai_gadz = c => c.def.type === "Gadz" && !c.def.proche;
function log(g, txt, cls) { g.log.push({ t: g.tour, txt, cls }); if (g.onLog) g.onLog(txt, cls); }

function gagner(g, p, n, source, pourquoi) {
  if (n <= 0 || g.fini) return;
  p.points += n;
  if (source === "tuysse") p.stats.ptsTuysse += n; else p.stats.ptsCartes += n;
  log(g, `${p.nom} marque ${n} point${n > 1 ? "s" : ""}${pourquoi ? " (" + pourquoi + ")" : ""} → ${p.points}`, "pts");
  if (p.points >= g.opts.cible) { g.fini = true; g.gagnant = p.i; log(g, `🏆 ${p.nom} atteint ${g.opts.cible} points de Trad's et gagne !`, "fin"); }
}
function piocher(g, p, n = 1) {
  for (let k = 0; k < n; k++) {
    if (!p.pioche.length) {
      if (!p.kjib.length) return;
      p.pioche = melanger(g, p.kjib.splice(0));
      p.stats.remel++;
      log(g, `${p.nom} a vidé sa pioche : on remélange le K'jib.`, "warn");
      gagner(g, adv(g, p), g.opts.penalite, "cartes", "pioche vide adverse");
    }
    p.main.push(p.pioche.shift());
  }
}

// ---------------- Tours ----------------
function debutTour(g) {
  if (g.fini) return;
  g.tour++;
  const p = g.joueurs[g.actif], o = adv(g, p);
  p.gadzPose = false; p.tempo = { tuyssages: 0, tuysses: new Set(), hymne: false, gorgu: false, zamat: false, chalons: false, premierPose: false };
  p.pool = { any: 0 };
  for (const c of p.zone) { c.engage = false; c.tuysseCnt = 0; c.tuysseMax = a(c, "tuysse_ready") ? 2 : 1; c.tuysseDuTour = false; c.untapUsed = false; c.viaTuysse = false; if (c.biaude < g.tour) c.biaude = -1; }
  if (p.zagJusqua != null && p.zagJusqua < g.tour) p.zagJusqua = null;
  if (p.prochain.res) { p.pool.any += p.prochain.res; log(g, `${p.nom} récupère ${p.prochain.res} ressources (Gnassage).`); p.prochain.res = 0; }
  if (p.tab && a(p.tab, "tab_bordels") && p.zone.length >= 4) gagner(g, p, 1, "cartes", "Bordel's");
  if (p.tab && a(p.tab, "tab_birse") && p.zone.filter(c => c.def.type === "Gadz").length < o.zone.filter(c => c.def.type === "Gadz").length) { piocher(g, p, 1); log(g, `${p.nom} pioche 1 carte (Birse).`); }
  const premierTour = g.tour === 1;
  if (!premierTour) piocher(g, p, 1);
  log(g, `— Tour ${g.tour} : ${p.nom} —`, "tour");
}
function finTour(g) {
  if (g.fini) return;
  const p = g.joueurs[g.actif];
  // Les effets « jusqu'à la fin de son prochain tour » (Crap's) expirent
  for (const c of p.zone) if (c.crap === g.tour) c.crap = -1;
  g.joueurs.forEach(j => j.pool = { any: 0 });
  g.actif = 1 - g.actif;
  debutTour(g);
}

// ---------------- Ressource ----------------
function lignee(p, c) { return p.zone.some(x => x !== c && vrai_gadz(x) && Math.abs(x.def.prom - c.def.prom) === 1); }
function valeurRes(g, p, c) {
  let n = c.def.conscrit && c.recus >= 3 ? 2 : 1;
  if (a(c, "res_lineage") && lignee(p, c)) n++;
  n += c.pinsBonus;
  if (c.biaude >= g.tour) n++;
  if (p.tempo && p.tempo.gorgu && g.actif === p.i) n++;
  return n;
}
// Qui décide : l'interface pour un joueur humain (g.choixPar[i]), sinon l'IA
const choisir = (g, p, q) => (g.choixPar && g.choixPar[p.i]) ? g.choixPar[p.i](g, p, q) : choixIA(g, p, q);
const humain = (g, p) => !!(g.choixPar && g.choixPar[p.i]);
// Dégager jusqu'à n cartes engagées de sa zone (le joueur choisit lesquelles)
async function degager(g, p, sauf, n, qui) {
  const cands = p.zone.filter(x => x !== sauf && x.engage && !(a(x, "res_untap") && x.untapUsed));
  if (!cands.length) return;
  const pris = [].concat(await choisir(g, p, { carte: { def: { name: qui } }, type: "degager", options: cands, n: Math.min(n, cands.length) }) || []).slice(0, n);
  for (const t of pris) { t.engage = false; log(g, `${qui} : ${t.def.name} est dégagé.`); }
}
function bloqueC(g, c) { return g.opts.arrivee === "C" && c.arrive === g.tour && !c.haste; }
function peutEngager(g, c) { return !c.engage && !bloqueC(g, c); }
// type : null = ressource normale, sinon ressource réservée (Chant, Trad's…)
async function engager(g, p, c, type = null, bonus = 0) {
  if (c.engage || bloqueC(g, c)) return false;
  c.engage = true;
  if (g.actif === p.i && p.tempo) p.tempo.engagesRes = (p.tempo.engagesRes || 0) + 1;
  const n = valeurRes(g, p, c) + bonus;
  const r = fx(c).find(f => f.startsWith("res2:"));
  if (type && r && r.split(":")[1] === type) { p.pool[type] = (p.pool[type] || 0) + Math.max(2, n); log(g, `${p.nom} engage ${c.def.name} : +${Math.max(2, n)} pour un ${type}.`); }
  else { p.pool.any += n; log(g, `${p.nom} engage ${c.def.name} : +${n} ressource${n > 1 ? "s" : ""}.`); }
  if (a(c, "res_untap") && !c.untapUsed) {
    c.untapUsed = true;
    await degager(g, p, c, 1, c.def.name);
  }
  return true;
}
function choisirADegager(g, p, sauf) {
  // On dégage en priorité un Gadz qui peut encore tuysser, sinon n'importe lequel
  const cands = p.zone.filter(x => x !== sauf && x.engage && !(a(x, "res_untap") && x.untapUsed));
  cands.sort((x, y) => (vrai_gadz(y) - vrai_gadz(x)) || (valeurRes(g, p, y) - valeurRes(g, p, x)));
  return cands[0] || null;
}
function totalPool(p, type) { return p.pool.any + (type ? (p.pool[type] || 0) : 0); }
function cout(g, p, c) {
  let k = c.def.cost;
  if (c.def.type === "Gadz") return k;
  if (p.tab) {
    const t = fx(p.tab).find(f => f.startsWith("tab_cost:"));
    let red = 0;
    if (t && t.split(":")[1] === c.def.type) red = 1;
    if (c.def.tab && p.tab.def.name === c.def.tab) red = 1; // le monôme coûte 1 de moins avec son Tabagn's (pas de cumul)
    k -= red;
  }
  if (c.def.name === "GGT" && p.tempo && p.tempo.zamat) k -= 1;
  if (g.opts.reduction && c.def.type !== "Tabagn's" && c.def.cost >= 2) k -= g.opts.reduction;
  if (c.def.fx[0] === "gala") return Math.max(0, k - (p.tempo ? p.zone.filter(x => p.tempo.tuysses && p.tempo.tuysses.has(x.uid)).length : 0));
  return Math.max(0, k);
}
// Potentiel : ressources dispo + ce que les cartes dégagées pourraient donner
function potentiel(g, p, type) { return totalPool(p, type) + p.zone.filter(c => !c.engage && !bloqueC(g, c)).reduce((s, c) => s + (type && fx(c).some(f => f === "res2:" + type) ? Math.max(2, valeurRes(g, p, c)) : valeurRes(g, p, c)), 0); }
async function payer(g, p, montant, type, reserves = new Set()) {
  if (humain(g, p) && totalPool(p, type) < montant) {
    const dispo = p.zone.filter(c => !c.engage && !bloqueC(g, c));
    const pris = await choisir(g, p, { carte: { def: { name: "Paiement" } }, type: "payer", options: dispo, besoin: montant - totalPool(p, type), resType: type, n: dispo.length });
    if (!pris) return false;
    for (const c of pris) await engager(g, p, c, type && fx(c).includes("res2:" + type) ? type : null);
  }
  // On engage automatiquement ce qu'il faut, en gardant les Gadz réservés (pour tuysser)
  const ordre = () => p.zone.filter(c => !c.engage && !bloqueC(g, c) && !reserves.has(c.uid)).sort((x, y) => scoreGarder(g, p, x) - scoreGarder(g, p, y));
  let guard = 0;
  while (totalPool(p, type) < montant && guard++ < 20) {
    const l = ordre(); if (!l.length) break;
    const res2 = l.find(c => type && fx(c).includes("res2:" + type));
    await engager(g, p, res2 || l[0], res2 ? type : null);
  }
  if (totalPool(p, type) < montant) return false;
  let reste = montant;
  if (type && p.pool[type]) { const u = Math.min(p.pool[type], reste); p.pool[type] -= u; reste -= u; }
  p.pool.any -= reste;
  return true;
}
function scoreGarder(g, p, c) { // plus c'est bas, plus on l'engage volontiers
  if (!vrai_gadz(c)) return -10;
  if (c.def.conscrit && c.recus >= 3) return -8;
  return -valeurRes(g, p, c) + (peutParticiper(g, p, c) ? 5 : 0);
}

// ---------------- Poser des cartes ----------------
function peutPoserGadz(g, p, c) {
  if (c.def.type !== "Gadz") return false;
  // Une même personne ne peut pas être deux fois dans la zone de manip'
  if (p.zone.some(x => x.def.id === c.def.id)) return false;
  if (c.def.proche) return true;
  return !p.gadzPose;
}
async function arriver(g, p, c, opts = {}) {
  c.engage = false; c.arrive = g.tour; c.recus = c.recus || 0; c.tuysseCnt = 0; c.tuysseMax = a(c, "tuysse_ready") ? 2 : 1;
  c.haste = !!opts.haste || (p.tab && a(p.tab, "tab_p3")) || (!c.def.proche && p.zone.some(x => a(x, "haste_first")) && !p.tempo.premierPose);
  if (!c.def.proche) p.tempo.premierPose = true;
  p.zone.push(c);
  log(g, `${p.nom} pose ${c.def.name}.`);
  if (a(c, "arrive_draw")) { piocher(g, p, 1); log(g, `${c.def.name} : pioche 1.`); }
  if (a(c, "arrive_draw_lineage") && lignee(p, c)) { piocher(g, p, 1); log(g, `${c.def.name} : pioche 1 (lignée).`); }
  if (a(c, "arrive_res")) { p.pool.any += 1; log(g, `${c.def.name} : +1 ressource.`); }
  if (a(c, "arrive_young_res")) { const n = p.zone.filter(x => vrai_gadz(x) && x.def.prom > c.def.prom).length; p.pool.any += n; log(g, `${c.def.name} : +${n} ressource${n > 1 ? "s" : ""}.`); }
  if (a(c, "arrive_untap")) await degager(g, p, c, 1, c.def.name);
  if (a(c, "arrive_look3")) await regarder3(g, p, c.def.name, "dessous");
}
// Regarder les 3 cartes du dessus et en prendre 1 ; les autres vont dessous (Äk'o, Cir'c') ou restent dessus (Zamat)
async function regarder3(g, p, qui, reste = "dessous") {
  const top = p.pioche.slice(0, 3); if (!top.length) return;
  const garde = await choisir(g, p, { carte: { def: { name: qui } }, type: "regarder", options: top, n: 1, reste }) || top[0];
  p.pioche.splice(p.pioche.indexOf(garde), 1); p.main.push(garde);
  if (reste === "dessous") for (const r of top.filter(x => x !== garde)) { p.pioche.splice(p.pioche.indexOf(r), 1); p.pioche.push(r); }
  log(g, `${qui} : ${p.nom} regarde 3 cartes et en garde 1.`);
}
function valeurCarte(g, p, c, besoinGadz) { if (vrai_gadz(c)) return besoinGadz ? 10 : 3; return 2 + Math.min(c.def.cost, 5) * .5; }

function quitterZone(g, p, c) {
  p.zone.splice(p.zone.indexOf(c), 1);
  c.engage = false; c.extraFx = []; c.pinsBonus = 0;
  p.main.push(c);
  log(g, `${c.def.name} retourne dans la main de ${p.nom}.`);
  if (a(c, "leave_draw2")) { piocher(g, p, 2); log(g, `${c.def.name} : pioche 2.`); }
  if (p.tab && a(p.tab, "tab_kin")) { piocher(g, p, 1); log(g, `KIN : ${p.nom} pioche 1.`); }
}

// ---------------- Tuyssage ----------------
function nouveau(g, p, c) { return c.arrive === g.tour && !c.haste && g.opts.arrivee !== "B"; }
function peutParticiper(g, p, c) { return vrai_gadz(c) && !nouveau(g, p, c) && c.crap < 0; }
function peutTuysser(g, p, anc, jeune, chaine = false) {
  if (!anc || !jeune || anc === jeune) return false;
  if (!vrai_gadz(anc) || !vrai_gadz(jeune)) return false;
  if (anc.def.prom >= jeune.def.prom) return false;
  if (!peutParticiper(g, p, anc) || !peutParticiper(g, p, jeune)) return false;
  if (jeune.def.conscrit && jeune.recus >= 3) return false;
  if (chaine) return true;
  if (jeune.engage) return false;
  // Pas de limite par tour : un Gadz tuysse tant qu'il est dégagé (K'psul's et GGT peuvent en plus retuysser engagés)
  if (!anc.engage) return true;
  return anc.viaTuysse && anc.tuysseCnt < anc.tuysseMax;
}
function pointsTuysse(g, p, anc, jeune) {
  const d = jeune.def.prom - anc.def.prom;
  let n = jeune.def.conscrit ? 2 : 1;
  if (a(anc, "decade_bonus")) n += Math.floor(d / 10);
  else if (d === 1 || d >= 10) n += 1;
  if (d === 1 && p.zone.some(x => a(x, "static_next_prom"))) n += 1;
  if (d === 1 && a(anc, "next_prom_bonus")) n += 1;
  if (p.tempo.hymne) n += 1;
  if (anc.ggtBonus === g.tour) n += 1;
  return n;
}
async function tuysser(g, p, anc, jeune, opts = {}) {
  if (!peutTuysser(g, p, anc, jeune, opts.chaine)) return false;
  // Fenêtre de réaction de l'adversaire (Manip')
  if (!opts.sansReaction && g.reaction) {
    const annule = await g.reaction(g, adv(g, p), { type: "tuysse", anc, jeune, joueur: p });
    if (annule && !peutTuysser(g, p, anc, jeune, opts.chaine)) { log(g, `Le tuyssage ${anc.def.name} → ${jeune.def.name} n'a pas lieu.`, "warn"); return false; }
  }
  const pts = pointsTuysse(g, p, anc, jeune);
  if (!opts.chaine) {
    // Un Gadz qui peut tuysser plusieurs fois (K'psul's, GGT) ne s'engage qu'une fois qu'il a fini
    anc.viaTuysse = true;
    if (anc.tuysseCnt + 1 >= anc.tuysseMax) anc.engage = true;
  }
  anc.tuysseCnt++;
  // « Ne s'engage pas » / « reste dégagé » : seulement la première fois par tour pour un même Gadz
  const garderJeune = (a(jeune, "tuyssed_ready") || a(anc, "keep_ready")) && jeune.gardeTour !== g.tour;
  if (garderJeune) jeune.gardeTour = g.tour; else jeune.engage = true;
  jeune.tuysseDuTour = true;
  jeune.recus++;
  p.tempo.tuyssages++; p.tempo.tuysses.add(jeune.uid);
  p.stats.tuysse++;
  log(g, `${anc.def.name} tuysse ${jeune.def.name}.`, "tuy");
  gagner(g, p, pts, "tuysse", `${anc.def.name} → ${jeune.def.name}`);
  if (g.onEvent) await g.onEvent("tuysse", { p, anc, jeune, pts });
  if (jeune.def.conscrit && jeune.recus === 3) log(g, `${jeune.def.name} a été tuyssé 3 fois : il donne désormais 2 ressources.`);
  if (a(anc, "draw_on_tuysse")) { piocher(g, p, 1); log(g, `${anc.def.name} : pioche 1.`); }
  if (anc.def.name === "Pordo" && p.zone.some(x => a(x, "partner_draw"))) { piocher(g, p, 1); log(g, `Guillaume : pioche 1.`); }
  if (p.tab && a(p.tab, "tab_chalons") && !p.tempo.chalons) { p.tempo.chalons = true; piocher(g, p, 1); log(g, `Chalon's : pioche 1.`); }
  return true;
}

// ---------------- Protection contre les Manip' ----------------
function protege(g, owner, c) {
  if (owner.zagJusqua != null && owner.zagJusqua >= g.tour) return true;
  if (c.biaude >= g.tour) return true;
  if (a(c, "protect_older") && owner.zone.some(x => vrai_gadz(x) && x.def.prom < c.def.prom)) return true;
  if (owner.zone.some(x => a(x, "protect_partner") && x.def.partner === c.def.name)) return true;
  return false;
}

// ---------------- Jouer une carte ----------------
// choix(g, p, question) → réponse ; fourni par l'IA ou par l'interface
function cibles(g, p, c) {
  const o = adv(g, p);
  switch (c.def.fx[0]) {
    case "craps": return o.zone.filter(vrai_gadz);
    case "patator": return o.zone.filter(x => x.def.type === "Gadz");
    case "jetplacks": return o.zone.filter(x => !x.engage && !protege(g, o, x));
    case "biaude": case "pins": return p.zone.filter(x => x.def.type === "Gadz");
    case "sandwich": return p.zone.filter(x => !x.engage);
    case "ggt": return p.zone.filter(vrai_gadz);
    case "cp": return p.zone.filter(vrai_gadz).length >= 2 ? p.zone.filter(vrai_gadz) : [];
    default: return null;
  }
}
function jouable(g, p, c, enReaction = false) {
  if (g.fini) return false;
  const monTour = g.actif === p.i;
  if (c.def.type === "Gadz") { if (!monTour || enReaction) return false; if (!peutPoserGadz(g, p, c)) return false; return potentiel(g, p, null) >= c.def.cost; }
  if (c.def.type !== "Manip'" && (!monTour || enReaction)) return false;
  const t = cibles(g, p, c); if (t && !t.length) return false;
  if (c.def.defausse && p.main.filter(x => x !== c).length < c.def.defausse) return false;
  const k = cout(g, p, c);
  return potentiel(g, p, c.def.type) >= k;
}
async function jouer(g, p, c, choix, opts = {}) {
  if (!jouable(g, p, c, opts.reaction)) return false;
  const k = c.def.type === "Gadz" ? c.def.cost : cout(g, p, c);
  // Cible choisie AVANT de payer (sinon on risque de s'engager soi-même la cible)
  let cible = null, cible2 = null;
  const t = cibles(g, p, c);
  if (t) {
    cible = await choix(g, p, { carte: c, type: "cible", options: t, n: c.def.fx[0] === "jetplacks" ? 2 : 1 });
    if (!cible || (Array.isArray(cible) && !cible.length)) return false;
    if (c.def.fx[0] === "cp") { cible2 = await choix(g, p, { carte: c, type: "source", options: p.zone.filter(x => vrai_gadz(x) && x !== cible), n: 1 }); if (!cible2) return false; }
  }
  // Coût supplémentaire : défausser une carte de la main
  let defs = [];
  if (c.def.defausse) {
    defs = [].concat(await choix(g, p, { carte: c, type: "defausse", options: p.main.filter(x => x !== c), n: c.def.defausse }) || []);
    if (defs.length < c.def.defausse) return false;
  }
  const reserves = new Set(opts.reserves || []);
  if (cible && !Array.isArray(cible) && c.def.fx[0] === "sandwich") reserves.add(cible.uid);
  if (k > 0 && !(await payer(g, p, k, c.def.type === "Gadz" ? null : c.def.type, reserves))) return false;
  p.main.splice(p.main.indexOf(c), 1);
  for (const x of defs) { p.main.splice(p.main.indexOf(x), 1); p.kjib.push(x); log(g, `${p.nom} défausse ${x.def.name}.`); }
  p.stats.joues[c.def.name] = (p.stats.joues[c.def.name] || 0) + 1;
  if (c.def.type === "Gadz") { if (!c.def.proche) { if (p.extraPose) p.extraPose = false; else p.gadzPose = true; } await arriver(g, p, c); if (g.onEvent) await g.onEvent("pose", { p, c }); return true; }
  log(g, `${p.nom} joue ${c.def.name}${k ? " (" + k + ")" : ""}.`, "carte");
  if (g.onEvent) await g.onEvent("joue", { p, c, k });
  if (c.def.type === "Tabagn's") { if (p.tab) p.kjib.push(p.tab); p.tab = c; return true; }
  await effet(g, p, c, choix, cible, cible2);
  p.kjib.push(c);
  return true;
}
async function effet(g, p, c, choix, cible, cible2) {
  const o = adv(g, p);
  for (const f of c.def.fx) {
    const [code, arg] = f.split(":");
    switch (code) {
      case "draw": piocher(g, p, +arg); break;
      case "untap": await degager(g, p, null, +arg, c.def.name); break;
      case "zamat": await regarder3(g, p, "Zamat", "dessus"); p.tempo.zamat = true; break;
      case "weeks_fams": {
        const dispo = [...p.main.filter(vrai_gadz), ...p.kjib.filter(vrai_gadz)].filter((x, i, l) => !p.zone.some(z => z.def.id === x.def.id) && l.findIndex(y => y.def.id === x.def.id) === i);
        const pris = await choix(g, p, { carte: c, type: "weeks", options: dispo, n: 2 }) || [];
        for (const x of [].concat(pris).slice(0, 2)) { const src = p.main.includes(x) ? p.main : p.kjib; src.splice(src.indexOf(x), 1); await arriver(g, p, x, { haste: true }); }
        break;
      }
      case "craps": cible.crap = g.tour + 1 + (cible.owner === g.actif ? 0 : 0); cible.crap = g.tour + 1; log(g, `${cible.def.name} est Crap's jusqu'à la fin du prochain tour de ${o.nom}.`); break;
      case "gorgu": p.tempo.gorgu = true; log(g, `Gorgu : ce tour-ci, chaque Gadz donne 1 ressource de plus.`); break;
      case "pts_per_chant": gagner(g, p, Math.min(4, p.kjib.filter(x => x.def.type === "Chant").length), "cartes", "Monome"); break;
      case "zag_pts": if (p.zone.filter(vrai_gadz).length >= 5) gagner(g, p, 3, "cartes", "Zag"); break;
      case "biaude_pts": gagner(g, p, Math.min(3, p.tempo.engagesRes || 0), "cartes", "Biaude"); break;
      case "pins_pts": gagner(g, p, Math.min(4, p.kjib.filter(x => x.def.type === "Trad's").length), "cartes", "Pin's Trad's"); break;
      case "zag": p.zagJusqua = g.tour + 1; log(g, `Zag : les Gadz de ${p.nom} sont protégés des Manip'.`); break;
      case "patator": {
        if (cible.def.name === "Pordo" || a(cible, "return_hand")) { /* retourne en main de toute façon */ }
        quitterZone(g, o, cible);
        if (!(cible.def.name === "Pordo")) { o.main.splice(o.main.indexOf(cible), 1); o.pioche.unshift(cible); log(g, `${cible.def.name} part sur le dessus de la pioche de ${o.nom}.`); }
        break;
      }
      case "biaude": cible.biaude = g.tour + 1; log(g, `Biaude sur ${cible.def.name}.`); break;
      case "gala": gagner(g, p, 2 * p.zone.filter(x => p.tempo.tuysses.has(x.uid)).length, "cartes", "Gala des Fignos"); break;
      case "rochefoucs": gagner(g, p, p.tempo.tuyssages, "cartes", "La Rochefouc's"); for (const x of p.zone) { x.engage = false; x.tuysseCnt = 0; x.viaTuysse = false; } log(g, `Tous les Gadz de ${p.nom} sont dégagés.`); break;
      case "gnassage": p.prochain.res = (p.prochain.res || 0) + 3; break;
      case "ggt": cible.tuysseMax += 1; cible.ggtBonus = g.tour; if (cible.engage && cible.viaTuysse) { /* peut encore tuysser */ } log(g, `GGT : ${cible.def.name} peut tuysser une fois de plus ce tour.`); break;
      case "weeks_p3": for (const j of g.joueurs) { const n = j.main.length; j.pioche.push(...j.main.splice(0)); melanger(g, j.pioche); piocher(g, j, n + (j === p ? 1 : 0)); } log(g, `Week's P3 : tout le monde repioche !`); gagner(g, p, 1, "cartes", "Week's P3"); break;
      case "cp": { const src = fx(cible2).filter(f => f !== "conscrit"); cible.extraFx.push(...src); log(g, `CP : ${cible.def.name} gagne l'effet de ${cible2.def.name}.`); break; }
      case "pts_per_gadz": gagner(g, p, Math.min(6, p.zone.filter(x => x.def.type === "Gadz").length), "cartes", "La 23-151"); break;
      case "pins": cible.pinsBonus += 1; log(g, `Pin's Trad's : ${cible.def.name} donne 1 ressource de plus.`); break;
      case "sandwich": await engager(g, p, cible, null, 2); break;
      case "jetplacks": for (const x of [].concat(cible).slice(0, 2)) { if (!protege(g, o, x)) { x.engage = true; log(g, `${x.def.name} est engagé (quillons !).`); } } break;
      case "vacances": {
        for (const j of g.joueurs) for (const x of j.zone.filter(y => y.def.type === "Gadz")) quitterZone(g, j, x);
        log(g, `Vacances d'été : tous les Gadz retournent en main.`, "warn");
        // La rentrée : celui qui l'a jouée repose aussitôt jusqu'à 3 Gadz
        const dispo = p.main.filter(vrai_gadz).filter((x, i, l) => l.findIndex(y => y.def.id === x.def.id) === i);
        const pris = await choix(g, p, { carte: c, type: "weeks", options: dispo, n: 3 }) || [];
        for (const x of [].concat(pris).slice(0, 3)) { p.main.splice(p.main.indexOf(x), 1); await arriver(g, p, x); }
        break;
      }
      case "hymne": p.tempo.hymne = true; log(g, `Hymne : ce tour-ci, chaque tuyssage rapporte +1.`); gagner(g, p, p.tempo.tuyssages, "cartes", "Hymne, tuyssages déjà faits"); break;
      case "draw_per_gadz": piocher(g, p, Math.min(3, p.zone.filter(x => x.def.type === "Gadz").length)); break;
      case "clocheton": { const l = p.zone.filter(x => vrai_gadz(x) && !x.engage); l.forEach(x => x.engage = true); gagner(g, p, l.length, "cartes", "Le Clocheton"); break; }
      case "monome": case "monome_all": {
        const max = code === "monome_all" ? 99 : +arg;
        const dispo = p.zone.filter(x => vrai_gadz(x) && (code === "monome_all" || !x.engage) && peutParticiper(g, p, x));
        let file = await choix(g, p, { carte: c, type: "monome", options: dispo, n: max }) || [];
        file = [].concat(file).sort((x, y) => x.def.prom - y.def.prom);
        let ok = 0;
        for (let i = 0; i + 1 < file.length; i++) {
          const anc = file[i], jeune = file[i + 1];
          if (anc.def.prom === jeune.def.prom) continue;
          if (await tuysser(g, p, anc, jeune, { chaine: true, sansReaction: i > 0 })) ok++;
        }
        file.forEach((x, i) => { const garde = (c.def.fx.includes("first_ready") && i === 0) || (c.def.fx.includes("last_ready") && i === file.length - 1); if (!garde) x.engage = true; else x.engage = false; });
        if (ok && c.def.fx.includes("after_point")) gagner(g, p, 1, "cartes", c.def.name);
        if (c.def.fx.includes("after_draw")) piocher(g, p, 1);
        break;
      }
    }
    if (g.fini) return;
  }
}

// =====================================================================
//                                IA
// =====================================================================
// Paires de tuyssage : on cherche la meilleure combinaison (petites zones → recherche exhaustive bornée)
function meilleuresPaires(g, p, exclus = new Set()) {
  const l = p.zone.filter(c => vrai_gadz(c) && !exclus.has(c.uid));
  let best = { pts: 0, paires: [] };
  const used = new Set();
  function rec(paires, pts, depth) {
    if (pts > best.pts) best = { pts, paires: paires.slice() };
    if (depth > 8) return;
    for (const anc of l) {
      if (used.has(anc.uid) && !(anc.tuysseMax > 1 && paires.filter(q => q[0] === anc).length < anc.tuysseMax)) continue;
      if (paires.some(q => q[1] === anc)) continue;
      for (const j of l) {
        if (used.has(j.uid) || j === anc) continue;
        if (!peutTuysserSim(g, p, anc, j, paires)) continue;
        used.add(anc.uid); used.add(j.uid); paires.push([anc, j]);
        rec(paires, pts + pointsTuysse(g, p, anc, j) + (a(anc, "draw_on_tuysse") ? .6 : 0), depth + 1);
        paires.pop(); used.delete(j.uid);
        if (!paires.some(q => q[0] === anc || q[1] === anc)) used.delete(anc.uid);
      }
    }
  }
  rec([], 0, 0);
  return best;
}
function peutTuysserSim(g, p, anc, j, paires) {
  if (anc.def.prom >= j.def.prom) return false;
  if (!peutParticiper(g, p, anc) || !peutParticiper(g, p, j)) return false;
  if (j.def.conscrit && j.recus >= 3) return false;
  if (j.engage) return false;
  const deja = paires.filter(q => q[0] === anc).length + (anc.engage ? anc.tuysseCnt : 0);
  if (deja === 0) return !anc.engage;
  return deja < anc.tuysseMax && (anc.viaTuysse || paires.some(q => q[0] === anc));
}
// Valeur estimée (en points) d'une carte jouée maintenant
function estimer(g, p, c) {
  const o = adv(g, p), f = c.def.fx[0].split(":")[0];
  const nG = p.zone.filter(vrai_gadz).length;
  switch (f) {
    case "draw": return .7 * +c.def.fx[0].split(":")[1];
    case "zamat": return .9;
    case "weeks_fams": return Math.min(2, p.main.filter(vrai_gadz).length + p.kjib.filter(vrai_gadz).length) * 1.6;
    case "craps": return o.zone.filter(vrai_gadz).length >= 2 ? 1.2 : .3;
    case "gorgu": return p.zone.filter(x => !x.engage).length * .5;
    case "zag_pts": return nG >= 5 ? 3 : 0;
    case "biaude_pts": return Math.min(3, (p.tempo.engagesRes || 0)) + (p.tempo.engagesRes >= 3 ? 0 : .3);
    case "pins_pts": return Math.min(4, p.kjib.filter(x => x.def.type === "Trad's").length);
    case "pts_per_chant": return Math.min(4, p.kjib.filter(x => x.def.type === "Chant").length) * 1;
    case "zag": return o.main.length && nG >= 3 ? .8 : .2;
    case "patator": return o.zone.filter(vrai_gadz).length ? 1.8 : 0;
    case "biaude": return .9;
    case "gala": return 2 * p.zone.filter(x => p.tempo.tuysses.has(x.uid)).length;
    case "rochefoucs": return p.tempo.tuyssages + p.zone.filter(vrai_gadz).length * .7;
    case "gnassage": return 1.6;
    case "ggt": return nG >= 3 ? 2 : 0;
    case "weeks_p3": return p.main.length <= 2 ? 2.3 : 1.2;
    case "cp": return nG >= 3 ? 1.5 : 0;
    case "pts_per_gadz": return Math.min(6, p.zone.filter(x => x.def.type === "Gadz").length);
    case "pins": return 1.6;
    case "sandwich": return .9;
    case "jetplacks": return 0; // gardé pour réagir
    case "vacances": { const nO = o.zone.filter(x => x.def.type === "Gadz").length, nM = p.zone.filter(x => x.def.type === "Gadz").length; return o.points - p.points >= 3 && nO >= nM && nO >= 4 ? 3 + (nO - nM) : 0; }
    case "hymne": return p.tempo.tuyssages + meilleuresPaires(g, p).paires.length * .9;
    case "draw_per_gadz": return Math.min(3, nG) * .7;
    case "clocheton": { const libres = p.zone.filter(x => vrai_gadz(x) && !x.engage).length; return libres - meilleuresPaires(g, p).pts * .9; }
    case "monome": case "monome_all": { const l = p.zone.filter(x => vrai_gadz(x) && (f === "monome_all" || !x.engage) && peutParticiper(g, p, x)).length; const n = Math.min(l, c.def.fx[0] === "monome_all" ? 99 : +c.def.fx[0].split(":")[1]); return Math.max(0, n - 1) * 1.4 - (n >= 2 ? 1.2 : 0) + (c.def.fx.includes("after_draw") ? .7 : 0) + (c.def.fx.includes("after_point") ? 1 : 0); }
    default:
      if (c.def.type === "Tabagn's") return p.tab ? .2 : (f === "tab_bordels" ? 2.5 : 1.8);
      return .5;
  }
}
const choixIA = async (g, p, q) => {
  const o = adv(g, p);
  switch (q.type) {
    case "cible": {
      const f = q.carte.def.fx[0];
      if (f === "jetplacks") { const l = q.options.slice().sort((x, y) => (vrai_gadz(y) - vrai_gadz(x)) || (x.def.prom - y.def.prom)); return l.slice(0, 2); }
      if (f === "craps" || f === "patator") { const l = q.options.slice().sort((x, y) => scoreMenace(g, o, y) - scoreMenace(g, o, x)); return l[0]; }
      if (f === "sandwich") { const l = q.options.slice().sort((x, y) => scoreGarder(g, p, x) - scoreGarder(g, p, y)); return l[0]; }
      if (f === "ggt") { const l = q.options.slice().sort((x, y) => x.def.prom - y.def.prom); return l[0]; }
      if (f === "cp") { const l = q.options.slice().sort((x, y) => x.def.prom - y.def.prom); return l[0]; }
      return q.options.slice().sort((x, y) => valeurRes(g, p, y) - valeurRes(g, p, x))[0];
    }
    case "source": return q.options.find(x => fx(x).some(f => ["tuysse_ready", "decade_bonus", "next_prom_bonus", "draw_on_tuysse", "res_lineage"].includes(f))) || q.options[0];
    case "defausse": return q.options.slice().sort((x, y) => valeurGarder(g, p, x) - valeurGarder(g, p, y)).slice(0, q.n);
    case "degager": { const l = q.options.slice().sort((x, y) => (vrai_gadz(y) - vrai_gadz(x)) || (valeurRes(g, p, y) - valeurRes(g, p, x))); return l.slice(0, q.n); }
    case "regarder": { const besoinGadz = p.zone.filter(vrai_gadz).length + p.main.filter(vrai_gadz).length < 4; return q.options.slice().sort((x, y) => valeurCarte(g, p, y, besoinGadz) - valeurCarte(g, p, x, besoinGadz))[0]; }
    case "weeks": return q.options.slice().sort((x, y) => x.def.prom - y.def.prom).slice(0, q.n);
    case "monome": { const l = q.options.slice().sort((x, y) => x.def.prom - y.def.prom); return l.length <= q.n ? l : l.slice(0, q.n); }
  }
  return null;
};
// Ce que l'IA perd en défaussant une carte (plus c'est bas, plus elle s'en sépare volontiers)
function valeurGarder(g, p, c) {
  if (c.def.type === "Tabagn's") return p.tab || p.main.filter(x => x.def.type === "Tabagn's").length > 1 ? -2 : .8;
  if (vrai_gadz(c)) return p.main.filter(vrai_gadz).length > 2 ? 1 : 3;
  if (c.def.proche) return .3;
  return .5 + estimer(g, p, c) * .5;
}
function scoreMenace(g, o, c) { return (vrai_gadz(c) ? 3 : 0) + (c.def.conscrit ? 3 : 0) + fx(c).length + (o.zone.some(x => x !== c && vrai_gadz(x) && Math.abs(x.def.prom - c.def.prom) === 1) ? 1 : 0); }

// Réaction de l'IA : Jetplack's sur un gros tuyssage
async function reactionIA(g, p, ev) {
  if (ev.type !== "tuysse") return false;
  const c = p.main.find(x => x.def.fx[0] === "jetplacks");
  if (!c) return false;
  const pts = pointsTuysse(g, ev.joueur, ev.anc, ev.jeune);
  if (pts < 2 && g.joueurs[ev.joueur.i].points < g.opts.cible - 3) return false;
  const o = ev.joueur;
  const cibl = [ev.anc, ev.jeune].filter(x => !x.engage && !protege(g, o, x));
  if (!cibl.length) return false;
  if (potentiel(g, p, "Manip'") < cout(g, p, c)) return false;
  await payer(g, p, cout(g, p, c), "Manip'");
  p.main.splice(p.main.indexOf(c), 1); p.kjib.push(c);
  p.stats.joues[c.def.name] = (p.stats.joues[c.def.name] || 0) + 1;
  log(g, `${p.nom} réagit : ${c.def.name} !`, "carte");
  cibl.slice(0, 2).forEach(x => { x.engage = true; log(g, `${x.def.name} est engagé (quillons !).`); });
  return true;
}

// Un tour complet de l'IA. pas(action) permet à l'interface d'animer chaque étape.
async function tourIA(g, pas = async () => {}) {
  const p = g.joueurs[g.actif];
  const step = async () => { await pas(); return !g.fini; };
  // 1. Poser un Gadz (le meilleur pour la lignée / l'effet d'arrivée)
  const gadzMain = p.main.filter(vrai_gadz);
  for (let k = 0; k < 2; k++) {
    const gm = p.main.filter(vrai_gadz); if (!gm.length || p.gadzPose) break;
    gm.sort((x, y) => scorePose(g, p, y) - scorePose(g, p, x));
    await jouer(g, p, gm[0], choixIA); if (!await step()) return;
  }
  // 2. Tabagn's si aucun
  // 3. Boucle : carte la plus rentable tant qu'elle vaut mieux que de garder les paires
  let guard = 0;
  while (guard++ < 12 && !g.fini) {
    const paires = meilleuresPaires(g, p);
    const reserves = new Set(paires.paires.flat().map(c => c.uid));
    const libre = totalPool(p, null) + p.zone.filter(c => !c.engage && !bloqueC(g, c) && !reserves.has(c.uid)).reduce((s, c) => s + valeurRes(g, p, c), 0);
    const cands = p.main.filter(c => c.def.type !== "Gadz" || c.def.proche).filter(c => jouable(g, p, c));
    let best = null, bestV = .25;
    for (const c of cands) {
      if (["gala", "rochefoucs", "biaude_pts"].includes(c.def.fx[0])) continue; // après les tuyssages
      const k = c.def.type === "Gadz" ? c.def.cost : cout(g, p, c);
      let v = c.def.proche ? .9 : estimer(g, p, c);
      const resType = c.def.type !== "Gadz" ? totalPool(p, c.def.type) - totalPool(p, null) + p.zone.filter(x => !x.engage && !reserves.has(x.uid) && fx(x).includes("res2:" + c.def.type)).length : 0;
      const manque = Math.max(0, k - libre - resType);
      v -= manque * .75; // casser des paires coûte des points
      v -= k * .08;
      if (c.def.defausse) { const pire = p.main.filter(x => x !== c).sort((x, y) => valeurGarder(g, p, x) - valeurGarder(g, p, y))[0]; v -= pire ? Math.max(0, valeurGarder(g, p, pire)) * .6 : 9; }
      if (v > bestV) { bestV = v; best = c; }
    }
    if (!best) break;
    const ok = await jouer(g, p, best, choixIA, { reserves: [...reserves] });
    if (!ok) break;
    if (!await step()) return;
  }
  // 4. Tuyssages
  let paires = meilleuresPaires(g, p).paires;
  for (const [anc, j] of paires) { await tuysser(g, p, anc, j); if (!await step()) return; }
  // 5. Gala / Rochefouc's, puis nouveaux tuyssages si tout est dégagé
  for (const nom of ["gala", "rochefoucs"]) {
    const c = p.main.find(x => x.def.fx[0] === nom && jouable(g, p, x));
    if (c && estimer(g, p, c) >= 2) { await jouer(g, p, c, choixIA); if (!await step()) return;
      if (nom === "rochefoucs") { for (const [anc, j] of meilleuresPaires(g, p).paires) { await tuysser(g, p, anc, j); if (!await step()) return; } } }
  }
  for (let k = 0; k < 3 && !g.fini; k++) { const pr = meilleuresPaires(g, p).paires; if (!pr.length) break; for (const [anc, j] of pr) { await tuysser(g, p, anc, j); if (!await step()) return; } }
  // 6. Reste : cartes bon marché avec la ressource restante
  guard = 0;
  while (guard++ < 6 && !g.fini) {
    const c = p.main.filter(x => (x.def.type !== "Gadz" || x.def.proche) && x.def.type !== "Manip'" && jouable(g, p, x)).sort((x, y) => estimer(g, p, y) - estimer(g, p, x))[0];
    if (!c || estimer(g, p, c) < .3) break;
    if (!await jouer(g, p, c, choixIA)) break;
    if (!await step()) return;
  }
}
function scorePose(g, p, c) {
  let s = 0;
  if (p.zone.some(x => vrai_gadz(x) && Math.abs(x.def.prom - c.def.prom) === 1)) s += 3;
  if (c.def.conscrit) s += 4;
  if (fx(c).some(f => f.startsWith("arrive"))) s += 1.5;
  if (a(c, "tuysse_ready") || a(c, "decade_bonus")) s += 2;
  // Diversité de prom's
  if (!p.zone.some(x => x.def.prom === c.def.prom)) s += 1;
  return s;
}

const api = { degager, fx, a, lignee, bloqueC, cibles, nouvellePartie, deckAleatoire, finTour, jouer, jouable, tuysser, peutTuysser, engager, peutEngager, valeurRes, cout, pointsTuysse, tourIA, choixIA, reactionIA, meilleuresPaires, protege, nouveau, peutParticiper, potentiel, totalPool, vrai_gadz, rngFrom, CARTES, PAR_ID };
if (typeof module !== "undefined") module.exports = api; else root.Moteur = api;
})(this);
