'use strict';
// Only explicitly scheduled task reminders and consented service requests are delivered.
const db=require('../db');
const tg=require('../bot/telegram');
const {createWorkspace}=require('../services/bot_workspace');
let timer,running=false;
const workspace=createWorkspace(db,{adminId:process.env.TELEGRAM_ADMIN_CHAT_ID});
async function runDeadlineReminders(){
 if(running)return;
 running=true;
 try{await workspace.dispatch(tg.send);}finally{running=false;}
}
function startDeadlineReminders(){
 if(!process.env.TELEGRAM_BOT_TOKEN||timer)return;
 const tick=()=>runDeadlineReminders().catch(e=>console.error('[workspace] Delivery worker failed:',e.code||'DELIVERY_ERROR'));
 timer=setInterval(tick,60000);timer.unref?.();tick();
 console.log('[workspace] Task reminders enabled; legacy tax broadcasts disabled');
}
module.exports={startDeadlineReminders,runDeadlineReminders};
