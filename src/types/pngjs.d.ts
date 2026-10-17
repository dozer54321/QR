declare module "pngjs" {
  export class PNG {
    constructor(opts: { width: number; height: number });
    data: Uint8Array;
    width: number;
    height: number;
    static sync: {
      write(png: PNG): Buffer;
    };
  }
}
