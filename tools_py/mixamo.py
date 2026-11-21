"""Mixamo catalog search + batch export (user's own session token in ~/maydon/.secrets/mixamo_token).
  mixamo.py search <query> [<query>...]        -> merges hits into raw/anim/mixamo/catalog.json
  mixamo.py get <list.json>                    -> downloads [{"id","name","file"}] as FBX (no skin, 30 fps)
Files stay local (Mixamo licence: use in games OK, no redistribution of raw files)."""
import json, os, sys, time, urllib.request, urllib.parse

ROOT = os.path.expanduser('~/maydon/raw/anim/mixamo')
TOKEN = open(os.path.expanduser('~/maydon/.secrets/mixamo_token')).read().strip()
API = 'https://www.mixamo.com/api/v1'
HDR = {'Authorization': 'Bearer ' + TOKEN, 'X-Api-Key': 'mixamo2', 'Accept': 'application/json',
       'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}


def req(path, body=None, tries=4):
    url = path if path.startswith('http') else API + path
    for i in range(tries):
        try:
            r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                       headers=HDR, method='POST' if body is not None else 'GET')
            with urllib.request.urlopen(r, timeout=60) as f:
                return json.loads(f.read())
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                sys.exit('token rejected (%d) - refresh ~/maydon/.secrets/mixamo_token' % e.code)
            if i == tries - 1:
                raise
        except Exception:
            if i == tries - 1:
                raise
        time.sleep(2 + 3 * i)


def search(queries):
    path = os.path.join(ROOT, 'catalog.json')
    cat = json.load(open(path)) if os.path.exists(path) else {}
    for q in queries:
        page, n = 1, 0
        while True:
            d = req('/products?page=%d&limit=96&order=&type=Motion%%2CMotionPack&query=%s' % (page, urllib.parse.quote(q)))
            for r in d.get('results', []):
                e = cat.setdefault(r['id'], {'name': r['name'], 'desc': r.get('description', ''), 'type': r.get('type'), 'q': []})
                if q not in e['q']:
                    e['q'].append(q)
                n += 1
            if page >= d.get('pagination', {}).get('num_pages', 1):
                break
            page += 1
        print('%-28s %4d hits' % (q, n))
    json.dump(cat, open(path, 'w'), indent=1, ensure_ascii=False)
    print('catalog:', len(cat), 'motions')


def get(listfile):
    char = req('/characters/primary')['primary_character_id']
    items = json.load(open(listfile))
    out = os.path.join(ROOT, 'fbx')
    os.makedirs(out, exist_ok=True)
    for it in items:
        dst = os.path.join(out, it['file'] + '.fbx')
        if os.path.exists(dst) and os.path.getsize(dst) > 1000:
            continue
        p = req('/products/%s?similar=0&character_id=%s' % (it['id'], char))
        g = dict(p['details']['gms_hash'])
        g['params'] = ','.join(str(v[1]) for v in g.get('params', []))
        if 'mirror' in it:
            g['mirror'] = it['mirror']
        body = {'character_id': char, 'gms_hash': [g], 'type': p['type'], 'product_name': p['name'],
                'preferences': {'format': 'fbx7_2019', 'skin': 'false', 'fps': '30', 'reducekf': '0'}}
        req('/animations/export', body)
        for _ in range(90):
            time.sleep(2)
            m = req('/characters/%s/monitor' % char)
            if m.get('status') == 'completed':
                urllib.request.urlretrieve(m['job_result'], dst)
                break
            if m.get('status') == 'failed':
                print('FAILED', it['name'], m)
                break
        print('ok' if os.path.exists(dst) else '--', it['file'], '<-', p['name'], flush=True)


if __name__ == '__main__':
    {'search': lambda: search(sys.argv[2:]), 'get': lambda: get(sys.argv[2])}[sys.argv[1]]()
