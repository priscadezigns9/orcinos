importScripts('../shared/sw-factory.js');

registerOrcinosSW({
    cacheName: 'nurasen-v1',
    assets: [
        '/nurasen/',
        '/nurasen/index.html',
        '/nurasen/dashboard.html',
        '/logos/NURASEN_DEFINITIVE_2026.png'
    ]
});
