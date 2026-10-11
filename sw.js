// The Buttercream - service worker (makes the site installable as an app)
const CACHE = "buttercream-v1";
const SHELL = ["./", "./index.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const req = e.request;
  const url = new URL(req.url);
  // Only handle this site's own files. Menu, orders and login (Supabase) always go to the network.
  if (req.method !== "GET" || url.origin !== self.location.origin) return;

  // Pages: always try the newest version first, fall back to the saved copy when offline
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then(res => { const copy = res.clone(); caches.open(CACHE).then(c => c.put("./index.html", copy)); return res; })
        .catch(() => caches.match("./index.html"))
    );
    return;
  }

  // Icons and other small files: saved copy first
  e.respondWith(caches.match(req).then(hit => hit || fetch(req)));
});
