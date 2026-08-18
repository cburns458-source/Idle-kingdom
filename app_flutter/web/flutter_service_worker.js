// Replaces the caching Flutter PWA worker from earlier deploys.
// The browser fetches this script from the network, so a new deploy can
// take over, drop the cached "Sign in to play" bundle, and reload.
self.addEventListener('install', function (event) {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches
      .keys()
      .then(function (keys) {
        return Promise.all(keys.map(function (key) {
          return caches.delete(key);
        }));
      })
      .then(function () {
        return self.registration.unregister();
      })
      .then(function () {
        return self.clients.matchAll({type: 'window'});
      })
      .then(function (clients) {
        for (var i = 0; i < clients.length; i++) {
          clients[i].navigate(clients[i].url);
        }
      }),
  );
});

self.addEventListener('fetch', function (event) {
  event.respondWith(fetch(event.request));
});
