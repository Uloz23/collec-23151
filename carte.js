// Rendu des cartes de la Collec' 23-151, partagé par l'appli (index.html) et le jeu (duel.html).
// Utilisation : const R = CarteRendu({ total: () => nombre de cartes, hasAudio: carte => bool, RLABEL }); R.cardEl(carte, version)
window.CarteRendu = function (ctx) {
const RLABEL = ctx.RLABEL;
const hasAudio = c => ctx.hasAudio ? ctx.hasAudio(c) : !!c.audio;
const CARDS = { get length() { return ctx.total(); } };
/* ================= Illustrations provisoires ================= */
let uidc = 0;
// Assombrit une couleur #rrggbb (f = 0 noir, 1 inchangée)
const shade = (hex, f) => { const n = parseInt(hex.slice(1), 16); return "#" + [16, 8, 0].map(k => Math.round(((n >> k) & 255) * f).toString(16).padStart(2, "0")).join(""); };
const ART = {
  gadz: (u, h) => `<svg viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><defs><radialGradient id="g${u}" cx=".5" cy=".38" r=".75"><stop offset="0" stop-color="hsl(${h} 45% 40%)"/><stop offset="1" stop-color="hsl(${h} 55% 11%)"/></radialGradient></defs><rect width="400" height="300" fill="url(#g${u})"/><circle cx="200" cy="120" r="50" fill="#1a1012"/><path d="M78 300 C86 206 140 182 200 182 C260 182 314 206 322 300 Z" fill="#1a1012"/><path d="M172 186 L200 232 L228 186" fill="none" stroke="hsl(${h} 40% 70%)" stroke-width="5" opacity=".45"/><text x="200" y="138" text-anchor="middle" font-size="52" font-family="Georgia,serif" fill="hsl(${h} 45% 65%)" opacity=".55">?</text></svg>`,
  trad: (u, h, c = {}) => `<svg viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><defs><radialGradient id="g${u}" cx=".5" cy=".5" r=".7"><stop offset="0" stop-color="${c.bg || `hsl(${h} 55% 32%)`}"/><stop offset="1" stop-color="${c.bg ? shade(c.bg, .28) : `hsl(${h} 60% 9%)`}"/></radialGradient></defs><rect width="400" height="300" fill="url(#g${u})"/><g stroke="#f1dfae" stroke-opacity=".12" stroke-width="2">${Array.from({length: 18}, (_, i) => { const a = i * Math.PI / 9; return `<line x1="200" y1="150" x2="${200 + Math.cos(a) * 320}" y2="${150 + Math.sin(a) * 320}"/>`; }).join("")}</g><path d="M150 85 h28 v102 h102 v28 h-130 Z" fill="none" stroke="${c.fg || "#d4b26a"}" stroke-width="8" stroke-linejoin="round"/><circle cx="200" cy="150" r="96" fill="none" stroke="${c.fg || "#d4b26a"}" stroke-opacity=".35" stroke-width="2"/></svg>`,
  chant: (u, h, c = {}) => `<svg viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><defs><linearGradient id="g${u}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${c.bg ? shade(c.bg, .35) : `hsl(${h} 50% 14%)`}"/><stop offset="1" stop-color="${c.bg || `hsl(${h} 45% 30%)`}"/></linearGradient></defs><rect width="400" height="300" fill="url(#g${u})"/><g stroke="${c.fg || "#f1dfae"}" stroke-opacity=".5" stroke-width="2">${[0,1,2,3,4].map(i => `<path d="M-10 ${110 + i * 16} C120 ${80 + i * 16} 280 ${150 + i * 16} 410 ${115 + i * 16}"/>`).join("")}</g><g fill="${c.fg || "#f1dfae"}"><ellipse cx="110" cy="150" rx="14" ry="10" transform="rotate(-20 110 150)"/><rect x="121" y="88" width="4" height="60"/><ellipse cx="200" cy="168" rx="14" ry="10" transform="rotate(-20 200 168)"/><rect x="211" y="106" width="4" height="60"/><ellipse cx="270" cy="150" rx="14" ry="10" transform="rotate(-20 270 150)"/><rect x="281" y="88" width="4" height="60"/><path d="M125 88 L215 106 L215 118 L125 100 Z"/></g></svg>`,
  manip: (u, h, c = {}) => `<svg viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><defs><radialGradient id="g${u}" cx=".5" cy=".55" r=".75"><stop offset="0" stop-color="${c.bg || `hsl(${h} 70% 38%)`}"/><stop offset="1" stop-color="${c.bg ? shade(c.bg, .25) : `hsl(${h} 60% 9%)`}"/></radialGradient></defs><rect width="400" height="300" fill="url(#g${u})"/><g fill="#f1dfae" opacity=".18">${Array.from({length: 14}, (_, i) => `<circle cx="${(i * 73) % 400}" cy="${(i * 131) % 300}" r="${2 + (i % 4)}"/>`).join("")}</g><path d="M150 70 h100 l-14 160 h-72 Z" fill="rgba(241,223,174,.12)" stroke="#f1dfae" stroke-width="5" stroke-linejoin="round"/><path d="M158 128 h84 l-9 100 h-66 Z" fill="${c.fg || "#d4b26a"}" opacity=".85"/><g fill="#fff6dc" opacity=".8"><circle cx="185" cy="190" r="4"/><circle cx="210" cy="165" r="3"/><circle cx="200" cy="205" r="2.5"/><circle cx="222" cy="198" r="3"/></g><rect x="150" y="62" width="100" height="14" rx="4" fill="#fff6dc" opacity=".85"/></svg>`,
  tabagn: (u, h, c = {}) => `<svg viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><defs><linearGradient id="g${u}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${c.bg ? shade(c.bg, .35) : `hsl(${h} 45% 14%)`}"/><stop offset="1" stop-color="${c.bg || `hsl(${h} 50% 32%)`}"/></linearGradient></defs><rect width="400" height="300" fill="url(#g${u})"/><g fill="#1a1012"><rect x="60" y="150" width="280" height="110"/><path d="M50 152 L200 80 L350 152 Z"/><rect x="185" y="50" width="30" height="50"/></g><g fill="${c.fg || "#d4b26a"}" opacity=".8">${[0,1,2,3,4,5].map(k => `<rect x="${82 + k * 42}" y="175" width="18" height="26"/><rect x="${82 + k * 42}" y="216" width="18" height="26"/>`).join("")}</g><path d="M0 262 H400 V300 H0 Z" fill="#120b0c"/></svg>`,
  bordels: u => `<svg viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><defs><linearGradient id="s${u}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0a1022"/><stop offset=".65" stop-color="#3b1b38"/><stop offset="1" stop-color="#7a2d3a"/></linearGradient><linearGradient id="r${u}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#24304f"/><stop offset="1" stop-color="#0c1224"/></linearGradient><radialGradient id="l${u}" cx=".72" cy=".24" r=".35"><stop offset="0" stop-color="#f1dfae" stop-opacity=".45"/><stop offset="1" stop-color="#f1dfae" stop-opacity="0"/></radialGradient></defs><rect width="400" height="300" fill="url(#s${u})"/><rect width="400" height="300" fill="url(#l${u})"/><g fill="#f1dfae"><circle cx="40" cy="30" r="1.2"/><circle cx="92" cy="58" r="1"/><circle cx="150" cy="22" r="1.4"/><circle cx="210" cy="48" r="1"/><circle cx="350" cy="40" r="1.2"/><circle cx="380" cy="90" r="1"/><circle cx="20" cy="95" r="1"/></g><circle cx="288" cy="72" r="30" fill="#f1dfae"/><circle cx="302" cy="64" r="27" fill="#1a1530"/><path d="M0 175 L0 150 L28 150 L28 138 L44 138 L44 150 L70 150 L70 128 L78 120 L86 128 L86 150 L120 150 L120 142 L150 142 L150 150 L400 150 L400 175 Z" fill="#1b1220"/><g fill="#3a2430"><rect x="140" y="160" width="260" height="12"/><path d="M150 172 h250 v20 h-250 Z"/></g><g fill="#0f1426"><path d="M162 192 a14 14 0 0 1 28 0 Z"/><path d="M204 192 a14 14 0 0 1 28 0 Z"/><path d="M246 192 a14 14 0 0 1 28 0 Z"/><path d="M288 192 a14 14 0 0 1 28 0 Z"/><path d="M330 192 a14 14 0 0 1 28 0 Z"/><path d="M372 192 a14 14 0 0 1 28 0 Z"/></g><g fill="#d4b26a"><circle cx="176" cy="157" r="2"/><circle cx="218" cy="157" r="2"/><circle cx="260" cy="157" r="2"/><circle cx="302" cy="157" r="2"/><circle cx="344" cy="157" r="2"/><circle cx="386" cy="157" r="2"/></g><rect x="0" y="192" width="400" height="60" fill="url(#r${u})"/><g stroke="#f1dfae" stroke-linecap="round" opacity=".55"><path d="M262 205 h40" stroke-width="2"/><path d="M270 216 h26" stroke-width="1.6"/><path d="M276 228 h16" stroke-width="1.3"/></g><path d="M0 252 Q200 236 400 252 L400 300 L0 300 Z" fill="#2a0f18"/><g stroke="#4a1a26" stroke-width="3" stroke-linecap="round"><path d="M10 300 L70 256"/><path d="M80 300 L120 255"/><path d="M150 300 L172 254"/><path d="M220 300 L226 253"/><path d="M290 300 L280 254"/><path d="M360 300 L334 256"/></g><g fill="#5e1424"><circle cx="52" cy="270" r="4"/><circle cx="60" cy="266" r="4"/><circle cx="56" cy="274" r="4"/><circle cx="300" cy="272" r="4"/><circle cx="308" cy="268" r="4"/><circle cx="304" cy="277" r="4"/></g></svg>`
};

const esc = s => String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const pad = n => String(n).padStart(3, "0");

/* Génération d'un Gadz : P1 = les 1ères années actuelles. Elle se recalcule à chaque rentrée de septembre. */
function pOf(card) {
  let m = /(\d{3})/.exec(card.sub || "");
  if (!m) { const m2 = /(\d{2})\s*$/.exec(card.sub || ""); if (!m2) return null; m = [0, "2" + m2[1]]; }
  const now = new Date();
  const firstYears = 200 + (now.getFullYear() - 2000) - (now.getMonth() < 8 ? 1 : 0); // 226 pour 2026-2027
  return firstYears - Number(m[1]) + 1;
}
function textSize(t) {
  const n = t.length + 22 * (t.split("\n").length - 1); // une ligne sautée compte comme du texte
  return n <= 22 ? "t-xs" : n <= 48 ? "t-s" : n <= 80 ? "t-m" : n <= 125 ? "t-l" : "t-xl";
}
function textboxHTML(card) {
  const gadz = card.type === "Gadz" && !card.kind; // un proche (Za, Zon…) n'a pas de Pn
  if (!gadz && !card.text) return `<div class="textbox empty"></div>`; // cadre vide : distingue la normale de la textless
  const p = gadz ? pOf(card) : null;
  const sz = card.text ? textSize(card.text) : "";
  if (p) return `<div class="textbox gadz ${sz}"><div class="pn">${p === 1 ? ".onscrit" : p === 2 ? "Ancien" : "P" + p}</div>${card.text ? `<p class="pn-sub">${esc(card.text)}</p>` : ""}</div>`;
  return `<div class="textbox ${sz}"><p>${esc(card.text)}</p></div>`;
}
// Fond neutre des Gadz sans photo
const GADZ_DEFAULT = { normale: "assets/gadz-defaut-normale.jpg", textless: "assets/gadz-defaut-textless.jpg?v=2" };
const photoOf = c => c.photo || (c.type === "Gadz" && !c.kind ? GADZ_DEFAULT : null);
// Étoiles des dorées : surtout sur le cadre or, quelques-unes sur l'image
function sparklesHTML() {
  let h = "";
  for (let i = 0; i < 13; i++) {
    const edge = i < 8, side = i % 4;
    const x = edge ? (side === 0 ? 3 : side === 1 ? 97 : 5 + Math.random() * 90) : 15 + Math.random() * 70;
    const y = edge ? (side === 2 ? 2 : side === 3 ? 98 : 5 + Math.random() * 90) : 12 + Math.random() * 60;
    h += `<i class="${i % 3 ? "s" : ""}" style="left:${x.toFixed(1)}%;top:${y.toFixed(1)}%;--d:${(1.8 + Math.random() * 1.8).toFixed(2)}s;--w:${(-Math.random() * 3).toFixed(2)}s"></i>`;
  }
  return `<div class="sparkles" aria-hidden="true">${h}</div>`;
}
// Taille du nom selon sa longueur : au-delà de 22 caractères, il passe sur deux lignes
const nameSize = n => n.length > 40 ? " long2 xl" : n.length > 22 ? " long2" : n.length > 15 ? " long" : "";
function cardEl(card, variant = "normale") {
  const el = document.createElement("div");
  // Les dorées sont aussi en pleine carte (mise en page textless + cadre or)
  const full = variant === "textless" || variant === "doree";
  el.className = `card r-${card.rarity} v-${variant}${variant === "doree" ? " v-textless" : ""}`;
  const u = ++uidc;
  el.innerHTML = `<div class="card-in"><div class="frame">
    <div class="bar top"><span class="name${nameSize(card.name)}">${esc(card.name)}</span></div>
    <div class="art">${photoOf(card) ? `<img src="${full && photoOf(card).textless ? photoOf(card).textless : photoOf(card).normale}" alt="">` : ART[card.art](u, card.hue, { bg: card.colors.bg, fg: card.colors.fg })}</div>
    <div class="bar mid"><span class="type">${hasAudio(card) ? "♪ " : ""}${card.kind ? esc(card.type) + " – " + esc(card.kind) : esc(card.type) + (card.sub ? " · " + esc(card.sub) : "")}</span><span class="rarity rl-${card.rarity}" role="img" aria-label="${RLABEL[card.rarity]}"></span></div>
    ${textboxHTML(card)}
    <div class="numbering"><span>${card.fams ? esc(card.fams) : "23-151"}</span><span>${pad(card.num || card.id)} / ${pad(CARDS.length)}</span></div>
  </div></div><div class="foil" aria-hidden="true"></div>${variant === "doree" ? sparklesHTML() : ""}`;
  return el;
}
function backEl() {
  const el = document.createElement("div");
  el.className = "cardback";
  el.innerHTML = `<div class="cardback-in"><div class="cardback-face"><div class="cardback-am"></div><div class="cardback-logo"></div></div></div>`;
  return el;
}

return { shade, ART, esc, pad, pOf, textSize, textboxHTML, GADZ_DEFAULT, photoOf, sparklesHTML, cardEl, backEl, get uidc() { return uidc; } };
};
