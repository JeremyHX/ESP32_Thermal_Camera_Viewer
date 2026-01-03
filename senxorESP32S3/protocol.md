# ESP32 Thermal Camera Communication Protocol

This document describes the TCP/IP protocol used for communication between the ESP32 thermal camera and client applications.

## Connection

The ESP32 uses two separate TCP ports to prevent command responses from interfering with frame streaming:

| Port | Purpose | Description |
|------|---------|-------------|
| **3333** | Frame streaming | Thermal frames pushed automatically on connect |
| **3334** | Commands | WREG/RREG/RRSE/POLL commands and responses |

**Connection Modes:**

1. **Full streaming mode**: Connect to both ports
   - Port 3333: Receive thermal frame stream
   - Port 3334: Send commands and receive responses
   - Quadrant registers updated on every frame automatically

2. **Polling mode**: Connect to port 3334 only
   - Send POLL command to set update frequency (1-25 Hz)
   - Quadrant registers updated at specified frequency
   - No frame data transmitted (lower bandwidth)
   - Useful for headless operation or low-bandwidth scenarios

## Packet Format

All packets follow this structure:

```
[3 spaces][#][4-char hex length][4-char command][data][4-char CRC]
```

| Field | Size | Description |
|-------|------|-------------|
| Padding | 3 bytes | Three space characters (`"   "`) |
| Delimiter | 1 byte | Start character (`#`) |
| Length | 4 bytes | Hex length of (command + data + CRC) |
| Command | 4 bytes | Command identifier (e.g., `GFRA`, `WREG`, `RREG`) |
| Data | Variable | Command-specific payload |
| CRC | 4 bytes | Hex checksum or `XXXX` to skip validation |

---

## Commands

### GFRA - Thermal Frame (ESP32 → Client)

Thermal frame data pushed automatically when capturing.

**Packet Structure** (10,256 bytes total):
```
   #2808GFRA[thermal data][CRC]
```

| Field | Size | Description |
|-------|------|-------------|
| Thermal Data | 10,240 bytes | 80 × 64 pixels, 16-bit unsigned (little-endian) |

**Frame Layout** (80 × 64 pixels):

| Rows | Indices | Content |
|------|---------|---------|
| 0-1 | 0-159 | Header metadata (2 rows) |
| 2-63 | 160-5119 | Thermal image (80×62) |

**Header Fields** (first 2 rows):

| Index | Content |
|-------|---------|
| `[0]` | Frame number |
| `[1]` | VDD (supply voltage in mV) |
| `[2]` | Die temperature (mK) |
| `[5]` | Max temperature in frame (mK) |
| `[6]` | Min temperature in frame (mK) |

**Pixel Format**:
- Format: `uint16_t` raw sensor values (little-endian)
- Order: Row-major (left-to-right, top-to-bottom)
- Actual image: 80×62 pixels starting at row 2 (index 160)

---

### WREG - Write Register (Client → ESP32)

Write a value to a register.

**Request**:
```
   #000CWREG[AA][VV][CRC]
```

| Field | Size | Description |
|-------|------|-------------|
| AA | 2 bytes | Register address (hex) |
| VV | 2 bytes | Value to write (hex, 8-bit) |

**Response**:
```
   #0008WREG[CRC]
```

---

### RREG - Read Register (Client → ESP32)

Read a value from a register.

**Request**:
```
   #000ARREG[AA][CRC]
```

| Field | Size | Description |
|-------|------|-------------|
| AA | 2 bytes | Register address (hex) |

**Response** (standard 8-bit registers):
```
   #000ARREG[VV][CRC]
```

**Response** (quadrant/burner 16-bit registers 0xC0-0xD5):
```
   #000CRREG[VVVV][CRC]
```

| Field | Size | Description |
|-------|------|-------------|
| VV | 2 bytes | 8-bit register value (hex) |
| VVVV | 4 bytes | 16-bit register value (hex) |

---

### RRSE - Read Register Sequence (Client → ESP32)

Read multiple registers in a single request.

**Request**:
```
   #[len]RRSE[AA1][AA2]...[AAn]FF[CRC]
```

| Field | Size | Description |
|-------|------|-------------|
| AAn | 2 bytes each | Register addresses (hex) |
| FF | 2 bytes | Terminator |

**Response**:
```
   #[len]RRSE[AA1][VV1][AA2][VV2]...[CRC]
```

Note: Quadrant/burner registers (0xC0-0xD5) return 4-byte values, others return 2-byte values.

---

### POLL - Set Polling Frequency (Client → ESP32)

Set the frequency at which the ESP32 reads thermal frames and updates quadrant registers when operating in polling mode (port 3334 only, without port 3333 connected).

