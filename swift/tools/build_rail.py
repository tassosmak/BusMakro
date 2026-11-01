"""Metro and tram data for the app, from STASY's official GTFS feed (data.gov.gr):

    python3 build_rail.py stasy_gtfs.zip ../BusMakroApp/Shared/Rail.json

The feed's platforms are merged into stations (same name, within 400 m), each line keeps its most
common station order per direction, and every station gets its departure times for a typical
weekday, Saturday and Sunday (minutes after midnight, as gaps from the previous one to stay small).
The app works out "next trains" from these, so it keeps working after the feed's dates run out."""
import csv, io, json, math, sys, unicodedata, zipfile
from collections import Counter, defaultdict
from datetime import date

COLORS = {'M1': '#00A651', 'M2': '#E2231A', 'M3': '#0072BC', 'T6': '#00A79D', 'T7': '#00A79D'}
NAMES_EN = {'M1': 'Line 1', 'M2': 'Line 2', 'M3': 'Line 3', 'T6': 'Tram 6', 'T7': 'Tram 7'}
NAMES = {'M1': 'Γραμμή 1', 'M2': 'Γραμμή 2', 'M3': 'Γραμμή 3', 'T6': 'Τραμ 6', 'T7': 'Τραμ 7'}

# the metro's names are in capitals in the feed: written out properly, with English
PROPER = {
    'ΑΓ. ΔΗΜΗΤΡΙΟΣ': ('Άγιος Δημήτριος', 'Agios Dimitrios'),
    'ΑΓΙΑ ΒΑΡΒΑΡΑ': ('Αγία Βαρβάρα', 'Agia Varvara'),
    'ΑΓΙΑ ΜΑΡΙΝΑ': ('Αγία Μαρίνα', 'Agia Marina'),
    'ΑΓΙΑ ΠΑΡΑΣΚΕΥΗ': ('Αγία Παρασκευή', 'Agia Paraskevi'),
    'ΑΓΙΟΣ ΑΝΤΩΝΙΟΣ': ('Άγιος Αντώνιος', 'Agios Antonios'),
    'ΑΓΙΟΣ ΕΛΕΥΘΕΡΙΟΣ': ('Άγιος Ελευθέριος', 'Agios Eleftherios'),
    'ΑΓΙΟΣ ΙΩΑΝΝΗΣ': ('Άγιος Ιωάννης', 'Agios Ioannis'),
    'ΑΓΙΟΣ ΝΙΚΟΛΑΟΣ': ('Άγιος Νικόλαος', 'Agios Nikolaos'),
    'ΑΙΓΑΛΕΩ': ('Αιγάλεω', 'Egaleo'),
    'ΑΚΡΟΠΟΛΗ': ('Ακρόπολη', 'Akropoli'),
    'ΑΛΙΜΟΣ': ('Άλιμος', 'Alimos'),
    'ΑΜΠΕΛΟΚΗΠΟΙ': ('Αμπελόκηποι', 'Ambelokipi'),
    'ΑΝΘΟΥΠΟΛΗ': ('Ανθούπολη', 'Anthoupoli'),
    'ΑΝΩ ΠΑΤΗΣΙΑ': ('Άνω Πατήσια', 'Ano Patissia'),
    'ΑΡΓΥΡΟΥΠΟΛΗ': ('Αργυρούπολη', 'Argyroupoli'),
    'ΑΤΤΙΚΗ': ('Αττική', 'Attiki'),
    'ΒΙΚΤΩΡΙΑ': ('Βικτώρια', 'Viktoria'),
    'Δ. ΠΛΑΚΕΝΤΙΑΣ': ('Δουκίσσης Πλακεντίας', 'Doukissis Plakentias'),
    'ΔΑΦΝΗ': ('Δάφνη', 'Dafni'),
    'ΔΗΜΟΤΙΚΟ ΘΕΑΤΡΟ': ('Δημοτικό Θέατρο', 'Dimotiko Theatro'),
    'ΕΘΝΙΚΗ ΑΜΥΝΑ': ('Εθνική Άμυνα', 'Ethniki Amyna'),
    'ΕΙΡΗΝΗ': ('Ειρήνη', 'Irini'),
    'ΕΛ. ΒΕΝΙΖΕΛΟΣ': ('Ελευθέριος Βενιζέλος', 'Airport'),
    'ΕΛΑΙΩΝΑΣ': ('Ελαιώνας', 'Eleonas'),
    'ΕΛΛΗΝΙΚΟ': ('Ελληνικό', 'Elliniko'),
    'ΕΥΑΓΓΕΛΙΣΜΟΣ': ('Ευαγγελισμός', 'Evangelismos'),
    'ΗΛΙΟΥΠΟΛΗ': ('Ηλιούπολη', 'Ilioupoli'),
    'ΗΡΑΚΛΕΙΟ': ('Ηράκλειο', 'Iraklio'),
    'ΘΗΣΕΙΟ': ('Θησείο', 'Thissio'),
    'ΚΑΛΛΙΘΕΑ': ('Καλλιθέα', 'Kallithea'),
    'ΚΑΝΤΖΑ': ('Παιανία-Κάντζα', 'Paiania-Kantza'),
    'ΚΑΤ': ('ΚΑΤ', 'KAT'),
    'ΚΑΤΕΧΑΚΗ': ('Κατεχάκη', 'Katehaki'),
    'ΚΑΤΩ ΠΑΤΗΣΙΑ': ('Κάτω Πατήσια', 'Kato Patissia'),
    'ΚΕΡΑΜΙΚΟΣ': ('Κεραμεικός', 'Kerameikos'),
    'ΚΗΦΙΣΙΑ': ('Κηφισιά', 'Kifissia'),
    'ΚΟΡΥΔΑΛΛΟΣ': ('Κορυδαλλός', 'Korydallos'),
    'ΚΟΡΩΠΙ': ('Κορωπί', 'Koropi'),
    'ΜΑΝΙΑΤΙΚΑ': ('Μανιάτικα', 'Maniatika'),
    'ΜΑΡΟΥΣΙ': ('Μαρούσι', 'Marousi'),
    'ΜΕΓΑΡΟ ΜΟΥΣΙΚΗΣ': ('Μέγαρο Μουσικής', 'Megaro Moussikis'),
    'ΜΕΤΑΞΟΥΡΓΕΙΟ': ('Μεταξουργείο', 'Metaxourgio'),
    'ΜΟΝΑΣΤΗΡΑΚΙ': ('Μοναστηράκι', 'Monastiraki'),
    'ΜΟΣΧΑΤΟ': ('Μοσχάτο', 'Moschato'),
    'Ν.ΚΟΣΜΟΣ': ('Νέος Κόσμος', 'Neos Kosmos'),
    'ΝΕΑ ΙΩΝΙΑ': ('Νέα Ιωνία', 'Nea Ionia'),
    'ΝΕΡΑΤΖΙΩΤΙΣΣΑ': ('Νερατζιώτισσα', 'Neratziotissa'),
    'ΝΙΚΑΙΑ': ('Νίκαια', 'Nikaia'),
    'ΝΟΜΙΣΜΑΤΟΚΟΠΕΙΟ': ('Νομισματοκοπείο', 'Nomismatokopio'),
    'ΟΜΟΝΟΙΑ': ('Ομόνοια', 'Omonia'),
    'ΠΑΛΛΗΝΗ': ('Παλλήνη', 'Pallini'),
    'ΠΑΝΕΠΙΣΤΗΜΙΟ': ('Πανεπιστήμιο', 'Panepistimio'),
    'ΠΑΝΟΡΜΟΥ': ('Πανόρμου', 'Panormou'),
    'ΠΕΙΡΑΙΑΣ': ('Πειραιάς', 'Piraeus'),
    'ΠΕΡΙΣΣΟΣ': ('Περισσός', 'Perissos'),
    'ΠΕΡΙΣΤΕΡΙ': ('Περιστέρι', 'Peristeri'),
    'ΠΕΤΡΑΛΩΝΑ': ('Πετράλωνα', 'Petralona'),
    'ΠΕΥΚΑΚΙΑ': ('Πευκάκια', 'Pefkakia'),
    'Σ. ΛΑΡΙΣΗΣ': ('Σταθμός Λαρίσης', 'Larissa Station'),
    'ΣΕΠΟΛΙΑ': ('Σεπόλια', 'Sepolia'),
    'ΣΥΓΓΡΟΥ-ΦΙΞ': ('Συγγρού-Φιξ', 'Syngrou-Fix'),
    'ΣΥΝΔΕΣΗ ΠΡΟΑΣΤΙΑΚΟΥ': ('Σύνδεση Προαστιακού', 'Suburban Rail Link'),
    'ΣΥΝΤΑΓΜΑ': ('Σύνταγμα', 'Syntagma'),
    'ΤΑΥΡΟΣ': ('Ταύρος', 'Tavros'),
    'ΦΑΛΗΡΟ': ('Φάληρο', 'Faliro'),
    'ΧΑΛΑΝΔΡΙ': ('Χαλάνδρι', 'Halandri'),
    'ΧΟΛΑΡΓΟΣ': ('Χολαργός', 'Holargos'),
}


