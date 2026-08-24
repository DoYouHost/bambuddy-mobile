#!/usr/bin/env python3
"""Print the versionName/versionCode baked into built Play bundles.

Reads base/manifest/AndroidManifest.xml straight out of the .aab zip: aapt2
refuses the bundle container ("could not identify format of APK") and bundletool
is not part of the toolchain here. That manifest is aapt2's protobuf XML rather
than binary XML, but pulling two attributes out of it needs only the handful of
field numbers below — no generated schema, no dependency.

usage: tool/aab_versions.py [BUNDLE...]   (default: build/dist/*.aab)
"""

import sys
import zipfile
from glob import glob

# android:versionCode / android:versionName. Matched on the platform resource id
# and not on the attribute name, which in the proto manifest is namespace-bare
# and would also match a same-named attribute of some other namespace.
VERSION_CODE = 0x0101021B
VERSION_NAME = 0x0101021C

# Field numbers from aapt2's Resources.proto: XmlNode.element,
# XmlElement.attribute, XmlAttribute.value and XmlAttribute.resource_id.
NODE_ELEMENT = 1
ELEMENT_ATTRIBUTE = 4
ATTR_VALUE = 3
ATTR_RESOURCE_ID = 5

MANIFEST = "base/manifest/AndroidManifest.xml"


def _varint(buf, i):
    result = shift = 0
    while True:
        byte = buf[i]
        i += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, i
        shift += 7


def _fields(buf):
    """Walk one protobuf message, yielding (field_number, payload) for varint
    and length-delimited fields and stepping over the fixed-width ones."""
    i = 0
    while i < len(buf):
        key, i = _varint(buf, i)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, i = _varint(buf, i)
            yield number, value
        elif wire == 2:
            length, i = _varint(buf, i)
            yield number, buf[i:i + length]
            i += length
        elif wire == 5:
            i += 4
        elif wire == 1:
            i += 8
        else:
            raise ValueError(f"{MANIFEST}: unsupported wire type {wire}")


def bundle_versions(path):
    """Return (versionName, versionCode) as strings, or (None, None)."""
    with zipfile.ZipFile(path) as bundle:
        raw = bundle.read(MANIFEST)
    root = next(payload for number, payload in _fields(raw)
                if number == NODE_ELEMENT)
    found = {}
    for number, payload in _fields(root):
        if number != ELEMENT_ATTRIBUTE:
            continue
        attribute = dict(_fields(payload))
        resource_id = attribute.get(ATTR_RESOURCE_ID)
        if resource_id in (VERSION_CODE, VERSION_NAME):
            found[resource_id] = attribute.get(ATTR_VALUE, b"").decode("utf-8")
    return found.get(VERSION_NAME), found.get(VERSION_CODE)


def main(argv):
    paths = argv or sorted(glob("build/dist/*.aab"))
    if not paths:
        print("No bundles in build/dist — nothing to report.")
        return 0

    rows = []
    for path in paths:
        try:
            name, code = bundle_versions(path)
        except (OSError, KeyError, ValueError, StopIteration) as err:
            print(f"{path}: cannot read {MANIFEST} ({err})", file=sys.stderr)
            return 1
        if name is None or code is None:
            print(f"{path}: manifest carries no version", file=sys.stderr)
            return 1
        rows.append((path, name, code))

    width = max(len(path) for path, _, _ in rows)
    print("Built bundles:")
    for path, name, code in rows:
        print(f"  {path:<{width}}  {name:<20}  versionCode {code}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
