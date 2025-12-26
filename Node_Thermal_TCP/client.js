
const net = require("net");
const WebSocket = require("ws");
const express = require("express");
const http = require("http");
const path = require("path");

const FRAME_WIDTH = 80;
const FRAME_HEIGHT = 62;
const RAW_FRAME_SIZE = FRAME_WIDTH * FRAME_HEIGHT * 2; // 9920 bytes
const STRIP_HEAD = 160;
const STRIP_TAIL = 160;
const TCP_FRAME_SIZE = RAW_FRAME_SIZE + STRIP_HEAD + STRIP_TAIL; // 10240

let receiveBuffer = Buffer.alloc(0);
let client = null;
let reconnectTimeout = null;
let quadrantPollInterval = null;

const ESP32_HOST = "192.168.4.213"; // your ESP32 IP
const ESP32_PORT = 3333;

// Quadrant state
let quadrantConfig = {
  xSplit: 40,
  ySplit: 31,
  aMax: 0, aCenter: 0,
  bMax: 0, bCenter: 0,
  cMax: 0, cCenter: 0,
  dMax: 0, dCenter: 0
};

// Pending register read callbacks
const pendingReads = new Map();

// ============ Protocol Helpers ============

function buildPacket(command, data = "") {
  const payload = command + data;
  const length = (payload.length + 4).toString(16).toUpperCase().padStart(4, "0");
  return `   #${length}${payload}XXXX`;
}

function buildWREG(address, value) {
  const addr = address.toString(16).toUpperCase().padStart(2, "0");
  const val = value.toString(16).toUpperCase().padStart(2, "0");
  return buildPacket("WREG", addr + val);
}

function buildRREG(address) {
  const addr = address.toString(16).toUpperCase().padStart(2, "0");
  return buildPacket("RREG", addr);
}

function buildRRSE(addresses) {
  const data = addresses.map(a => a.toString(16).toUpperCase().padStart(2, "0")).join("") + "FF";
  return buildPacket("RRSE", data);
}

function sendToESP32(packet) {
  if (client && !client.destroyed) {
    client.write(packet);
  }
}

function writeRegister(address, value) {
  sendToESP32(buildWREG(address, value));
}

function readRegister(address, callback) {
  pendingReads.set(address, callback);
  sendToESP32(buildRREG(address));
}

function readQuadrantRegisters() {
  // Read all quadrant registers: C0-C9
  const addresses = [0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9];
  sendToESP32(buildRRSE(addresses));
}

function parseRRSEResponse(data) {
  // Parse RRSE response: pairs of [addr][value]
  // Quadrant registers (C0-C9) return 4-byte values, others return 2-byte values
  const results = {};
  let offset = 0;

  while (offset < data.length) {
    if (offset + 2 > data.length) break;
    const addrStr = data.substring(offset, offset + 2);
    const addr = parseInt(addrStr, 16);
    offset += 2;

    // Quadrant registers (0xC0-0xC9) are 16-bit, others are 8-bit
    const isQuadrantReg = addr >= 0xC0 && addr <= 0xC9;
    const valueLen = isQuadrantReg ? 4 : 2;

    if (offset + valueLen > data.length) break;
    const valueStr = data.substring(offset, offset + valueLen);
    const value = parseInt(valueStr, 16);
    offset += valueLen;

    results[addr] = value;
  }

  return results;
}

function updateQuadrantFromRRSE(results) {
  if (results[0xC0] !== undefined) quadrantConfig.xSplit = results[0xC0];
  if (results[0xC1] !== undefined) quadrantConfig.ySplit = results[0xC1];
  if (results[0xC2] !== undefined) quadrantConfig.aMax = results[0xC2];
  if (results[0xC3] !== undefined) quadrantConfig.aCenter = results[0xC3];
  if (results[0xC4] !== undefined) quadrantConfig.bMax = results[0xC4];
  if (results[0xC5] !== undefined) quadrantConfig.bCenter = results[0xC5];
  if (results[0xC6] !== undefined) quadrantConfig.cMax = results[0xC6];
  if (results[0xC7] !== undefined) quadrantConfig.cCenter = results[0xC7];
  if (results[0xC8] !== undefined) quadrantConfig.dMax = results[0xC8];
  if (results[0xC9] !== undefined) quadrantConfig.dCenter = results[0xC9];

  broadcastQuadrantConfig();
}

