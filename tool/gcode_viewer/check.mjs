// Post-vendoring check: does the copied parser still read a BambuStudio plate?
//
// Run after re-copying the vendored sources (see PROVENANCE). It is not a test
// suite — the server has those — only the tripwire for a copy that landed
// truncated, from the wrong path, or from a version whose annotations moved.
import { build } from 'esbuild';
import assert from 'node:assert/strict';

const bundled = await build({
  entryPoints: ['src/vendor/gcodeToolpath.ts'],
  bundle: true,
  format: 'esm',
  write: false,
  target: ['node20'],
});
const source = Buffer.from(bundled.outputFiles[0].text).toString('base64');
const parser = await import(`data:text/javascript;base64,${source}`);

// BambuStudio's own annotations, which are the whole reason this parser exists:
// reading only the OrcaSlicer/PrusaSlicer spellings turns a 2-layer plate into
// one unrecognised blob.
const gcode = [
  '; FEATURE: Outer wall',
  '; LINE_WIDTH: 0.42',
  'M83',
  'G1 Z0.2',
  '; CHANGE_LAYER',
  '; Z_HEIGHT: 0.2',
  'G1 X10 Y10 E0',
  'G1 X20 Y10 E0.5',
  'G1 X20 Y20 E0.5',
  '; FEATURE: Sparse infill',
  'G1 X10 Y20 E0.5',
  '; CHANGE_LAYER',
  '; Z_HEIGHT: 0.4',
  'G1 Z0.4',
  'G1 X10 Y10 E0.5',
  // An arc, which is a tenth of what a real plate is made of.
  'G2 X20 Y10 I5 J0 E0.7',
].join('\n');

const parsed = parser.parseGcodeToolpath(gcode);

assert.equal(parsed.layers.length, 2, 'layer markers');
assert.equal(parsed.defaultWidth, 0.42, 'line width annotation');
assert.ok(parsed.segmentCount > 10, 'arc interpolated into chords');
assert.deepEqual(parsed.bounds.min, [10, 10, 0.2], 'bounds');
assert.deepEqual(parsed.bounds.max, [20, 20, 0.4], 'bounds');

console.log(`ok — ${parsed.layers.length} layers, ${parsed.segmentCount} segments`);

// ── the fonts ────────────────────────────────────────────────────────────────
//
// A subset that came out empty, truncated or in the wrong format looks exactly
// like a good one from the outside: the page just renders in the system face,
// with nothing logged anywhere. So check the payloads rather than trusting the
// build to have run.
const { readFile } = await import('node:fs/promises');
const stylesheet = await readFile(
  new URL('../../assets/gcode/fonts.css', import.meta.url),
  'utf8',
);
const faces = stylesheet.split('@font-face').slice(1);
assert.equal(faces.length, 5, 'five faces (Manrope 400/600/700, mono 400/700)');

for (const face of faces) {
  const family = /font-family: '([^']+)'/.exec(face)?.[1];
  const weight = /font-weight: (\d+)/.exec(face)?.[1];
  const base64 = /base64,([^)]+)\)/.exec(face)?.[1];
  assert.ok(family && weight && base64, 'face declares family, weight, payload');

  const payload = Buffer.from(base64, 'base64');
  const where = `${family} ${weight}`;
  // 'wOF2' — the woff2 signature. Anything else means the format changed or
  // the payload is not a font at all.
  assert.equal(payload.subarray(0, 4).toString('latin1'), 'wOF2', where);
  // A face carrying only ASCII lands around 12 KB; below that something was
  // dropped, and Polish is the first thing to go.
  assert.ok(payload.length > 10_000, `${where} is suspiciously small`);
}

// A stray closing tag would end the <style> block the app inlines this into.
assert.ok(!stylesheet.includes('</style'), 'no literal </style');
console.log(`ok — ${faces.length} font faces, ${(stylesheet.length / 1024).toFixed(1)} KiB inlined`);
