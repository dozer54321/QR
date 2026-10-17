import { useEffect, useId, useRef, useState } from "react";
import jsQR from "jsqr";
import { colorGap, paintCode, sampleStill, type Ecc, type Photo } from "@/lib/qr/paint";

const STORAGE_KEY = "latent-qr";

const LEVELS: { id: Ecc; name: string; detail: string }[] = [
  { id: "L", name: "L", detail: "7 percent recovery. Smallest code." },
  { id: "M", name: "M", detail: "15 percent recovery." },
  { id: "Q", name: "Q", detail: "25 percent recovery." },
  { id: "H", name: "H", detail: "30 percent recovery. Best once a photo is woven in." },
];

type Saved = {
  text?: string;
  fg?: string;
  bg?: string;
  ecc?: Ecc;
  size?: number;
  conceal?: number;
};

function isEcc(value: string): value is Ecc {
  return value === "L" || value === "M" || value === "Q" || value === "H";
}

const DEFAULT_TEXT = "https://yourmomon.top";

export function LatentStudio({ openingSrc }: { openingSrc: string }) {
  const baseId = useId();
  const [previewUrl, setPreviewUrl] = useState(openingSrc);
  const fileRef = useRef<HTMLInputElement>(null);
  const [text, setText] = useState(DEFAULT_TEXT);
  const [fg, setFg] = useState("#141210");
  const [bg, setBg] = useState("#f4efe6");
  const [ecc, setEcc] = useState<Ecc>("H");
  const [size, setSize] = useState(720);
  const [conceal, setConceal] = useState(62);
  const [photo, setPhoto] = useState<Photo | null>(null);
  const [photoName, setPhotoName] = useState("");
  const [dragging, setDragging] = useState(false);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState("");
  const [readable, setReadable] = useState(true);
  const [built, setBuilt] = useState(true);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const saved = JSON.parse(raw) as Saved;
        if (typeof saved.text === "string") setText(saved.text);
        if (typeof saved.fg === "string" && /^#[0-9a-fA-F]{6}$/.test(saved.fg)) setFg(saved.fg);
        if (typeof saved.bg === "string" && /^#[0-9a-fA-F]{6}$/.test(saved.bg)) setBg(saved.bg);
        if (typeof saved.ecc === "string" && isEcc(saved.ecc)) setEcc(saved.ecc);
        if (typeof saved.size === "number") setSize(Math.min(1080, Math.max(320, saved.size)));
        if (typeof saved.conceal === "number") setConceal(Math.min(100, Math.max(0, saved.conceal)));
      }
    } catch {
      /* keep defaults */
    }
    setReady(true);
  }, []);

  useEffect(() => {
    if (!ready) return;
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ text, fg, bg, ecc, size, conceal }));
  }, [ready, text, fg, bg, ecc, size, conceal]);

  useEffect(() => {
    if (!ready) return;
    const trimmed = text.trim();
    if (!trimmed) {
      setBuilt(false);
      setError("");
      setReadable(false);
      setPreviewUrl("");
      return;
    }
    let image;
    try {
      image = paintCode({
        text: trimmed,
        ecc,
        fg,
        bg,
        conceal: conceal / 100,
        pixelSize: size,
        photo,
      });
    } catch {
      setBuilt(false);
      setError("That message is too long for this error correction. Shorten it, or drop to Q or M.");
      setReadable(false);
      setPreviewUrl("");
      return;
    }
    const off = document.createElement("canvas");
    off.width = image.width;
    off.height = image.height;
    const ctx = off.getContext("2d");
    if (!ctx) return;
    const frame = ctx.createImageData(image.width, image.height);
    frame.data.set(image.data);
    ctx.putImageData(frame, 0, 0);
    setPreviewUrl(off.toDataURL("image/png"));
    setError("");
    setBuilt(true);
    const expected = trimmed;
    const pixels = image.data;
    const width = image.width;
    const height = image.height;
    const timer = window.setTimeout(() => {
      const hit = jsQR(pixels, width, height, { inversionAttempts: "attemptBoth" });
      setReadable(hit?.data === expected);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [ready, text, fg, bg, ecc, size, conceal, photo]);

  function takeFile(file: File | undefined) {
    if (!file || !file.type.startsWith("image/")) return;
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      const side = 640;
      const scratch = document.createElement("canvas");
      scratch.width = side;
      scratch.height = side;
      const ctx = scratch.getContext("2d");
      if (!ctx) return;
      const crop = Math.min(img.width, img.height);
      const sx = (img.width - crop) / 2;
      const sy = (img.height - crop) / 2;
      ctx.drawImage(img, sx, sy, crop, crop, 0, 0, side, side);
      const frame = ctx.getImageData(0, 0, side, side);
      setPhoto({ data: new Uint8ClampedArray(frame.data), width: side, height: side });
      setPhotoName(file.name);
      URL.revokeObjectURL(url);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      setError("That image could not be opened.");
    };
    img.src = url;
  }

  function download() {
    if (!previewUrl || !built) return;
    const link = document.createElement("a");
    link.href = previewUrl;
    link.download = "latent.png";
    link.click();
  }

  const gap = colorGap(fg, bg);
  const faint = gap < 90;
  const messageId = `${baseId}-message`;
  const fgId = `${baseId}-fg`;
  const bgId = `${baseId}-bg`;
  const sizeId = `${baseId}-size`;
  const hideId = `${baseId}-hide`;
  const photoId = `${baseId}-photo`;

  let status = "The preview updates as you type.";
  if (error) status = error;
  else if (built && faint) status = "Those colors sit too close. A phone may miss the mark.";
  else if (built && photo && !readable) status = "Hidden too deep. Ease the veil until it reads.";
  else if (built && readable) status = photo ? "Woven in, and a phone can still read it." : "A phone can read this.";

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col gap-8 px-4 py-8 md:px-8 md:py-12">
      <header className="flex max-w-xl flex-col gap-3">
        <p className="font-sans text-sm font-medium tracking-widest text-safelight uppercase">Latent</p>
        <h1 className="font-display text-4xl leading-tight text-paper">A mark the picture keeps.</h1>
        <p className="font-sans text-base leading-relaxed text-silver">
          Type a link or any text. Drop a photograph if you want the code woven through it. The eyes of the
          mark stay sharp so a phone can lock on.
        </p>
      </header>

      <div className="grid items-start gap-8 lg:grid-cols-5">
        <section className="flex flex-col gap-4 lg:col-span-3" aria-labelledby={`${baseId}-preview-title`}>
          <h2 id={`${baseId}-preview-title`} className="font-display text-2xl text-paper">
            Preview
          </h2>
          <div
            className={`bg-paper p-4 ${dragging ? "outline-2 outline-offset-4 outline-safelight" : ""}`}
            onDragOver={(event) => {
              event.preventDefault();
              setDragging(true);
            }}
            onDragLeave={() => setDragging(false)}
            onDrop={(event) => {
              event.preventDefault();
              setDragging(false);
              takeFile(event.dataTransfer.files[0]);
            }}
          >
            {previewUrl ? (
              <img
                src={previewUrl}
                alt={text.trim() ? `QR code for ${text.trim()}` : "QR preview"}
                className="h-auto w-full"
              />
            ) : (
              <p className="flex aspect-square items-center justify-center px-6 text-center font-sans text-base text-ink">
                {error || "Type a link and the mark appears here."}
              </p>
            )}
          </div>
          <p role="status" aria-live="polite" className="font-sans text-sm text-silver">
            {status}
          </p>
          <button
            type="button"
            onClick={download}
            disabled={!built}
            className="min-h-12 bg-safelight px-4 font-sans text-base font-medium text-ink disabled:opacity-40"
          >
            Download PNG
          </button>
        </section>

        <form className="flex flex-col gap-6 lg:col-span-2" onSubmit={(event) => event.preventDefault()}>
          <div className="flex flex-col gap-2">
            <label htmlFor={messageId} className="font-sans text-sm font-medium text-paper">
              Link or text
            </label>
            <textarea
              id={messageId}
              value={text}
              onChange={(event) => setText(event.target.value)}
              rows={4}
              spellCheck={false}
              className="min-h-24 w-full resize-y border border-silver/40 bg-ink px-3 py-3 font-sans text-base text-paper"
              placeholder="https:// or any note"
            />
          </div>

          <fieldset className="flex flex-col gap-3">
            <legend className="font-sans text-sm font-medium text-paper">Colors</legend>
            <ColorField id={fgId} label="Dark modules" value={fg} onChange={setFg} />
            <ColorField id={bgId} label="Light modules" value={bg} onChange={setBg} />
          </fieldset>

          <div className="flex flex-col gap-2">
            <label htmlFor={sizeId} className="font-sans text-sm font-medium text-paper">
              Size, {size} pixels
            </label>
            <input
              id={sizeId}
              type="range"
              min={320}
              max={1080}
              step={40}
              value={size}
              onChange={(event) => setSize(Number(event.target.value))}
              className="accent-safelight min-h-12 w-full"
            />
          </div>

          <fieldset className="flex flex-col gap-2">
            <legend className="font-sans text-sm font-medium text-paper">Error correction</legend>
            {LEVELS.map((level) => {
              const id = `${baseId}-ecc-${level.id}`;
              return (
                <label key={level.id} htmlFor={id} className="flex min-h-12 items-center gap-3">
                  <input
                    id={id}
                    type="radio"
                    name={`${baseId}-ecc`}
                    value={level.id}
                    checked={ecc === level.id}
                    onChange={() => setEcc(level.id)}
                    className="accent-safelight size-5"
                  />
                  <span className="font-sans text-base text-paper">
                    <span className="font-medium">{level.name}</span>
                    <span className="text-silver"> — {level.detail}</span>
                  </span>
                </label>
              );
            })}
          </fieldset>

          <fieldset className="flex flex-col gap-3">
            <legend className="font-sans text-sm font-medium text-paper">Photograph</legend>
            <p className="font-sans text-sm leading-relaxed text-silver">
              The picture fills the code. Finder squares stay solid so a camera can find them. Drop a photo on
              the preview, or pick one.
            </p>
            <input
              ref={fileRef}
              id={photoId}
              type="file"
              accept="image/*"
              className="sr-only"
              onChange={(event) => takeFile(event.target.files?.[0])}
            />
            <div className="flex flex-col gap-2">
              <label
                htmlFor={photoId}
                className="flex min-h-12 items-center justify-center border border-silver/50 px-4 font-sans text-base text-paper"
              >
                {photoName || "Choose a photograph"}
              </label>
              <button
                type="button"
                className="min-h-12 border border-silver/50 px-4 font-sans text-base text-paper"
                onClick={() => {
                  setPhoto(sampleStill());
                  setPhotoName("Darkroom still");
                }}
              >
                Use a darkroom still
              </button>
              {photo ? (
                <button
                  type="button"
                  className="min-h-12 px-4 font-sans text-base text-silver"
                  onClick={() => {
                    setPhoto(null);
                    setPhotoName("");
                    if (fileRef.current) fileRef.current.value = "";
                  }}
                >
                  Remove photograph
                </button>
              ) : null}
            </div>
            <div className={`flex flex-col gap-2 ${photo ? "" : "opacity-40"}`}>
              <label htmlFor={hideId} className="font-sans text-sm font-medium text-paper">
                How hidden, {conceal} percent
              </label>
              <input
                id={hideId}
                type="range"
                min={0}
                max={100}
                step={1}
                value={conceal}
                disabled={!photo}
                onChange={(event) => setConceal(Number(event.target.value))}
                className="accent-safelight min-h-12 w-full"
              />
            </div>
          </fieldset>
        </form>
      </div>
    </main>
  );
}

function ColorField({
  id,
  label,
  value,
  onChange,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (next: string) => void;
}) {
  const hexId = `${id}-hex`;
  const [draft, setDraft] = useState(value);
  useEffect(() => {
    setDraft(value);
  }, [value]);
  const safe = /^#[0-9a-fA-F]{6}$/.test(value) ? value : "#141210";
  return (
    <div className="flex items-center gap-3">
      <label htmlFor={id} className="w-28 shrink-0 font-sans text-sm text-silver">
        {label}
      </label>
      <input
        id={id}
        type="color"
        value={safe}
        onChange={(event) => onChange(event.target.value)}
        className="size-12 shrink-0 border border-silver/40 bg-ink"
      />
      <input
        id={hexId}
        aria-label={`${label} hex`}
        value={draft}
        spellCheck={false}
        onChange={(event) => {
          const next = event.target.value;
          setDraft(next);
          if (/^#[0-9a-fA-F]{6}$/.test(next)) onChange(next);
        }}
        className="min-h-12 w-full border border-silver/40 bg-ink px-3 font-sans text-base text-paper"
      />
    </div>
  );
}
