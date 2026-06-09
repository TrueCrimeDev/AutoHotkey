/**
 * DBGp packet classification for the MCP server.
 * Wire framing (both directions, TCP and stdio) is <length>\0<xml>\0 and is
 * implemented once in @ahk/dbgp-protocol; DbgpFrameParser is that framer in
 * lenient mode, which diverts raw script output that shares a stdio pipe.
 */

import { DBGpFramer } from '@ahk/dbgp-protocol';

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
  private framer = new DBGpFramer(undefined, { divertRaw: true });

  /** Feed raw bytes; returns any complete XML payloads. */
  feed(chunk: Buffer): string[] {
    return this.framer.push(chunk);
  }

  /** Bytes diverted because they were not part of any DBGp frame (raw script output). */
  drainRaw(): string {
    return this.framer.drainRaw();
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
