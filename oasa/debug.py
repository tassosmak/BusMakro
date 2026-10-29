"""Debug flag and thread-safe logger (terminal + in-app overlay)."""
import os, sys, threading
from collections import deque
from datetime import datetime


# ---- Debug flag -------------------------------------------------------------
# Set DEBUG_DEFAULT = True here, or run with `--debug`, or BUSMAKRO_DEBUG=1.
# When on: everything is logged to the terminal AND shown in an in-app overlay
# (toggle it with the 🐞 button in the top bar).
DEBUG_DEFAULT = False

DEBUG = (DEBUG_DEFAULT
         or '--debug' in sys.argv
         or os.environ.get('BUSMAKRO_DEBUG', '').lower() in ('1', 'true', 'yes', 'on'))

DEBUG_LINES = deque(maxlen=300)

_debug_lock = threading.Lock()

_debug_seq = [0]

def log(msg, level='INFO'):
    """Thread-safe debug log: terminal + in-app overlay. No-op unless DEBUG."""
    if not DEBUG:
        return
    line = f'{datetime.now():%H:%M:%S.%f}'[:-3] + f' [{level}] {msg}'
    with _debug_lock:
        DEBUG_LINES.append(line)
        _debug_seq[0] += 1
    print(line, flush=True)
