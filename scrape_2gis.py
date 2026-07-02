# -*- coding: utf-8 -*-
"""Скрейпер 2GIS без официального ключа: Playwright открывает поиск, перехватывает
запрос сайта к catalog.api.2gis.com (с публичным веб-ключом), затем реплеит его
постранично и тянет название+телефон. Вывод: CSV name,phone,city,niche.

Запуск: python scrape_2gis.py <niche> <city_slug:Город> [<city_slug:Город> ...]
Пример: python scrape_2gis.py accounting almaty:Алматы shymkent:Шымкент
"""
import sys, json, csv, re, time, urllib.parse, urllib.request
from playwright.sync_api import sync_playwright

NICHE_QUERY = {
    'accounting': 'бухгалтерские услуги',
    'audit': 'аудиторские услуги',
    'legal': 'юридические услуги',
    'taxi': 'таксопарк',
    'courier': 'курьерская служба',
    'beauty': 'маникюр',
    'food': 'кофейня',
}
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36'

niche = sys.argv[1] if len(sys.argv) > 1 else 'accounting'
query = NICHE_QUERY.get(niche, niche)
cities = [c.split(':', 1) for c in (sys.argv[2:] or ['almaty:Алматы'])]
import datetime
OUT = r'C:/Users/USER/Desktop/esep/scraped_%s_%s.csv' % (niche, datetime.date.today().isoformat())

def capture_api_url(city_slug):
    holder = {'url': None}
    with sync_playwright() as p:
        b = p.chromium.launch(channel='chrome')
        pg = b.new_page(user_agent=UA, viewport={'width': 1280, 'height': 900})
        def on_req(req):
            u = req.url
            # Идеал — живой /items; но фронт 2ГИС (2026) на поиске зовёт только
            # markers/clustered — из него берём хотя бы публичный key.
            if 'catalog.api.2gis' in u:
                if '/items' in u and not holder['url']:
                    holder['url'] = u
                elif not holder.get('any'):
                    holder['any'] = u
        pg.on('request', on_req)
        try:
            pg.goto('https://2gis.kz/%s/search/%s' % (city_slug, urllib.parse.quote(query)),
                    wait_until='domcontentloaded', timeout=60000)
            pg.wait_for_timeout(6000)
            # 2ГИС (2026) не шлёт items-запрос без взаимодействия — скроллим
            # выдачу, пока не поймаем catalog.api.../items (до ~20 сек).
            for _ in range(6):
                if holder['url']:
                    break
                pg.mouse.wheel(0, 1200)
                pg.wait_for_timeout(2500)
        except Exception as e:
            print('  goto err:', e)
        b.close()
    return holder['url'] or holder.get('any')

def set_param(url, key, val):
    parts = urllib.parse.urlparse(url)
    q = dict(urllib.parse.parse_qsl(parts.query))
    q[key] = val
    return urllib.parse.urlunparse(parts._replace(query=urllib.parse.urlencode(q)))

def phones_from_item(it):
    out = []
    for g in it.get('contact_groups', []):
        for c in g.get('contacts', []):
            if c.get('type') == 'phone':
                v = c.get('value') or c.get('text') or ''
                if v: out.append(v)
    return out

def region_id_for(city_name, key):
    u = 'https://catalog.api.2gis.ru/2.0/region/search?' + urllib.parse.urlencode(
        {'q': city_name, 'key': key, 'locale': 'ru_KZ'})
    req = urllib.request.Request(u, headers={'User-Agent': UA})
    data = json.loads(urllib.request.urlopen(req, timeout=25).read().decode('utf-8', 'ignore'))
    items = (data.get('result') or {}).get('items') or []
    return items[0]['id'] if items else None

def items_url_from(captured_url, city_name):
    """Если перехватили не /items (а markers/clustered) — строим items-запрос
    сами: из перехваченного берём key, регион ищем по имени города."""
    if '/items' in captured_url.split('?')[0]:
        return captured_url
    q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(captured_url).query))
    key = q.get('key')
    if not key:
        return None
    rid = region_id_for(city_name, key)
    if not rid:
        return None
    return 'https://catalog.api.2gis.ru/3.0/items?' + urllib.parse.urlencode(
        {'q': query, 'key': key, 'locale': 'ru_KZ', 'region_id': rid})

def scrape_city(city_slug, city_name, base_url, writer, seen):
    base = set_param(base_url, 'fields', 'items.contact_groups,items.point,items.address_name,items.name')
    base = set_param(base, 'page_size', '12')
    found = 0
    for page in range(1, 7):
        u = set_param(base, 'page', str(page))
        try:
            req = urllib.request.Request(u, headers={'User-Agent': UA})
            data = json.loads(urllib.request.urlopen(req, timeout=25).read().decode('utf-8', 'ignore'))
        except Exception as e:
            print('  page %d err: %s' % (page, e)); break
        items = (data.get('result') or {}).get('items') or []
        if not items: break
        for it in items:
            name = it.get('name') or it.get('name_ex', {}).get('primary') or ''
            for ph in phones_from_item(it):
                d = re.sub(r'\D', '', ph)
                if len(d) == 11 and d.startswith('8'): d = '7' + d[1:]
                if len(d) == 10: d = '7' + d
                if len(d) == 11 and d.startswith('7') and d not in seen:
                    seen.add(d); writer.writerow([name, '+' + d, city_name, niche]); found += 1
        time.sleep(0.8)
    print('  %s: +%d' % (city_name, found))
    return found

def main():
    f = open(OUT, 'w', newline='', encoding='utf-8')
    w = csv.writer(f); w.writerow(['name', 'phone', 'city', 'niche'])
    seen = set(); total = 0
    for city_slug, city_name in cities:
        print('город %s (%s) ...' % (city_name, city_slug))
        api = capture_api_url(city_slug)
        if not api:
            print('  не перехватил API'); continue
        api = items_url_from(api, city_name)
        if not api:
            print('  не собрал items-URL (нет key/региона)'); continue
        total += scrape_city(city_slug, city_name, api, w, seen)
    f.close()
    print('\nВСЕГО: %d уникальных номеров → %s' % (total, OUT))

if __name__ == '__main__':
    main()
