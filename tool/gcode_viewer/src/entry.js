/*
 * The in-app G-code preview.
 *
 * Runs inside the WebView on a page the app composes and loads with the
 * server's own base URL, so `fetch` here is same-origin with the API and the
 * app's auth headers ride along. Nothing is stored: no localStorage, no
 * cookies, no session.
 *
 * Everything it needs arrives in `window.__BB` before this script runs, and
 * every outcome is posted back to Flutter through the `BambuddyReport`
 * channel — the page is never left to fail silently, which is the bug that
 * started all this (issue #17).
 */
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

import {
  parseGcodeToolpath,
  layersByFilament,
  filterLayersByType,
} from './vendor/gcodeToolpath.ts';
import {
  buildSegmentData,
  makeToolpath,
  computeColors,
  TYPE_COLOR,
  DEFAULT_RANGES_COLORS,
} from './vendor/toolpathRenderer.js';

const cfg = window.__BB || {};
const labels = cfg.labels || {};

function report(what) {
  try {
    window.BambuddyReport.postMessage(what);
  } catch (e) {
    /* channel missing (a browser, a test) — the page still works */
  }
}

function fail(reason) {
  setStatus(labels.failed || 'Failed', true);
  report(`error:${reason}`);
}

const statusEl = document.getElementById('status');
const uiEl = document.getElementById('ui');

function setStatus(text, sticky) {
  if (!statusEl) return;
  statusEl.textContent = text || '';
  statusEl.style.display = text ? 'flex' : 'none';
  statusEl.dataset.sticky = sticky ? '1' : '';
}

/**
 * Tells Flutter the page is up and showing its own progress, so the app can
 * take its spinner down — two of them, one drawn over the other, is what the
 * user sees otherwise. Deliberately not "ready": the preview is still coming,
 * and the watchdog must keep running.
 */
function reportAlive() {
  report('loading');
}

/** Yields to the compositor so a status change actually paints before the
 *  parse takes the main thread for a few seconds. */
const paint = () =>
  new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));

async function fetchGcode() {
  let res;
  try {
    res = await fetch(cfg.gcodeUrl, {
      headers: cfg.headers || {},
      credentials: 'same-origin',
    });
  } catch (e) {
    throw { reason: 'network' };
  }
  if (!res.ok) throw { reason: `http:${res.status}` };
  return res.text();
}

function frameCamera(camera, controls, bounds, volume) {
  // Not Box3.setFromObject: the renderer keeps segment positions in a data
  // texture and the geometry attribute is only the 8-vertex template, so
  // measuring the object reports millimetres and parks the camera in orbit.
  const box = bounds
    ? new THREE.Box3(
        new THREE.Vector3(bounds.min[0], bounds.min[2], -bounds.max[1]),
        new THREE.Vector3(bounds.max[0], bounds.max[2], -bounds.min[1]),
      )
    : new THREE.Box3(
        new THREE.Vector3(0, 0, 0),
        new THREE.Vector3(volume.x, 1, -volume.y),
      );
  const center = box.getCenter(new THREE.Vector3());
  const radius = Math.max(box.getSize(new THREE.Vector3()).length() / 2, 0.001);
  const vFov = THREE.MathUtils.degToRad(camera.fov);
  const hFov = 2 * Math.atan(Math.tan(vFov / 2) * camera.aspect);
  const distance =
    1.15 * Math.max(radius / Math.sin(vFov / 2), radius / Math.sin(hFov / 2));
  camera.position
    .copy(center)
    .addScaledVector(new THREE.Vector3(0.7, 0.5, 0.7).normalize(), distance);
  camera.near = Math.max(distance / 1000, 0.01);
  camera.far = distance + radius * 4;
  camera.updateProjectionMatrix();
  controls.target.copy(center);
  controls.update();
}

/**
 * `#rgb` / `#rrggbb` → the packed integer the renderer's colour buffer takes.
 *
 * Ported from the server's own viewer; the fallback green is theirs too, and
 * it matters: a slot with no colour recorded must still draw as something.
 */