def table(z, name):
    return list(csv.DictReader(io.TextIOWrapper(z.open(name), 'utf-8-sig')))


def key(name):
    return ''.join(c for c in unicodedata.normalize('NFD', name.upper()) if unicodedata.category(c) != 'Mn').strip()


def metres(a, b):
    dy = (a[0] - b[0]) * 111_320
    dx = (a[1] - b[1]) * 111_320 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)


def minutes(t):
    h, m, s = map(int, t.split(':'))
    return h * 60 + m + (1 if s >= 30 else 0)


def main(src, out):
    z = zipfile.ZipFile(src)
    routes = {r['route_id']: r for r in table(z, 'routes.txt')}
    # platforms → stations
    stations, of_platform = [], {}
    for p in table(z, 'stops.txt'):
        pos = (float(p['stop_lat']), float(p['stop_lon']))
        k = key(p['stop_name'])
        st = next((s for s in stations if s['key'] == k and metres(s['pos'], pos) < 400), None)
        if st is None:
            raw = p['stop_name'].strip()
            el, en = PROPER.get(raw, (raw, ''))
            st = {'key': k, 'name': el, 'name_en': en, 'pos': pos, 'n': 0, 'lines': set()}
            stations.append(st)
        st['n'] += 1
        of_platform[p['stop_id']] = st
    for i, s in enumerate(stations):
        s['id'] = f'R{i + 1:03d}'
    # a typical day of each kind: the service running on that date
    by_date = {r['date']: r['service_id'] for r in table(z, 'calendar_dates.txt') if r['exception_type'] == '1'}
    pick = {}
    for d, sid in sorted(by_date.items()):
        wd = date(int(d[:4]), int(d[4:6]), int(d[6:])).weekday()
        kind = 'wd' if wd < 5 else 'sa' if wd == 5 else 'su'
        if kind not in pick and (kind != 'wd' or wd == 2):  # a Wednesday for weekdays
            pick[kind] = sid
    service_kind = {v: k for k, v in pick.items()}
    trips = {t['trip_id']: t for t in table(z, 'trips.txt')}
    seqs = defaultdict(list)
    for r in table(z, 'stop_times.txt'):
        seqs[r['trip_id']].append((int(r['stop_sequence']), r['stop_id'], r['departure_time']))
    order = defaultdict(Counter)  # (line, direction) → station sequences
    times = defaultdict(lambda: defaultdict(list))  # (station, line, direction) → kind → minutes
    for tid, rows in seqs.items():
        t = trips[tid]
        line = routes[t['route_id']]['route_short_name']
        d = t['direction_id'] or '0'
        rows.sort()
        path = tuple(of_platform[s]['id'] for _, s, _ in rows)
        order[(line, d)][path] += 1
        kind = service_kind.get(t['service_id'])
        for _, s, dep in rows[:-1]:  # no departures from the last stop
            of_platform[s]['lines'].add(line)
            if kind:
                times[(of_platform[s]['id'], line, d)][kind].append(minutes(dep))
        of_platform[rows[-1][1]]['lines'].add(line)
    name_of = {s['id']: s['name'] for s in stations}
    lines = []
    for rid, r in sorted(routes.items(), key=lambda kv: kv[1]['route_short_name']):
        line = r['route_short_name']
        dirs = []
        for d in ('0', '1'):
            if order[(line, d)]:
                path = list(order[(line, d)].most_common(1)[0][0])
                dirs.append({'d': d, 'to': name_of[path[-1]], 'stations': path})
        lines.append({'id': line, 'name': NAMES.get(line, r['route_long_name']), 'name_en': NAMES_EN.get(line, line),
                      'kind': 'tram' if r['route_type'] == '0' else 'metro', 'color': COLORS.get(line, '#666666'),
                      'dirs': dirs})
    deps = {}
    for (sid, line, d), kinds in times.items():
        entry = {}
        for kind, ms in kinds.items():
            ms = sorted(set(ms))
            entry[kind] = [ms[0]] + [b - a for a, b in zip(ms, ms[1:])]
        deps[f'{sid}|{line}|{d}'] = entry
    data = {'source': 'STASY S.A. GTFS', 'lines': lines,
            'stations': {s['id']: {'name': s['name'], 'name_en': s['name_en'], 'lat': round(s['pos'][0], 6), 'lon': round(s['pos'][1], 6),
                                   'lines': sorted(s['lines'])} for s in stations if s['lines']},
            'departures': deps}
    json.dump(data, open(out, 'w'), ensure_ascii=False, separators=(',', ':'))
    print(len(data['stations']), 'stations,', len(lines), 'lines,', len(deps), 'timetables; days', pick)


if __name__ == '__main__':
    main(*sys.argv[1:])
