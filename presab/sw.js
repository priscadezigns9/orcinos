/**
 * Presab Service Worker - V3
 * Caches the shell for offline use.
 * Network-first for everything to ensure updates are seen.
 */

const CACHE_NAME = 'presab-v3';
const SHELL = [
  '/presab/',
  '/presab/index.html',
  '/presab/teacher.html',
  '/presab/manifest.json',
  'https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&family=Cormorant:ital,wght@0,300;0,400;1,300;1,400&family=Urbanist:wght@300;400;500;600;700&display=swap'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))));
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  e.respondWith(
    fetch(e.request).then(res => {
      if (e.request.method === 'GET' && res.status === 200) {
        const clone = res.clone();
        caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
      }
      return res;
    }).catch(() => caches.match(e.request).then(cached => cached || (e.request.mode === 'navigate' ? caches.match('/presab/index.html') : null)))
  );
});
