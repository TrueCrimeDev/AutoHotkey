/**
 * DBGp frame parser and packet classifier.
 * Wire framing (both directions, TCP and stdio): <length>\0<xml>\0
 * where <length> is the ASCII decimal byte count of <xml>.
 */

export interface DbgpStreamPacket {
  kind: 'stream';
  stream: 'stdout' | 'stderr';
  text: string;
}

export interface DbgpInitPacket {
  kind: 'init';
  attributes: Record<string, string>;
}

export interface DbgpResponsePacket {
  kind: 'response';
  attributes: Record<string, string>;
  raw: string;
}

export type DbgpPacket = DbgpStreamPacket | DbgpInitPacket | DbgpResponsePacket;

export class DbgpFrameParser {
  private buffer = Buffer.alloc(0);
  private rawChunks: Buffer[] = [];

  /** Feed raw bytes; returns any complete XML payloads. */
  feed(chunk: Buffer): string[] {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    const messages: string[] = [];

    for (;;) {
      // A frame starts with an ASCII decimal length. Anything else is raw
      // passthrough output (e.g. Print() writes directly to the stdout handle
      // in stdio debug mode, bypassing DBGp stream redirection) — divert it.
      let skip = 0;
      while (skip < this.buffer.length && (this.buffer[skip] < 0x30 || this.buffer[skip] > 0x39)) skip++;
      if (skip > 0) {
        this.rawChunks.push(this.buffer.subarray(0, skip));
        this.buffer = this.buffer.subarray(skip);
      }

      const nullPos = this.buffer.indexOf(0);
      if (nullPos === -1) break;

      const lengthStr = this.buffer.subarray(0, nullPos).toString('ascii');
      const dataLength = parseInt(lengthStr, 10);
      if (isNaN(dataLength) || dataLength < 0 || String(dataLength) !== lengthStr) {
        // Digit-led junk that isn't a valid length prefix — divert one byte and resync.
        this.rawChunks.push(this.buffer.subarray(0, 1));
        this.buffer = this.buffer.subarray(1);
        continue;
      }

      const totalNeeded = nullPos + 1 + dataLength + 1;
      if (this.buffer.length < totalNeeded) break; // wait for more data

      messages.push(this.buffer.subarray(nullPos + 1, nullPos + 1 + dataLength).toString('utf-8'));
      this.buffer = this.buffer.subarray(totalNeeded);
    }

    return messages;
  }

  /** Bytes diverted because they were not part of any DBGp frame (raw script output). */
  drainRaw(): string {
    if (this.rawChunks.length === 0) return '';
    const text = Buffer.concat(this.rawChunks).toString('utf-8');
    this.rawChunks = [];
    return text;
  }
}

export function parseAttributes(tagBody: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const re = /(\w+)="([^"]*)"/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(tagBody)) !== null) attrs[m[1]] = m[2];
  return attrs;
}

export function classifyPacket(xml: string): DbgpPacket {
  const streamMatch = xml.match(/<stream([^>]*)>([\s\S]*?)<\/stream>/);
  if (streamMatch) {
    const attrs = parseAttributes(streamMatch[1]);
    return {
      kind: 'stream',
      stream: attrs.type === 'stderr' ? 'stderr' : 'stdout',
      text: Buffer.from(streamMatch[2].trim(), 'base64').toString('utf-8'),
    };
  }

  const initMatch = xml.match(/<init([^>]*?)\/?>/);
  if (initMatch) {
    return { kind: 'init', attributes: parseAttributes(initMatch[1]) };
  }

  const respMatch = xml.match(/<response([^>]*?)\/?>/);
  return {
    kind: 'response',
    attributes: respMatch ? parseAttributes(respMatch[1]) : {},
    raw: xml,
  };
}
