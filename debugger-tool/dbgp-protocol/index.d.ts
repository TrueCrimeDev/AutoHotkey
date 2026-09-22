/// <reference types="node" />
export class DBGpFramer {
  constructor(maxFrameBytes?: number);
  reset(): void;
  push(chunk: Buffer): string[];
}
