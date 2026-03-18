import { describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
import { WebSocket, WebSocketServer } from 'ws';
import { createServer } from './server.js';

let server;
let port;

function connectClient() {
  return new Promise((resolve) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    ws.on('open', () => resolve(ws));
  });
}

function waitForMessage(ws) {
  return new Promise((resolve) => {
    ws.once('message', (data) => resolve(JSON.parse(data)));
  });
}

function send(ws, obj) {
  ws.send(JSON.stringify(obj));
}

beforeAll(() => {
  return new Promise((resolve) => {
    server = createServer(0); // port 0 = random available port
    server.on('listening', () => {
      port = server.address().port;
      resolve();
    });
  });
});

afterAll(() => {
  server.close();
});

describe('room creation', () => {
  it('should create a room and return a 4-char code', async () => {
    const ws = await connectClient();
    send(ws, { type: 'create_room' });
    const msg = await waitForMessage(ws);
    expect(msg.type).toBe('room_created');
    expect(msg.code).toMatch(/^[A-Z0-9]{4}$/);
    ws.close();
  });
});

describe('room joining', () => {
  it('should let a guest join an existing room', async () => {
    const host = await connectClient();
    send(host, { type: 'create_room' });
    const created = await waitForMessage(host);

    const guest = await connectClient();
    const hostMsgPromise = waitForMessage(host);
    send(guest, { type: 'join_room', code: created.code });

    const guestMsg = await waitForMessage(guest);
    expect(guestMsg.type).toBe('peer_joined');
    expect(guestMsg.your_role).toBe('guest');

    const hostMsg = await hostMsgPromise;
    expect(hostMsg.type).toBe('peer_joined');
    expect(hostMsg.your_role).toBe('host');

    host.close();
    guest.close();
  });

  it('should error on non-existent room', async () => {
    const ws = await connectClient();
    send(ws, { type: 'join_room', code: 'ZZZZ' });
    const msg = await waitForMessage(ws);
    expect(msg.type).toBe('error');
    expect(msg.message).toBe('Room not found');
    ws.close();
  });

  it('should error on full room', async () => {
    const host = await connectClient();
    send(host, { type: 'create_room' });
    const created = await waitForMessage(host);

    const guest1 = await connectClient();
    send(guest1, { type: 'join_room', code: created.code });
    await waitForMessage(guest1); // peer_joined

    const guest2 = await connectClient();
    send(guest2, { type: 'join_room', code: created.code });
    const msg = await waitForMessage(guest2);
    expect(msg.type).toBe('error');
    expect(msg.message).toBe('Room full');

    host.close();
    guest1.close();
    guest2.close();
  });
});

describe('relay', () => {
  it('should forward messages between peers', async () => {
    const host = await connectClient();
    send(host, { type: 'create_room' });
    const created = await waitForMessage(host);

    const guest = await connectClient();
    send(guest, { type: 'join_room', code: created.code });
    await waitForMessage(guest); // peer_joined
    await waitForMessage(host);  // peer_joined

    const guestMsgPromise = waitForMessage(guest);
    send(host, { type: 'relay', data: { type: 'game_start', board: ['','','','','','','','',''] } });
    const relayed = await guestMsgPromise;
    expect(relayed.type).toBe('relay');
    expect(relayed.data.type).toBe('game_start');

    host.close();
    guest.close();
  });
});

describe('disconnect', () => {
  it('should notify peer when other disconnects', async () => {
    const host = await connectClient();
    send(host, { type: 'create_room' });
    const created = await waitForMessage(host);

    const guest = await connectClient();
    send(guest, { type: 'join_room', code: created.code });
    await waitForMessage(guest); // peer_joined
    await waitForMessage(host);  // peer_joined

    const hostMsgPromise = waitForMessage(host);
    guest.close();
    const msg = await hostMsgPromise;
    expect(msg.type).toBe('peer_left');

    host.close();
  });
});
