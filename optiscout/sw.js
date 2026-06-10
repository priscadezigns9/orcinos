const CACHE_NAME = "optiscout-v1";
const ASSETS = ["index.html", "dashboard.html", "../logos/OPTISCOUT_DEFINITIVE_2026.png"];
self.addEventListener("install", e => e.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(ASSETS))));
self.addEventListener("fetch", e => e.respondWith(caches.match(e.request).then(r => r || fetch(e.request))));