/**
 * Orcinos Shared Service Worker Factory
 * 
 * Generates a cacheable service worker configuration for any product.
 * Used by: Nurasen, Optiscout (and any future PWA products)
 * 
 * Usage in a product's sw.js:
 *   importScripts('../shared/sw-factory.js');
 *   registerOrcinosSW({ cacheName: 'nurasen-v1', assets: [...] });
 */

function registerOrcinosSW(config = {}) {
    const {
        cacheName = 'orcinos-app-v1',
        assets = [],
        networkFirst = false
    } = config;

    self.addEventListener('install', event => {
        event.waitUntil(
            caches.open(cacheName).then(cache => cache.addAll(assets))
        );
    });

    self.addEventListener('activate', event => {
        event.waitUntil(
            caches.keys().then(keys =>
                Promise.all(
                    keys.filter(key => key !== cacheName)
                        .map(key => caches.delete(key))
                )
            )
        );
    });

    self.addEventListener('fetch', event => {
        if (networkFirst) {
            event.respondWith(
                fetch(event.request)
                    .then(response => {
                        const clone = response.clone();
                        caches.open(cacheName).then(cache => cache.put(event.request, clone));
                        return response;
                    })
                    .catch(() => caches.match(event.request))
            );
        } else {
            event.respondWith(
                caches.match(event.request)
                    .then(response => response || fetch(event.request))
            );
        }
    });
}
