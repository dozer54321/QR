import QRCode from "qrcode";

export type Ecc = "L" | "M" | "Q" | "H";

export type Rgb = { r: number; g: number; b: number };

export type Photo = {
  data: Uint8ClampedArray;
  width: number;
  height: number;
};

export type CodeImage = {
  data: Uint8ClampedArray;
  width: number;
  height: number;
};

const QUIET = 4;

export function encode(text: string, ecc: Ecc) {
  return QRCode.create(text, { errorCorrectionLevel: ecc }).modules;
}

export function parseHex(hex: string): Rgb {
  const raw = hex.trim().replace("#", "");
  const full =
    raw.length === 3
      ? raw
          .split("")
          .map((c) => c + c)
          .join("")
      : raw.padEnd(6, "0").slice(0, 6);
  const n = Number.parseInt(full, 16);
  if (Number.isNaN(n)) return { r: 20, g: 18, b: 16 };
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

export function toHex(c: Rgb): string {
  const b = (v: number) => clampByte(v).toString(16).padStart(2, "0");
  return `#${b(c.r)}${b(c.g)}${b(c.b)}`;
}

function clampByte(n: number) {
  return Math.max(0, Math.min(255, Math.round(n)));
}

function lum(c: Rgb) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
}

function mix(a: Rgb, b: Rgb, t: number): Rgb {
  return {
    r: a.r + (b.r - a.r) * t,
    g: a.g + (b.g - a.g) * t,
    b: a.b + (b.b - a.b) * t,
  };
}

/** Keep a floor so a camera still separates dark modules from light ones. */
function pushLum(color: Rgb, dark: boolean): Rgb {
  const L = lum(color);
  if (dark) {
    const cap = 72;
    if (L <= cap) return color;
    const scale = cap / Math.max(1, L);
    return { r: color.r * scale, g: color.g * scale, b: color.b * scale };
  }
  const floor = 198;
  if (L >= floor) return color;
  const lift = floor - L;
  return { r: color.r + lift, g: color.g + lift, b: color.b + lift };
}

function sample(photo: Photo, u: number, v: number): Rgb {
  const x = Math.min(photo.width - 1, Math.max(0, Math.floor(u * photo.width)));
  const y = Math.min(photo.height - 1, Math.max(0, Math.floor(v * photo.height)));
  const i = (y * photo.width + x) * 4;
  return { r: photo.data[i] ?? 0, g: photo.data[i + 1] ?? 0, b: photo.data[i + 2] ?? 0 };
}

function fillRect(
  out: Uint8ClampedArray,
  width: number,
  x: number,
  y: number,
  w: number,
  h: number,
  color: Rgb,
) {
  const r = clampByte(color.r);
  const g = clampByte(color.g);
  const b = clampByte(color.b);
  const x1 = Math.max(0, x);
  const y1 = Math.max(0, y);
  const x2 = Math.min(width, x + w);
  const height = out.length / 4 / width;
  const y2 = Math.min(height, y + h);
  for (let yy = y1; yy < y2; yy++) {
    let i = (yy * width + x1) * 4;
    for (let xx = x1; xx < x2; xx++) {
      out[i] = r;
      out[i + 1] = g;
      out[i + 2] = b;
      out[i + 3] = 255;
      i += 4;
    }
  }
}

function paintPhotoCell(
  out: Uint8ClampedArray,
  width: number,
  x0: number,
  y0: number,
  cell: number,
  photo: Photo,
  col: number,
  row: number,
  n: number,
  veil: Rgb,
  veilMix: number,
) {
  for (let yy = 0; yy < cell; yy++) {
    for (let xx = 0; xx < cell; xx++) {
      const u = (col + xx / cell) / n;
      const v = (row + yy / cell) / n;
      const px = mix(sample(photo, u, v), veil, veilMix);
      const i = ((y0 + yy) * width + (x0 + xx)) * 4;
      out[i] = clampByte(px.r);
      out[i + 1] = clampByte(px.g);
      out[i + 2] = clampByte(px.b);
      out[i + 3] = 255;
    }
  }
}

export function paintCode(opts: {
  text: string;
  ecc: Ecc;
  fg: string;
  bg: string;
  conceal: number;
  pixelSize: number;
  photo: Photo | null;
}): CodeImage {
  const matrix = encode(opts.text, opts.ecc);
  const n = matrix.size;
  const span = n + QUIET * 2;
  const cell = Math.max(4, Math.floor(opts.pixelSize / span));
  const width = cell * span;
  const height = width;
  const out = new Uint8ClampedArray(width * height * 4);
  const fg = parseHex(opts.fg);
  const bg = parseHex(opts.bg);
  const photo = opts.photo;
  const conceal = photo ? Math.min(1, Math.max(0, opts.conceal)) : 0;

  fillRect(out, width, 0, 0, width, height, bg);

  for (let row = 0; row < n; row++) {
    for (let col = 0; col < n; col++) {
      const dark = matrix.get(row, col) !== 0;
      const reserved = matrix.reservedBit[row * n + col] !== 0;
      const x0 = (col + QUIET) * cell;
      const y0 = (row + QUIET) * cell;
      const solid = !photo || reserved || conceal <= 0.001;
      if (solid) {
        fillRect(out, width, x0, y0, cell, cell, dark ? fg : bg);
        continue;
      }
      const inset = Math.max(1, Math.round(cell * (0.06 + conceal * 0.16)));
      const core = cell - inset * 2;
      paintPhotoCell(out, width, x0, y0, cell, photo, col, row, n, bg, 0.08);
      const shot = sample(photo, (col + 0.5) / n, (row + 0.5) / n);
      const target = dark ? fg : bg;
      const blend = 1 - conceal * 0.5;
      const color = pushLum(mix(shot, target, blend), dark);
      if (core > 0) fillRect(out, width, x0 + inset, y0 + inset, core, core, color);
    }
  }

  return { data: out, width, height };
}

/** A small darkroom still, so the weave can be tried before a real photo. */
export function sampleStill(size = 480): Photo {
  const data = new Uint8ClampedArray(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const nx = x / size;
      const ny = y / size;
      const windowX = 0.22;
      const windowY = 0.18;
      const inWindow = nx > windowX && nx < windowX + 0.28 && ny > windowY && ny < windowY + 0.46;
      const mullion = inWindow && (Math.abs(nx - (windowX + 0.14)) < 0.012 || Math.abs(ny - (windowY + 0.23)) < 0.012);
      const lamp = Math.hypot(nx - 0.74, ny - 0.62);
      const lampGlow = Math.max(0, 1 - lamp / 0.22);
      let r = 28 + ny * 18;
      let g = 22 + ny * 12;
      let b = 18 + ny * 8;
      if (inWindow && !mullion) {
        r = 214 - ny * 30;
        g = 168 - ny * 20;
        b = 112;
      }
      if (mullion) {
        r = 36;
        g = 28;
        b = 22;
      }
      r += lampGlow * 180;
      g += lampGlow * 92;
      b += lampGlow * 36;
      const shade = nx > 0.5 ? (nx - 0.5) * 40 : 0;
      const i = (y * size + x) * 4;
      data[i] = clampByte(r - shade);
      data[i + 1] = clampByte(g - shade * 0.6);
      data[i + 2] = clampByte(b - shade * 0.3);
      data[i + 3] = 255;
    }
  }
  return { data, width: size, height: size };
}

export function colorGap(fg: string, bg: string) {
  const a = lum(parseHex(fg));
  const b = lum(parseHex(bg));
  return Math.abs(a - b);
}
