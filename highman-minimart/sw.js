const VERSION='highman-shell-v4';
const SHELL=[
  '/highman-minimart/',
  '/highman-minimart/manifest.webmanifest',
  '/highman-minimart/icons/icon-192.png',
  '/highman-minimart/icons/icon-512.png',
  '/logos/ORCINOS_DEFINITIVE_2026.png',
  '/logos/orcinos_icon.png',
  '/payroll/supabase-js.js',
  '/highman-minimart/html5-qrcode.min.js'
];
self.addEventListener('install',event=>{
  event.waitUntil(caches.open(VERSION).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('highman-shell-')&&k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch',event=>{
  const req=event.request,url=new URL(req.url);
  if(req.method!=='GET'||url.origin!==location.origin)return;
  // Keep the app shell available offline, but always prefer the latest deployed app.
  if(req.mode==='navigate'&&url.pathname.startsWith('/highman-minimart/')){
    event.respondWith(fetch(req).then(response=>{
      if(response.ok){const copy=response.clone();caches.open(VERSION).then(c=>c.put('/highman-minimart/',copy));}
      return response;
    }).catch(()=>caches.match('/highman-minimart/')));
    return;
  }
  if(SHELL.includes(url.pathname)){
    event.respondWith(caches.match(req).then(cached=>cached||fetch(req).then(response=>{
      if(response.ok){const copy=response.clone();caches.open(VERSION).then(c=>c.put(req,copy));}
      return response;
    })));
  }
});