**Request**:
```
   #000APOLL[FF][CRC]
```

| Field | Size | Description |
|-------|------|-------------|
| FF | 2 bytes | Frequency in Hz (hex, 00-19) |

**Frequency Values**:
- `00` = Stop polling (default on connect)
- `01` = 1 Hz
- `19` = 25 Hz (maximum, camera limit)
- Values > 25 (0x19) are capped to 25 Hz

**Response** (when port 3333 NOT connected):
```
   #0008POLL[CRC]
```

**Response** (when port 3333 IS connected):
No response - command is rejected. Use streaming mode instead.

**Behavior**:
- Only active when connected to port 3334 but NOT port 3333
- When port 3333 is connected, frame streaming mode is used and POLL is ignored
- Poll frequency resets to 0 on port 3334 disconnect
- Quadrant and burner registers (0xC2-0xD5) are updated silently at the specified rate

---

## Register Map

### Control Registers

| Address | Name | R/W | Description |
|---------|------|-----|-------------|
| `0xB0` | Control | R/W | System control (3 = reinitialize) |
| `0xB1` | Capture | R/W | Capture mode (0x00=stop, 0x03=start) |
| `0xB2` | Version | R | Firmware version (high byte) |
| `0xB3` | Version | R | Firmware version (low byte) |

### Quadrant Analysis Registers

| Address | Name | R/W | Default | Description |
|---------|------|-----|---------|-------------|
| `0xC0` | Xsplit | R/W | 40 | X split point (0-80), persisted to NVS |
| `0xC1` | Ysplit | R/W | 31 | Y split point (0-62), persisted to NVS |
| `0xC2` | Amax | R | - | Maximum value in quadrant A (16-bit) |
| `0xC3` | Acenter | R | - | Center pixel value in quadrant A (16-bit) |
| `0xC4` | Bmax | R | - | Maximum value in quadrant B (16-bit) |
| `0xC5` | Bcenter | R | - | Center pixel value in quadrant B (16-bit) |
| `0xC6` | Cmax | R | - | Maximum value in quadrant C (16-bit) |
| `0xC7` | Ccenter | R | - | Center pixel value in quadrant C (16-bit) |
| `0xC8` | Dmax | R | - | Maximum value in quadrant D (16-bit) |
| `0xC9` | Dcenter | R | - | Center pixel value in quadrant D (16-bit) |

### Burner Registers

Each quadrant has a configurable "burner" point with X/Y coordinates and a temperature reading.

| Address | Name | R/W | Default | Description |
|---------|------|-----|---------|-------------|
| `0xCA` | Aburnerx | R/W | 20 | Burner X coordinate in quadrant A, persisted to NVS |
| `0xCB` | Aburnery | R/W | 15 | Burner Y coordinate in quadrant A, persisted to NVS |
| `0xCC` | Aburnert | R | - | Temperature at burner point in quadrant A (16-bit) |
| `0xCD` | Bburnerx | R/W | 60 | Burner X coordinate in quadrant B, persisted to NVS |
| `0xCE` | Bburnery | R/W | 15 | Burner Y coordinate in quadrant B, persisted to NVS |
| `0xCF` | Bburnert | R | - | Temperature at burner point in quadrant B (16-bit) |
| `0xD0` | Cburnerx | R/W | 20 | Burner X coordinate in quadrant C, persisted to NVS |
| `0xD1` | Cburnery | R/W | 46 | Burner Y coordinate in quadrant C, persisted to NVS |
| `0xD2` | Cburnert | R | - | Temperature at burner point in quadrant C (16-bit) |
| `0xD3` | Dburnerx | R/W | 60 | Burner X coordinate in quadrant D, persisted to NVS |
| `0xD4` | Dburnery | R/W | 46 | Burner Y coordinate in quadrant D, persisted to NVS |
| `0xD5` | Dburnert | R | - | Temperature at burner point in quadrant D (16-bit) |

**Burner Coordinate Rules**:
- Coordinates are absolute image coordinates (X: 0-79, Y: 0-61)
- Coordinates are clamped to stay within the quadrant bounds:
  - **A**: X ∈ [0, Xsplit-1], Y ∈ [0, Ysplit-1]
  - **B**: X ∈ [Xsplit, 79], Y ∈ [0, Ysplit-1]
  - **C**: X ∈ [0, Xsplit-1], Y ∈ [Ysplit, 61]
  - **D**: X ∈ [Xsplit, 79], Y ∈ [Ysplit, 61]
- Default values are the center of each quadrant (with Xsplit=40, Ysplit=31)

### Device ID Registers

