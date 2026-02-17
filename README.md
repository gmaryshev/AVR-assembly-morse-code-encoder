# AVR-assembly-morse-code-encoder

AVR assembly solution for a Morse code encoder on the Arduino Mega 2560. The program converts a text message into an encoded byte sequence and flashes the on-board LEDs using short pulses for dots and long pulses for dashes.

Implement Morse code encoding/decoding routines in AVR assembly and display the result using the Arduino Mega 2560 LED bank.
- Key objectives: register/stack parameter passing, return values in registers, stack frames, and program-memory table lookup.

**Morse Encoding Format**
- A single byte represents one letter.
- High nibble: length of the dot/dash sequence (1 to 4).
- Low nibble: the dot/dash bits (0 = dot, 1 = dash), right-aligned; leading zeros are ignored.
- Special value `0xff` indicates a word space (LEDs stay off for three long delays).

**Code Overview**
All logic is in [morse_encoder.asm](morse_encoder.asm). Core routines implemented:
- `leds_on`: turns on 0 to 6 LEDs based on `r16`.
- `leds_off`: turns all LEDs off.
- `morse_flash`: decodes one encoded byte and flashes dots/dashes with timing gaps.
- `flash_message`: walks a null-terminated encoded buffer in SRAM and calls `morse_flash`.
- `alphabet_encode`: converts a lowercase ASCII letter to the encoded byte using the `ITU_MORSE` table in program memory.
- `encode_message`: converts a null-terminated message string to an encoded buffer, using `alphabet_encode`.

**How to Run**
- The program is structured for the Arduino Mega 2560 using the lab setup specified in the assignment.
- Select the message to encode by changing which `MESSAGE##` label is loaded in the "TOUCH CAREFULLY" section in [morse_encoder.asm](morse_encoder.asm).
- The encoded buffer is flashed three times in the main loop.

**Notes**
- Messages are expected to be lowercase letters and spaces.
- The `ITU_MORSE` table is eight-byte aligned per entry, with zero-terminated dot/dash strings.
- Delay routines are provided by the starter code and are called by `morse_flash`.

**Detailed Walkthrough (Based on This Implementation)**
- **Startup and test path:** The reset code initializes the stack pointer, configures the LED ports as outputs, copies a test encoded sequence (`sos`) into SRAM, and then calls `flash_message` with `TESTBUFFER` so the LED flashing can be verified before running the full encoder flow.
- **`flash_message` (SRAM byte stream to LED flashes):** The caller pushes a two-byte SRAM address onto the stack. Inside `flash_message`, the function builds a stack-frame pointer (`Y`) to pull the address, loads it into `Z`, and then loops: it reads one byte from `Z+`, copies it into `r16`, and calls `morse_flash`. The loop stops when the byte is `0x00`, which marks the end of the encoded message.
- **`morse_flash` (encoded byte to dot/dash timing):** This routine interprets the encoded byte by extracting the sequence length and dot/dash bits. It isolates the low nibble using shifts and `swap`, then iterates over the number of symbols. Each bit (0 for dot, 1 for dash) triggers a flash sequence: `leds_on`, `delay_short`/`delay_long`, `leds_off`, then `delay_long` to separate symbols. When the count reaches zero it returns.
- **`leds_on` / `leds_off` (LED port control):** `leds_on` maps the requested LED count in `r16` to the specific bit patterns for `PORTB` and `PORTL`, so 1–6 LEDs are lit in a consistent order. `leds_off` writes zeros to both ports to clear the LEDs.
- **`encode_message` (ASCII to encoded buffer):** The caller pushes the source message address in program memory and the destination buffer address in SRAM. The function pulls both addresses from its stack frame, then loops over each character with `lpm`. For each nonzero character it calls `alphabet_encode`, stores the returned byte into the destination buffer, and advances. The loop ends on the `0x00` terminator.
- **`alphabet_encode` (single character to encoded byte):** This routine receives a lowercase ASCII letter from the stack and uses the `ITU_MORSE` table in program memory. It walks the table entries (each 8 bytes wide) looking for the matching letter, then reads the dot/dash sequence and builds the encoded byte: `r19` tracks the length, while `r20` accumulates the dot/dash bits (dots keep a 0, dashes set a 1 after shifting). At the end it combines the length (high nibble) with the bit sequence (low nibble), placing the result in `r0` as the return value.
- **End-to-end flow:** The main logic encodes a selected `MESSAGE##` label into a buffer via `encode_message`, then displays it by calling `flash_message` three times in a loop.
