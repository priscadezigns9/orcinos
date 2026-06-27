importScripts('../shared/sw-factory.js');

registerOrcinosSW({
    cacheName: 'optiscout-v1',
    assets: [
        'index.html',
        'dashboard.html',
        '../logos/OPTISCOUT_DEFINITIVE_2026.png'
    ]
});
