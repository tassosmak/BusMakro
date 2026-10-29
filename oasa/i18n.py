"""Greek / English interface text and place names.

    t('key', n=3)           interface text in the current language
    name(greek, english)    a stop/line/route name: Greek as-is, or English (OASA's own English
                            name when there is one, otherwise transliterated with ELOT 743)

The language defaults to the Mac's language and is remembered (NSUserDefaults 'language').
"""
import unicodedata
from Foundation import NSLocale, NSUserDefaults

LANGS = ('el', 'en')
_KEY = 'language'

STRINGS = {
    'en': {
        # app / top bar
        'finding_stops': 'Finding stops near you…',
        'stops_near_you': 'Stops near you',
        'stops_near_centre': 'Stops near the map centre',
        'stops_in_area': 'Stops in this area',
        'locating': 'Locating…',
        'located': 'Located you · showing nearest stops',
        'loc_unavailable': 'Location unavailable',
        'loc_map_centre': 'Location unavailable · using the map centre',
        'loading_line': 'Loading line {line}…',
        'line_live': 'Line {line} · {n} live buses',
        'line_updated': 'Line {line} · Updated {time}',
        'no_route_for_line': 'No route data for line {line}',
        'error': 'Error: {msg}',
        'map_error': 'Map: {msg}',
        'err_nearby': 'Nearby stops: {msg}',
        'err_lines_at_stop': 'Lines at stop: {msg}',
        # controls
        'back': '‹ Back',
        'locate_me': '📍 Locate me',
        'search_stop': 'Search stop name…',
        'browse_line': 'Browse a line…',
        'tab_arrivals': 'Arrivals', 'tab_route': 'Route', 'tab_nearby': 'Nearby',
        'follow_bus': 'Follow this bus on the map',
        # headings
        'h_stops_near_you': 'STOPS NEAR YOU',
        'h_stops_in_area': 'STOPS IN THIS AREA',
        'h_stop': '{name} · STOP {id}',
        'h_approaching': 'APPROACHING BUSES',
        'h_along_line': 'STOPS ALONG LINE {line}',
        'h_nearest_on_line': 'NEAREST STOPS ON THIS LINE',
        'closest': 'CLOSEST',
        # home / stop screens
        'stop_n': 'Stop {id}',
        'walk': '~{n} min walk',
        'no_stops_nearby': 'No stops found nearby.',
        'loading_lines_at_stop': 'Loading lines at this stop…',
        'no_lines_at_stop': 'No lines found for this stop.',
        'min': '{n} min',
        'approx_min': '~{n} min',
        'then': 'Then {list}',
        'live': 'Live',
        'scheduled': 'Scheduled · leaves the terminus {depart}, here ~{arrive}',
        'no_more_today': 'No more buses today',
        # line view
        'unnamed_stop': 'Unnamed stop',
        'no_route_data': 'No route data for this line.',
        'no_stops_route': 'No stops for this route.',
        'bus_to_next': 'Bus {id} · {dist} to next stop',
        'loading_line_short': 'Loading line…',
        'tap_locate': 'Tap “Locate me” to find the nearest stops.',
        'bus_eta': 'Bus {id} · {eta}',
        'no_approaching_bus': 'No approaching bus',
        'no_stop_coords': 'No stops with coordinates on this line.',
        'bus_n': 'Bus {id}',
        'trip_unavailable': 'Trip unavailable',
        'no_delay_data': 'No delay data',
        'on_time': 'On time',
        'est': 'est.',
        'choose_stop': 'Choose a stop to see approaching buses.',
        'no_approaching': 'No confirmed approaching vehicles found for this stop.',
        'due': 'Due',
        'eta_min_sec': '{m}:{s:02d} min',
        # search / favourites / errors / updates
        'search_bar': 'Search stops or lines',
        'h_favourites': 'FAVOURITES',
        'h_search_lines': 'LINES',
        'h_search_stops': 'STOPS',
        'no_results': 'No stops or lines match “{q}”.',
        'index_loading': 'Loading the stop list… (first launch only)',
        'lines_list': 'Lines {list}',
        'fav_add': 'Save to favourites',
        'fav_remove': 'Remove from favourites',
        'tab_home_nearby': 'Nearby',
        'tab_favourites': 'Favourites',
        'no_favourites': 'No favourites yet. Open a stop and tap ☆ to save it.',
        'fav_loading': 'Loading arrivals…',
        'fav_none_live': 'No buses on the road right now',
        'err_offline': 'No internet connection',
        'err_service': 'Couldn’t reach the bus service',
        'tap_retry': '{msg} · click to try again',
        'stale_data': '{msg} · showing data from {time}',
        'update_available': '⬆︎ Update {v}',
        'up_to_date': 'BusMakro {v} is up to date',
        'update_failed': 'Couldn’t check for updates',
        'm_check_updates': 'Check for Updates…',
        'tip_expand': 'Expand the map',
        'alert_meta': '{date} · {lines} · click to read',
        'alert_line': 'Line {list}',
        'alert_lines': 'Lines {list}',
        'tip_collapse': 'Show the panels again',
        # menus
        'm_about': 'About {app}', 'm_hide': 'Hide {app}', 'm_hide_others': 'Hide Others',
        'm_show_all': 'Show All', 'm_quit': 'Quit {app}',
        'm_edit': 'Edit', 'm_undo': 'Undo', 'm_redo': 'Redo', 'm_cut': 'Cut', 'm_copy': 'Copy',
        'm_paste': 'Paste', 'm_select_all': 'Select All',
        'm_view': 'View', 'm_refresh': 'Refresh', 'm_locate': 'Locate Me', 'm_back': 'Back',
        'm_language': 'Language',
        'm_window': 'Window', 'm_minimize': 'Minimize', 'm_zoom': 'Zoom', 'm_close': 'Close',
    },
    'el': {
        'finding_stops': 'Αναζήτηση στάσεων κοντά σας…',
        'stops_near_you': 'Στάσεις κοντά σας',
        'stops_near_centre': 'Στάσεις κοντά στο κέντρο του χάρτη',
        'stops_in_area': 'Στάσεις σε αυτή την περιοχή',
        'locating': 'Εντοπισμός…',
        'located': 'Βρέθηκε η θέση σας · πλησιέστερες στάσεις',
        'loc_unavailable': 'Η τοποθεσία δεν είναι διαθέσιμη',
        'loc_map_centre': 'Η τοποθεσία δεν είναι διαθέσιμη · χρήση κέντρου χάρτη',
        'loading_line': 'Φόρτωση γραμμής {line}…',
        'line_live': 'Γραμμή {line} · {n} λεωφορεία σε κίνηση',
        'line_updated': 'Γραμμή {line} · Ενημέρωση {time}',
        'no_route_for_line': 'Δεν υπάρχουν δεδομένα διαδρομής για τη γραμμή {line}',
        'error': 'Σφάλμα: {msg}',
        'map_error': 'Χάρτης: {msg}',
        'err_nearby': 'Κοντινές στάσεις: {msg}',
        'err_lines_at_stop': 'Γραμμές στη στάση: {msg}',
        'back': '‹ Πίσω',
        'locate_me': '📍 Η θέση μου',
        'search_stop': 'Αναζήτηση στάσης…',
        'browse_line': 'Επιλογή γραμμής…',
        'tab_arrivals': 'Αφίξεις', 'tab_route': 'Διαδρομή', 'tab_nearby': 'Κοντά',
        'follow_bus': 'Παρακολούθηση του λεωφορείου στον χάρτη',
        'h_stops_near_you': 'ΣΤΑΣΕΙΣ ΚΟΝΤΑ ΣΑΣ',
        'h_stops_in_area': 'ΣΤΑΣΕΙΣ ΣΕ ΑΥΤΗ ΤΗΝ ΠΕΡΙΟΧΗ',
        'h_stop': '{name} · ΣΤΑΣΗ {id}',
        'h_approaching': 'ΛΕΩΦΟΡΕΙΑ ΠΟΥ ΕΡΧΟΝΤΑΙ',
        'h_along_line': 'ΣΤΑΣΕΙΣ ΤΗΣ ΓΡΑΜΜΗΣ {line}',
        'h_nearest_on_line': 'ΠΛΗΣΙΕΣΤΕΡΕΣ ΣΤΑΣΕΙΣ ΤΗΣ ΓΡΑΜΜΗΣ',
        'closest': 'ΠΙΟ ΚΟΝΤΑ',
        'stop_n': 'Στάση {id}',
        'walk': '~{n} λεπτά με τα πόδια',
        'no_stops_nearby': 'Δεν βρέθηκαν στάσεις κοντά.',
        'loading_lines_at_stop': 'Φόρτωση γραμμών της στάσης…',
        'no_lines_at_stop': 'Δεν βρέθηκαν γραμμές για αυτή τη στάση.',
        'min': '{n} λεπ.',
        'approx_min': '~{n} λεπ.',
        'then': 'Μετά {list}',
        'live': 'Ζωντανά',
        'scheduled': 'Προγραμματισμένο · αναχώρηση από αφετηρία {depart}, εδώ ~{arrive}',
        'no_more_today': 'Δεν υπάρχουν άλλα δρομολόγια σήμερα',
        'unnamed_stop': 'Στάση χωρίς όνομα',
        'no_route_data': 'Δεν υπάρχουν δεδομένα διαδρομής για αυτή τη γραμμή.',
        'no_stops_route': 'Δεν υπάρχουν στάσεις για αυτή τη διαδρομή.',
        'bus_to_next': 'Λεωφορείο {id} · {dist} ως την επόμενη στάση',
        'loading_line_short': 'Φόρτωση γραμμής…',
        'tap_locate': 'Πατήστε «Η θέση μου» για τις πλησιέστερες στάσεις.',
        'bus_eta': 'Λεωφορείο {id} · {eta}',
        'no_approaching_bus': 'Δεν έρχεται λεωφορείο',
        'no_stop_coords': 'Δεν υπάρχουν στάσεις με συντεταγμένες σε αυτή τη γραμμή.',
        'bus_n': 'Λεωφορείο {id}',
        'trip_unavailable': 'Μη διαθέσιμο δρομολόγιο',
        'no_delay_data': 'Χωρίς στοιχεία καθυστέρησης',
        'on_time': 'Στην ώρα του',
        'est': 'εκτ.',
        'choose_stop': 'Επιλέξτε στάση για να δείτε τα λεωφορεία που έρχονται.',
        'no_approaching': 'Δεν βρέθηκαν λεωφορεία που να έρχονται σε αυτή τη στάση.',
        'due': 'Φτάνει',
        'eta_min_sec': '{m}:{s:02d} λεπ.',
        'search_bar': 'Αναζήτηση στάσης ή γραμμής',
        'h_favourites': 'ΑΓΑΠΗΜΕΝΑ',
        'h_search_lines': 'ΓΡΑΜΜΕΣ',
        'h_search_stops': 'ΣΤΑΣΕΙΣ',
        'no_results': 'Δεν βρέθηκαν στάσεις ή γραμμές για «{q}».',
        'index_loading': 'Φόρτωση λίστας στάσεων… (μόνο την πρώτη φορά)',
        'lines_list': 'Γραμμές {list}',
        'fav_add': 'Αποθήκευση στα αγαπημένα',
        'fav_remove': 'Αφαίρεση από τα αγαπημένα',
        'tab_home_nearby': 'Κοντά',
        'tab_favourites': 'Αγαπημένα',
        'no_favourites': 'Δεν υπάρχουν αγαπημένα. Ανοίξτε μια στάση και πατήστε ☆ για αποθήκευση.',
        'fav_loading': 'Φόρτωση αφίξεων…',
        'fav_none_live': 'Κανένα λεωφορείο σε κίνηση τώρα',
        'err_offline': 'Δεν υπάρχει σύνδεση στο διαδίκτυο',
        'err_service': 'Δεν ήταν δυνατή η σύνδεση με την υπηρεσία',
        'tap_retry': '{msg} · πατήστε για επανάληψη',
        'stale_data': '{msg} · δεδομένα από {time}',
        'update_available': '⬆︎ Ενημέρωση {v}',
        'up_to_date': 'Το BusMakro {v} είναι ενημερωμένο',
        'update_failed': 'Δεν ήταν δυνατός ο έλεγχος για ενημερώσεις',
        'm_check_updates': 'Έλεγχος για ενημερώσεις…',
        'tip_expand': 'Μεγέθυνση χάρτη',
        'alert_meta': '{date} · {lines} · πατήστε για ανάγνωση',
        'alert_line': 'Γραμμή {list}',
        'alert_lines': 'Γραμμές {list}',
        'tip_collapse': 'Εμφάνιση των πάνελ',
        'm_about': 'Σχετικά με το {app}', 'm_hide': 'Απόκρυψη {app}', 'm_hide_others': 'Απόκρυψη άλλων',
        'm_show_all': 'Εμφάνιση όλων', 'm_quit': 'Έξοδος από {app}',
        'm_edit': 'Επεξεργασία', 'm_undo': 'Αναίρεση', 'm_redo': 'Επανάληψη', 'm_cut': 'Αποκοπή',
        'm_copy': 'Αντιγραφή', 'm_paste': 'Επικόλληση', 'm_select_all': 'Επιλογή όλων',
        'm_view': 'Προβολή', 'm_refresh': 'Ανανέωση', 'm_locate': 'Η θέση μου', 'm_back': 'Πίσω',
        'm_language': 'Γλώσσα',
        'm_window': 'Παράθυρο', 'm_minimize': 'Ελαχιστοποίηση', 'm_zoom': 'Μεγέθυνση', 'm_close': 'Κλείσιμο',
    },
}
LANG_NAMES = {'el': 'Ελληνικά', 'en': 'English'}


