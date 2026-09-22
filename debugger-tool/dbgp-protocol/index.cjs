'use strict';

// DBGp lengths count UTF-8 bytes, independently of socket chunk boundaries.
class DBGpFramer {
  constructor(maxFrameBytes = 64 * 1024 * 1024) {
    this.maxFrameBytes = maxFrameBytes;
    this.reset();
  }

  reset() {
    this.buffer = Buffer.alloc(0);
    this.length = null;
  }

  push(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
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
}

exports.DBGpFramer = DBGpFramer;
