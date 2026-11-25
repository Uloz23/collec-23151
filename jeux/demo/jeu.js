/* Jeu d'essai du socle : des étoiles apparaissent, touche-les avant qu'elles ne s'éteignent.
   Sert de modèle pour les vrais jeux : tout passe par « api » (voir index.html, section Jeux). */
(function () {
  let timers = [], api, root, running = false;
  const clear = () => { timers.forEach(t => clearTimeout(t)); timers = []; };
  const css = `
    .dm { position: absolute; inset: 0; display: grid; place-items: center; text-align: center; font-family: var(--f-label); color: var(--gold-soft); }
    .dm-box { display: grid; gap: 14px; justify-items: center; padding: 20px; max-width: 420px; }
    .dm-big { font-family: var(--f-gadz); font-size: 34px; color: var(--gold-soft); }
    .dm-hud { position: absolute; top: 10px; left: 0; right: 0; display: flex; justify-content: center; gap: 24px; font-size: 18px; letter-spacing: .1em; z-index: 2; pointer-events: none; }
    .dm-star { position: absolute; width: 64px; height: 64px; margin: -32px 0 0 -32px; border: 0; border-radius: 50%; cursor: pointer; font-size: 40px; line-height: 64px;
      background: radial-gradient(circle, rgba(255,236,170,.35), transparent 70%); color: #ffe9a8; animation: dmIn .2s ease-out; touch-action: manipulation; }
    @keyframes dmIn { from { transform: scale(.3); opacity: 0; } }
    .dm-muted { color: var(--muted); font-size: 15px; }`;
  function screen(html) { root.innerHTML = `<style>${css}</style><div class="dm">${html}</div>`; }
  async function menu() {
    let best = "";
    try { const b = await api.bests(); if (b.normal) best = `Ton record : ${b.normal.score} étoiles`; } catch (e) {}
    screen(`<div class="dm-box"><span class="dm-big">Démo</span>
      <span>Touche un maximum d'étoiles en 15 secondes.</span><span class="dm-muted">${best}</span>
      <button class="btn-primary" id="dm-go" type="button">Jouer</button></div>`);
    root.querySelector("#dm-go").onclick = play;
  }
  function play() {
    running = true; let score = 0, left = 15;
    root.innerHTML = `<style>${css}</style><div class="dm-hud"><span id="dm-s">0 ★</span><span id="dm-t">15 s</span></div>`;
    const spawn = () => {
      if (!running) return;
      const b = document.createElement("button"); b.className = "dm-star"; b.type = "button"; b.textContent = "★";
      b.style.left = (10 + Math.random() * 80) + "%"; b.style.top = (15 + Math.random() * 75) + "%";
      b.onpointerdown = () => { score++; root.querySelector("#dm-s").textContent = score + " ★"; b.remove(); try { api.sfx.flip(); } catch (e) {} };
      root.appendChild(b); timers.push(setTimeout(() => b.remove(), 1100));
      timers.push(setTimeout(spawn, 280 + Math.random() * 320));
    };
    spawn();
    const tick = () => { left--; const t = root.querySelector("#dm-t"); if (t) t.textContent = left + " s"; if (left <= 0) return end(score); timers.push(setTimeout(tick, 1000)); };
    timers.push(setTimeout(tick, 1000));
  }
  async function end(score) {
    running = false; clear();
    screen(`<div class="dm-box"><span class="dm-big">${score} ★</span><span class="dm-muted">Envoi du score…</span></div>`);
    let line = "";
    try {
      const r = await api.submit("normal", score, null, { duree: 15 });
      line = r.test ? "Compte test : score non enregistré." : r.record ? `Nouveau record ! ${r.rank ? r.rank + (r.rank > 1 ? "e" : "er") + " de la fam's" : ""}` : `Ton record : ${r.best}`;
      if (r.boosters) line += ` · 🎁 +${r.boosters} booster`;
    } catch (e) { line = "Score non envoyé (connexion ?)"; }
    screen(`<div class="dm-box"><span class="dm-big">${score} ★</span><span>${line}</span>
      <button class="btn-primary" id="dm-again" type="button">Rejouer</button><button class="btn-ghost" id="dm-quit" type="button">Quitter</button></div>`);
    root.querySelector("#dm-again").onclick = play;
    root.querySelector("#dm-quit").onclick = () => api.quit();
  }
  Collec.jeu("demo", {
    start(a, r) { api = a; root = r; menu(); },
    stop() { running = false; clear(); }
  });
})();