The device can be uniquely identified by its Bluetooth MAC address, available via registers `0xE0-0xE5`. This is the same MAC address used in BLE advertising, allowing clients to confirm they're communicating with the same device over both WiFi and Bluetooth.

| Address | Name | R/W | Description |
|---------|------|-----|-------------|
| `0xE0` | DevID0 | R | BT MAC byte 0 (MSB) |
| `0xE1` | DevID1 | R | BT MAC byte 1 |
| `0xE2` | DevID2 | R | BT MAC byte 2 |
| `0xE3` | DevID3 | R | BT MAC byte 3 |
| `0xE4` | DevID4 | R | BT MAC byte 4 |
| `0xE5` | DevID5 | R | BT MAC byte 5 (LSB) |

**Example**: If the BT MAC is `D8:3B:DA:4A:2D:B6`, the registers return:
- `0xE0` = `0xD8`, `0xE1` = `0x3B`, `0xE2` = `0xDA`, `0xE3` = `0x4A`, `0xE4` = `0x2D`, `0xE5` = `0xB6`

**BLE Correlation**: The BLE advertising serial number uses the last 4 bytes (registers `0xE2-0xE5`) as a 32-bit value in little-endian format.

---

## Quadrant Layout

The quadrant analysis operates on the **image area only** (80×62 pixels), excluding the 2 header rows.

```
     0          Xsplit           80
   0 ┌────────────┬────────────────┐
     │            │                │
     │     A      │       B        │
     │  (top-left)│   (top-right)  │
     │            │                │
Ysplit├────────────┼────────────────┤
     │            │                │
     │     C      │       D        │
     │(bottom-left)│(bottom-right) │
     │            │                │
  62 └────────────┴────────────────┘
```

**Quadrant Definitions** (on 80×62 image):
- **A**: x ∈ [0, Xsplit), y ∈ [0, Ysplit)
- **B**: x ∈ [Xsplit, 80), y ∈ [0, Ysplit)
- **C**: x ∈ [0, Xsplit), y ∈ [Ysplit, 62)
- **D**: x ∈ [Xsplit, 80), y ∈ [Ysplit, 62)

**Register Values**:
- `*max`: Highest pixel value in the quadrant
- `*center`: Pixel value at the geometric center of the quadrant

**Center Pixel Coordinates** (relative to image, not frame):
- Acenter: `(Xsplit/2, Ysplit/2)`
- Bcenter: `(Xsplit + (80-Xsplit)/2, Ysplit/2)`
- Ccenter: `(Xsplit/2, Ysplit + (62-Ysplit)/2)`
- Dcenter: `(Xsplit + (80-Xsplit)/2, Ysplit + (62-Ysplit)/2)`

---

## Connection Flow

```
1. Client connects to ESP32:3333 (frame port)
2. ESP32 writes 0x03 to register 0xB1 (starts capture)
3. ESP32 pushes thermal frames continuously (10,240 bytes each)
4. Client connects to ESP32:3334 (command port)
5. Client sends WREG/RREG/RRSE commands on port 3334
6. ESP32 responds on port 3334 (no interference with frames)
7. On frame port disconnect, capture stops (0x00 written to 0xB1)
```

---

## Example Usage

### Read Quadrant Max Values

**Request**: Read all 4 max values using RRSE
```
   #0014RRSEC2C4C6C8FF[CRC]
```

**Response**:
```
   #0020RRSEC2[Amax]C4[Bmax]C6[Cmax]C8[Dmax][CRC]
```

### Set Split Point

**Request**: Set Xsplit to 20
```
   #000CWREGC014[CRC]
```

**Response**:
```
   #0008WREG[CRC]
```

### Read Current Split Values

**Request**: Read Xsplit
```
   #000ARREGC0[CRC]
```

**Response**:
```
   #000CRREGC0[Xsplit as 4 hex digits][CRC]
```

### Enable Polling at 5 Hz

**Request**: Set poll frequency to 5 Hz (only on port 3334, without 3333 connected)
```
   #000APOLL05[CRC]
```

**Response**:
```
   #0008POLL[CRC]
```

### Stop Polling

**Request**: Stop polling
```
   #000APOLL00[CRC]
```

**Response**:
```
   #0008POLL[CRC]
```

---

## CRC Calculation

The CRC is a simple checksum of all bytes from the length field to the end of data (excluding the CRC itself).

To skip CRC validation, use `XXXX` as the CRC value.

---

## Notes

- All hex values are uppercase ASCII (e.g., `0A` not `0a`)
- Quadrant and burner values are calculated on every frame automatically
- Xsplit, Ysplit, and burner coordinates persist across reboots (stored in NVS)
- The 16-bit register values are transmitted as 4 hex characters (big-endian ASCII representation)
