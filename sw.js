// Service worker : installation sur l'écran d'accueil et notifications.
// Il ne met rien en cache : tout vient toujours du réseau, donc les mises à jour sont immédiates.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
// Pour les fichiers du site, on redemande toujours au serveur s'il y a du nouveau (sinon le téléphone peut garder
// l'ancienne version jusqu'à 10 minutes après une mise à jour). Les images et sons de Supabase restent en cache normal.
self.addEventListener("fetch", e => {
  const same = new URL(e.request.url).origin === self.location.origin;
  e.respondWith(same && e.request.method === "GET" ? fetch(e.request, { cache: "no-cache" }) : fetch(e.request));
});

// Notification reçue du serveur
self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || "Collec' 23-151", {
    body: d.body || "", icon: "assets/icone-192.png", tag: d.tag || undefined, renotify: !!d.tag,
    data: { url: d.url || "./" }
  }));
});

// Toucher la notification ouvre (ou ramène) l'appli
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || "./", self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(ws => {
    for (const w of ws) if (w.url.startsWith(self.registration.scope)) { w.navigate(url).catch(() => {}); return w.focus(); }
    return self.clients.openWindow(url);
  }));
});
