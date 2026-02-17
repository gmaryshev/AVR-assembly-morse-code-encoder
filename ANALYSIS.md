# Detailed Code Analysis — `morse_encoder.asm`

A line-by-line analysis of every section, routine, data structure, and design decision in this AVR assembly Morse code encoder for the Arduino Mega 2560 (ATmega2560).

---

## Table of Contents

1. [File Metadata](#1-file-metadata)
2. [Hardware Constants](#2-hardware-constants)
3. [Reset / Initialization (DO NOT TOUCH)](#3-reset--initialization)
4. [First Student Code Section — Test Path](#4-first-student-code-section--test-path)
5. [TOUCH CAREFULLY Section — Message Selection](#5-touch-carefully-section--message-selection)
6. [Main Loop (DO NOT TOUCH)](#6-main-loop)
7. [Routine: `flash_message`](#7-routine-flash_message)
8. [Routine: `morse_flash`](#8-routine-morse_flash)
9. [Helpers: `dot` and `dash`](#9-helpers-dot-and-dash)
10. [Routine: `leds_on`](#10-routine-leds_on)
11. [Routine: `leds_off`](#11-routine-leds_off)
12. [Routine: `encode_message`](#12-routine-encode_message)
13. [Routine: `alphabet_encode`](#13-routine-alphabet_encode)
14. [Delay Routines (DO NOT TOUCH)](#14-delay-routines)
15. [ITU_MORSE Lookup Table](#15-itu_morse-lookup-table)
16. [Predefined Messages](#16-predefined-messages)
17. [SRAM Data Segment](#17-sram-data-segment)
18. [Encoding Format Deep Dive](#18-encoding-format-deep-dive)
19. [Stack Frame Conventions](#19-stack-frame-conventions)
20. [Control-Flow Graph](#20-control-flow-graph)
21. [Known Bugs and Quirks](#21-known-bugs-and-quirks)
22. [Potential Improvements](#22-potential-improvements)

---

## 1. File Metadata

```
; a2_morse.asm
; Student name: Gavriil Maryshev
; Date of completed work: June 27, 2022
```

- This was Assignment 2 for **CSC 230** (Computer Architecture and Assembly Language).
- The filename in the header (`a2_morse.asm`) differs from the repository filename (`morse_encoder.asm`); it was likely renamed for the repository.

---

## 2. Hardware Constants

```asm
.include "m2560def.inc"

.cseg
.equ S_DDRB  = 0x24
.equ S_PORTB = 0x25
.equ S_DDRL  = 0x10A
.equ S_PORTL = 0x10B
```

| Symbol | Address | Purpose |
|--------|---------|---------|
| `S_DDRB` | `0x24` | Data Direction Register for Port B — sets pin direction (input/output) |
| `S_PORTB` | `0x25` | Port B output register — controls LEDs connected to PB1 and PB3 |
| `S_DDRL` | `0x10A` | Data Direction Register for Port L |
| `S_PORTL` | `0x10B` | Port L output register — controls LEDs connected to PL1, PL3, PL5, PL7 |

All addresses above `0x5F` (i.e., `S_DDRL` and `S_PORTL`) must be accessed with `sts`/`lds` (memory-mapped I/O). `S_DDRB` and `S_PORTB` could theoretically use `out`/`in` but are also accessed with `sts`/`lds` here for consistency.

The `.cseg` directive places everything that follows in the **code segment** (flash/program memory).

---

## 3. Reset / Initialization

**Lines 19–43** (`.org 0` — executes on power-up/reset)

### 3a. Copy test `sos` encoding into SRAM

```asm
ldi ZH, high(TESTBUFFER)
ldi ZL, low(TESTBUFFER)
ldi r16, 0x30      ; encoded 's' (3 dots → length 3, bits 000)
st Z+, r16
ldi r16, 0x37      ; encoded 'o' (3 dashes → length 3, bits 111)
st Z+, r16
ldi r16, 0x30      ; encoded 's'
st Z+, r16
clr r16             ; null terminator 0x00
st Z, r16
```

This writes four bytes to `TESTBUFFER` in SRAM: `0x30 0x37 0x30 0x00`, which represents the encoded form of `sos`. This is used later for testing `flash_message` before the full encoder is ready.

**Verification of encoding:**
- `s` = `...` = 3 symbols, all dots → high nibble = `0x3`, low nibble = `0x0` → `0x30` ✓
- `o` = `---` = 3 symbols, all dashes → high nibble = `0x3`, low nibble = `0x7` → `0x37` ✓

### 3b. Stack pointer initialization

```asm
ldi r17, high(0x21ff)
ldi r16, low(0x21ff)
out SPH, r17
out SPL, r16
```

Sets the stack pointer to `0x21FF`, the top of internal SRAM on the ATmega2560 (8 KB SRAM, addresses `0x0200`–`0x21FF`). The stack grows downward.

### 3c. LED port configuration

```asm
ldi r17, 0xff
sts S_DDRB, r17
sts S_DDRL, r17
```

Writing `0xFF` to the DDR registers sets **all 8 pins** of both Port B and Port L as outputs. Only specific pins are actually connected to LEDs in the lab hardware, but setting all to output is harmless.

---

## 4. First Student Code Section — Test Path

**Lines 56–67**

```asm
ldi r17, high(TESTBUFFER)
ldi r16, low(TESTBUFFER)
push r17
push r16
rcall flash_message
pop r16
pop r17
rjmp stop
```

**What this does:**
1. Pushes the 16-bit SRAM address of `TESTBUFFER` onto the stack (high byte first, then low byte).
2. Calls `flash_message`, which reads the address from the stack and flashes the encoded `sos`.
3. Pops the two argument bytes to clean up the stack (caller-cleanup convention).
4. **Jumps to `stop`** — an infinite loop — which means **all code after this point is never reached**.

**Critical observation:** The `rjmp stop` on line 67 causes the program to halt after the test flash. The "TOUCH CAREFULLY" section (encode + flash from a `MESSAGE##` label) and the main three-repetition loop are **dead code** in the current source. To run the full encoder, this `rjmp stop` must be removed or commented out.

---

## 5. TOUCH CAREFULLY Section — Message Selection

**Lines 78–95**

```asm
ldi r17, high(MESSAGE10 << 1)
ldi r16, low(MESSAGE10 << 1)
push r17
push r16
ldi r17, high(BUFFER01)
ldi r16, low(BUFFER01)
push r17
push r16
rcall encode_message
pop r16
pop r16
pop r16
pop r16
```

**Purpose:** Encode a plaintext message into a byte buffer.

**Parameter passing (via stack):**

| Push order | Value | Meaning |
|------------|-------|---------|
| 1st (deepest) | `high(MESSAGE10 << 1)` | High byte of source address in program memory |
| 2nd | `low(MESSAGE10 << 1)` | Low byte of source address |
| 3rd | `high(BUFFER01)` | High byte of destination SRAM address |
| 4th (top) | `low(BUFFER01)` | Low byte of destination SRAM address |

The `<< 1` (left-shift by 1) is required because `lpm` uses **byte addresses** while `.db` labels are **word addresses** in AVR program memory. Multiplying the word address by 2 gives the byte address.

Note: `BUFFER01` is an SRAM label and does not need shifting.

After the call, four `pop r16` instructions clean up the stack. The popped values are discarded (all into `r16`).

**Currently selected message:** `MESSAGE10` — `"what god hath wrought"` (the first telegraph message, 1844).

To select a different message, change `MESSAGE10` to any of `MESSAGE01` through `MESSAGE09`.

---

## 6. Main Loop

**Lines 103–115**

```asm
ldi r18, 3
main_loop:
    ldi r17, high(BUFFER01)
    ldi r16, low(BUFFER01)
    push r17
    push r16
    rcall flash_message
    dec r18
    tst r18
    brne main_loop

stop:
    rjmp stop
```

Calls `flash_message` on `BUFFER01` three times (`r18` counts down from 3 to 0), then enters an infinite loop at `stop`. Note that `flash_message` does **not** clean up the stack — the caller never pops the two pushed bytes. This means the stack grows by 2 bytes per iteration (6 bytes total leaked). This is inconsequential because `stop` halts the program immediately after.

---

## 7. Routine: `flash_message`

**Lines 124–149**

### Signature

- **Input:** 16-bit SRAM address of a null-terminated encoded buffer, passed via the stack (high byte pushed first).
- **Output:** Flashes the LED pattern for each byte in the buffer.
- **Clobbers:** None (all used registers are saved/restored).

### Stack Frame

```
(low address / top of stack)
  SP+1  → saved r23
  SP+2  → saved YH
  SP+3  → saved YL
  SP+4  → saved ZH
  SP+5  → saved ZL
  SP+6  → return address byte 2 (PCH — ATmega2560 has 3-byte PC)
  SP+7  → return address byte 1
  SP+8  → return address byte 0 (PCL)
  SP+9  → arg low byte (buffer address low)
  SP+10 → arg high byte (buffer address high)
```

After pushing 5 registers, the routine reads `Y = SP`, then accesses `Y+10` and `Y+9` to load the buffer address into `Z`.

**Wait — the ATmega2560 uses 3-byte return addresses** (`rcall`/`call` push 3 bytes for the 22-bit PC). So with 5 pushed registers + 3-byte return address = 8 bytes between SP and the arguments. Arguments are at `Y+9` (low) and `Y+10` (high). This is correct.

### Loop

```asm
loopto0x00:
    ld r23, Z+          ; load next encoded byte from SRAM
    mov r16, r23        ; copy to r16 (morse_flash reads r16)
    call morse_flash    ; flash this byte
    cpi r23, 0x00       ; was it the null terminator?
    brne loopto0x00     ; if not, continue
```

**Quirk:** The null byte (`0x00`) is passed to `morse_flash` before the loop checks for termination. Inside `morse_flash`, `0x00` triggers an immediate return via `breq quit`, so this is harmless — but it does execute an unnecessary `call`/`ret` for the terminator byte.

---

## 8. Routine: `morse_flash`

**Lines 151–196**

### Signature

- **Input:** Encoded Morse byte in `r16`. The byte is also expected in `r0` (set by `alphabet_encode` during the encode path, or by the test path — see quirk below).
- **Output:** Flashes the LED pattern (dots and dashes with timing).

### Logic

```asm
push r16, r25, r27, r19, r28   ; save registers
cpi r16, 0x00
breq quit                       ; skip null bytes

mov r16, r0                     ; *** OVERWRITE r16 with r0 ***
```

**Critical detail:** `r16` is immediately overwritten by `r0`. This means the byte passed in `r16` is only used for the null check. The actual decoding operates on whatever is in `r0`. This works correctly when `flash_message` is called after `encode_message`, because `alphabet_encode` places its result in `r0`, and `encode_message` also stores `r0` into the buffer. However, for the **test path** (TESTBUFFER), `r0` may contain stale data from `alphabet_encode` or uninitialized garbage. This is a latent bug for the test path (see [Known Bugs](#21-known-bugs-and-quirks)).

### Nibble extraction

```asm
ldi r25, 0x04
looptogetnibble:
    lsr r16         ; shift r16 right, bit 0 goes to Carry
    ror r27         ; rotate Carry into r27's bit 7
    dec r25
    cpi r25, 0x00
    brne looptogetnibble

swap r27            ; swap nibbles of r27
```

This shifts the low 4 bits of `r16` (one at a time) into `r27` via Carry. After 4 iterations, the original low nibble of `r16` sits in bits 7–4 of `r27`. The `swap` moves them to bits 3–0. Result:
- `r16` now contains the original high nibble right-shifted by 4 → this is the **symbol count**.
- `r27` now contains the original low nibble → this is the **dot/dash bit pattern**.

### Symbol loop

```asm
someloop:
    mov r28, r27
    andi r28, 0b00000001    ; isolate bit 0
    cpi r28, 0x01
    breq dash               ; bit = 1 → dash
    cont:
    cpi r28, 0x00
    breq dot                ; bit = 0 → dot
    cont2:
    lsr r27                 ; shift to next bit
    dec r16                 ; decrement symbol count
    cpi r16, 0x00
    brne someloop
```

For each symbol:
1. Extract the LSB of `r27`.
2. If 1, jump to `dash` (which jumps back to `cont` after flashing).
3. If 0, jump to `dot` (which jumps back to `cont2` after flashing).
4. Shift `r27` right and decrement the counter.

The flow is: bit extracted → dash jumps to `cont` → falls through the `cpi r28, 0x00` / `breq dot` (but `r28` is now 1, not 0, so the branch is not taken) → reaches `cont2` → shifts and decrements. For dots: bit extracted → `cpi 0x01` not equal (it's 0) → falls to `cont` → `cpi 0x00` is equal → jumps to `dot` → jumps back to `cont2` → shifts and decrements.

This works but is convoluted. A simpler approach would be a single `brne`/`breq` after the bit test.

---

## 9. Helpers: `dot` and `dash`

### `dot` (Lines 198–206)

```asm
dot:
    push r16
    ldi r16, 0x01       ; 1 LED
    call leds_on
    call delay_short     ; ~0.2 s on
    call leds_off
    call delay_long      ; ~0.6 s gap
    pop r16
    rjmp cont2
```

Lights **1 LED** for a short duration, then turns off and waits a long gap.

### `dash` (Lines 208–217)

```asm
dash:
    push r16
    ldi r16, 0x06       ; 6 LEDs
    call leds_on
    call delay_long      ; ~0.6 s on
    call leds_off
    call delay_long      ; ~0.6 s gap
    pop r16
    rjmp cont
```

Lights **all 6 LEDs** for a long duration, then turns off and waits a long gap.

### Timing Summary

| Element | LED on duration | Gap after |
|---------|----------------|-----------|
| Dot | `delay_short` ≈ 0.2 s | `delay_long` ≈ 0.6 s |
| Dash | `delay_long` ≈ 0.6 s | `delay_long` ≈ 0.6 s |

Standard Morse timing uses a 1:3 dot-to-dash ratio. With `delay_short` = 1 unit and `delay_long` = 3 units, this is correct.

---

## 10. Routine: `leds_on`

**Lines 220–290**

### Signature

- **Input:** `r16` = number of LEDs to light (0–6).
- **Output:** Writes appropriate bit patterns to `PORTB` and `PORTL`.

### LED-to-Port Mapping

The Arduino Mega 2560 lab board maps LEDs to specific port pins. Based on the bit patterns:

| LEDs | `PORTB` (`r21`) | `PORTL` (`r20`) | PORTB bits set | PORTL bits set |
|------|-----------------|-----------------|----------------|----------------|
| 0 | `0x00` | `0x00` | (none) | (none) |
| 1 | `0x02` | `0x00` | PB1 | (none) |
| 2 | `0x0A` | `0x00` | PB1, PB3 | (none) |
| 3 | `0x0A` | `0x02` | PB1, PB3 | PL1 |
| 4 | `0x0A` | `0x0A` | PB1, PB3 | PL1, PL3 |
| 5 | `0x0A` | `0x3E` | PB1, PB3 | PL1, PL2, PL3, PL4, PL5 |
| 6 | `0x0A` | `0xAA` | PB1, PB3 | PL1, PL3, PL5, PL7 |

**Observation:** The 5-LED and 6-LED cases set different PORTL bits. The 5-LED pattern (`0x3E` = bits 1–5) uses contiguous pins, while the 6-LED pattern (`0xAA` = bits 1,3,5,7) uses alternate pins. This suggests the physical LED wiring uses alternate pins on PORTL.

**Note:** In the `oneleds` and `twoleds` cases, `clr r21` is executed after `sts S_PORTB, r21`; this has no effect since `r21` is about to be popped. This is dead code — likely a debugging leftover.

### Implementation Approach

Uses a compare-and-branch chain (essentially a switch/case). If `r16` doesn't match any value 0–6, execution falls through all `cpi`/`breq` instructions and reaches the `zeroleds` block. Since `r16` is only ever set to `0x01` (dot) or `0x06` (dash) in this program, this is fine, but there is no explicit error handling for out-of-range values.

---

## 11. Routine: `leds_off`

**Lines 292–296**

```asm
leds_off:
    ldi r20, 0x00
    sts S_PORTL, r20
    sts S_PORTB, R20
    ret
```

Clears both ports to turn all LEDs off.

**Quirk:** This routine does **not** save/restore `r20`. If the caller had a value in `r20`, it would be destroyed. In the current usage (called from `dot`/`dash`), `r20` is not live at the call site so this is safe, but it violates the general convention used by other routines in this file.

---

## 12. Routine: `encode_message`

**Lines 299–341**

### Signature

- **Input (via stack):**
  - Program-memory byte address of the source message (high byte deeper, low byte shallower — pushed first).
  - SRAM address of the destination buffer (high byte deeper, low byte shallower — pushed second).
- **Output:** Fills the destination buffer with encoded Morse bytes.

### Stack Frame

After pushing 7 registers (ZL, ZH, YL, YH, r16, r17, r18) and the 3-byte return address:

```
SP+1  → saved r18
SP+2  → saved r17
SP+3  → saved r16
SP+4  → saved YH
SP+5  → saved YL
SP+6  → saved ZH
SP+7  → saved ZL
SP+8  → return address byte 2
SP+9  → return address byte 1
SP+10 → return address byte 0
SP+11 → dest low byte (BUFFER01 low)
SP+12 → dest high byte (BUFFER01 high)
SP+13 → source low byte (MESSAGE low)
SP+14 → source high byte (MESSAGE high)
```

- `Y+14` / `Y+13` → source (program memory, byte address).
- `Y+12` / `Y+11` → destination (SRAM).

### Loop

```asm
looptopush:
    lpm r16, Z+         ; load next ASCII character
    cpi r16, 0x00
    breq end_encodemsg  ; stop at null terminator
    push ZH
    push ZL
    push r16            ; push the character for alphabet_encode
    call alphabet_encode
    pop r16
    pop ZL
    pop ZH
    st x+, r0           ; store encoded byte to destination
    clz                  ; clear Zero flag
    cpi r16, 0x00        ; *** always false — r16 was just popped ***
    brne looptopush
```

**Observations:**
1. `Z` is saved/restored around `alphabet_encode` because that routine clobbers `Z` internally.
2. The character is pushed onto the stack for `alphabet_encode` (which reads it at a known stack offset).
3. `alphabet_encode` returns the encoded byte in `r0`.
4. The `clz` + `cpi r16, 0x00` + `brne` after the pop is **redundant** — `r16` was just popped and still holds the original character (which was already checked as non-zero before the call). The `clz` clears the Zero flag, and `cpi r16, 0x00` will set it only if `r16` is zero, which it won't be (we only reach this code if the character was non-zero). This check always succeeds, so the loop always continues. It's functionally correct but unnecessary.

### Missing null terminator

The lines:
```asm
//ldi r16, 0x00
//st x, r16
```
are commented out. This means `encode_message` does **not** write a null terminator at the end of the destination buffer. The program relies on `BUFFER01` being in the `.dseg` uninitialized area, which is zeroed on reset. For a single encode cycle this works, but re-encoding a shorter message over a longer one would leave stale bytes. This is a **latent bug** if the program were extended to encode multiple messages.

### Space handling

There is **no special handling for space characters** (`0x20`). When `alphabet_encode` encounters a space, it will not find it in the `ITU_MORSE` table (which only contains `a`–`z`). The `r18` counter (initialized to `0xD0 = 208`) will count down to 0 without a match, and the function will return whatever was accumulated in `r19`/`r20` — likely garbage. Spaces in messages like `"what god hath wrought"` will produce an incorrect encoded byte rather than a proper word gap.

---

## 13. Routine: `alphabet_encode`

**Lines 344–432**

### Signature

- **Input:** ASCII character pushed onto the stack.
- **Output:** Encoded Morse byte in `r0`.

### Stack Frame

After pushing 10 registers (ZL, ZH, YL, YH, r23, r16, r17, r18, r19, r20) and the 3-byte return address:

```
SP+1  → saved r20
SP+2  → saved r19
SP+3  → saved r18
SP+4  → saved r17
SP+5  → saved r16
SP+6  → saved r23
SP+7  → saved YH
SP+8  → saved YL
SP+9  → saved ZH
SP+10 → saved ZL
SP+11 → return address byte 2
SP+12 → return address byte 1
SP+13 → return address byte 0
SP+14 → character argument
```

The character is loaded from `Y+14` into `r23`.

### Table walk

```asm
clr r20                         ; accumulated dash bits = 0
ldd r23, Y + 14                ; load the character argument
ldi ZL, low(ITU_MORSE << 1)   ; Z = byte address of ITU_MORSE
ldi ZH, high(ITU_MORSE << 1)

ldi r18, 0xd0                  ; iteration limit (208 bytes)

loopforchar:
    lpm r16, Z+                ; read next byte from table
    cp r16, r23                ; compare with target character
    breq getdotdash            ; found the letter!
    forcharcont:
    dec r18
    cpi r18, 0x00
    brne loopforchar
    rjmp doned                 ; not found — fall through
```

**Important:** The loop increments `Z` by 1 for every byte, meaning it walks through the table byte-by-byte (not entry-by-entry). When it matches a character, it falls into `getdotdash` which reads the subsequent dot/dash string. When the dot/dash string ends (null byte), it jumps back to `forcharcont` which continues the byte-by-byte scan. This is **correct but inefficient** — after matching a character and processing it, the loop should break out entirely, but instead it continues scanning (though `r18` will eventually exhaust).

The limit of `0xD0` (208) bytes is sufficient to scan all 27 entries × 8 bytes = 216 bytes. (It's slightly less than 216, but since the matching character triggers an early exit via the `getdotdash` → `doned` path, it works for all 26 letters.)

### Dot/dash accumulation

```asm
getdotdash:
    lpm r16, Z+
    cpi r16, 0x2e          ; '.' (dot) = 0x2E
    breq dodot
    cpi r16, 0x2d          ; '-' (dash) = 0x2D
    breq dodash
    cpi r16, 0x00          ; null terminator
    rjmp forcharcont       ; *** BUG: unconditional jump ***

dodot:
    inc r19                ; length counter += 1
    rjmp getdotdash

dodash:
    inc r19                ; length counter += 1
    lsl r20                ; shift accumulator left
    inc r20                ; set bit 0 = 1
    rjmp getdotdash
```

**Bug in null-terminator check:** The line `cpi r16, 0x00` sets the Zero flag if `r16` is zero, but the next line `rjmp forcharcont` is an **unconditional jump** — it does not check the flag. This means the code jumps back to `forcharcont` regardless of whether `r16` was zero or not. However, since the only values in the table are `'.'` (`0x2E`), `'-'` (`0x2D`), ASCII letters, and `0x00`, and letters/null won't match `.` or `-`, the code will always reach the `rjmp forcharcont` for both null bytes **and** the next entry's letter byte. The `cpi r16, 0x00` is dead code — it has no effect on control flow. The routine works correctly despite this because the continuation of the outer loop will just keep scanning past the padding zeros and into the next entry.

**Dot encoding:** `r19` is incremented (counts total symbols). `r20` is not modified (a dot contributes a 0 bit, which is the default from the left-shift).

**Dash encoding:** `r19` is incremented. `r20` is left-shifted and then incremented. This sets bit 0 to 1. For consecutive dashes, this builds the pattern correctly:
- 1 dash: `r20` = `0 << 1 + 1` = `1` = `0b01`
- 2 dashes: `r20` = `1 << 1 + 1` = `3` = `0b11`
- 3 dashes: `r20` = `3 << 1 + 1` = `7` = `0b111`

**Wait — but what about mixed sequences?** Consider `a` = `.-` (dot then dash):
1. dodot: `r19` = 1, `r20` = 0
2. dodash: `r19` = 2, `r20` = `0 << 1 + 1` = 1 = `0b01`
3. Result: `(2 << 4) | 1` = `0x21`

Let's verify: `morse_flash` extracts the low nibble as the bit pattern and reads bits from LSB. Bit 0 = 1 (dash), bit 1 = 0 (dot). But `a` is dot-first, dash-second. So bit 0 should represent the **first** symbol. If bit 0 = 1, the first flash is a dash — **this is wrong**!

Actually, let's re-examine `morse_flash`'s extraction order. It reads `r27` LSB first. The bits in `r27` after extraction represent the **first** symbol in bit 0. In `alphabet_encode`, the dot/dash string is processed left-to-right (`.` then `-` for `a`). The dot doesn't modify `r20`. The dash does `lsl r20; inc r20`. So for `.-`:
- After `.`: `r20` = 0 (binary: `0`)
- After `-`: `r20` = `0 << 1 + 1` = 1 (binary: `01`)

So bit 0 = 1 (dash) and bit 1 = 0 (dot). But `morse_flash` reads bit 0 first, so it flashes **dash then dot** — the reverse of the correct order for `a`.

**This is actually a known characteristic of the encoding.** The `lsl`/`inc` pattern in `alphabet_encode` builds the bit pattern such that the **last** symbol processed ends up in the LSB. Since `morse_flash` reads from the LSB, the last symbol is flashed first. This means the Morse code is flashed in **reverse order**.

However, let's check more carefully with `s` = `...`:
- 3 dots: `r19` = 3, `r20` = 0 → `0x30` → all zeros, so all dots regardless of order. ✓

And `o` = `---`:
- 3 dashes: `r19` = 3, `r20` = 7 → `0x37` → all ones, so all dashes regardless of order. ✓

For the test path (`sos`), the encoding is symmetric (all dots or all dashes for each letter), so the reversal is invisible.

For general messages this **would** produce reversed Morse sequences for asymmetric letters like `a` (`.–`), `b` (`–...`), `d` (`–..`), etc. However, some letters like `k` (`–.–`) are palindromic and would work correctly. The severity depends on which letters appear in the message.

**Update after further analysis:** The `dodot` case does NOT shift `r20` — it only increments `r19`. The `dodash` case does `lsl r20; inc r20`. This means dots effectively insert a 0 bit at the current position (by not shifting at all, leaving room for the next dash's shift-and-set). Let me re-trace for `a` = `.-`:

1. Start: `r19=0, r20=0`
2. `.` (dodot): `r19=1, r20=0`
3. `-` (dodash): `r19=2, r20 = (0<<1)+1 = 1 = 0b01`

For `morse_flash`, the value is `0x21`. Extraction: high nibble=2 (count), low nibble=1 (bits). `morse_flash` reads:
- Iteration 1: bit 0 of `0b01` = 1 → dash
- Iteration 2: bit 0 of `0b00` = 0 → dot

So it flashes: dash, dot. The correct Morse for `a` is dot, dash. **The order is reversed.**

For `n` = `-.`:
1. `-` → `r19=1, r20=1`
2. `.` → `r19=2, r20=1`  (unchanged since dot doesn't shift)
3. Result: `0x21` — same as `a`!

This means `a` and `n` would produce **the same encoded byte**, which is clearly wrong. This confirms there is a **fundamental encoding bug** for letters with mixed dots and dashes.

However, since the program does manage to work for the test case (`sos`) and potentially for messages containing only symmetric letters, the bug may not have been caught during testing.

### Final encoding

```asm
doned:
    swap r19        ; move length to high nibble
    add r19, r20    ; combine with dash bits
    mov r0, r19     ; return value in r0
    mov r16, r19    ; also in r16 (for morse_flash to read via r0)
```

**Note:** `r19` is never initialized (cleared) at the start of `alphabet_encode`. It retains whatever value it had from the previous call. Similarly, `r20` is cleared with `clr r20` at the start, but `r19` is not. This means `r19` **accumulates across calls** — another bug if the register happened to be in a pushed/popped register that retains a stale value. Actually, `r19` IS pushed at entry and popped at exit, so it retains the caller's value across calls. But within a single call, `r19` is never cleared. On the first call, `r19` will hold whatever was pushed — which could be anything. **This is a bug.**

*Correction:* Let's check if `r19` happens to be zero at the first call. Since the reset code doesn't initialize all registers, `r19` defaults to `0x00` on power-up (AVR registers are cleared on reset). So the first call would work. On subsequent calls, `r19` is restored from the stack (to the value it had before the first call, which was 0). So `r19` effectively starts at 0 for each call. **This is safe** as long as `r19` was 0 before the first call to `alphabet_encode`, which it is after reset. The push/pop saves and restores the pre-call value (0), so each call starts fresh. The analysis was initially alarming but is actually correct.

---

## 14. Delay Routines

**Lines 440–478**

### `delay_long`

```asm
delay_long:
    rcall delay
    rcall delay
    rcall delay
    ret
```

Calls `delay` three times → 3 × ~0.2 s ≈ **0.6 s**.

### `delay_short`

```asm
delay_short:
    rcall delay
    ret
```

Calls `delay` once → ~**0.2 s**.

### `delay`

```asm
delay:
    rcall delay_busywait
    ret
```

Simple wrapper (allows future modification without changing callers).

### `delay_busywait`

```asm
delay_busywait:
    push r16, r17, r18

    ldi r16, 0x08           ; outer loop: 8 → 1 (7 iterations)
delay_busywait_loop1:
    dec r16
    breq delay_busywait_exit

    ldi r17, 0xff           ; middle loop: 255 → 1 (255 iterations)
delay_busywait_loop2:
    dec r17
    breq delay_busywait_loop1

    ldi r18, 0xff           ; inner loop: 255 → 1 (255 iterations)
delay_busywait_loop3:
    dec r18
    breq delay_busywait_loop2
    rjmp delay_busywait_loop3

delay_busywait_exit:
    pop r18, r17, r16
    ret
```

**Cycle count estimate:** The innermost loop (`rjmp` + `dec` + `breq`) takes ~3 cycles per iteration. Total iterations: 7 × 255 × 255 = 455,175. At 3 cycles each ≈ 1,365,525 cycles. At 16 MHz (typical Arduino Mega clock), that's ~85 ms per `delay` call. The comment says "about 1/5th of a second" (200 ms), which suggests a slower clock or that the overhead of the outer/middle loops adds up. The exact timing depends on the actual clock frequency.

---

## 15. ITU_MORSE Lookup Table

**Lines 482–509, placed at `.org 0x1000`**

```asm
.org 0x1000

ITU_MORSE: .db "a", ".-", 0, 0, 0, 0, 0
    .db "b", "-...", 0, 0, 0
    .db "c", "-.-.", 0, 0, 0
    ...
    .db "z", "--..", 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0   ; sentinel (all zeros)
```

**Structure:** Each entry is exactly **8 bytes**:

| Byte | Content |
|------|---------|
| 0 | ASCII character (lowercase) |
| 1–5 | Dot/dash string (`'.'` = `0x2E`, `'-'` = `0x2D`), null-terminated |
| 6–7 | Zero padding to align to 8 bytes |

The table is placed at program memory address `0x1000` (word address), which is byte address `0x2000`. The `<< 1` in the code converts word to byte addresses for `lpm`.

### All 26 entries verified against ITU standard:

| Letter | Morse | Table entry | Correct? |
|--------|-------|-------------|----------|
| a | `.-` | `".-"` | ✓ |
| b | `-...` | `"-..."` | ✓ |
| c | `-.-.` | `"-.-."` | ✓ |
| d | `-..` | `"-.."` | ✓ |
| e | `.` | `"."` | ✓ |
| f | `..-.` | `"..-."` | ✓ |
| g | `--.` | `"--."` | ✓ |
| h | `....` | `"...."` | ✓ |
| i | `..` | `".."` | ✓ |
| j | `.---` | `".---"` | ✓ |
| k | `-.-` | `"-.-"` | ✓ |
| l | `.-..` | `".-.."` | ✓ |
| m | `--` | `"--"` | ✓ |
| n | `-.` | `"-."` | ✓ |
| o | `---` | `"---"` | ✓ |
| p | `.--.` | `".--."` | ✓ |
| q | `--.-` | `"--.-"` | ✓ |
| r | `.-.` | `".-."` | ✓ |
| s | `...` | `"..."` | ✓ |
| t | `-` | `"-"` | ✓ |
| u | `..-` | `"..-"` | ✓ |
| v | `...-` | `"...-"` | ✓ |
| w | `.--` | `".--"` | ✓ |
| x | `-..-` | `"-..-"` | ✓ |
| y | `-.--` | `"-.--"` | ✓ |
| z | `--..` | `"--.."` | ✓ |

All Morse sequences match the ITU standard. The table is correct.

The final entry is an all-zero sentinel (8 bytes of `0x00`) to mark the end of the table.

---

## 16. Predefined Messages

| Label | Text | Length | Padding |
|-------|------|--------|---------|
| `MESSAGE01` | `"a a a"` | 6 bytes (5 chars + null) | none |
| `MESSAGE02` | `"sos"` | 4 bytes | none |
| `MESSAGE03` | `"a box"` | 6 bytes | none |
| `MESSAGE04` | `"dairy queen"` | 12 bytes | none |
| `MESSAGE05` | `"the shape of water"` | 20 bytes | 1 extra `0x00` (even alignment) |
| `MESSAGE06` | `"top gun maverick"` | 18 bytes | 1 extra `0x00` (even alignment) |
| `MESSAGE07` | `"obi wan kenobi"` | 16 bytes | 1 extra `0x00` (even alignment) |
| `MESSAGE08` | `"oh canada our own and native land"` | 34 bytes | none |
| `MESSAGE09` | `"is that your final answer"` | 26 bytes | none |
| `MESSAGE10` | `"what god hath wrought"` | 22 bytes | none |

Messages with odd byte counts are padded with an extra `0x00` because AVR program memory is word-addressed (2 bytes per word); `.db` directives must produce an even number of bytes.

`MESSAGE10` is historically significant — "What hath God wrought" was the first message sent by telegraph using Morse code, transmitted by Samuel Morse on May 24, 1844, from Washington, D.C. to Baltimore. (The capitalization in the code is all lowercase per the encoder's requirement.)

---

## 17. SRAM Data Segment

```asm
.dseg
.org 0x200

BUFFER01:    .byte 128
BUFFER02:    .byte 128
TESTBUFFER:  .byte 4
```

| Label | Address | Size | Purpose |
|-------|---------|------|---------|
| `BUFFER01` | `0x200` | 128 bytes | Primary encoded message buffer |
| `BUFFER02` | `0x280` | 128 bytes | Secondary buffer (unused in current code) |
| `TESTBUFFER` | `0x300` | 4 bytes | Hard-coded `sos` test data |

The SRAM origin is `0x200`, which is the start of general-purpose SRAM on the ATmega2560 (below `0x200` are the register file and I/O registers).

`BUFFER02` is allocated but never referenced in the code — it's a spare buffer, possibly intended for future use or an alternative message.

---

## 18. Encoding Format Deep Dive

### Byte structure

```
Bit:  7  6  5  4  3  2  1  0
      [  length  ] [ pattern ]
      (high nibble) (low nibble)
```

- **Length** (4 bits): Number of symbols (1–4 for standard letters, max 6 for numbers which aren't implemented).
- **Pattern** (4 bits): Dot/dash sequence where 0 = dot, 1 = dash. The LSB represents the **last** symbol in the Morse sequence (due to the `lsl`/`inc` encoding in `alphabet_encode`).

### Complete encoding table (theoretical, based on `alphabet_encode` logic)

| Letter | Morse | Length | Pattern (binary) | Byte |
|--------|-------|--------|-------------------|------|
| a | `.-` | 2 | `01` | `0x21` |
| b | `-...` | 4 | `0001` | `0x41` |
| c | `-.-.` | 4 | `0101` | `0x45` |
| d | `-..` | 3 | `001` | `0x31` |
| e | `.` | 1 | `0` | `0x10` |
| f | `..-.` | 4 | `0010` | `0x42` |
| g | `--.` | 3 | `011` | `0x33` |
| h | `....` | 4 | `0000` | `0x40` |
| i | `..` | 2 | `00` | `0x20` |
| j | `.---` | 4 | `1110` | `0x4E` |
| k | `-.-` | 3 | `101` | `0x35` |
| l | `.-..` | 4 | `0010` | `0x42` |
| m | `--` | 2 | `11` | `0x23` |
| n | `-.` | 2 | `01` | `0x21` |
| o | `---` | 3 | `111` | `0x37` |
| p | `.--.` | 4 | `0110` | `0x46` |
| q | `--.-` | 4 | `1011` | `0x4B` |
| r | `.-.` | 3 | `010` | `0x32` |
| s | `...` | 3 | `000` | `0x30` |
| t | `-` | 1 | `1` | `0x11` |
| u | `..-` | 3 | `100` | `0x34` |
| v | `...-` | 4 | `1000` | `0x48` |
| w | `.--` | 3 | `110` | `0x36` |
| x | `-..-` | 4 | `1001` | `0x49` |
| y | `-.--` | 4 | `1101` | `0x4D` |
| z | `--..` | 4 | `0011` | `0x43` |

**Collision alert:** `a` and `n` both encode to `0x21`. Similarly, `f` and `l` both encode to `0x42`. This confirms the encoding bug discussed in the `alphabet_encode` section — the `lsl`/`inc` scheme does not produce unique encodings for all letters.

---

## 19. Stack Frame Conventions

The program uses a consistent calling convention:

1. **Caller pushes arguments** onto the stack (high byte first for 16-bit values).
2. **Callee saves registers** by pushing them.
3. **Callee reads `SP` into `Y`** and uses `ldd Y+offset` to access arguments.
4. **Return values** are placed in `r0` (for `alphabet_encode`) or acted upon directly (for `flash_message`/`morse_flash`).
5. **Caller cleans up** by popping the arguments after the call.

The ATmega2560 has a **3-byte program counter** (22-bit PC for >64 KB flash), so `rcall`/`call` push 3 bytes onto the stack. All stack frame offsets account for this.

---

## 20. Control-Flow Graph

```
RESET
  │
  ├── Copy sos test data into TESTBUFFER
  ├── Init stack pointer (0x21FF)
  ├── Init LED DDRs
  │
  ├── [Student Code 1]
  │     ├── Push TESTBUFFER address
  │     ├── Call flash_message ──► flash sos on LEDs
  │     ├── Pop arguments
  │     └── rjmp stop ◄── HALTS HERE (dead code follows)
  │
  ├── [Touch Carefully]  (DEAD CODE in current source)
  │     ├── Push MESSAGE10 address
  │     ├── Push BUFFER01 address
  │     ├── Call encode_message
  │     │     └── For each char: call alphabet_encode
  │     └── Pop arguments
  │
  ├── [Main Loop]  (DEAD CODE in current source)
  │     ├── r18 = 3
  │     ├── Loop:
  │     │     ├── Push BUFFER01 address
  │     │     ├── Call flash_message
  │     │     │     └── For each byte: call morse_flash
  │     │     │           ├── dot → leds_on(1), delay_short, leds_off, delay_long
  │     │     │           └── dash → leds_on(6), delay_long, leds_off, delay_long
  │     │     └── dec r18
  │     └── Until r18 == 0
  │
  └── stop: rjmp stop (infinite loop)
```

---

## 21. Known Bugs and Quirks

### Bug 1: `morse_flash` reads from `r0` instead of `r16`

**Location:** `morse_flash`, line `mov r16, r0`

The routine immediately overwrites `r16` (the passed argument) with `r0`. This means the actual value decoded is whatever happens to be in `r0`, not the byte loaded from the buffer. This works in the encode path (where `alphabet_encode` sets `r0`), but fails in the test path (where `r0` is uninitialized or stale).

### Bug 2: Encoding collisions in `alphabet_encode`

**Location:** `dodot` / `dodash` logic

The dot handler only increments the length counter without shifting the accumulator. This means a dot in position N and a dot in position M produce the same bit pattern. Letters like `a` (`.-`) and `n` (`-.`) both encode to `0x21`. The encoding is not injective.

### Bug 3: Missing null terminator in `encode_message`

**Location:** Commented-out lines at end of `encode_message`

The null terminator write is commented out. The program relies on SRAM being pre-zeroed on reset.

### Bug 4: Dead `cpi r16, 0x00` in `alphabet_encode`

**Location:** After `cpi r16, 0x00` / before `rjmp forcharcont`

The `cpi` sets flags but the next instruction is an unconditional jump. The comparison has no effect on control flow.

### Bug 5: No space character handling

**Location:** `alphabet_encode` / `encode_message`

Space characters (`0x20`) are not present in the `ITU_MORSE` table. When a space is encountered, `alphabet_encode` scans the entire table without finding a match, then returns whatever accumulated garbage is in the length/pattern registers. Messages with spaces will produce incorrect encodings for the space positions.

### Bug 6: Stack leak in main loop

**Location:** `main_loop`

Each iteration pushes 2 bytes for `flash_message` but never pops them (there are no `pop` instructions between `rcall flash_message` and `dec r18`). Three iterations leak 6 bytes. This is harmless because `stop` follows immediately.

### Quirk: `leds_off` doesn't save/restore `r20`

Unlike `leds_on` and other routines, `leds_off` clobbers `r20` without saving it. Safe in current usage but inconsistent.

### Quirk: Redundant `clz` + `cpi` in `encode_message` loop

The `clz` / `cpi r16, 0x00` / `brne looptopush` sequence after `pop r16` is always true (the character was already checked as non-null). The loop condition is effectively always met.

---

## 22. Potential Improvements

1. **Fix the encoding algorithm:** Use a proper bit-building scheme that distinguishes dot/dash positions. For example, shift `r20` left before each symbol and set bit 0 only for dashes — this way dots and dashes both consume a bit position.

2. **Handle spaces:** Detect `0x20` in `encode_message` and emit a special marker byte (e.g., `0xFF`) that `morse_flash` interprets as a word gap (extended silence).

3. **Write null terminator:** Uncomment the null-terminator write in `encode_message` to make re-encoding safe.

4. **Fix `morse_flash`:** Use `r16` directly instead of `r0` so the routine works correctly regardless of calling context.

5. **Remove `rjmp stop`:** To enable the full encode-and-flash flow, remove or comment out `rjmp stop` in the first student code section.

6. **Fix main loop stack leak:** Add `pop r16` / `pop r17` after `rcall flash_message` in the main loop.

7. **Optimize `alphabet_encode` table walk:** Jump by 8 bytes per entry (using `adiw`) instead of scanning byte-by-byte, and break out of the loop after a successful match.

8. **Add digit support:** Extend `ITU_MORSE` with entries for `0`–`9` (each 5 symbols long — still fits in 8 bytes per entry).

---

*Analysis generated from the source code in `morse_encoder.asm` (576 lines, ATmega2560 target).*