def _initial_language():
    saved = NSUserDefaults.standardUserDefaults().stringForKey_(_KEY)
    if saved in LANGS:
        return str(saved)
    preferred = NSLocale.preferredLanguages()
    return 'el' if preferred and str(preferred[0]).startswith('el') else 'en'


_lang = _initial_language()


def lang():
    return _lang


def set_lang(code):
    global _lang
    if code in LANGS:
        _lang = code
        NSUserDefaults.standardUserDefaults().setObject_forKey_(code, _KEY)


def t(key, **kw):
    text = STRINGS[_lang].get(key) or STRINGS['en'][key]
    return text.format(**kw) if kw else text


# ---- Names ----------------------------------------------------------------------
# ELOT 743 (the Greek standard OASA's English names follow), simplified.
_PAIRS = {'ΟΥ': 'OU', 'ΓΓ': 'NG', 'ΓΧ': 'NCH', 'ΓΞ': 'NX'}
_START = {'ΜΠ': 'B'}    # μπ is B at the start of a word, MP inside it
_INSIDE = {'ΜΠ': 'MP'}
_VOICELESS = set('ΘΚΞΠΣΤΦΧΨ')  # αυ/ευ become AF/EF before these (and at the end), AV/EV otherwise
_ONE = dict(zip('ΑΒΓΔΕΖΗΙΚΛΜΝΞΟΠΡΣΤΥΦΩ', 'AVGDEZIIKLMNXOPRSTYFO'))
_ONE.update({'Θ': 'TH', 'Χ': 'CH', 'Ψ': 'PS', 'Σ': 'S'})


