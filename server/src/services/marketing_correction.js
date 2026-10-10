'use strict';
const {VAT_POST,legacyVatBody}=require('./marketing_review');
const {marketingPostHtml}=require('./telegram_text');
const {requireTelegramSuccess}=require('../bot/transport');

// One explicitly approved correction, not a general-purpose channel editor.
const CHAT='@esepfinancialsupport',MESSAGE_ID=169,KEY='vat-2026-10-10-message-169';
const correctedPost={...VAT_POST,body:'Исправлено 10.10.2026. В предыдущей версии были указаны устаревшие ставка и порог НДС. Ниже — уточнённая информация с источниками.\n\n'+VAT_POST.body};
const replacementText=correctedPost.title+'\n\n'+correctedPost.body;
function decodeText(value) {
  return value.replace(/<br\s*\/?\s*>/gi,'\n').replace(/<[^>]*>/g,'')
    .replace(/&#(x[0-9a-f]+|\d+);/gi,(_,n)=>String.fromCodePoint(n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):Number(n)))
    .replace(/&(lt|gt|quot|apos|nbsp|amp);/g,(_,x)=>({lt:'<',gt:'>',quot:'"',apos:"'",nbsp:'\u00a0',amp:'&'})[x]);
}
function parsePublicPost(html) {
  const start=html.indexOf('data-post="esepfinancialsupport/169"');
  if(start<0)throw Error('PUBLIC_POST_NOT_FOUND');
  const next=html.indexOf('data-post="',start+12);
  const block=html.slice(start,next<0?undefined:next);
  const match=block.match(/<div class="tgme_widget_message_text js-message_text"[^>]*>([\s\S]*?)<\/div>/);
  if(!match)throw Error('PUBLIC_POST_TEXT_MISSING');
  return decodeText(match[1]);
}
async function readPublicPost(fetchImpl=fetch) {
  const r=await fetchImpl('https://t.me/s/esepfinancialsupport/169',{signal:AbortSignal.timeout(12000)});
  if(!r.ok)throw Error('PUBLIC_POST_READ_FAILED');
  const html=await r.text();
  if(html.length>2e6)throw Error('PUBLIC_POST_TOO_LARGE');
  return parsePublicPost(html);
}
async function correctVatPost(c,request,readPublic=readPublicPost) {
  const observed=await readPublic();
  const known=[true,false].map(old=>VAT_POST.title+'\n\n'+legacyVatBody(old));
  if(observed!==replacementText&&!known.includes(observed))throw Error('PUBLIC_POST_CONTENT_CHANGED');
  // Commit the before-image independently, so it survives a crash after Telegram edits.
  await c.query(`INSERT INTO marketing_channel_corrections(correction_key,chat_id,message_id,original_text,replacement_text,status)
      VALUES($1,$2,$3,$4,$5,'pending') ON CONFLICT DO NOTHING`,[KEY,CHAT,MESSAGE_ID,observed,replacementText]);
  await c.query('BEGIN');
  try {
    const receipt=(await c.query('SELECT * FROM marketing_channel_corrections WHERE correction_key=$1 FOR UPDATE',[KEY])).rows[0];
    if(receipt.replacement_text!==replacementText)throw Error('CORRECTION_VERSION_MISMATCH');
    if(observed!==replacementText){
      // A later manual edit must not be overwritten by a repeat deployment.
      if(receipt.status==='done')throw Error('CORRECTED_POST_CHANGED');
      const response=requireTelegramSuccess(await request('editMessageText',{
        chat_id:CHAT,message_id:MESSAGE_ID,text:marketingPostHtml(correctedPost),parse_mode:'HTML',
        link_preview_options:{is_disabled:true},
        reply_markup:{inline_keyboard:[[{text:'Разъяснения КГД',url:'https://www.gov.kz/situations/817/intro?lang=ru'}]]},
      }));
      if(response.result?.message_id!==MESSAGE_ID||response.result?.text!==replacementText)throw Error('CORRECTION_RESULT_MISMATCH');
    }
    await c.query("UPDATE marketing_channel_corrections SET status='done',edited_at=COALESCE(edited_at,NOW()),last_error=NULL WHERE correction_key=$1",[KEY]);
    await c.query('COMMIT');
    return {messageId:MESSAGE_ID,changed:observed!==replacementText,verified:true};
  } catch(e) {await c.query('ROLLBACK');throw e;}
}
module.exports={correctVatPost,readPublicPost,parsePublicPost,replacementText,correctedPost};
