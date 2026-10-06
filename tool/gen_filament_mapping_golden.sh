#!/usr/bin/env bash
# Regenerates test/fixtures/filament_mapping_golden.json by running the web's
# own mapping code (useFilamentMapping.ts + amsHelpers.ts from a bambuddy
# checkout) over seeded random printers and print files. The Dart port in
# lib/core/ams/filament_mapping.dart must reproduce every answer.
#
#   tool/gen_filament_mapping_golden.sh [path/to/bambuddy]   (default reference/bambuddy)
set -euo pipefail
ref="${1:-reference/bambuddy}"
src="$ref/frontend/src"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/utils" "$work/hooks"

# Type-only imports go; react, colour names and dates get stubs — none of them
# decides a slot.
sed -e "s#^import { parseUTCDate } from './date';#const parseUTCDate = (s: string) => new Date(s);#" \
  "$src/utils/amsHelpers.ts" > "$work/utils/amsHelpers.ts"
sed -e "s#^import { useMemo } from 'react';#const useMemo = (f: () => unknown) => f();#" \
    -e "s#^import { getColorName } from '../utils/colors';#const getColorName = (_c: string, _s?: string) => '';#" \
    -e "/^import type /d" \
    -e "s#from '../utils/amsHelpers';#from '../utils/amsHelpers.ts';#" \
  "$src/hooks/useFilamentMapping.ts" > "$work/hooks/useFilamentMapping.ts"

cat > "$work/gen.ts" <<'TS'
import { buildLoadedFilaments, buildFilamentComparison, buildAmsMapping } from './hooks/useFilamentMapping.ts';
import { effectivePreferLowest } from './utils/amsHelpers.ts';

let seed = 20261005;
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
const pick = <T,>(xs: T[]): T => xs[Math.floor(rnd() * xs.length)];
const types = ['PLA', 'PLA', 'PETG', 'PA-CF', 'PA12-CF', 'ABS', ''];
const colours = ['FF0000FF', 'F01010FF', 'E02828FF', '00FF00FF', '1E4821FF', '38202FFF', '2A4A2AFF', 'FFFFFF00', '000000FF', '0A0A0AFF'];
const idxs = ['GFA00', 'GFA00', 'GFA01', '', ''];

const cases = [];
const record = (status: Record<string, unknown>, filaments: Record<string, unknown>[], manual: Record<number, number>, inventory: Record<string, number>, setting: boolean) => {
  const loaded = buildLoadedFilaments(status as never);
  const preferLowest = effectivePreferLowest(setting, status.ams_filament_backup as boolean | null);
  const fts = (status.fila_switch as { installed: boolean } | undefined)?.installed === true;
  const comparison = buildFilamentComparison(
    { filaments } as never, loaded, manual, preferLowest,
    new Map(Object.entries(inventory).map(([k, v]) => [Number(k), v])), fts,
  );
  cases.push({
    status, filaments, manual, inventory, setting,
    mapping: buildAmsMapping(comparison) ?? null,
    statuses: comparison.map((c) => c.status),
    loaded: loaded.map((l) => ({ global: l.globalTrayId, color: l.color, extruder: l.extruderId ?? null })),
  });
};

// The ranking case `findNearestSimilar` exists for (amsHelpers.ts): two
// eligible spools where the first in slot order is the further one — purple
// #38202F is nearer #1E4821 in RGB, the green #2A4A2A perceptually.
for (const order of [['38202FFF', '2A4A2AFF'], ['2A4A2AFF', '38202FFF']]) {
  record(
    { id: 1, ams: [{ id: 0, tray: order.map((c, i) => ({ id: i, tray_type: 'PLA', tray_color: c, tray_info_idx: '', remain: 50 })) }], vt_tray: [] },
    [{ slot_id: 1, type: 'PLA', color: '#1E4821', tray_info_idx: '', used_grams: 10 }],
    {}, {}, false,
  );
}

