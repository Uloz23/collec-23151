// Fonction serveur Supabase « notifs » : envoie les notifications sur les téléphones.
// Appelée chaque minute par le réveil automatique (cron) de la base.
// @deno-types="npm:@types/web-push@3.6.4"
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC = "BD47_5tqgiO5fWOutYBVb7rTdH_EqZhTCUOff6byo59sGOVlUs7vQhrm2EO41QxRVxZ0Yi1Nvb_rC7r2yFKpWsc";
const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET")!;

webpush.setVapidDetails("https://uloz23.github.io/collec-23151/", VAPID_PUBLIC, VAPID_PRIVATE);

const rpc = (fn: string, body: unknown = {}) =>
  fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== CRON_SECRET) return new Response("Accès refusé", { status: 401 });
  const r = await rpc("push_collect");
  if (!r.ok) return new Response("Erreur base : " + (await r.text()), { status: 500 });
  const list: { endpoint: string; p256dh: string; auth: string; title: string; body: string; url: string; tag: string }[] = await r.json();
  const gone: string[] = [];
  let sent = 0;
  await Promise.all(list.map(async (m) => {
    try {
      await webpush.sendNotification(
        { endpoint: m.endpoint, keys: { p256dh: m.p256dh, auth: m.auth } },
        JSON.stringify({ title: m.title, body: m.body, url: m.url, tag: m.tag }),
        { TTL: 12 * 3600 },
      );
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) gone.push(m.endpoint); // téléphone désabonné
    }
  }));
  if (gone.length) await rpc("push_gone", { p_endpoints: gone });
  return Response.json({ envoyees: sent, retirees: gone.length });
});