function broadcastQuadrantConfig() {
  const message = JSON.stringify({ type: "quadrant", data: quadrantConfig });
  for (const wsClient of wss.clients) {
    if (wsClient.readyState === WebSocket.OPEN) {
      wsClient.send(message);
    }
  }
}

// Web UI
const app = express();
app.use(express.static(path.join(__dirname, "public")));
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

function broadcastFrame(frame) {
  const message = JSON.stringify({ type: "frame" });
  for (const wsClient of wss.clients) {
    if (wsClient.readyState === WebSocket.OPEN) {
      // Send frame as binary
      wsClient.send(frame);
    }
  }
}

// ============ TCP Data Parser ============

// The ESP32 sends raw thermal frames as a continuous stream
// Protocol-wrapped responses (RRSE, RREG, WREG) are interleaved

function findPacketStart(buffer, startFrom = 0) {
  // Look for "   #" pattern
  for (let i = startFrom; i < buffer.length - 3; i++) {
    if (buffer[i] === 0x20 && buffer[i + 1] === 0x20 && buffer[i + 2] === 0x20 && buffer[i + 3] === 0x23) {
      return i;
    }
  }
  return -1;
}

function processProtocolPacket(buffer) {
  // Parse a protocol packet starting at buffer position 0
  // Returns: { consumed: bytes_consumed, command: string } or null if incomplete

  if (buffer.length < 8) return null;

  const lengthStr = buffer.slice(4, 8).toString("ascii");
  const payloadLen = parseInt(lengthStr, 16);

  if (isNaN(payloadLen) || payloadLen < 8 || payloadLen > 1000) {
    // Invalid - not a real protocol packet
    return null;
  }

  const totalPacketLen = 4 + 4 + payloadLen;
  if (buffer.length < totalPacketLen) return null;

  const command = buffer.slice(8, 12).toString("ascii");

  if (command === "RRSE") {
    const data = buffer.slice(12, 8 + payloadLen - 4).toString("ascii");
    const results = parseRRSEResponse(data);
    updateQuadrantFromRRSE(results);
  } else if (command === "RREG") {
    const data = buffer.slice(12, 8 + payloadLen - 4).toString("ascii");
    if (data.length >= 4) {
      const addr = parseInt(data.substring(0, 2), 16);
      const isQuadrantReg = addr >= 0xC0 && addr <= 0xC9;
      const valueStr = data.substring(2, isQuadrantReg ? 6 : 4);
      const value = parseInt(valueStr, 16);

      const callback = pendingReads.get(addr);
      if (callback) {
        callback(value);
        pendingReads.delete(addr);
      }
    }
  }
  // WREG acknowledgments are silently consumed

  return { consumed: totalPacketLen, command };
}

function processData() {
  // First, check for and process any protocol packets
  let protocolIdx = findPacketStart(receiveBuffer);
  while (protocolIdx !== -1 && protocolIdx < receiveBuffer.length) {
    // Process protocol packet at this position
    const packetBuffer = receiveBuffer.slice(protocolIdx);
    const result = processProtocolPacket(packetBuffer);

    if (result) {
      // Remove the protocol packet from the buffer
      const before = receiveBuffer.slice(0, protocolIdx);
      const after = receiveBuffer.slice(protocolIdx + result.consumed);
      receiveBuffer = Buffer.concat([before, after]);
      // Look for more protocol packets
      protocolIdx = findPacketStart(receiveBuffer);
    } else {
      // Incomplete packet, wait for more data
      break;
    }
  }

  // Now process raw thermal frames
  // Frames are TCP_FRAME_SIZE bytes
  while (receiveBuffer.length >= TCP_FRAME_SIZE) {
    // Check if there's a protocol packet before the next frame boundary
    const nextProtocol = findPacketStart(receiveBuffer, 0);
    if (nextProtocol !== -1 && nextProtocol < TCP_FRAME_SIZE) {
      // There's a protocol packet embedded - extract frame data before it
      // This shouldn't normally happen, but handle it gracefully
      break;
    }

    const frame = receiveBuffer.slice(STRIP_HEAD, STRIP_HEAD + RAW_FRAME_SIZE);
    receiveBuffer = receiveBuffer.slice(TCP_FRAME_SIZE);
    broadcastFrame(frame);
  }
}

