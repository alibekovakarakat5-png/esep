const { test } = require('node:test');
const assert = require('node:assert/strict');
const { escapeTelegramText, marketingPostHtml } = require('../src/services/telegram_text');

test('marketing content cannot introduce invalid Telegram HTML', () => {
  assert.equal(marketingPostHtml({ title: 'A & B < C', body: 'Оборот < 43.25 млн\n<script> > 0' }),
    '<b>A &amp; B &lt; C</b>\n\nОборот &lt; 43.25 млн\n&lt;script&gt; &gt; 0');
});
test('plain text, newlines and missing values remain safe', () => {
  assert.equal(escapeTelegramText('Документы\nполучены'), 'Документы\nполучены');
  assert.equal(escapeTelegramText(null), '');
});
