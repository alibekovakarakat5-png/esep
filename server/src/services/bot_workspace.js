'use strict';
const {escapeTelegramText:esc}=require('./telegram_text');
const guide=require('../bot/guide');

// Additive migration, explicitly applied before a release. No visitor or legacy lead is reclassified.
const schema=`
CREATE TABLE IF NOT EXISTS bot_work_profiles (
 chat_id TEXT PRIMARY KEY, role TEXT NOT NULL DEFAULT 'unknown' CHECK(role IN ('own','clients','unknown')),
 last_update_id BIGINT, last_update_at TIMESTAMPTZ);
CREATE TABLE IF NOT EXISTS bot_work_sessions (
 chat_id TEXT PRIMARY KEY, step TEXT NOT NULL, data JSONB NOT NULL, version INT NOT NULL DEFAULT 1,
 active BOOLEAN NOT NULL DEFAULT true);
CREATE TABLE IF NOT EXISTS bot_document_tasks (
 id BIGSERIAL PRIMARY KEY, chat_id TEXT NOT NULL, client_name TEXT NOT NULL, period TEXT NOT NULL,
 items JSONB NOT NULL, status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','done','archived')),
 revision INT NOT NULL DEFAULT 1, repeat_of BIGINT REFERENCES bot_document_tasks(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 UNIQUE(chat_id,repeat_of,period));
CREATE INDEX IF NOT EXISTS bot_document_tasks_owner ON bot_document_tasks(chat_id,updated_at DESC);
CREATE TABLE IF NOT EXISTS bot_task_reminders (
 id BIGSERIAL PRIMARY KEY, task_id BIGINT NOT NULL REFERENCES bot_document_tasks(id), chat_id TEXT NOT NULL,
 scheduled_at TIMESTAMPTZ NOT NULL, state TEXT NOT NULL DEFAULT 'pending'
 CHECK(state IN ('pending','sending','sent','failed','uncertain','cancelled')),
 message_id BIGINT, attempted_at TIMESTAMPTZ, delivered_at TIMESTAMPTZ);
CREATE UNIQUE INDEX IF NOT EXISTS bot_task_one_reminder ON bot_task_reminders(task_id) WHERE state IN ('pending','sending');
CREATE TABLE IF NOT EXISTS bot_service_requests (
 id BIGSERIAL PRIMARY KEY, chat_id TEXT NOT NULL, task_id BIGINT REFERENCES bot_document_tasks(id),
 scope_key TEXT NOT NULL, role TEXT NOT NULL, client_count TEXT NOT NULL, note TEXT NOT NULL,
 context JSONB NOT NULL, username TEXT, consent_at TIMESTAMPTZ NOT NULL, consent_version TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'new' CHECK(status IN ('new','contacted','pilot','closed','cancelled')),
 revision INT NOT NULL DEFAULT 1, notification_state TEXT NOT NULL DEFAULT 'pending'
 CHECK(notification_state IN ('pending','sending','sent','failed','uncertain','cancelled')),
 notified_at TIMESTAMPTZ, attempted_at TIMESTAMPTZ, message_id BIGINT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
CREATE UNIQUE INDEX IF NOT EXISTS bot_request_active ON bot_service_requests(chat_id,scope_key) WHERE status IN ('new','contacted','pilot');
CREATE TABLE IF NOT EXISTS bot_work_events (
 id BIGSERIAL PRIMARY KEY, chat_id TEXT NOT NULL, update_id BIGINT NOT NULL, event TEXT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE(chat_id,update_id,event));
CREATE TABLE IF NOT EXISTS bot_work_operations (
 chat_id TEXT NOT NULL, update_id BIGINT NOT NULL, response JSONB,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY(chat_id,update_id));
`;
const categories=['Выписка банка','Акты и накладные','Счета и ЭСФ','Документы по сотрудникам','Чеки и расходы'];
const roles={own:'Для своего бизнеса',clients:'Для клиентов',unknown:'Пока не указано'};
const counts={own:'Свой бизнес','1-5':'1–5','6-20':'6–20','20plus':'Больше 20',unknown:'Пока не знаю'};
const statuses={new:'Ожидает ответа команды',contacted:'Команда связалась с вами',pilot:'Обсуждается пилот',closed:'Закрыта',cancelled:'Отменена вами'};
const deliveryStates={pending:'ожидает отправки',sending:'отправляется',sent:'доставлено',failed:'не доставлено',uncertain:'доставка не подтверждена',cancelled:'отменено'};
const eventLabels={visit:'Посещения',task_started:'Начали список',workspace_opened:'Открыли свои задачи',role_selected:'Указали роль',task_saved:'Сохранили список',request_text_prepared:'Подготовили текст запроса',task_opened:'Открыли список',task_updated:'Обновили список',reminder_opted_in:'Назначили напоминание',reminder_delivered:'Напоминание доставлено',reminders_disabled:'Выключили напоминания',request_submitted:'Отправили заявку',owner_notified:'Команда уведомлена'};
Object.assign(eventLabels,{result_delivered:'Ответ бота доставлен',period_repeated:'Создали следующий период',reminder_action:'Открыли список после напоминания'});
const cb=(text,data)=>({text,callback_data:data});
const view=(text,rows=[])=>({text,extra:{reply_markup:{inline_keyboard:[...rows,[cb('📂 Мои задачи','ws:list'),cb('🏠 Меню','ui:menu')]]}}});
const month=(date,offset=0)=>{const d=new Date(date.getTime()+5*3600e3);return new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+offset,1)).toISOString().slice(0,7);};
const nextMonth=p=>{const [y,m]=p.split('-').map(Number);return new Date(Date.UTC(y,m,1)).toISOString().slice(0,7);};
const periodLabel=p=>p.slice(5)+'.'+p.slice(0,4);
const clean=(text,max)=>typeof text==='string'&&text.trim().length>0&&text.trim().length<=max&&!/[\x00-\x1f\x7f]/.test(text)?text.trim():null;
function parsePeriod(text){const m=/^(0[1-9]|1[0-2])\.(20\d{2})$/.exec(text);return m?`${m[2]}-${m[1]}`:null;}
function parseDate(text,now){
 const m=/^(\d{2})\.(\d{2})\.(20\d{2})$/.exec(text);if(!m)return null;
 const iso=`${m[3]}-${m[2]}-${m[1]}`,d=new Date(`${iso}T09:00:00+05:00`);
 if(!Number.isFinite(d.getTime())||new Date(d.getTime()+5*3600e3).toISOString().slice(0,10)!==iso)return null;
 return d>now&&d.getTime()-now.getTime()<=366*864e5?d:null;
}
function requestText(t){
 const missing=t.items.filter(i=>!i.done);
 return `Здравствуйте! Для ${t.client_name} за ${periodLabel(t.period)} прошу подготовить:\n${missing.map(i=>'• '+i.label).join('\n')}\nЕсли что-то не относится к этому периоду, пожалуйста, сообщите.`;
}
function wizard(s,now){
 const v=s.version,d=s.data;
 const cancel=[cb('Отменить ввод','ws:pause')];
 if(s.step==='role')return view('📋 <b>Запрос документов</b>\n\nДля кого вы готовите список? Выбор можно изменить позже.',[[cb(roles.own,`ws:role:${v}:own`)],[cb(roles.clients,`ws:role:${v}:clients`)],[cb('Пропустить',`ws:role:${v}:unknown`)]]);
 if(s.step==='client')return view('Как назвать клиента или свой бизнес?\n\nНапишите короткое название, до 60 символов. БИН и телефон не нужны.',[cancel]);
 if(s.step==='period')return view(`📋 ${esc(d.client)}\n\nЗа какой месяц нужны документы? Выберите или напишите <code>09.2026</code>.`,[[cb(periodLabel(month(now,-1)),`ws:period:${v}:${month(now,-1)}`),cb(periodLabel(month(now)),`ws:period:${v}:${month(now)}`)],cancel]);
 if(s.step==='items')return view(`📋 <b>${esc(d.client)} · ${periodLabel(d.period)}</b>\n\nВыберите нужные документы. Список зависит от вашей работы — можно добавить свой пункт.\n\n${d.items.length?d.items.map(i=>'• '+esc(i.label)).join('\n'):'Пока ничего не выбрано.'}`,
 [...categories.map((label,i)=>[cb((d.items.some(x=>x.key===String(i))?'✓ ':'+ ')+label,`ws:category:${v}:${i}`)]),[cb('Добавить свой пункт',`ws:custom:${v}`)],[cb('Изменить название',`ws:edit:${v}:client`),cb('Другой период',`ws:edit:${v}:period`)],[cb('Сохранить список',`ws:save:${v}`)],cancel]);
 if(s.step==='custom')return view('Напишите название документа или короткое пояснение, до 100 символов.',[[cb('Вернуться к списку',`ws:edit:${v}:items`)],cancel]);
 if(s.step==='reminder')return view('Когда напомнить <b>вам</b> о недостающих документах?\n\nНапишите дату <code>15.10.2026</code>. Напоминание придёт в 09:00 по Алматы. Это ваша рабочая дата, не налоговый срок.',[[cb('Завтра в 09:00',`ws:tomorrow:${v}`)],cancel]);
 if(s.step==='count')return view('💬 <b>Обсудить работу в Esep</b>\n\nСколько компаний вы ведёте? Это поможет понять масштаб задачи.',[[cb('Свой бизнес',`ws:count:${v}:own`),cb('1–5',`ws:count:${v}:1-5`)],[cb('6–20',`ws:count:${v}:6-20`),cb('Больше 20',`ws:count:${v}:20plus`)],[cb('Пока не знаю',`ws:count:${v}:unknown`)],cancel]);
 if(s.step==='note')return view('Что хотите улучшить с Esep?\n\nНапишите коротко, до 500 символов. Например: «Веду 8 клиентов, теряю запросы документов в переписке».',[cancel]);
 if(s.step==='consent')return view(`💬 <b>Проверьте заявку</b>\n\n${d.taskLabel?'Задача: '+esc(d.taskLabel)+'\n':''}Компаний: ${esc(counts[d.count]||d.count)}\nЗапрос: ${esc(d.note)}\n\nНажимая «Отправить заявку», вы разрешаете команде Esep связаться с вами в Telegram по этой задаче. Передадим текст заявки и контекст выбранного списка. Подписка на рассылку не включается.`,[[cb('Отправить заявку',`ws:submit:${v}`)],[cb('Изменить текст',`ws:edit:${v}:note`)],cancel]);
 return view('Откройте сохранённую задачу или подготовьте новый список.',[[cb('Подготовить запрос','ws:new')]]);
}
function requestCard(r,admin=false){
 const text=`💬 <b>Заявка №${r.id} сохранена</b>\n${statuses[r.status]}\n\n${esc(r.note)}\n\n${r.context.taskLabel?'Задача: '+esc(r.context.taskLabel)+'\n':''}Компаний: ${esc(counts[r.client_count]||r.client_count)}`;
 if(!admin)return view(text, ['new','contacted','pilot'].includes(r.status)?[[cb('Отменить заявку',`ws:withdraw:${r.id}:${r.revision}`)]]:[]);
 return view(text+`\nРоль: ${esc(roles[r.role]||roles.unknown)}\nУведомление: ${deliveryStates[r.notification_state]}\nСогласие на связь: ${new Date(r.consent_at).toISOString().slice(0,10)}${r.context.pending?.length?'\nОжидаются: '+r.context.pending.map(esc).join(', '):''}`,
 [[{text:'Ответить в Telegram',url:`tg://user?id=${encodeURIComponent(r.chat_id)}`}],...(['new','contacted','pilot'].includes(r.status)?[[cb('Связались',`wa:status:${r.id}:${r.revision}:contacted`),cb('Пилот',`wa:status:${r.id}:${r.revision}:pilot`)],[cb('Закрыть',`wa:status:${r.id}:${r.revision}:closed`)]]:[]),[cb('Все заявки','wa:list')]]);
}

