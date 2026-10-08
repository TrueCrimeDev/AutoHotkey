'use strict';

// DBGp lengths count UTF-8 bytes, independently of socket chunk boundaries.
//
// Strict mode (default) treats anything that is not a well-formed frame as a
// protocol error. Lenient mode (`divertRaw: true`) instead diverts bytes that
// cannot start a frame into a raw buffer: in /Debug=stdio mode the engine
// shares the pipe with script output, so Print() text written straight to the
// stdout handle can appear between frames.
class DBGpFramer {
  constructor(maxFrameBytes = 64 * 1024 * 1024, { divertRaw = false } = {}) {
    this.maxFrameBytes = maxFrameBytes;
    this.divertRaw = divertRaw;
    this.reset();
  }

  reset() {
    this.buffer = Buffer.alloc(0);
    this.length = null;
    this.rawChunks = [];
  }

  push(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    return this.divertRaw ? this.pushLenient() : this.pushStrict();
  }

  /** Bytes diverted in lenient mode because they were not part of any frame. */
  drainRaw() {
    if (this.rawChunks.length === 0) return '';
    const text = Buffer.concat(this.rawChunks).toString('utf8');
    this.rawChunks = [];
    return text;
  }

  pushStrict() {
    const messages = [];
    try {
      while (true) {
        if (this.length === null) {
          const delimiter = this.buffer.indexOf(0);
          if (delimiter < 0) {
            if (this.buffer.length > 10) throw new Error('Invalid DBGp length header');
            break;
          }
          const bytes = this.buffer.subarray(0, delimiter);
          if (!delimiter || delimiter > 10 || bytes.some(byte => byte < 48 || byte > 57)) throw new Error('Invalid DBGp length header');
          const header = bytes.toString('ascii');
          const length = Number(header);
          if (!Number.isSafeInteger(length) || length > this.maxFrameBytes) throw new Error('DBGp frame exceeds limit');
          this.length = length;
          this.buffer = this.buffer.subarray(delimiter + 1);
        }
        if (this.buffer.length < this.length + 1) break;
        if (this.buffer[this.length] !== 0) throw new Error('Invalid DBGp frame terminator');
        messages.push(this.buffer.subarray(0, this.length).toString('utf8'));
        this.buffer = this.buffer.subarray(this.length + 1);
        this.length = null;
      }
      return messages;
    } catch (error) {
      this.reset();
      throw error;
    }
  }

  // The header is only consumed once its whole frame has been validated, so a
  // digit-led run of raw output can be diverted one byte at a time and resynced.
  pushLenient() {
    const messages = [];
    const divert = count => {
      this.rawChunks.push(this.buffer.subarray(0, count));
      this.buffer = this.buffer.subarray(count);
    };
    while (this.buffer.length) {
      let skip = 0;
      while (skip < this.buffer.length && (this.buffer[skip] < 48 || this.buffer[skip] > 57)) skip++;
      if (skip) divert(skip);
      const delimiter = this.buffer.indexOf(0);
      if (delimiter < 0) {
        if (this.buffer.length > 10) { divert(1); continue; }
        break;
      }
      if (!delimiter || delimiter > 10) { divert(1); continue; }
      const header = this.buffer.subarray(0, delimiter);
      if (header.some(byte => byte < 48 || byte > 57)) { divert(1); continue; }
      const length = Number(header.toString('ascii'));
      if (!Number.isSafeInteger(length) || length > this.maxFrameBytes) { divert(1); continue; }
      const total = delimiter + 1 + length + 1;
      if (this.buffer.length < total) break;
      if (this.buffer[total - 1] !== 0) { divert(1); continue; }
      messages.push(this.buffer.subarray(delimiter + 1, total - 1).toString('utf8'));
      this.buffer = this.buffer.subarray(total);
    }
    return messages;
  }
}

exports.DBGpFramer = DBGpFramer;