function connectToESP32(retryDelay = 3000) {
  if (client) {
    client.destroy();
    client = null;
  }

  if (quadrantPollInterval) {
    clearInterval(quadrantPollInterval);
    quadrantPollInterval = null;
  }

  client = new net.Socket();

  client.connect(ESP32_PORT, ESP32_HOST, () => {
    console.log(`Connected to ESP32 at ${ESP32_HOST}:${ESP32_PORT}`);
    receiveBuffer = Buffer.alloc(0); // reset buffer

    // Read initial quadrant config after short delay
    setTimeout(() => {
      readQuadrantRegisters();
    }, 500);

    // Start periodic polling for quadrant values (every 500ms)
    quadrantPollInterval = setInterval(() => {
      readQuadrantRegisters();
    }, 500);
  });

  client.setTimeout(5000); // optional timeout

  client.on("timeout", () => {
    console.warn("TCP connection timed out");
    client.destroy(); // will trigger 'close'
  });

  client.on("data", (data) => {
    receiveBuffer = Buffer.concat([receiveBuffer, data]);
    processData();
  });

  client.on("error", (err) => {
    console.error("TCP Client Error:", err.message);
    client.destroy(); // ensure 'close' fires
  });

  client.on("close", () => {
    console.log("ESP32 TCP connection closed");
    if (quadrantPollInterval) {
      clearInterval(quadrantPollInterval);
      quadrantPollInterval = null;
    }
    if (!reconnectTimeout) {
      reconnectTimeout = setTimeout(() => {
        reconnectTimeout = null;
        console.log("Attempting to reconnect to ESP32...");
        connectToESP32();
      }, retryDelay);
    }
  });
}

// ============ WebSocket Message Handling ============

wss.on("connection", (ws) => {
  console.log("Browser client connected");

  // Send current quadrant config to new client
  ws.send(JSON.stringify({ type: "quadrant", data: quadrantConfig }));

  ws.on("message", (message) => {
    try {
      const msg = JSON.parse(message);

      switch (msg.type) {
        case "setXsplit":
          const xVal = Math.max(0, Math.min(80, parseInt(msg.value)));
          writeRegister(0xC0, xVal);
          quadrantConfig.xSplit = xVal;
          broadcastQuadrantConfig();
          break;

        case "setYsplit":
          const yVal = Math.max(0, Math.min(64, parseInt(msg.value)));
          writeRegister(0xC1, yVal);
          quadrantConfig.ySplit = yVal;
          broadcastQuadrantConfig();
          break;

        case "resetDefaults":
          writeRegister(0xC0, 40);
          writeRegister(0xC1, 31);
          quadrantConfig.xSplit = 40;
          quadrantConfig.ySplit = 31;
          broadcastQuadrantConfig();
          break;

        case "getQuadrantConfig":
          readQuadrantRegisters();
          break;
      }
    } catch (e) {
      // Ignore non-JSON messages
    }
  });

  ws.on("close", () => {
    console.log("Browser client disconnected");
  });
});

connectToESP32(); // initial connection

server.listen(8080, () => {
  console.log("🌐 WebSocket/HTTP server ready at http://localhost:8080");
});
