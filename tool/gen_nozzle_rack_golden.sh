#!/usr/bin/env bash
# Regenerates test/fixtures/nozzle_rack_golden.json by running the web's own
# rack helpers (utils/nozzleRack.ts from a bambuddy checkout) over seeded random
# racks and filament groups. lib/core/printers/nozzle_rack.dart must reproduce
# every answer.
#
#   tool/gen_nozzle_rack_golden.sh [path/to/bambuddy]   (default reference/bambuddy)
set -euo pipefail
ref="${1:-reference/bambuddy}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sed -e "/^import type /d" "$ref/frontend/src/utils/nozzleRack.ts" > "$work/nozzleRack.ts"

cat > "$work/gen.ts" <<'TS'
import { autoAssignRackPositions, rackOptionsForGroup } from './nozzleRack.ts';

let seed = 1784;
const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
const pick = <T,>(xs: T[]): T => xs[Math.floor(rnd() * xs.length)];
const diameters = ['0.4', '0.4', '0.40', '0.2', '0.6', ''];
const codes = ['HS01', 'HS01', 'HH01', ''];
const flows = ['Standard', 'High Flow', 'High Flow', ''];
const colours = ['FF0000FF', '00FF00FF', '000000FF', '00000000'];

const cases = [];
for (let n = 0; n < 300; n++) {
  const rack = [{ id: 1, nozzle_diameter: '0.4', nozzle_type: 'HS01', filament_color: '' }];
  for (let id = 16; id <= 21; id++) {
    if (rnd() < 0.15) continue;
    rack.push({ id, nozzle_diameter: pick(diameters), nozzle_type: pick(codes), filament_color: pick(colours) });
  }
  if (rnd() < 0.5) rack.push({ id: 0, nozzle_diameter: pick(diameters), nozzle_type: pick(codes), filament_color: pick(colours) });
  const groups: Record<number, Record<string, unknown>> = {};
  for (let g = 0; g < 1 + Math.floor(rnd() * 3); g++) {
    groups[g] = { on_rack: rnd() < 0.8, nozzle_diameter: pick(['0.4', '0.40', '0.2']), volume_type: pick(flows), filament_color: '#' + pick(colours).slice(0, 6) };
  }
  const pinned: Record<number, number> = {};
  for (const g of Object.keys(groups)) if (rnd() < 0.3) pinned[Number(g)] = 1 + Math.floor(rnd() * 7);
  const map = new Map(Object.entries(groups).map(([k, v]) => [Number(k), v]));
  const eligible = Object.fromEntries(
    Object.entries(groups).map(([k, g]) => [k, rackOptionsForGroup(rack as never, g as never, (key) => key).map((o) => o.eligible)]),
  );
  cases.push({ rack, groups, pinned, assigned: autoAssignRackPositions(rack as never, map as never, pinned), eligible });
}
console.log(JSON.stringify(cases));
TS
node --experimental-strip-types --no-warnings "$work/gen.ts" > test/fixtures/nozzle_rack_golden.json
echo "wrote $(python3 -c 'import json;print(len(json.load(open("test/fixtures/nozzle_rack_golden.json"))))') cases"
