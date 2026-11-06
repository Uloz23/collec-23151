// Service worker minimal : il permet d'installer la Collec' sur l'écran d'accueil.
// Il ne met rien en cache : tout vient toujours du réseau, donc les mises à jour sont immédiates.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", e => { e.respondWith(fetch(e.request)); });
