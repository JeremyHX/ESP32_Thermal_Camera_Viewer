# ESP32 Thermal Camera Communication Protocol

This document describes the TCP/IP protocol used for communication between the ESP32 thermal camera and client applications.

## Connection

- **Transport**: TCP/IP
- **Default Port**: 3333 (configurable via `CONFIG_MI_TCP_PORT`)
- **Behavior**: Server pushes thermal frames automatically when a client connects

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

**Pixel Layout**:
- Resolution: 80 (width) × 64 (height)
- Format: `uint16_t` raw sensor values
- Order: Row-major (left-to-right, top-to-bottom)

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

**Response** (quadrant 16-bit registers 0xC0-0xC9):
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

Note: Quadrant registers return 4-byte values, others return 2-byte values.

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
| `0xC1` | Ysplit | R/W | 31 | Y split point (0-64), persisted to NVS |
| `0xC2` | Amax | R | - | Maximum value in quadrant A (16-bit) |
| `0xC3` | Acenter | R | - | Center pixel value in quadrant A (16-bit) |
| `0xC4` | Bmax | R | - | Maximum value in quadrant B (16-bit) |
| `0xC5` | Bcenter | R | - | Center pixel value in quadrant B (16-bit) |
| `0xC6` | Cmax | R | - | Maximum value in quadrant C (16-bit) |
| `0xC7` | Ccenter | R | - | Center pixel value in quadrant C (16-bit) |
| `0xC8` | Dmax | R | - | Maximum value in quadrant D (16-bit) |
| `0xC9` | Dcenter | R | - | Center pixel value in quadrant D (16-bit) |

---

## Quadrant Layout

The thermal image is divided into 4 quadrants based on `Xsplit` and `Ysplit`:

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
  64 └────────────┴────────────────┘
```

**Quadrant Definitions**:
- **A**: x ∈ [0, Xsplit), y ∈ [0, Ysplit)
- **B**: x ∈ [Xsplit, 80), y ∈ [0, Ysplit)
- **C**: x ∈ [0, Xsplit), y ∈ [Ysplit, 64)
- **D**: x ∈ [Xsplit, 80), y ∈ [Ysplit, 64)

**Register Values**:
- `*max`: Highest pixel value in the quadrant
- `*center`: Pixel value at the geometric center of the quadrant

**Center Pixel Coordinates**:
- Acenter: `(Xsplit/2, Ysplit/2)`
- Bcenter: `(Xsplit + (80-Xsplit)/2, Ysplit/2)`
- Ccenter: `(Xsplit/2, Ysplit + (64-Ysplit)/2)`
- Dcenter: `(Xsplit + (80-Xsplit)/2, Ysplit + (64-Ysplit)/2)`

---

## Connection Flow

```
1. Client connects to ESP32:3333
2. ESP32 writes 0x03 to register 0xB1 (starts capture)
3. ESP32 pushes GFRA packets continuously (~10KB each)
4. Client can send WREG/RREG commands at any time
5. On disconnect, capture stops (0x00 written to 0xB1)
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

---

## CRC Calculation

The CRC is a simple checksum of all bytes from the length field to the end of data (excluding the CRC itself).

To skip CRC validation, use `XXXX` as the CRC value.

---

## Notes

- All hex values are uppercase ASCII (e.g., `0A` not `0a`)
- Quadrant values are calculated on every frame automatically
- Xsplit and Ysplit persist across reboots (stored in NVS)
- The 16-bit register values are transmitted as 4 hex characters (big-endian ASCII representation)
