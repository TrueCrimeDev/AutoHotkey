// Simulates AutoHotkey64.exe /Debug=stdio: emits init, answers commands.
// Invoked as: node fake-ahk.js /Debug=stdio <script>

function frame(xml) {
  const body = Buffer.from(xml, 'utf-8');
  return Buffer.concat([
    Buffer.from(String(body.length), 'ascii'),
    Buffer.from([0]),
    body,
    Buffer.from([0]),
  ]);
}

process.stdout.write(frame('<init appid="AutoHotkey" language="AutoHotkey" protocol_version="1"/>'));

let buf = '';
process.stdin.on('data', (chunk) => {
  buf += chunk.toString('utf-8');
  let idx;
  while ((idx = buf.indexOf('\0')) !== -1) {
    const command = buf.slice(0, idx);
    buf = buf.slice(idx + 1);
    const tidMatch = command.match(/-i (\d+)/);
    const tid = tidMatch ? tidMatch[1] : '0';
    const name = command.split(' ')[0];

    if (name === 'run') {
      // Emit one stdout stream packet, then report script end and exit.
      const b64 = Buffer.from('fake output\n', 'utf-8').toString('base64');
      process.stdout.write(frame(`<stream type="stdout" encoding="base64">${b64}</stream>`));
      process.stdout.write(frame(`<response command="run" transaction_id="${tid}" status="stopping" reason="ok"/>`));
      setTimeout(() => process.exit(0), 50);
    } else if (name === 'stop') {
      process.stdout.write(frame(`<response command="stop" transaction_id="${tid}" status="stopped" reason="ok"/>`));
      setTimeout(() => process.exit(0), 50);
    } else {
      process.stdout.write(frame(`<response command="${name}" transaction_id="${tid}" status="starting" reason="ok"/>`));
    }
  }
});