def _strip_accents(s):
    return ''.join(c for c in unicodedata.normalize('NFD', s) if unicodedata.category(c) != 'Mn')


def transliterate(text):
    """Greek → Latin (ELOT 743), keeping each letter's case. Non-Greek text passes through."""
    src = _strip_accents(text or '').replace('ς', 'σ')
    up = src.upper()
    out, i = [], 0
    while i < len(src):
        two = up[i:i + 2]
        word_start = i == 0 or not up[i - 1].isalpha()
        if two in ('ΑΥ', 'ΕΥ'):
            nxt = up[i + 2:i + 3]
            latin = two[0].translate({ord('Α'): 'A', ord('Ε'): 'E'}) + ('F' if not nxt.isalpha() or nxt in _VOICELESS else 'V')
            n = 2
        elif len(two) == 2 and (two in _PAIRS or two in _START):
            latin = _PAIRS.get(two) or (_START if word_start else _INSIDE)[two]
            n = 2
        else:
            latin, n = _ONE.get(up[i], src[i]), 1
        if src[i].islower():
            latin = latin.lower()
        elif n == 1 and len(latin) > 1 and i + 1 < len(src) and src[i + 1].islower():
            latin = latin.capitalize()  # Θέμα → Thema, not THema
        out.append(latin)
        i += n
    return ''.join(out)


def name(greek, english=None):
    """A place/line name in the current language."""
    if _lang == 'el':
        return greek or english or ''
    english = (english or '').strip()
    return english if english else transliterate(greek or '')


def line_label(line_id):
    """A line number for display: Χ95 → X95 in English (as printed on the buses)."""
    return line_id if _lang == 'el' else (line_id or '').replace('Χ', 'X').replace('Α', 'A').replace('Β', 'B').replace('Ε', 'E')