function packColor(hex) {
  const value = String(hex || '').replace('#', '');
  const full =
    value.length === 3
      ? value
          .split('')
          .map((c) => c + c)
          .join('')
      : value;
  const n = Number.parseInt(full.slice(0, 6), 16);
  return Number.isFinite(n) ? n : 0x00ae42;
}

const cssColor = (rgb) =>
  `rgb(${rgb.map((v) => Math.round(v * 255)).join(',')})`;

/**
 * The legend for the current colouring: named chips where the colours mean
 * categories, the renderer's own blue-to-red ramp where they mean a number.
 *
 * Names come from the app, not from the renderer: the vendored `TYPE_LABEL` is
 * upstream's Korean, and every string the user reads has to come through
 * `AppLocalizations`.
 */
function buildLegend(mode, data, colors, hidden, onToggleType) {
  const legend = document.getElementById('legend');
  if (!legend) return;
  legend.innerHTML = '';

  if (colors.cont) {
    // Height and width are measurements, so the legend is the scale itself.
    const stops = DEFAULT_RANGES_COLORS.map(cssColor).join(',');
    const ramp = document.createElement('div');
    ramp.className = 'ramp';
    ramp.style.background = `linear-gradient(to right, ${stops})`;
    const scale = document.createElement('div');
    scale.className = 'scale';
    scale.innerHTML =
      `<span>${colors.min.toFixed(2)}</span>` +
      `<span>${colors.unit || ''}</span>` +
      `<span>${colors.max.toFixed(2)}</span>`;
    legend.append(ramp, scale);
    setLegendCount(0, 0);
    return;
  }

  if (mode === 'filament') {
    // In this mode a vertex's "type" is its filament slot + 1, so the slots in
    // use are read off the same metadata the colours come from.
    const used = new Set();
    for (let v = 0; v < data.nV; v += 1) used.add(data.meta.vType[v]);
    const slots = [...used].sort((a, b) => a - b);
    for (const slotPlusOne of slots) {
      const slot = Math.max(0, slotPlusOne - 1);
      legend.appendChild(
        chipFor(
          filamentColor(slot),
          (labels.filaments || {})[slot] || `#${slot + 1}`,
          null,
          false,
          onToggleType,
        ),
      );
    }
    setLegendCount(slots.length, 0);
    return;
  }

  const names = labels.features || {};
  let shown = 0;
  let hiddenShown = 0;
  // 0 is travel, which has its own toggle rather than a chip.
  for (let type = 1; type < data.typeLengths.length; type += 1) {
    // A hidden type has no records left, so its length is zero — it still has
    // to be listed, or the only way back is a reset.
    if ((!data.typeLengths[type] && !hidden.has(type)) || !names[type]) continue;
    shown += 1;
    if (hidden.has(type)) hiddenShown += 1;
    legend.appendChild(
      chipFor(
        cssColor(TYPE_COLOR[type] || [0.5, 0.5, 0.5]),
        names[type],
        type,
        hidden.has(type),
        onToggleType,
      ),
    );
  }
  setLegendCount(shown, hiddenShown);
}

function chipFor(color, text, type, hidden, onToggle) {
  const chip = document.createElement('button');
  chip.type = 'button';
  chip.className = 'chip';
  chip.style.setProperty('--c', color);
  chip.textContent = text;
  chip.setAttribute('aria-pressed', hidden ? 'false' : 'true');
  // Filament slots are not toolpath types, so they colour but do not filter.
  if (type != null) chip.addEventListener('click', () => onToggle(type));
  return chip;
}

/** `n / total` for the legend header; empty when nothing is listed. */
function setLegendCount(shown, hiddenCount) {
  const countEl = document.getElementById('legend-count');
  if (countEl) countEl.textContent = shown ? `${shown - hiddenCount} / ${shown}` : '';
}

/** The AMS colour for a tool index, as CSS. */
function filamentColor(slot) {
  const colors = cfg.filamentColors || [];
  return colors[slot] || colors[0] || '#00ae42';
}

