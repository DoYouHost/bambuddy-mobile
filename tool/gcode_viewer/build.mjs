// Bundles src/entry.js (plus three.js and the vendored slicer renderer) into
// the single file the app inlines into its WebView page. See PROVENANCE.
import { build } from 'esbuild';
import { readFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const outFile = resolve(here, '../../assets/gcode/viewer.js');

await mkdir(dirname(outFile), { recursive: true });

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
  outfile: outFile,
});

// The bundle is inlined between <script> tags. A literal closing tag anywhere
// inside it — in a string, a comment, a regex — would end the script early and
// leave the rest of the bundle on the page as text.
const text = await readFile(outFile, 'utf8');
if (text.includes('</script')) {
  throw new Error('bundle contains a literal </script — it cannot be inlined');
}

console.log(`viewer.js: ${(text.length / 1024).toFixed(1)} KiB`);
