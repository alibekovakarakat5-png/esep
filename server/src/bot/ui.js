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
      'Здесь можно прикинуть налоги и зарплату, посмотреть сроки и перейти в свой кабинет.\n\n'+
      '<b>С чего начнём?</b> Выберите задачу на клавиатуре внизу.\nКоманды запоминать не нужно.',
    extra:{reply_markup:{keyboard:[[labels.calculators,labels.deadlines],[labels.accountant,labels.account],[labels.reference,labels.support]],resize_keyboard:true,is_persistent:true,one_time_keyboard:false,input_field_placeholder:'Выберите задачу или напишите сумму'}},
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
    '<b>1.</b> Откройте «Рассчитать» и выберите задачу.\n'+
    '<b>2.</b> Напишите сумму обычным сообщением: <code>300 000</code> или <code>3 млн</code>.\n'+
    '<b>3.</b> После ответа можно ввести другую сумму или вернуться в меню.\n\n'+
    'Выбранный расчёт сохраняется на 30 минут. Для смены задачи нажмите «Рассчитать».\n'+
    'Фото, документы и голосовые сообщения бот пока не разбирает.',extra:inline([[callback('🧮 Перейти к расчётам','ui:calculators')],[callback('Быстрые команды','ui:commands'),callback('Поддержка','ui:support')]])};
}
function commands() {
  return {text:'⌨️ <b>Быстрые команды</b>\n\n/menu — главное меню\n/calc — налог 910\n/salary — зарплата\n/self — самозанятый\n/social — соцплатежи\n/deadlines — сроки\n/status — мой аккаунт\n/cancel — отменить выбор\n\nМожно сразу написать <code>/salary 300000</code>.',extra:inline([[callback('⬅️ Помощь','ui:help')]])};
}
function support() {
  return {text:'💬 <b>Поддержка Esep</b>\n\nНе получается расчёт или вход в кабинет? Напишите, на каком шаге возникла проблема.\n\nКнопка откроет WhatsApp. Сообщение отправите вы сами.',extra:inline([[{text:'Написать в поддержку',url:'https://wa.me/77059914789'}],[callback('Как пользоваться ботом','ui:help'),callback('Привязать аккаунт','ui:link')]])};
}
function accountant() {
  return {text:'💼 <b>Esep для бухгалтера</b>\n\n'+
    'Быстрые расчёты и справка — здесь, работа с клиентами — в кабинете Esep.\n\n'+
    'Ведёте несколько компаний? Можем разобрать ваш текущий процесс и обсудить подходящий пилот.\n\n'+
    'Расскажите, что отнимает больше времени: документы, сроки или контроль клиентов.',extra:inline([
      [{text:'Открыть кабинет Esep',url:'https://app.esepkz.com'}],
      [{text:'Обсудить мою задачу',url:'https://wa.me/77059914789?text='+encodeURIComponent('Здравствуйте! Я бухгалтер, хочу обсудить Esep для работы с клиентами.')}],
      [callback('К расчётам','ui:calculators')],
    ])};
}
function form910() {
  return {text:'📋 <b>Что такое форма 910?</b>\n\n910.00 — форма декларации. Номер формы не является суммой дохода.\n\nДля предварительного расчёта понадобится доход за полугодие.',extra:inline([[callback('Указать доход','prompt_calc')],[callback('⬅️ Справка','ui:reference')]])};
}
module.exports={labels,textAction,home,calculators,prompt,reference,help,commands,support,accountant,form910,inline,definitions};
