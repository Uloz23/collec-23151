/* Monome Hero : le jeu complet est dans index.html (prototype validé), chargé dans un cadre.
   Il récupère l'« api » de l'appli via parent.__collecGameApi (même site), pour la progression et les scores. */
(function () {
  let fr = null;
  Collec.jeu("rythme", {
    start(api, root) {
      window.__collecGameApi = api;
      fr = document.createElement("iframe");
      fr.src = api.asset("index.html") + "?v=" + encodeURIComponent((api.game.settings && api.game.settings.version) || "1");
      fr.title = api.game.name;
      fr.allow = "autoplay; fullscreen";
      fr.style.cssText = "position:absolute;inset:0;width:100%;height:100%;border:0;background:#0b1030";
      fr.addEventListener("load", () => { try { fr.contentWindow.focus(); } catch (e) {} });
      root.appendChild(fr);
    },
    back() { try { return !!(fr && fr.contentWindow.__mhBack && fr.contentWindow.__mhBack()); } catch (e) { return false; } },
    stop() {
      try { fr && fr.contentWindow && fr.contentWindow.__mhStop && fr.contentWindow.__mhStop(); } catch (e) {}
      if (fr) fr.remove();
      fr = null;
      try { delete window.__collecGameApi; } catch (e) { window.__collecGameApi = undefined; }
    }
  });
})();
