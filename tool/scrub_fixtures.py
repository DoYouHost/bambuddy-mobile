#!/usr/bin/env python3
"""Trim and scrub one captured API response into a committable fixture.

A capture is worth having because it is the server's own JSON — but the server's
own JSON carries the LAN it runs on and the serial of the printer it talks to,
and a fixture lives in a public repository. Both are masked in a diagnostic log
(`LogRedactor`), so leaving them in a fixture would be holding the fixture to a
lower standard than the log.

What is replaced, in place and keeping the shape a parser sees:

* IPv4 addresses -> 192.0.2.x, the RFC 5737 documentation range, so nobody has
  to wonder whether an address in the repo is somebody's real one.
* Bambu serials -> the first three characters (which say the model, not the
  unit) plus a fixed tail of the same length.
* Fields whose NAME says the value is private -> `[REDACTED]`. Keyed on the same
  list as `LogRedactor._secretKey`, because a smart plug's `ha_entity_id` reads
  `switch.szafa_biuro`: Home Assistant entities are named by their owner, so the
  string maps a home and says which room the printer stands in. That one shipped
  in this repository before anyone noticed, which is the whole argument for
  keying on names here rather than trusting the value patterns above.

  Serials stay out of that list on purpose: replacing them with a same-length
  dummy keeps a fixture parseable by code that cares about their shape, and
  `[REDACTED]` would not.

Names are deliberately left alone: file, project and printer names are what make
a captured record readable, and the capture tool says out loud that they go in.

    scrub_fixtures.py <input.json> <output.json> [--max N]
"""
from __future__ import annotations

import argparse
import json
import re
import sys

IPV4 = re.compile(
    r'\b(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]\d|\d)\.){3}'
    r'(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]\d|\d)\b'
)
# Bambu serials as they actually turn up: 15 characters, two digits, a letter,
# then alphanumerics. Covers the printer (20P9…) and the AMS unit (19C0…).
SERIAL = re.compile(r'\b(\d{2}[A-Z])[0-9A-Z]{12}\b')

# Parity with `LogRedactor._secretKey` (lib/core/diagnostics/log_redactor.dart).
# When one list grows the other has to, or the fixture is held to a lower
# standard than the log — which is the thing this file exists to prevent.
#
# `entity` and `topic` are fenced by a non-alphanumeric so they cannot swallow
# `identity` or a word that merely ends in them; `rest_*` is scoped to that
# prefix so `cover_url` and `external_camera_url` stay readable.
SECRET_KEY = re.compile(
    r'(token|api_?key|(?:^|[^a-z0-9])key(?:$|[^a-z0-9])|secret|password|passwd'
    r'|authorization|access_?code|cookie|username'
    r'|(?:^|[^a-z0-9])entity|(?:^|[^a-z0-9])topic|headers|rest_\w*(?:url|body))',
    re.IGNORECASE,
)


def scrub_text(text: str) -> str:
    out = IPV4.sub('192.0.2.10', text)
    return SERIAL.sub(lambda m: f'{m.group(1)}000000000001'[:15], out)


def redacted(value):
    """A secret-named field's replacement — except `None`, which stays `None`.

    Same rule as the log redactor: an absent value has nothing to leak, and
    whether one is set is often the diagnosis (a plug with no `ha_power_entity`
    reports no power). `[REDACTED]` on that field would read as "configured".
    """
    return None if value is None else '[REDACTED]'


def scrub(node):
    if isinstance(node, dict):
        return {
            key: redacted(value) if SECRET_KEY.search(key) else scrub(value)
            for key, value in node.items()
        }
    if isinstance(node, list):
        return [scrub(value) for value in node]
    if isinstance(node, str):
        return scrub_text(node)
    return node


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('destination')
    parser.add_argument('--max', type=int, default=8,
                        help='keep at most N records of a list (default 8)')
    args = parser.parse_args(argv)

    with open(args.source, encoding='utf-8') as handle:
        data = json.load(handle)

    dropped = 0
    if isinstance(data, list) and len(data) > args.max:
        dropped = len(data) - args.max
        data = data[:args.max]

    with open(args.destination, 'w', encoding='utf-8') as handle:
        json.dump(scrub(data), handle, indent=2, ensure_ascii=False)
        handle.write('\n')

    kind = f'{len(data)} records' if isinstance(data, list) else 'object'
    extra = f', {dropped} more dropped' if dropped else ''
    print(f'{args.destination.rsplit("/", 1)[-1]}: {kind}{extra}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
