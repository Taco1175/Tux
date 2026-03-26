#!/usr/bin/env python3
"""
TUX Relay Server
================
A lightweight WebSocket relay for online co-op play.
Deploy this on any VPS (DigitalOcean, Linode, AWS, etc.) to allow
players to connect without port forwarding.

Requirements:
    pip install websockets

Run:
    python3 relay_server.py [--port 9999] [--host 0.0.0.0]

Players connect to:
    ws://YOUR_SERVER_IP:9999

Protocol:
    Client → Server:  {"action": "host"}
                      {"action": "join", "code": "ABC123"}
                      {"action": "relay", "data": "<base64 payload>"}
    Server → Client:  {"type": "hosted", "code": "ABC123"}
                      {"type": "joined", "peer_count": 2}
                      {"type": "peer_joined", "peer_id": 3}
                      {"type": "peer_left", "peer_id": 3}
                      {"type": "relay", "from": 2, "data": "<base64 payload>"}
                      {"type": "error", "message": "..."}
"""

import asyncio
import json
import random
import string
import logging
import argparse
from typing import Dict, Optional, Set

# pip install websockets
try:
    import websockets
    from websockets.server import WebSocketServerProtocol
except ImportError:
    print("ERROR: Install websockets:  pip install websockets")
    raise SystemExit(1)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("tux-relay")

# ---------------------------------------------------------------------------
# Room management
# ---------------------------------------------------------------------------

class Room:
    def __init__(self, code: str, host_ws) -> None:
        self.code = code
        self.host_ws = host_ws
        self.members: Dict[int, object] = {}   # peer_id -> websocket
        self.next_peer_id = 2                  # host is always peer 1

    def add_member(self, ws) -> int:
        peer_id = self.next_peer_id
        self.next_peer_id += 1
        self.members[peer_id] = ws
        return peer_id

    def remove_ws(self, ws) -> Optional[int]:
        for pid, member_ws in list(self.members.items()):
            if member_ws == ws:
                del self.members[pid]
                return pid
        return None

    def all_websockets(self) -> Set:
        return {self.host_ws} | set(self.members.values())

    def size(self) -> int:
        return 1 + len(self.members)


rooms: Dict[str, Room] = {}           # code -> Room
ws_to_room: Dict[object, str] = {}    # websocket -> room code
ws_to_peer: Dict[object, int] = {}    # websocket -> peer_id (1 for host)

MAX_ROOM_SIZE = 4
CODE_LENGTH   = 6


def _make_code() -> str:
    chars = string.ascii_uppercase + string.digits
    chars = chars.replace("O", "").replace("0", "").replace("I", "").replace("1", "")
    while True:
        code = "".join(random.choices(chars, k=CODE_LENGTH))
        if code not in rooms:
            return code


# ---------------------------------------------------------------------------
# Message handlers
# ---------------------------------------------------------------------------

async def _send(ws, msg: dict) -> None:
    try:
        await ws.send(json.dumps(msg))
    except Exception:
        pass


async def handle_host(ws) -> None:
    if ws in ws_to_room:
        await _send(ws, {"type": "error", "message": "Already in a room."})
        return

    code = _make_code()
    room = Room(code, ws)
    rooms[code] = room
    ws_to_room[ws] = code
    ws_to_peer[ws] = 1  # host is peer 1

    log.info("Room %s created", code)
    await _send(ws, {"type": "hosted", "code": code})


async def handle_join(ws, code: str) -> None:
    if ws in ws_to_room:
        await _send(ws, {"type": "error", "message": "Already in a room."})
        return

    code = code.upper().strip()
    room = rooms.get(code)
    if not room:
        await _send(ws, {"type": "error", "message": "Room not found."})
        return
    if room.size() >= MAX_ROOM_SIZE:
        await _send(ws, {"type": "error", "message": "Room is full."})
        return

    peer_id = room.add_member(ws)
    ws_to_room[ws] = code
    ws_to_peer[ws] = peer_id

    log.info("Peer %d joined room %s (%d/%d)", peer_id, code, room.size(), MAX_ROOM_SIZE)

    # Tell the new peer they're in
    await _send(ws, {"type": "joined", "peer_id": peer_id, "peer_count": room.size()})

    # Tell everyone else a new peer arrived
    for other_ws in room.all_websockets():
        if other_ws != ws:
            await _send(other_ws, {"type": "peer_joined", "peer_id": peer_id})


async def handle_relay(ws, data: str) -> None:
    code = ws_to_room.get(ws)
    if not code:
        return
    room = rooms.get(code)
    if not room:
        return

    sender_peer = ws_to_peer.get(ws, 0)
    msg = {"type": "relay", "from": sender_peer, "data": data}

    # Broadcast to everyone in the room except sender
    for other_ws in room.all_websockets():
        if other_ws != ws:
            await _send(other_ws, msg)


async def handle_disconnect(ws) -> None:
    code = ws_to_room.pop(ws, None)
    peer_id = ws_to_peer.pop(ws, None)

    if not code or code not in rooms:
        return

    room = rooms[code]

    if ws == room.host_ws:
        # Host left — close the room
        log.info("Host left room %s — closing", code)
        for member_ws in list(room.members.values()):
            await _send(member_ws, {"type": "error", "message": "Host disconnected. Room closed."})
            ws_to_room.pop(member_ws, None)
            ws_to_peer.pop(member_ws, None)
        del rooms[code]
    else:
        # Member left
        room.remove_ws(ws)
        log.info("Peer %d left room %s (%d remaining)", peer_id, code, room.size())
        for other_ws in room.all_websockets():
            await _send(other_ws, {"type": "peer_left", "peer_id": peer_id})
        if room.size() == 0:
            del rooms[code]


# ---------------------------------------------------------------------------
# Connection handler
# ---------------------------------------------------------------------------

async def handler(ws: "WebSocketServerProtocol") -> None:
    log.info("New connection from %s", ws.remote_address)
    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await _send(ws, {"type": "error", "message": "Invalid JSON."})
                continue

            action = msg.get("action", "")

            if action == "host":
                await handle_host(ws)
            elif action == "join":
                await handle_join(ws, msg.get("code", ""))
            elif action == "relay":
                await handle_relay(ws, msg.get("data", ""))
            elif action == "ping":
                await _send(ws, {"type": "pong"})
            else:
                await _send(ws, {"type": "error", "message": f"Unknown action: {action}"})

    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        await handle_disconnect(ws)
        log.info("Connection closed from %s", ws.remote_address)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main(host: str, port: int) -> None:
    log.info("TUX Relay Server starting on %s:%d", host, port)
    log.info("Max room size: %d players | Max rooms: unlimited", MAX_ROOM_SIZE)
    async with websockets.serve(handler, host, port):
        log.info("Ready. Waiting for connections...")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="TUX WebSocket Relay Server")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=9999, help="Port (default: 9999)")
    args = parser.parse_args()
    asyncio.run(main(args.host, args.port))
