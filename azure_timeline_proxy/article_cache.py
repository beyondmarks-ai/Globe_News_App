from collections import OrderedDict
from threading import Lock
from time import monotonic

_values = OrderedDict()
_lock = Lock()


def get_summary(url, language):
    key = (url, language)
    with _lock:
        entry = _values.get(key)
        if entry and entry[0] > monotonic():
            _values.move_to_end(key)
            return dict(entry[1])
        _values.pop(key, None)
    return None


def put_summary(url, language, value):
    ttl = 300 if value.get('summaryKind') == 'source_excerpt' else 3600
    with _lock:
        _values[(url, language)] = (monotonic() + ttl, dict(value))
        _values.move_to_end((url, language))
        while len(_values) > 128:
            _values.popitem(last=False)
