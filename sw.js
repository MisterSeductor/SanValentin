// Service worker mínimo: permite instalar la app. No guarda copias, así que siempre ves la versión más nueva.
self.addEventListener("install",()=>self.skipWaiting());
self.addEventListener("activate",e=>e.waitUntil(self.clients.claim()));
self.addEventListener("fetch",()=>{});
