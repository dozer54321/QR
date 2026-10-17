declare module "qrcode" {
  export type ErrorCorrectionLevel = "L" | "M" | "Q" | "H";

  export interface QRCode {
    modules: {
      size: number;
      data: Uint8Array;
      reservedBit: Uint8Array;
      get(row: number, col: number): number;
    };
  }

  export function create(
    text: string,
    options?: { errorCorrectionLevel?: ErrorCorrectionLevel },
  ): QRCode;
}
