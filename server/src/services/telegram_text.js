'use strict';

// Content fields are plain text; only the caller supplies trusted HTML tags.
function escapeTelegramText(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function marketingPostHtml(post) {
  return `<b>${escapeTelegramText(post.title)}</b>\n\n${escapeTelegramText(post.body)}`;
}

module.exports = { escapeTelegramText, marketingPostHtml };
