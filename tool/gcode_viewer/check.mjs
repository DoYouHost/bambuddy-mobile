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