function createWorkspace(db,{now=()=>new Date(),adminId=''}={}){
 async function transaction(fn){const c=await db.connect();try{await c.query('BEGIN');const out=await fn(c);await c.query('COMMIT');return out;}catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}}
 const event=(c,id,u,name)=>c.query('INSERT INTO bot_work_events(chat_id,update_id,event) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',[id,u,name]);
 async function session(c,id,step,data){return (await c.query(`INSERT INTO bot_work_sessions(chat_id,step,data) VALUES($1,$2,$3::jsonb)
 ON CONFLICT(chat_id) DO UPDATE SET step=$2,data=$3::jsonb,version=bot_work_sessions.version+1,active=true RETURNING *`,[id,step,JSON.stringify(data)])).rows[0];}
 async function pause(c,id){await c.query('UPDATE bot_work_sessions SET active=false,version=version+1 WHERE chat_id=$1',[id]);}
 async function task(c,id,taskId){return (await c.query('SELECT * FROM bot_document_tasks WHERE id=$1 AND chat_id=$2 FOR UPDATE',[taskId,id])).rows[0];}
 async function card(c,t,prefix=''){
 const r=(await c.query('SELECT * FROM bot_task_reminders WHERE task_id=$1 ORDER BY id DESC LIMIT 1',[t.id])).rows[0];
 const missing=t.items.filter(i=>!i.done).length;
 const notice=r?.state==='pending'?`\n🔔 Напомню ${new Date(r.scheduled_at).toLocaleString('ru-RU',{timeZone:'Asia/Almaty',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'})} (Алматы).`:r&&['failed','uncertain','sending'].includes(r.state)?'\nДоставка последнего напоминания не подтверждена. Можно выбрать новую дату.':'';
 const rows=t.status==='archived'?[]:t.items.map((i,n)=>[cb(`${i.done?'✅':'⬜'} ${i.label}`,`ws:item:${t.id}:${t.revision}:${n}:${i.done?0:1}`)]);
 if(t.status==='open')rows.push([cb('📋 Текст запроса',`ws:text:${t.id}`)],[cb('🔔 Напомнить мне',`ws:remind:${t.id}`),cb('Выключить',`ws:off:${t.id}:${t.revision}`)]);
 if(t.status!=='archived')rows.push([cb('Повторить на следующий месяц',`ws:repeat:${t.id}`)],[cb('Обсудить с Esep',`ws:request:${t.id}`),cb('В архив',`ws:archive:${t.id}:${t.revision}`)]);
 return view(`${prefix}📋 <b>${esc(t.client_name)} · ${periodLabel(t.period)}</b>\n\n${t.items.map(i=>(i.done?'✅':'⬜')+' '+esc(i.label)).join('\n')}\n\n${t.status==='archived'?'В архиве.':missing?`Осталось ${missing} из ${t.items.length}.`:'Все пункты отмечены полученными.'}\nПолучение отмечаете вы; проверка файлов и отправка клиенту здесь не выполняются.${notice}`,rows);
 }
 async function list(c,id,page=0){
 page=Math.max(0,Math.min(10000,Number(page)||0));
 const rows=(await c.query("SELECT * FROM bot_document_tasks WHERE chat_id=$1 AND status<>'archived' ORDER BY updated_at DESC,id DESC LIMIT 7 OFFSET $2",[id,page*6])).rows;
 const s=(await c.query('SELECT * FROM bot_work_sessions WHERE chat_id=$1',[id])).rows[0];
 return view('📂 <b>Мои задачи</b>\n\n'+(rows.length?'Выберите список. Отметки и даты сохраняются между визитами.':'Подготовьте первый запрос документов и сохраните список.'),
 [[cb('➕ Подготовить запрос','ws:new')],...(s?.data?.client?[[cb('Продолжить черновик','ws:resume')]]:[]),...rows.slice(0,6).map(t=>[cb(`${t.status==='done'?'✅':'📋'} ${t.client_name} · ${periodLabel(t.period)}`,`ws:open:${t.id}`)]),...(page||rows.length>6?[[...(page?[cb('←',`ws:list:${page-1}`)]:[]),...(rows.length>6?[cb('Дальше →',`ws:list:${page+1}`)]:[])]]:[]),[cb('Мои обращения','ws:requests'),cb('Мой профиль','ws:profile')]]);
 }
 async function handle({chatId,updateId,text='',data='',username=null,navigation=false}){
 const id=String(chatId),isAdmin=adminId&&id===String(adminId),adminAction=data.startsWith('wa:')||/^\/(requests|audience)(?:\s|$)/.test(text);
 if(adminAction&&!isAdmin)return view('Это действие доступно только владельцу Esep.');
 if(data.length>64)return view('Кнопка устарела. Откройте свои задачи.');
 const parts=data.split(':');
 if(['open','text','item','remind','off','archive','repeat','request','receipt','withdraw'].includes(parts[1])&&(!/^\d{1,15}$/.test(parts[2]||'')))return view('Кнопка недоступна. Откройте свои задачи.');
 if(parts[0]==='wa'&&parts[1]==='status'&&!/^\d{1,15}$/.test(parts[2]||''))return view('Заявка недоступна.');
 return transaction(async c=>{
 await c.query('INSERT INTO bot_work_profiles(chat_id) VALUES($1) ON CONFLICT DO NOTHING',[id]);
 const profile=(await c.query('SELECT * FROM bot_work_profiles WHERE chat_id=$1 FOR UPDATE',[id])).rows[0];
 const cached=(await c.query('SELECT response FROM bot_work_operations WHERE chat_id=$1 AND update_id=$2',[id,updateId])).rows[0];
 if(cached)return cached.response;
 const today=now();
 const s=(await c.query('SELECT * FROM bot_work_sessions WHERE chat_id=$1',[id])).rows[0];
 const isWorkspace=data.startsWith('ws:')||adminAction||/^\/(docs|my)(?:\s|$)/.test(text)||/^\/start docs(?:_|$)/.test(text)||['📂 Мои задачи','мои задачи'].includes(text);
 if(profile.last_update_id!=null&&Number(profile.last_update_id)>updateId&&today-new Date(profile.last_update_at)<7*864e5){return isWorkspace||s?.active?view('Пришло более старое действие. Откройте актуальный список в «Мои задачи».'):null;}
 await c.query('UPDATE bot_work_profiles SET last_update_id=$2,last_update_at=$3 WHERE chat_id=$1',[id,updateId,today]);
 await event(c,id,updateId,'visit');
 const save=async out=>{await c.query('INSERT INTO bot_work_operations(chat_id,update_id,response) VALUES($1,$2,$3::jsonb)',[id,updateId,out==null?null:JSON.stringify(out)]);return out;};
 let a=data.split(':'),out;
 const plainStart=/^\/start(?:\s+(?!bind_|calc_|self_|reset|docs|social$|rates$|deadlines$|buh$|buhgalter$|firma$|partner$)[\w-]+)?$/i.test(text);
 const guideTopic=!s?.active?guide.intent(text):null;
 if(plainStart||data==='ws:welcome'||data==='ws:home'||data.startsWith('ws:welcomeRole:')||data.startsWith('ws:guide:')||guideTopic){
  await pause(c,id);
  if(a[1]==='welcomeRole'){
   if(!Object.hasOwn(roles,a[2]))return save(view('Выберите роль с помощью актуальных кнопок.'));
   await c.query('UPDATE bot_work_profiles SET role=$2 WHERE chat_id=$1',[id,a[2]]);
   await event(c,id,updateId,'role_selected');
   out=guide.home(a[2]);
  }else if(a[1]==='guide'||guideTopic){out=guide.answer(guideTopic||a[2],profile.role);await event(c,id,updateId,'guide_opened');}
  else {
   const alreadyChose=plainStart&&profile.role==='unknown'?(await c.query("SELECT 1 FROM bot_work_events WHERE chat_id=$1 AND event='role_selected' LIMIT 1",[id])).rows.length>0:false;
   out=data==='ws:welcome'||(plainStart&&profile.role==='unknown'&&!alreadyChose)?guide.welcome():guide.home(profile.role);
  }
  return save(out);
 }
 if(adminAction){
  if(text==='/audience'){
   const rolesCount=(await c.query('SELECT role,COUNT(*)::int AS n FROM bot_work_profiles WHERE chat_id<>$1 GROUP BY role',[String(adminId)])).rows;
   const events=(await c.query("SELECT event,COUNT(*)::int AS n,COUNT(DISTINCT chat_id)::int AS people FROM bot_work_events WHERE chat_id<>$1 AND created_at>=NOW()-INTERVAL '30 days' GROUP BY event ORDER BY event",[String(adminId)])).rows;
   const sources=(await c.query('SELECT COALESCE(first_start_payload,\'unknown\') AS source,COUNT(*)::int AS n FROM bot_users WHERE chat_id<>$1 GROUP BY first_start_payload ORDER BY n DESC LIMIT 10',[String(adminId)])).rows;
   const returned=(await c.query("SELECT COUNT(DISTINCT e.chat_id)::int AS n FROM bot_work_events e WHERE e.chat_id<>$1 AND e.event='task_opened' AND e.created_at>=NOW()-INTERVAL '30 days' AND EXISTS(SELECT 1 FROM bot_work_events s WHERE s.chat_id=e.chat_id AND s.event='task_saved' AND (s.created_at AT TIME ZONE 'Asia/Almaty')::date<(e.created_at AT TIME ZONE 'Asia/Almaty')::date)",[String(adminId)])).rows[0].n;
   out=view('📊 <b>Аудитория и действия</b>\n\nРоль посетителей с момента включения нового сценария:\n'+rolesCount.map(r=>`${roles[r.role]}: ${r.n}`).join('\n')+'\n\nЗа 30 дней (с момента включения учёта):\n'+events.map(r=>`${esc(eventLabels[r.event]||r.event)}: ${r.people} чел., ${r.n} действий`).join('\n')+`\nВернулись к спискам в другой день: ${returned} чел.`+'\n\nИсточники первого входа за всё время:\n'+sources.map(r=>`${esc(r.source)}: ${r.n}`).join('\n')+'\n\nАдминистратор исключён. Посещение и нажатие кнопки не означают заявку или продажу.');
  }else if(a[1]==='open'||a[1]==='status'){
   const r=(await c.query('SELECT * FROM bot_service_requests WHERE id=$1 FOR UPDATE',[a[2]])).rows[0];
   if(!r)out=view('Заявка не найдена.');
   else {if(a[1]==='status'&&Number(a[3])===r.revision&&['new','contacted','pilot'].includes(r.status)&&['contacted','pilot','closed'].includes(a[4])){
    Object.assign(r,(await c.query("UPDATE bot_service_requests SET status=$2,revision=revision+1,notification_state=CASE WHEN notification_state IN ('pending','sending') THEN 'cancelled' ELSE notification_state END WHERE id=$1 RETURNING *",[r.id,a[4]])).rows[0]);await event(c,id,updateId,'owner_'+a[4]);
   }out=requestCard(r,true);}
  }else{
   const rows=(await c.query("SELECT * FROM bot_service_requests WHERE status IN ('new','contacted','pilot') ORDER BY created_at LIMIT 50")).rows;
   out=view('📥 <b>Обращения в Esep</b>\n\n'+(rows.length?'Показаны до 50 открытых заявок.':'Открытых заявок нет.'),rows.map(r=>[cb(`№${r.id} · ${statuses[r.status]} · ${counts[r.client_count]}`,`wa:open:${r.id}`)]));
  }
  return save(out);
 }
 if(text==='/docs'||/^\/start docs(?:_|$)/.test(text))a=['ws','new'];
 if(text==='/my'||['📂 Мои задачи','мои задачи'].includes(text))a=['ws','list'];
 if(!isWorkspace&&(navigation||text.startsWith('/')||data||['меню','назад','отмена','рассчитать','🧮 рассчитать'].includes(text.toLowerCase()))){await pause(c,id);return save(null);}
 const action=a[1];
 if(action==='new'){
  const ns=await session(c,id,profile.role==='unknown'?'role':'client',{items:[]});await event(c,id,updateId,'task_started');out=wizard(ns,today);
 }else if(action==='list'){await pause(c,id);out=await list(c,id,a[2]);await event(c,id,updateId,'workspace_opened');}
 else if(action==='pause'){await pause(c,id);out=await list(c,id);}
 else if(action==='resume'&&s&&s.data.client){const ns=await session(c,id,s.step,s.data);out=wizard(ns,today);}
 else if(action==='profile'){await pause(c,id);out=view(`👤 <b>Мой профиль</b>\n\n${roles[profile.role]}\nНапоминания включаются отдельно в каждой задаче.`,[[cb('Для своего бизнеса','ws:profileRole:own'),cb('Для клиентов','ws:profileRole:clients')],[cb('Не указывать','ws:profileRole:unknown')],[cb('Выключить все напоминания','ws:offAll')]]);}
 else if(action==='profileRole'&&Object.hasOwn(roles,a[2])){await pause(c,id);await c.query('UPDATE bot_work_profiles SET role=$2 WHERE chat_id=$1',[id,a[2]]);await event(c,id,updateId,'role_selected');out=view('Роль сохранена.');}
 else if(action==='offAll'){await pause(c,id);await c.query("UPDATE bot_task_reminders SET state='cancelled' WHERE chat_id=$1 AND state IN ('pending','sending')",[id]);await event(c,id,updateId,'reminders_disabled');out=view('Будущие напоминания отключены. Списки сохранены.');}
 else if(action==='requests'){
  await pause(c,id);const rows=(await c.query('SELECT * FROM bot_service_requests WHERE chat_id=$1 ORDER BY id DESC LIMIT 20',[id])).rows;
  out=view('💬 <b>Мои обращения</b>\n\n'+(rows.length?'Выберите заявку.':'Вы можете описать задачу и разрешить команде ответить здесь.'),[[cb('Обсудить задачу','ws:request:0')],...rows.map(r=>[cb(`Заявка №${r.id}`,`ws:receipt:${r.id}`)])]);
 }else if(action==='receipt'||action==='withdraw'){
  const r=(await c.query('SELECT * FROM bot_service_requests WHERE id=$1 AND chat_id=$2 FOR UPDATE',[a[2],id])).rows[0];
  if(!r)out=view('Заявка недоступна.');else{if(action==='withdraw'&&Number(a[3])===r.revision&&['new','contacted','pilot'].includes(r.status))Object.assign(r,(await c.query("UPDATE bot_service_requests SET status='cancelled',revision=revision+1,notification_state=CASE WHEN notification_state IN ('pending','sending') THEN 'cancelled' ELSE notification_state END WHERE id=$1 RETURNING *",[r.id])).rows[0]);out=requestCard(r);}
 }else if(['open','text','item','remind','off','archive','repeat','request'].includes(action)){
  await pause(c,id);
  const t=a[2]==='0'&&action==='request'?null:await task(c,id,a[2]);
  if(!t&&!(action==='request'&&a[2]==='0'))out=view('Этот список недоступен. Откройте свои задачи.');
  else if(action==='request'){
   const existing=(await c.query("SELECT * FROM bot_service_requests WHERE chat_id=$1 AND scope_key=$2 AND status IN ('new','contacted','pilot')",[id,t?String(t.id):'general'])).rows[0];
   out=existing?requestCard(existing):wizard(await session(c,id,'count',{taskId:t?.id||null,taskLabel:t?`${t.client_name} · ${periodLabel(t.period)}`:null,items:[]}),today);
  }else if(action==='remind'&&t.status==='open')out=wizard(await session(c,id,'reminder',{taskId:t.id}),today);
  else if(action==='repeat'){
   const p=nextMonth(t.period),existing=(await c.query('SELECT * FROM bot_document_tasks WHERE chat_id=$1 AND repeat_of=$2 AND period=$3',[id,t.id,p])).rows[0];
   out=existing?await card(c,existing):wizard(await session(c,id,'items',{client:t.client_name,period:p,items:t.items.map(i=>({...i,done:false})),repeatOf:t.id}),today);
  }else if(action==='text'){
   out=t.status==='open'?view('📋 <b>Текст запроса подготовлен</b>\n\nСкопируйте и при необходимости измените перед отправкой:\n\n<pre>'+esc(requestText(t))+'</pre>\n\nБот не отправлял сообщение клиенту.',[[cb('К списку',`ws:open:${t.id}`)]]):await card(c,t);await event(c,id,updateId,'request_text_prepared');
  }else{
   if(['item','off','archive'].includes(action)&&Number(a[3])===t.revision&&t.status!=='archived'){
    if(action==='item'&&/^\d+$/.test(a[4]||'')&&t.items[Number(a[4])]&&['0','1'].includes(a[5])){
     t.items[Number(a[4])].done=a[5]==='1';t.status=t.items.every(i=>i.done)?'done':'open';
    }else if(action==='archive')t.status='archived';
    Object.assign(t,(await c.query('UPDATE bot_document_tasks SET items=$3::jsonb,status=$4,revision=revision+1,updated_at=NOW() WHERE id=$1 AND chat_id=$2 RETURNING *',[t.id,id,JSON.stringify(t.items),t.status])).rows[0]);
    if(action==='off'||t.status!=='open')await c.query("UPDATE bot_task_reminders SET state='cancelled' WHERE task_id=$1 AND state IN ('pending','sending')",[t.id]);
    await event(c,id,updateId,'task_updated');
   }
   out=await card(c,t);await event(c,id,updateId,'task_opened');
   if(action==='open'&&(await c.query("SELECT id FROM bot_task_reminders WHERE task_id=$1 AND state='sent' LIMIT 1",[t.id])).rows.length)await event(c,id,updateId,'reminder_action');
  }
 }else if(s?.active){
  if(data&&Number(a[2])!==s.version)return save(wizard(s,today));
  const d={...s.data};let step=s.step,valid=true;
  if(action==='role'&&step==='role'&&Object.hasOwn(roles,a[3])){await c.query('UPDATE bot_work_profiles SET role=$2 WHERE chat_id=$1',[id,a[3]]);step='client';await event(c,id,updateId,'role_selected');}
  else if(action==='edit'&&['items','client','period','note'].includes(a[3])&&(['client','period','items','custom'].includes(step)?['client','period','items'].includes(a[3]):step==='consent'&&a[3]==='note'))step=a[3];
  else if(action==='period'&&step==='period'&&/^20\d{2}-(0[1-9]|1[0-2])$/.test(a[3])){d.period=a[3];step='items';}
  else if(action==='category'&&step==='items'&&categories[Number(a[3])]){const k=String(Number(a[3])),found=d.items.some(i=>i.key===k);if(!found&&d.items.length>=10)return save(view('В одном списке до 10 пунктов.',[[cb('Вернуться',`ws:edit:${s.version}:items`)]]));d.items=found?d.items.filter(i=>i.key!==k):[...d.items,{key:k,label:categories[Number(k)],done:false}];}
  else if(action==='custom'&&step==='items')step='custom';
  else if(action==='save'&&step==='items'){
   if(!d.items.length)return save(view('Выберите хотя бы один документ.',[[cb('Вернуться к выбору',`ws:edit:${s.version}:items`)]]));
   const t=(await c.query(`INSERT INTO bot_document_tasks(chat_id,client_name,period,items,repeat_of) VALUES($1,$2,$3,$4::jsonb,$5)
    ON CONFLICT(chat_id,repeat_of,period) DO UPDATE SET period=EXCLUDED.period RETURNING *`,[id,d.client,d.period,JSON.stringify(d.items),d.repeatOf||null])).rows[0];
   await c.query("UPDATE bot_work_sessions SET active=false,version=version+1,data='{}'::jsonb WHERE chat_id=$1",[id]);await event(c,id,updateId,'task_saved');if(d.repeatOf)await event(c,id,updateId,'period_repeated');return save(await card(c,t,'Список сохранён.\n\n'));
  }else if(action==='count'&&step==='count'&&['own','1-5','6-20','20plus','unknown'].includes(a[3])){d.count=a[3];step='note';}
  else if(action==='submit'&&step==='consent'){
   const t=d.taskId?await task(c,id,d.taskId):null;
   if(d.taskId&&!t)return save(view('Список недоступен. Начните заявку заново.'));
   const r=(await c.query(`INSERT INTO bot_service_requests(chat_id,task_id,scope_key,role,client_count,note,context,username,consent_at,consent_version)
    VALUES($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9,'telegram-contact-v1') RETURNING *`,[id,t?.id||null,t?String(t.id):'general',profile.role,d.count,d.note,JSON.stringify({taskLabel:d.taskLabel||null,period:t?.period||null,pending:t?.items.filter(i=>!i.done).map(i=>i.label)||[]}),clean(username,64),today])).rows[0];
   await pause(c,id);await event(c,id,updateId,'request_submitted');return save(requestCard(r));
  }else if(step==='reminder'&&(!data||action==='tomorrow')){
   let date;if(action==='tomorrow'){const a=new Date(today.getTime()+5*3600e3+864e5).toISOString().slice(0,10);date=new Date(a+'T09:00:00+05:00');}else date=parseDate(text,today);
   if(!date)return save(view('Нужна будущая дата в пределах года, например <code>15.10.2026</code>. Отправка в 09:00 по Алматы.',[[cb('Завтра',`ws:tomorrow:${s.version}`)]]));
   const t=await task(c,id,d.taskId);if(!t||t.status!=='open'){await pause(c,id);return save(view('Задача завершена или недоступна. Напоминание не создано.'));}
   await c.query("UPDATE bot_task_reminders SET state='cancelled' WHERE task_id=$1 AND state IN ('pending','sending')",[t.id]);
   await c.query('INSERT INTO bot_task_reminders(task_id,chat_id,scheduled_at) VALUES($1,$2,$3)',[t.id,id,date]);
   await c.query('UPDATE bot_document_tasks SET revision=revision+1 WHERE id=$1',[t.id]);t.revision++;
   await pause(c,id);await event(c,id,updateId,'reminder_opted_in');return save(await card(c,t));
  }else if(!data&&step==='client'&&clean(text,60)){d.client=clean(text,60);step=d.period?'items':'period';}
  else if(!data&&step==='period'&&parsePeriod(text)){d.period=parsePeriod(text);step='items';}
  else if(!data&&step==='custom'&&clean(text,100)&&d.items.length<10){if(!d.items.some(i=>i.label===text.trim()))d.items=[...d.items,{key:'custom'+s.version,label:clean(text,100),done:false}];step='items';}
  else if(!data&&step==='note'&&clean(text,500)){d.note=clean(text,500);step='consent';}
  else valid=false;
  out=wizard(valid?await session(c,id,step,d):s,today);
  if(!valid)out.text='Не получилось принять ответ. '+out.text;
 }else out=isWorkspace?await list(c,id):null;
 return save(out);
 });
 }
 async function dispatch(send,{limit=20}={}){
 // Each attempt is durably claimed before contacting Telegram. A crash or ambiguous
 // transport failure is surfaced, never automatically resent with duplicate risk.
 await db.query("UPDATE bot_task_reminders SET state='uncertain' WHERE state='sending' AND attempted_at<NOW()-INTERVAL '5 minutes'");
 await db.query("UPDATE bot_service_requests SET notification_state='uncertain' WHERE notification_state='sending' AND attempted_at<NOW()-INTERVAL '5 minutes'");
 async function deliver(chatId,text,extra){
  try{const result=await send(chatId,text,extra);
   if(result?.ok&&Number.isSafeInteger(result.result?.message_id)&&String(result.result?.chat?.id)===String(chatId))return {state:'sent',messageId:result.result.message_id};
   return {state:[400,403,429].includes(result?.error_code)?'failed':'uncertain',messageId:null};
  }catch(e){return {state:[400,403,429].includes(e.telegramCode)?'failed':'uncertain',messageId:null};}
 }
 const ids=(await db.query("SELECT id,task_id FROM bot_task_reminders WHERE state='pending' AND scheduled_at<=$1 ORDER BY scheduled_at LIMIT $2",[now(),limit])).rows;
 for(const item of ids){
  const work=await transaction(async c=>{
   const t=(await c.query('SELECT * FROM bot_document_tasks WHERE id=$1 FOR UPDATE',[item.task_id])).rows[0];
   const r=(await c.query("SELECT * FROM bot_task_reminders WHERE id=$1 AND state='pending' FOR UPDATE",[item.id])).rows[0];
   if(!r)return null;
   if(!t||t.status!=='open'||t.chat_id!==r.chat_id){await c.query("UPDATE bot_task_reminders SET state='cancelled' WHERE id=$1",[r.id]);return null;}
   await c.query("UPDATE bot_task_reminders SET state='sending',attempted_at=$2 WHERE id=$1",[r.id,now()]);return {r,t};
  });
  if(!work)continue;
  // Recheck after the durable claim, locking the task until the send completes.
  // A completion/cancellation committed before this lock prevents the send.
  await transaction(async c=>{
   const t=(await c.query('SELECT * FROM bot_document_tasks WHERE id=$1 FOR UPDATE',[item.task_id])).rows[0];
   const r=(await c.query("SELECT * FROM bot_task_reminders WHERE id=$1 AND state='sending' FOR UPDATE",[item.id])).rows[0];
   if(!r)return;
   if(!t||t.status!=='open'){await c.query("UPDATE bot_task_reminders SET state='cancelled' WHERE id=$1",[r.id]);return;}
   const result=await deliver(r.chat_id,`🔔 <b>Ваше напоминание</b>\n\n${esc(t.client_name)} · ${periodLabel(t.period)}\nОсталось документов: ${t.items.filter(i=>!i.done).length}.\nОткройте список и обновите отметки.`,view('',[[cb('Открыть список',`ws:open:${t.id}`)],[cb('Отключить все напоминания','ws:offAll')]]).extra);
   await c.query("UPDATE bot_task_reminders SET state=$2,message_id=$3,delivered_at=CASE WHEN $2='sent' THEN NOW() ELSE NULL END WHERE id=$1",[r.id,result.state,result.messageId]);
   if(result.state==='sent')await event(c,r.chat_id,-Number(r.id),'reminder_delivered');
  });
 }
 if(!adminId)return;
 // A pending request remains visible to /requests even if its notification fails.
 const requests=(await db.query("SELECT id FROM bot_service_requests WHERE notification_state='pending' AND status='new' ORDER BY id LIMIT $1",[limit])).rows;
 for(const x of requests){
  const claimed=(await db.query("UPDATE bot_service_requests SET notification_state='sending',attempted_at=$2 WHERE id=$1 AND notification_state='pending' AND status='new' RETURNING id",[x.id,now()])).rows[0];if(!claimed)continue;
  await transaction(async c=>{
   const r=(await c.query("SELECT * FROM bot_service_requests WHERE id=$1 AND notification_state='sending' FOR UPDATE",[x.id])).rows[0];if(!r)return;
   if(r.status!=='new'){await c.query("UPDATE bot_service_requests SET notification_state='cancelled' WHERE id=$1",[r.id]);return;}
   const v=requestCard(r,true),result=await deliver(String(adminId),v.text,v.extra);
   await c.query("UPDATE bot_service_requests SET notification_state=$2,message_id=$3,notified_at=CASE WHEN $2='sent' THEN NOW() ELSE NULL END WHERE id=$1",[r.id,result.state,result.messageId]);
   if(result.state==='sent')await event(c,r.chat_id,-Number(r.id),'owner_notified');
  });
 }
 }
 async function recordDelivered(chatId,updateId,receipt){
  if(receipt?.ok&&Number.isSafeInteger(receipt.result?.message_id)&&String(receipt.result?.chat?.id)===String(chatId))await event(db,String(chatId),updateId,'result_delivered');
 }
 return {handle,dispatch,recordDelivered,assertReady:async()=>{
  for(const table of ['bot_work_profiles','bot_work_sessions','bot_document_tasks','bot_task_reminders','bot_service_requests','bot_work_events','bot_work_operations'])await db.query(`SELECT * FROM ${table} LIMIT 0`);
 }};
}
module.exports={schema,createWorkspace,parseDate,parsePeriod,requestText,view};
