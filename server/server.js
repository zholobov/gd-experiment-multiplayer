import { WebSocketServer } from 'ws';

const rooms = new Map();

function generateCode() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let code;
  do {
    code = '';
    for (let i = 0; i < 4; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
  } while (rooms.has(code));
  return code;
}

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

function findRoom(ws) {
  for (const [code, room] of rooms) {
    if (room.host === ws || room.guest === ws) {
      return [code, room];
    }
  }
  return [null, null];
}

function getPeer(room, ws) {
  if (room.host === ws) return room.guest;
  if (room.guest === ws) return room.host;
  return null;
}

export function createServer(port) {
  const wss = new WebSocketServer({ port });

  wss.on('connection', (ws) => {
    ws.on('message', (raw) => {
      let msg;
      try {
        msg = JSON.parse(raw);
      } catch {
        return;
      }

      if (msg.type === 'create_room') {
        const code = generateCode();
        rooms.set(code, { host: ws, guest: null });
        ws._roomCode = code;
        send(ws, { type: 'room_created', code });
      } else if (msg.type === 'join_room') {
        const room = rooms.get(msg.code);
        if (!room) {
          send(ws, { type: 'error', message: 'Room not found' });
        } else if (room.guest) {
          send(ws, { type: 'error', message: 'Room full' });
        } else {
          room.guest = ws;
          ws._roomCode = msg.code;
          send(ws, { type: 'peer_joined', your_role: 'guest' });
          send(room.host, { type: 'peer_joined', your_role: 'host' });
        }
      } else if (msg.type === 'relay') {
        const [code, room] = findRoom(ws);
        if (room) {
          const peer = getPeer(room, ws);
          if (peer) {
            send(peer, { type: 'relay', data: msg.data });
          }
        }
      }
    });

    ws.on('close', () => {
      const [code, room] = findRoom(ws);
      if (room) {
        const peer = getPeer(room, ws);
        if (peer) {
          send(peer, { type: 'peer_left' });
        }
        rooms.delete(code);
      }
    });
  });

  return wss;
}

// Run standalone when executed directly
import { fileURLToPath } from 'url';
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const PORT = process.env.PORT || 8080;
  const wss = createServer(PORT);
  console.log(`Relay server listening on ws://localhost:${PORT}`);
}
