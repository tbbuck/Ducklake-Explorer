// Print an SVG path for Apple's macOS icon tile: a superellipse
// (|x/a|^n + |y/a|^n = 1) centred on a 1024 canvas, 824 across, exponent 5.
// Used for the tile clip in the flat icon masters (the Icon Composer bundle
// does not need it: the system masks its layers itself).
//   node scripts/squircle-path.mjs
const cx = 512, cy = 512, a = 412, n = 5, steps = 180;
const pts = [];
for (let i = 0; i < steps; i++) {
  const t = (i / steps) * Math.PI * 2;
  const c = Math.cos(t), s = Math.sin(t);
  const x = cx + Math.sign(c) * a * Math.pow(Math.abs(c), 2 / n);
  const y = cy + Math.sign(s) * a * Math.pow(Math.abs(s), 2 / n);
  pts.push([x.toFixed(1), y.toFixed(1)]);
}
console.log('M ' + pts.map(p => p.join(' ')).join(' L ') + ' Z');
