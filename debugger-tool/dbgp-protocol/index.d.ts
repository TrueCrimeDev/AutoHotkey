/// <reference types="node" />
export interface DBGpFramerOptions {
  /** Divert bytes that cannot start a frame into a raw buffer instead of throwing (stdio transports). */
  divertRaw?: boolean;
}
export class DBGpFramer {
  constructor(maxFrameBytes?: number, options?: DBGpFramerOptions);
  reset(): void;
  push(chunk: Buffer): string[];
  /** Raw bytes diverted in lenient mode since the last drain; empty in strict mode. */
  drainRaw(): string;
}
