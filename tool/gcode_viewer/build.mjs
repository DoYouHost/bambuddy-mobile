// Bundles src/entry.js (plus three.js and the vendored slicer renderer) into
// the single file the app inlines into its WebView page, and subsets the app's
// own fonts into a stylesheet it inlines next to it. See PROVENANCE.
import { build } from 'esbuild';
import subsetFont from 'subset-font';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const assets = resolve(here, '../../assets/gcode');
const fonts = resolve(here, '../../assets/fonts');

await mkdir(assets, { recursive: true });

// ── the viewer bundle ────────────────────────────────────────────────────────

const bundleFile = resolve(assets, 'viewer.js');

await build({
  entryPoints: [resolve(here, 'src/entry.js')],
  bundle: true,
  minify: true,
  format: 'iife',
  // Android System WebView is Chromium and this app requires Android 11+, so
  // anything a 2021 Chrome understands is safe. Kept explicit because the
  // renderer needs WebGL2-era syntax and a lower target would down-level it.
  target: ['chrome100'],
  legalComments: 'inline',
  outfile: bundleFile,
});

// The bundle is inlined between <script> tags. A literal closing tag anywhere
// inside it — in a string, a comment, a regex — would end the script early and
// leave the rest of the bundle on the page as text.
const bundle = await readFile(bundleFile, 'utf8');
if (bundle.includes('</script')) {
  throw new Error('bundle contains a literal </script — it cannot be inlined');
}
report('viewer.js', bundle.length);

// ── the fonts ────────────────────────────────────────────────────────────────

/**
 * Every face the stylesheet asks for, and nothing else.
 *
 * The app's own fonts live in the APK, while the page is loaded with the
 * server's base URL — so it cannot fetch them, and without this it falls back
 * to whatever the system dresses the WebView in. Inlining them whole would add
 * some 700 KB; subset to the characters this page can actually show, they cost
 * a tenth of that.
 */
const FACES = [
  { family: 'Manrope', weight: 400, file: 'Manrope-400.ttf' },
  { family: 'Manrope', weight: 600, file: 'Manrope-600.ttf' },
  { family: 'Manrope', weight: 700, file: 'Manrope-700.ttf' },
  { family: 'JetBrains Mono', weight: 400, file: 'JetBrainsMono-400.ttf' },
  { family: 'JetBrains Mono', weight: 700, file: 'JetBrainsMono-700.ttf' },
];

/**
 * What to keep: ASCII, Latin-1 and Latin Extended-A, plus the punctuation the
 * page and the translations use.
 *
 * Latin Extended-A is what carries the Polish letters (and every other
 * Central-European one), so a new locale on the Latin script needs no change
 * here. A locale outside it — Cyrillic, Greek — would render in the system
 * face instead: legible, not ours, and fixed by widening this range.
 */
const keep = (() => {
  let text = '';
  for (let c = 0x20; c <= 0x7e; c += 1) text += String.fromCharCode(c);
  for (let c = 0xa0; c <= 0x17f; c += 1) text += String.fromCharCode(c);
  // The en dash is the layer window's separator ("12–47"), so it is load-bearing.
  return `${text}–—‘’“”…×°`;
})();

const faces = [];
for (const face of FACES) {
  const source = await readFile(resolve(fonts, face.file));
  const subset = await subsetFont(source, keep, { targetFormat: 'woff2' });
  faces.push(`@font-face {
  font-family: '${face.family}';
  font-style: normal;
  font-weight: ${face.weight};
  /* Nothing to wait for — the face is in the document — so painting text in a
     fallback first would be a flash for no reason. */
  font-display: block;
  src: url(data:font/woff2;base64,${subset.toString('base64')}) format('woff2');
}`);
}

const stylesheet = `${faces.join('\n')}\n`;
const fontsFile = resolve(assets, 'fonts.css');
await writeFile(fontsFile, stylesheet);
// Inlined into <style>, where a closing tag would end the block early.
if (stylesheet.includes('</style')) {
  throw new Error('font stylesheet contains a literal </style');
}
report('fonts.css', stylesheet.length);

function report(name, bytes) {
  console.log(`${name}: ${(bytes / 1024).toFixed(1)} KiB`);
}