/**
 * Per-vertex colours, plus what the legend needs to describe them.
 *
 * Only filament is ours. Feature, height and width come from the renderer,
 * which is also where their ranges come from — speed, fan and temperature are
 * deliberately absent: upstream derives those from *settings* rather than from
 * the toolpath, and a guess dressed as a measurement is worse than an honest
 * omission.
 */
function colorsFor(mode, data) {
  if (mode !== 'filament') return computeColors(data, mode, {});
  const color = new Float32Array(data.nV * 4);
  for (let v = 0; v < data.nV; v += 1) {
    color[v * 4] = packColor(filamentColor(Math.max(0, data.meta.vType[v] - 1)));
  }
  return { color, min: 0, max: 0, unit: '', cont: false };
}

/**
 * The layer window: two thumbs on a rail that is itself the layer stack.
 *
 * Hand-rolled because `input[type=range]` has one thumb, and two of them
 * overlapping cannot both stay reachable — the one on top swallows every touch
 * in the middle of the track. Pointer events cover mouse and touch alike, and
 * the rail captures the pointer so a drag that wanders off it keeps working.
 */
function makeLayerRange(onChange) {
  const track = document.getElementById('layers');
  const ticksEl = document.getElementById('ticks');
  const thumbHi = document.getElementById('thumb-hi');
  const thumbLo = document.getElementById('thumb-lo');
  const readout = document.getElementById('readout');
  const rLayer = document.getElementById('r-layer');
  const rZ = document.getElementById('r-z');
  const rRange = document.getElementById('r-range');

  let ticks = [];
  let lo = 0;
  let hi = 1;
  let dragging = null;

  /** One tick per sample, equal length, capped so tall plates stay readable. */
  const buildTicks = (count) => {
    const n = Math.max(2, Math.min(count, 40));
    if (ticks.length === n) return;
    ticksEl.innerHTML = '';
    ticks = Array.from({ length: n }, () =>
      ticksEl.appendChild(document.createElement('i')),
    );
  };

  const place = () => {
    thumbHi.style.bottom = `${hi * 100}%`;
    thumbLo.style.bottom = `${lo * 100}%`;
    // Clamped so the readout never rides off the top or bottom of the canvas.
    readout.style.bottom = `${Math.min(91, Math.max(9, hi * 100))}%`;
    const n = ticks.length;
    const nearest = Math.min(n - 1, Math.max(0, Math.round(hi * n - 0.5)));
    for (let i = 0; i < n; i += 1) {
      // Coverage, not point sampling: with 226 layers on 40 ticks a single
      // layer still lights exactly one tick instead of none.
      const on = (i + 1) / n >= lo && i / n <= hi;
      ticks[i].className = on || i === nearest ? 'on' : '';
    }
  };

  /** Pointer y → fraction of the rail, top being the last layer. */
  const fractionAt = (event) => {
    const box = track.getBoundingClientRect();
    if (box.height <= 0) return 0;
    return Math.min(1, Math.max(0, 1 - (event.clientY - box.top) / box.height));
  };

  const move = (event) => {
    if (!dragging) return;
    event.preventDefault();
    const at = fractionAt(event);
    if (dragging === 'hi') hi = Math.max(at, lo);
    else lo = Math.min(at, hi);
    place();
    onChange(lo, hi);
  };

  track.addEventListener('pointerdown', (event) => {
    const at = fractionAt(event);
    // Whichever thumb is nearer, so a tap near the bottom grabs the bottom one
    // rather than dragging the top one down over it.
    dragging = Math.abs(at - hi) <= Math.abs(at - lo) ? 'hi' : 'lo';
    track.setPointerCapture(event.pointerId);
    move(event);
  });
  track.addEventListener('pointermove', move);
  for (const type of ['pointerup', 'pointercancel']) {
    track.addEventListener(type, () => {
      dragging = null;
    });
  }

  return {
    /** Called back with the resolved layers, which own the labels. */
    render(a, b, count, zHeight) {
      buildTicks(count);
      rLayer.textContent = String(b + 1);
      rZ.textContent = zHeight != null ? `${zHeight.toFixed(2)} mm` : '';
      rRange.textContent =
        a === b ? labels.singleLayer || 'single layer' : `${a + 1}–${b + 1}`;
      const last = Math.max(1, count - 1);
      hi = b / last;
      lo = a / last;
      place();
    },
  };
}

