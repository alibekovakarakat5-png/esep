// Есеп Service Worker
// Версия: 1.0.0
// Функции: офлайн-кэш, получение push-уведомлений

const CACHE_NAME = 'esep-v1';
const OFFLINE_URL = '/';

// ─── Установка и кэш shell ───────────────────────────────────────────────────
self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll([OFFLINE_URL]);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys.filter(function (k) { return k !== CACHE_NAME; })
            .map(function (k) { return caches.delete(k); })
      );
    })
  );
  self.clients.claim();
});

// ─── Fetch: network-first, офлайн-фолбэк ────────────────────────────────────
self.addEventListener('fetch', function (event) {
  // Только GET запросы
  if (event.request.method !== 'GET') return;

  event.respondWith(
    fetch(event.request)
      .then(function (response) {
        // Кэшируем успешные ответы для статики
        if (response && response.status === 200 && response.type === 'basic') {
          var clone = response.clone();
          caches.open(CACHE_NAME).then(function (cache) {
            cache.put(event.request, clone);
          });
        }
        return response;
      })
      .catch(function () {
        // Офлайн — берём из кэша
        return caches.match(event.request).then(function (cached) {
          return cached || caches.match(OFFLINE_URL);
        });
      })
  );
});

// ─── Push: получение уведомлений от сервера (Phase 3) ───────────────────────
self.addEventListener('push', function (event) {
  var data = {};
  if (event.data) {
    try { data = event.data.json(); } catch (_) { data = { title: 'Есеп', body: event.data.text() }; }
  }

  var title   = data.title || 'Есеп';
  var options = {
    body:    data.body || '',
    icon:    '/icons/Icon-192.png',
    badge:   '/icons/Icon-192.png',
    tag:     data.tag || 'esep-default',
    data:    { url: data.url || '/' },
    actions: data.actions || [],
    requireInteraction: data.requireInteraction || false,
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// ─── Notification click: открыть/сфокусировать приложение ───────────────────
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var targetUrl = (event.notification.data && event.notification.data.url) ? event.notification.data.url : '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
      for (var i = 0; i < clientList.length; i++) {
        var client = clientList[i];
        if ('focus' in client) {
          client.navigate(targetUrl);
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(targetUrl);
    })
  );
});