for (let n = 0; n < 400; n++) {
  const units = [];
  const unitCount = Math.floor(rnd() * 3);
  for (let u = 0; u < unitCount; u++) {
    const ht = rnd() < 0.2;
    const id = ht ? 128 + u : u;
    const tray = [];
    for (let t = 0; t < (ht ? 1 : 4); t++) {
      tray.push({ id: t, tray_type: pick(types), tray_color: pick(colours), tray_info_idx: pick(idxs), remain: pick([-1, 0, 15, 40, 66, 100]) });
    }
    units.push({ id, tray });
  }
  const vt = [];
  const vtCount = Math.floor(rnd() * 3);
  for (let v = 0; v < vtCount; v++) {
    vt.push({ id: vtCount === 1 ? 254 : 254 + v, tray_type: pick(types), tray_color: pick(colours), tray_info_idx: pick(idxs), remain: pick([-1, 0, 50]) });
  }
  const dual = rnd() < 0.4;
  const status: Record<string, unknown> = {
    id: 1,
    ams: units,
    vt_tray: vt,
    nozzles: [{ nozzle_diameter: '0.4' }, { nozzle_diameter: dual && rnd() < 0.5 ? '0.4' : '' }],
    ams_extruder_map: dual ? Object.fromEntries(units.map((u) => [String(u.id), pick([0, 1])])) : {},
    fila_switch: { installed: rnd() < 0.15 },
    ams_filament_backup: pick([true, false, null]),
  };
  const filaments = [];
  let slot = 0;
  for (let f = 0; f < 1 + Math.floor(rnd() * 4); f++) {
    slot += 1 + (rnd() < 0.25 ? 1 : 0);
    const req: Record<string, unknown> = { slot_id: slot, type: pick(types.filter(Boolean)), color: '#' + pick(colours).slice(0, 6), tray_info_idx: pick(idxs), used_grams: 10 };
    if (dual && rnd() < 0.7) req.nozzle_id = pick([0, 1]);
    filaments.push(req);
  }
  const loaded = buildLoadedFilaments(status as never);
  const manual: Record<number, number> = {};
  for (const req of filaments) {
    if (rnd() < 0.2) manual[req.slot_id as number] = loaded.length && rnd() < 0.8 ? pick(loaded).globalTrayId : 99;
  }
  const inventory: Record<string, number> = {};
  for (const l of loaded) if (rnd() < 0.3) inventory[String(l.globalTrayId)] = pick([5, 120, 480, 900]);
  record(status, filaments, manual, inventory, rnd() < 0.5);
}
console.log(JSON.stringify(cases));
TS
node --experimental-strip-types --no-warnings "$work/gen.ts" > test/fixtures/filament_mapping_golden.json

# The colour names the mapping writes next to every slot (utils/colors.ts),
# and the web's slot labels.
cp "$src/utils/colors.ts" "$work/utils/colors.ts"
cat > "$work/colors.ts" <<'TS'
import { colorFamily, getColorName, setColorCatalog, disambiguateColorNames } from './utils/colors.ts';
import { formatSlotLabel } from './utils/amsHelpers.ts';

let seed = 7;
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
const hex2 = () => Math.floor(rnd() * 256).toString(16).padStart(2, '0');
const families = [];
for (let n = 0; n < 600; n++) {
  const alpha = rnd() < 0.1 ? '00' : rnd() < 0.5 ? 'FF' : '';
  const hex = `${rnd() < 0.5 ? '#' : ''}${hex2()}${hex2()}${hex2()}${alpha}`;
  families.push({ hex, family: colorFamily(hex) });
}
const catalog = { colors: { ffffff: 'Jade White', '000000': 'Black' }, by_material: { 'PLA Matte|#FFFFFF': 'Ivory White' } };
setColorCatalog(catalog.colors, catalog.by_material);
const names = [
  ['FFFFFFFF', 'PLA Matte'], ['#ffffff', null], ['000000ff', 'pla matte'], ['12345600', null], ['FF0000', null],
].map(([hex, material]) => ({ hex, material, name: getColorName(hex as string, material as string | null) }));
const pairs = [
  [['Blue', '#0028FF'], ['Blue', '#0A2989']], [['Blue', '#0028FF'], ['Navy', '#0A2989']],
  [['', '#0028FF'], ['Red', 'FF0000FF']], [['Red', ''], ['red', null]], [[null, 'zz'], ['Red', '#FF0000']],
].map(([a, b]) => ({ a, b, out: disambiguateColorNames({ name: a[0], hex: a[1] }, { name: b[0], hex: b[1] }) }));
const labels = [[0, 0, false], [1, 3, false], [128, 0, true], [129, 0, true], [3, 2, false]]
  .map(([a, t, ht]) => ({ ams: a, tray: t, ht, label: formatSlotLabel(a as number, t as number, ht as boolean, false) }));
console.log(JSON.stringify({ families, catalog, names, pairs, labels }));
TS
node --experimental-strip-types --no-warnings "$work/colors.ts" > test/fixtures/color_names_golden.json
echo "wrote colour names"
echo "wrote $(python3 -c 'import json;print(len(json.load(open("test/fixtures/filament_mapping_golden.json"))))') cases"
