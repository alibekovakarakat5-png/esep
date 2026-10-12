'use strict';
const {escapeTelegramText}=require('../services/telegram_text');

const labels = {
  calculators:'🧮 Рассчитать', deadlines:'📅 Сроки', accountant:'💼 Бухгалтеру',
  account:'👤 Мой Esep', reference:'📚 Справка', support:'💬 Поддержка',
};
const callback = (text,data) => ({text,callback_data:data});
const menuButton = () => callback('🏠 Главное меню','ui:menu');
const inline = rows => ({reply_markup:{inline_keyboard:[...rows,[menuButton()]]}});
const definitions = {
  calc:{title:'Налог по упрощёнке · 910',question:'Какой доход за полугодие?',hint:'Введите одну сумму в тенге, например 3 млн или 5 000 000.',examples:[1000000,3000000]},
  self:{title:'Самозанятый',question:'Какой доход за месяц?',hint:'Введите одну сумму в тенге, например 300 тыс или 500 000.',examples:[300000,500000]},
  salary:{title:'Зарплата сотрудника',question:'Какая зарплата начислена за месяц — до удержаний?',hint:'Введите одну сумму в тенге, например 300 000. Покажу сумму на руки и взносы.',examples:[200000,300000]},
};
const fmt = n=>n.toLocaleString('ru-RU');
function textAction(text) {
  const s=String(text).trim().toLowerCase();
  for(const [key,label] of Object.entries(labels))if(s===label.toLowerCase())return key;
  return ({'меню':'menu','главное меню':'menu','рассчитать':'calculators','калькулятор':'calculators','справка':'reference','поддержка':'support','назад':'menu','отмена':'menu'})[s] || null;
}
function home(name) {
  return {
    text:`<b>Esep · ваш помощник</b>\n\n${name?`Здравствуйте, ${escapeTelegramText(name)}!\n`:''}`+
      'Подготовьте запрос документов, сохраните список и вернитесь к тому, что ещё не получено. Здесь также доступны предварительные расчёты и справка.\n\n'+
      '<b>С чего начнём?</b> Нажмите кнопку под этим сообщением.',
    extra:{reply_markup:{inline_keyboard:[
      [callback('📋 Запросить документы','ws:new'),callback('📂 Мои задачи','ws:list')],
      [callback('Что мне даст Esep?','ws:guide:value'),callback('Мой первый шаг','ws:home')],
      [callback(labels.calculators,'ui:calculators'),callback(labels.deadlines,'ui:deadlines')],
      [callback(labels.accountant,'ui:accountant'),callback(labels.account,'ui:account')],
      [callback(labels.reference,'ui:reference'),callback(labels.support,'ui:support')],
    ]}},
  };
}
function calculators() {
  return {text:'🧮 <b>Что рассчитать?</b>\n\nВыберите задачу — затем я попрошу сумму.\n\nРасчёты предварительные: особенности вашей ситуации могут повлиять на итог.',extra:inline([
    [callback('Налог по упрощёнке · 910','prompt_calc')],
    [callback('Зарплата сотрудника','prompt_salary'),callback('Самозанятый','prompt_self')],
    [callback('Соцплатежи ИП за себя','go_social')],
  ])};
}
function prompt(kind,invalid=false) {
  const d=definitions[kind];
  return {text:`🧮 <b>${d.title}</b>\n\n${invalid?'Не получилось разобрать сумму. Попробуем ещё раз.\n\n':''}`+
    `<b>${d.question}</b>\n${d.hint}\n\nМожно выбрать сумму для примера ниже.`,
    extra:inline([d.examples.map(n=>callback(`${fmt(n)} ₸`,`run_${kind}_${n}`)),[callback('⬅️ Выбрать другой расчёт','ui:calculators')]])};
}
function reference() {
  return {text:'📚 <b>Справка</b>\n\nВыберите тему. Если нужен расчёт, откройте «Рассчитать» — бот проведёт по шагам.',extra:inline([
    [callback('Что такое форма 910?','ui:form910'),callback('Параметры расчёта','go_rates')],
    [callback('Соцплатежи за себя','go_social'),callback('Сроки 910','go_deadlines')],
    [callback('Как пользоваться ботом','ui:help')],
  ])};
}
function help() {
  return {text:'💡 <b>Как пользоваться Esep</b>\n\n'+
    '<b>Документы.</b> Выберите «Запросить документы», укажите название и месяц, отметьте нужные пункты и сохраните список. Текст запроса можно скопировать клиенту.\n\n'+
    '<b>Мои задачи.</b> Вернитесь к списку, отметьте полученное, назначьте себе напоминание или повторите список на следующий месяц.\n\n'+
    '<b>Связь с Esep.</b> В карточке задачи опишите, что хотите улучшить. Заявка отправится после вашего подтверждения; телефон не нужен.\n\n'+
    '<b>Расчёты.</b> Откройте «Рассчитать», выберите вариант и напишите сумму, например <code>300 000</code>. Выбор сохраняется на 30 минут.\n\n'+
    'Фото, документы и голосовые сообщения бот пока не разбирает. Полученные документы отмечаете вы сами.',extra:inline([[callback('📋 Запросить документы','ws:new'),callback('📂 Мои задачи','ws:list')],[callback('Быстрые команды','ui:commands'),callback('Поддержка','ui:support')]])};
}
function commands() {
  return {text:'⌨️ <b>Быстрые команды</b>\n\n/menu — главное меню\n/docs — подготовить запрос документов\n/my — мои задачи и обращения\n/calc — налог 910\n/salary — зарплата\n/self — самозанятый\n/social — соцплатежи\n/deadlines — сроки\n/status — мой аккаунт\n/cancel — отменить выбор\n\nМожно сразу написать <code>/salary 300000</code>.',extra:inline([[callback('⬅️ Помощь','ui:help')]])};
}
function support() {
  return {text:'💬 <b>Поддержка Esep</b>\n\nНе получается расчёт или вход в кабинет? Напишите, на каком шаге возникла проблема.\n\nКнопка откроет WhatsApp. Сообщение отправите вы сами.',extra:inline([[{text:'Написать в поддержку',url:'https://wa.me/77059914789'}],[callback('Как пользоваться ботом','ui:help'),callback('Привязать аккаунт','ui:link')]])};
}
function accountant() {
  return {text:'💼 <b>Esep для бухгалтера</b>\n\n'+
    'Подготовьте запрос документов, сохраните список клиента и отмечайте полученное.\n\n'+
    'Ведёте несколько компаний? Можем разобрать ваш текущий процесс и обсудить подходящий пилот.\n\n'+
    'Расскажите, что отнимает больше времени: документы, сроки или контроль клиентов.',extra:inline([
      [callback('📋 Подготовить запрос','ws:new'),callback('📂 Мои задачи','ws:list')],
      [{text:'Открыть кабинет Esep',url:'https://app.esepkz.com'}],
      [callback('Обсудить мою задачу','ws:request:0')],
      [callback('К расчётам','ui:calculators')],
    ])};
}
function form910() {
  return {text:'📋 <b>Что такое форма 910?</b>\n\n910.00 — форма декларации. Номер формы не является суммой дохода.\n\nДля предварительного расчёта понадобится доход за полугодие.',extra:inline([[callback('Указать доход','prompt_calc')],[callback('⬅️ Справка','ui:reference')]])};
}
module.exports={labels,textAction,home,calculators,prompt,reference,help,commands,support,accountant,form910,inline,definitions};
