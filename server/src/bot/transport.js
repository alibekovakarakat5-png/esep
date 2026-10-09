'use strict';
const https = require('https');

function createBotRequest({ token, client = https, timeoutMs = 10000 }) {
  return function request(method, body) {
    if (!token) return Promise.resolve({ ok: false, error_code: 503, description: 'Telegram is not configured' });
    return new Promise(resolve => {
      let settled = false, timer, req;
      const finish = result => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(result);
      };
      const fail = code => finish({ ok: false, error_code: code, description: 'Telegram request failed' });
      try {
        const data = JSON.stringify(body);
        req = client.request({ hostname: 'api.telegram.org', path: `/bot${token}/${method}`,
          method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } }, res => {
          let buf = '';
          res.on('data', c => {
            buf += c;
            if (buf.length > 1024 * 1024) { fail(502); req.destroy(); }
          });
          res.on('error', () => fail(502));
          res.on('aborted', () => fail(502));
          res.on('end', () => {
            try {
              const result = JSON.parse(buf);
              if (res.statusCode >= 200 && res.statusCode < 300 && result?.ok === true) finish(result);
              else fail(Number(result?.error_code) || res.statusCode || 502);
            } catch { fail(502); }
          });
        });
        req.on('error', () => fail(502));
        // Wall-clock deadline also covers DNS/connect and stalled response bodies.
        timer = setTimeout(() => { fail(504); req.destroy(); }, timeoutMs);
        req.end(data);
      } catch { fail(502); }
    });
  };
}

function requireTelegramSuccess(result) {
  if (result?.ok === true) return result;
  const err = new Error(`Telegram delivery failed (${result?.error_code || 503})`);
  err.code = 'TELEGRAM_DELIVERY_FAILED';
  err.telegramCode = result?.error_code;
  throw err;
}

module.exports = { createBotRequest, requireTelegramSuccess };
