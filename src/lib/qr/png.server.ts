import { PNG } from "pngjs";
import { paintCode } from "./paint";

export const DEFAULT_TEXT = "https://yourmomon.top";

export function openingDataUrl() {
  const image = paintCode({
    text: DEFAULT_TEXT,
    ecc: "H",
    fg: "#141210",
    bg: "#f4efe6",
    conceal: 0,
    pixelSize: 720,
    photo: null,
  });
  const png = new PNG({ width: image.width, height: image.height });
  png.data.set(image.data);
  const buf = PNG.sync.write(png);
  return `data:image/png;base64,${buf.toString("base64")}`;
}
