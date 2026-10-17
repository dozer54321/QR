import assert from "node:assert/strict";
import test from "node:test";
import jsQR from "jsqr";
import { paintCode, sampleStill } from "./paint.ts";

const TEXT = "https://yourmomon.top";

function read(image: { data: Uint8ClampedArray; width: number; height: number }) {
  return jsQR(image.data, image.width, image.height, { inversionAttempts: "attemptBoth" });
}

test("plain code decodes", () => {
  const image = paintCode({
    text: TEXT,
    ecc: "H",
    fg: "#141210",
    bg: "#f4efe6",
    conceal: 0,
    pixelSize: 640,
    photo: null,
  });
  const hit = read(image);
  assert.equal(hit?.data, TEXT);
});

test("woven still decodes at a hidden setting", () => {
  const photo = sampleStill(420);
  const image = paintCode({
    text: TEXT,
    ecc: "H",
    fg: "#141210",
    bg: "#f4efe6",
    conceal: 0.62,
    pixelSize: 720,
    photo,
  });
  const hit = read(image);
  assert.equal(hit?.data, TEXT);
});
