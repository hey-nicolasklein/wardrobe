const cacheName = 'form-shell-v1';
const shell = [
  '/',
  '/index.html',
  '/style.css',
  '/app.js',
  '/icon-192.png',
  '/icon-512.png',
  '/manifest.webmanifest',
];
self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(cacheName).then((cache) => cache.addAll(shell)));
  self.skipWaiting();
});
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key.startsWith('form-shell-') && key !== cacheName)
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (
    event.request.method !== 'GET' ||
    url.origin !== self.location.origin ||
    url.pathname.startsWith('/v1/') ||
    url.pathname.startsWith('/health/')
  )
    return;
  if (!shell.includes(url.pathname) && event.request.mode !== 'navigate')
    return;
  event.respondWith(
    fetch(event.request).catch(() =>
      caches.match(
        event.request.mode === 'navigate' ? '/index.html' : event.request,
      ),
    ),
  );
});