async function main() {
  const volume = cfg.volume || { x: 256, y: 256, z: 256 };
  const container = document.getElementById('view');

  // Flutter measures the system's gesture insets; CSS `env()` cannot see them
  // from inside a WebView, so they arrive in the config instead.
  document.documentElement.style.setProperty(
    '--inset-right',
    `${cfg.insetRight || 0}px`,
  );
  document.documentElement.classList.toggle('light', cfg.dark === false);

  setStatus(labels.loading || 'Loading…');
  reportAlive();
  const text = await fetchGcode();

  setStatus(labels.parsing || 'Reading G-code…');
  await paint();
  const parsed = parseGcodeToolpath(text);
  if (!parsed.layers.length) throw { reason: 'empty' };

  const scene = new THREE.Scene();
  // Matches --bg in the shell, so the canvas and the chrome are one surface.
  scene.background = new THREE.Color(cfg.dark === false ? 0xf6f8f4 : 0x0b0f0c);

  const width = container.clientWidth || 1;
  const height = container.clientHeight || 1;
  const camera = new THREE.PerspectiveCamera(45, width / height, 0.1, 10000);

  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(width, height);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  container.appendChild(renderer.domElement);

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.05;

  // The toolpath group is rotated -90° about X to take the slicer's Z-up space
  // into three's Y-up, which maps (x, y, z) to (x, z, -y) — so the bed's +Y
  // runs along world -Z and the grid belongs at -y/2, not +y/2.
  const grid = new THREE.GridHelper(
    Math.max(volume.x, volume.y),
    Math.ceil(Math.max(volume.x, volume.y) / 16),
    cfg.dark === false ? 0xc2cabd : 0x444444,
    cfg.dark === false ? 0xd8ded2 : 0x333333,
  );
  grid.position.set(volume.x / 2, 0, -volume.y / 2);
  scene.add(grid);

  // Only filament colouring needs its own mesh: it merges adjacent vertices by
  // tool where the other three merge by feature, so those three share a stream
  // and switching between them is a recolour, not a rebuild. The camera is
  // framed once, on the first build, so no switch yanks the view back from
  // wherever the user put it.
  const group = new THREE.Group();
  group.rotation.x = -Math.PI / 2;
  scene.add(group);

  let handle = null;
  let data = null;
  let framed = false;
  /** Layer window as fractions, so it survives a rebuild. */
  let lo = 0;
  let hi = 1;
  /** Toolpath types the user has switched off. */
  const hidden = new Set();
  let travelsOn = false;

  function build(mode) {
    if (handle) {
      group.remove(handle.mesh);
      group.remove(handle.travLines);
      // The handle owns instanced buffers and a data texture per segment; on a
      // large plate that is a lot of GPU memory to leave behind.
      handle.dispose();
    }
    // Filament colouring rewrites each record's type to its *slot*, so a set of
    // hidden feature types means something else entirely there — filtering by
    // it would hide slot 5 in place of supports. The chips do not filter in
    // that mode either, which is the same rule seen from the other side.
    const layers =
      mode === 'filament'
        ? layersByFilament(parsed.layers)
        : filterLayersByType(parsed.layers, hidden);
    data = buildSegmentData(layers, parsed.defaultWidth);
    handle = makeToolpath(THREE, data);
    group.add(handle.mesh);
    group.add(handle.travLines);
    setTravels(travelsOn);
    recolor(mode);
    applyRange();
    if (!framed) {
      framed = true;
      frameCamera(camera, controls, parsed.bounds, volume);
    }
  }

  function recolor(mode) {
    // The toolpath shader carries its own light directions, so the scene needs
    // no lights at all.
    const colors = colorsFor(mode, data);
    handle.setColors(colors.color);
    buildLegend(mode, data, colors, hidden, onToggleType);
  }

  // Hiding removes the records before the mesh is built rather than recolouring
  // them: the shader packs colour into a single float with no alpha, so there
  // is no transparent to set — and removal is the useful behaviour anyway, in
  // that a hidden support stops occluding what it covered.
  const onToggleType = (type) => {
    if (hidden.has(type)) hidden.delete(type);
    else hidden.add(type);
    build(mode);
  };

  const layerRange = makeLayerRange((a, b) => {
    lo = a;
    hi = b;
    applyRange();
  });

  function applyRange() {
    const last = handle.layerCount - 1;
    const a = Math.round(lo * last);
    const b = Math.round(hi * last);
    handle.setLayerRange(a, b);
    // `parsed.layers` is index-aligned with the rendered layers in every mode,
    // so the top layer's Z can be read straight off it.
    const layer = parsed.layers[Math.min(b, parsed.layers.length - 1)];
    layerRange.render(a, b, handle.layerCount, layer && layer.z);
  }

  function setTravels(on) {
    handle.setTravelVisible(on);
    for (const id of ['travels', 'dock-travels']) {
      document.getElementById(id).setAttribute('aria-pressed', String(on));
    }
  }

  for (const id of ['travels', 'dock-travels']) {
    document.getElementById(id).addEventListener('click', () => {
      travelsOn = !travelsOn;
      setTravels(travelsOn);
    });
  }
  document.getElementById('travels-label').textContent = labels.travels || 'Travels';

  const setCollapsed = (on) =>
    document.documentElement.classList.toggle('collapsed', on);
  document.getElementById('collapse').addEventListener('click', () => setCollapsed(true));
  document.getElementById('expand').addEventListener('click', () => setCollapsed(false));

  for (const id of ['reset', 'dock-reset']) {
    document.getElementById(id).addEventListener('click', () => {
      lo = 0;
      hi = 1;
      hidden.clear();
      build(mode);
      frameCamera(camera, controls, parsed.bounds, volume);
    });
  }

  // Filament colouring answers "which spool prints what", which is only a
  // question when more than one is involved; with a single colour it paints the
  // whole plate one shade and says nothing, so a single-material file opens on
  // features instead.
  const filaments = (cfg.filamentColors || []).filter(Boolean);
  let mode = new Set(filaments).size > 1 ? 'filament' : 'feature';
  build(mode);

  const modes = document.getElementById('modes');
  const offered = [
    ...(filaments.length ? [['filament', labels.colorByFilament || 'Filament']] : []),
    ['feature', labels.colorByFeature || 'Feature'],
    ['height', labels.colorByHeight || 'Height'],
    ['width', labels.colorByWidth || 'Width'],
  ];
  for (const [key, label] of offered) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = label;
    button.dataset.mode = key;
    button.className = key === mode ? 'on' : '';
    button.addEventListener('click', () => {
      if (mode === key) return;
      const rebuild = (mode === 'filament') !== (key === 'filament');
      mode = key;
      for (const other of modes.children) {
        other.className = other.dataset.mode === key ? 'on' : '';
      }
      if (rebuild) build(mode);
      else recolor(mode);
    });
    modes.appendChild(button);
  }

  const resize = () => {
    const w = container.clientWidth || 1;
    const h = container.clientHeight || 1;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h);
  };
  new ResizeObserver(resize).observe(container);

  const animate = () => {
    requestAnimationFrame(animate);
    controls.update();
    renderer.render(scene, camera);
  };
  animate();

  setStatus('');
  if (uiEl) uiEl.style.display = 'block';
  // Only after a frame exists: "ready" is what takes the app's spinner down.
  requestAnimationFrame(() => report('ready'));
}

main().catch((e) => {
  fail((e && e.reason) || 'script');
});
