# keymap-nv

A terminal does not send keys. It sends bytes, and the same keystroke
has three or four spellings depending on which input protocol the
terminal and the program agreed on. This package turns those bytes back
into keystrokes and mouse reports, with no terminal attached. The
spellings it reads are the classic ones documented in
[xterm's `ctlseqs`](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html),
xterm's `modifyOtherKeys`, and
[the kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/).
[termios-nv](https://novo-lang.org/packages/termios-nv) is built on it
and supplies the reading half.

## What it is

Press `q` at a terminal and the byte 0x71 arrives. Press Ctrl and `c`
and the byte 0x03 arrives, which is a different character rather than a
letter with a modifier attached. Press the up arrow and three bytes
arrive: ESC, `[`, `A`. A **decoder** is the state machine that reads
that stream and answers what was pressed.

There are several spellings because terminals gained abilities without
losing compatibility. The **legacy forms** are the oldest: a control
byte for Ctrl and a letter, and an escape sequence for anything with a
name. xterm's **`modifyOtherKeys`** adds `CSI 27 ; <modifiers> ;
<codepoint> ~`, which is what makes a combination such as Ctrl and Shift
and a letter expressible at all. The **kitty keyboard protocol** adds
`CSI <codepoint> ; <modifiers> : <event> u`, and with it key releases
and auto-repeat, which no older form can report. All three are
recognised at the same time. Their sequences do not collide, so the
decoder never has to be told which one the terminal is speaking.

A **modifier set** is shift, alt, ctrl and the platform key. On the wire
it is a single number, and that number is one plus a bitmask, so a
modifier parameter of 1 means nothing was held.

A character the keyboard produces arrives as **UTF-8**, which is one to
four bytes for one codepoint. The bytes of a codepoint arrive the way
the bytes of a sequence do, and the decoder holds them the same way.

The **mouse** is reported as a sequence too, in one of three encodings.
The button and the modifiers share one byte in all three, laid out the
same way.

| Bits of the button byte | Meaning |
| --- | --- |
| 0 and 1 | which button, or which wheel direction |
| 2 | shift |
| 3 | meta |
| 4 | ctrl |
| 5 | the pointer moved |
| 6 | this is a wheel event |
| 7 | this is one of buttons 8 to 11 |

A **bracketed paste** is pasted text wrapped in `CSI 200 ~` and
`CSI 201 ~`, so that a program can tell pasted text from typing. The
decoder reports the wrapper and then the payload, one byte at a time.

One case cannot be decided from the bytes at all. The byte 0x1B is the
Escape key, and it is also the first byte of every escape sequence.
Nothing later in the stream distinguishes them: what distinguishes them
is time. This package never guesses. It holds the byte, reports that it
is holding it, and resolves it when the caller — whose read timed out,
and who is the only party that could know — calls `flush`.

| Quantity | Value |
| --- | --- |
| Milliseconds a caller should wait after a lone ESC | 25 |
| Highest column or row the X10 mouse encoding can express | 223 |
| Modifier parameter that means nothing is held | 1 |
| Modifiers reported | 4 |
| Bytes of one escape sequence held by default | 64 |
| Largest value one parameter may hold | 65535 |

## Install

```
novo pkg add keymap-nv
```

## Example

```novo
use std.list
use std.str
use keydecode

fn main() [io]
    // A fresh decoder, holding nothing.
    var d = keydecode.decoder_new()

    // The three bytes a terminal sends for the up arrow: ESC [ A.
    let out = keydecode.feed(d, [0x1B, 0x5B, 0x41])
    // Keep the decoder the chunk returned; it is the one to feed next.
    d = out.decoder
    for e in out.events
        match e
            KeyPressed(stroke) =>
                match stroke.press
                    KeyNamed(KeyUp) => println("up")
                    _               => println("another key")
            _ => println("not a key")

    // A lone ESC. Nothing in the bytes says whether the user pressed
    // Escape or started a sequence, so the decoder holds the byte.
    let held = keydecode.feed(d, [0x1B])
    d = held.decoder

    if keydecode.is_pending(d)
        // The caller's read timed out, so no further byte is coming.
        // Only the caller knows that, so only the caller can say so.
        let done = keydecode.flush(d)
        d = done.decoder
        // One event: the Escape key.
        println(str.from_int(list.len(done.events)))
```

Build and test with `novo pkg build` and `novo test`.

## What the package contains

| Module | Contents |
| --- | --- |
| `keymodel` | What a keystroke is, before any question of how it arrived: the named keys, the keypad keys, the four modifiers, the press-repeat-release motion, and the conversions between a modifier set and the number it travels as. |
| `keydecode` | The state machine: the decoder value, the events it produces, the caller-set ceilings, the chunk and byte entry points, `flush`, and the questions a read loop asks about what the decoder is holding. |
| `mousedecode` | A mouse report and the three encodings it can arrive in, with the shared button-byte table written once. |

## How to choose an entry point

**`keydecode.feed` takes a chunk and answers a list of events.** A read
gives a chunk, and whatever the chunk did not finish stays held for the
next one. This is what a read loop uses.

**`keydecode.feed_byte` takes one byte.** It answers at most one event.
Most bytes of a sequence complete nothing. Use it where the bytes arrive
one at a time anyway.

**`keydecode.flush` resolves what is held.** Call it after a read that
timed out. On a decoder that is holding nothing it produces nothing and
is harmless, so it need not be guarded.

**`keydecode.decode_one` takes one complete sequence.** It answers
`None` for a prefix, for bytes this package does not recognise, and for
a chunk that holds more than one sequence. It is for the two callers
that are not read loops: a test with a fixture, and a program whose key
bindings are written as the bytes a terminal sends.

## The rules a user needs

1. **A lone ESC is never resolved from the bytes.** `feed_byte` and
   `feed` hold it however long ago it arrived, because a `core` package
   has no clock and cannot know. Only `flush` resolves it.
2. **`is_pending` is what a read loop switches on.** Pending means read
   with the escape timeout; settled means block. A loop that always
   timed out would spin. A loop that always blocked would leave the
   Escape key stuck until the next keystroke.
3. **`ESCAPE_TIMEOUT_MS` is a number, not a timer.** Nothing here waits.
   The value is the one vim, tmux and crossterm converge on. A caller on
   a high-latency link should wait longer and is free to.
4. **`flush` answers a list, not one event.** An `ESC [` that never
   finished is two events: the Escape key, then the character `[`.
5. **The modifier parameter is one plus a bitmask.** A parameter of 1
   means nothing was held. `keymodel.mods_of` applies the rule and
   `mods_param` is its inverse. A decoder that read the bitmask straight
   reports shift for every unmodified arrow key. See xterm's `ctlseqs`,
   "PC-Style Function Keys".
6. **Ctrl and a letter is reported as the letter with a modifier.** It
   is not reported as the control byte. `keymodel.control_char` gives
   the byte a legacy terminal would have sent, for a program that has to
   write one.
7. **Tab, Enter and Backspace are keys, not control characters.** Ctrl
   and `i` is byte 0x09, which is also Tab, and Ctrl and `m` is byte
   0x0D, which is also Enter. `keymodel.char_of_control` answers `None`
   for those bytes rather than claiming a letter. Backspace is 0x7F,
   which is the byte a terminal sends for that key; 0x08 is Ctrl and
   `h`, and 0x0A is Ctrl and `j`.
8. **Only the kitty protocol reports releases and repeats.** Every
   legacy decode carries `KeyDownEvent`, which is what a legacy terminal
   knows. See the kitty keyboard protocol, "Event types".
9. **A character outside ASCII arrives as its UTF-8 bytes.** The decoder
   assembles them into one `KeyChar` with the codepoint. A lead byte
   that promises continuation bytes is held until they arrive, so
   `is_pending` is true in the middle of a codepoint as well as in the
   middle of a sequence. A byte that leads no codepoint — 0x80 to 0xC1,
   or 0xF5 and above — is reported as a character with that value.
10. **Mouse coordinates are one-based, column first, exactly as the
    terminal sends them.** tui-nv's buffer is zero-based and converts at
    that boundary. See xterm's `ctlseqs`, "Mouse Tracking".
11. **The X10 mouse encoding cannot say anything past 223.** A terminal
    reports 223 forever past that column, and `X10_COORD_MAX` is the
    number. `coordinates_are_exact` answers whether a report is
    trustworthy. A program on a wide screen should ask the terminal for
    the SGR encoding, which is `CSI ? 1006 h`.
12. **Only the SGR encoding distinguishes a press from a release.** Its
    final byte says which. X10 and urxvt both report a release as button
    3, so which button was let go cannot be recovered.
13. **A paste arrives as a wrapper and a stream of bytes.**
    `KeyPasteStart`, then one `KeyPasteByte` per byte, then
    `KeyPasteEnd`. During a paste the decoder holds at most the five
    bytes of a half-arrived end marker, and reports them as pasted text
    as soon as a byte proves they were not the marker. `in_paste`
    answers whether a paste is open.
14. **A terminal's reply to a query arrives on this stream and is not a
    key.** `CSI 12 ; 40 R` is an answer to a cursor position query. This
    package reports it as `KeyUnknownSequence` rather than guessing, and
    for that reason it reads no key from a CSI ending in `R`;
    [ansi-nv](https://novo-lang.org/packages/ansi-nv)'s
    `vtquery.reply_of` is what reads it. The three function keys xterm
    spells the same way, `CSI 1 ; <mods> P`, `Q` and `S`, are read.
15. **win32-input-mode is not decoded.** `protocol_supported` answers
    `false` for it and `protocol_refusal` gives the reason. Its six
    parameters describe a Windows console key event record, with a
    virtual key code and a scan code, and mapping those onto this model
    needs a Windows keyboard-layout table.
16. **Both ceilings are the caller's.** `sequence_bytes_max` bounds one
    escape sequence, and beyond it the decoder reports
    `KeyUnknownSequence` and reads the bytes that follow as fresh input.
    `kitty_enabled` turns the kitty forms off, for a program running
    against a terminal it has not negotiated with. `legacy_limits` is
    that configuration. A single parameter stops growing at 65535, which
    is a number no form here claims, so a sequence carrying a longer run
    of digits is reported by its final byte.
17. **A key outside the closed set is reported rather than folded.** The
    kitty protocol names the modifier keys themselves, ten keypad keys
    that duplicate a named key, and three media keys that `KeyName` has
    no variant for. A sequence carrying one of those is
    `KeyUnknownSequence`.

## Running on a microcontroller

This package does not build for a device with no heap allocator, and
`novo build --target=nrf52-qemu` refuses it. The reason is the model
rather than the decoding. `KeyMods`, `KeyStroke` and `MouseReport` are
boxed structs, and `KeyPress`, `KeyName`, `KeyPadKey`,
`MouseButtonKind` and `KeyEvent` each carry a variant with a payload;
every one of those is a heap cell at that tier, and the compiler refuses
it where it is written. `KeyDecoder.held` is a `[u8]`, which is a second
heap cell and would have to become a fixed-capacity buffer —
[heapless-nv](https://novo-lang.org/packages/heapless-nv)'s.

What a device build would take is therefore a different model: `@value`
structs, and a discriminant field in place of each payload-carrying
variant. That is a different published interface, not a change of
implementation, so it is not something this release can do quietly.

Nothing here reads, waits or consults a clock, which is the other half
of what a firmware needs. A device with a serial console takes
keystrokes off a UART, and the bytes are the same bytes.

## What is not included

- **Bindings, chords, leader keys and modes.** A keymap in the editor
  sense is a program's configuration. What this package owes a program
  is an unambiguous value to look up.
- **Turning the protocols on.** Asking a terminal for bracketed paste or
  for the kitty protocol means writing `CSI ? 2004 h` or `CSI > 1 u`,
  which is the output direction.
  [ansi-nv](https://novo-lang.org/packages/ansi-nv)'s
  `seqwrite.set_mode` writes them.
- **Reading, timing and raw mode.** All three belong to the host.
  [termios-nv](https://novo-lang.org/packages/termios-nv) has raw mode,
  and the read loop is the program's own.
- **Query replies.** See rule 14.
- **win32-input-mode.** See rule 15.
- **A palette of key names beyond the closed set.** See rule 17.
- **Validation of a codepoint's continuation bytes.** The decoder takes
  as many bytes as the lead byte promises and reads the low six bits of
  each. A terminal that sends a byte outside 0x80 to 0xBF there has sent
  a codepoint no encoder produces.
- **A build for a device.** See "Running on a microcontroller".

## Related packages

- [ansi-nv](https://novo-lang.org/packages/ansi-nv) is the same job in
  the other direction: the escape sequences a program writes to a
  terminal, and the parser for the ones a terminal writes back. This
  package does not depend on it. The input stream is a different state
  machine: the X10 mouse encoding puts three raw bytes after the final
  byte, where a conforming sequence parser has already stopped
  collecting; and the lone-ESC ambiguity has no counterpart on output.
- [termios-nv](https://novo-lang.org/packages/termios-nv) owns the file
  descriptor. It puts the terminal in raw mode, runs the read, and is
  the party whose timeout drives `flush`.
- [tui-nv](https://novo-lang.org/packages/tui-nv) is the drawing half of
  a terminal program: layout, widgets and a cell buffer.
- [novo-vte](https://novo-lang.org/packages/novo-vte) is a terminal
  emulator's grid and the parser that fills it. A terminal emulator
  needs both directions, and this is the one that reads a keyboard.
- `std.tui` in the standard library has `tui.read_key`, which reads one
  byte from standard input without blocking. Reassembling an arrow key
  from the three bytes it answers is the caller's work, and this package
  is where that work is written down.

## Tests

```bash
novo test --isolate tests/keydecode_tests.nv   # 23 tests: the state machine
novo test --isolate tests/sequence_tests.nv    # 27 tests: every spelling it reads
novo test --isolate tests/model_tests.nv       # 16 tests: the two arithmetic modules
novo test --isolate tests/surface_tests.nv     # 15 tests: every signature, once
```

The reference implementations are crossterm for the key model, the kitty
keyboard protocol specification for the `CSI u` forms and the event
types, xterm's `ctlseqs` for `modifyOtherKeys`, the legacy sequences and
the three mouse encodings, and tmux and vim for the escape timeout.

`keydecode_tests.nv` feeds bytes one at a time and asserts what the
decoder is holding in between, because a chunk from a real read ends
where the kernel says it ends. The cases that matter are the lone ESC
held rather than resolved, a `flush` producing two events out of an
unfinished `ESC [`, the same keystroke arriving in all three protocols
and decoding to one value, a modifier parameter of 1 meaning nothing is
held, an X10 report at the ceiling reported as inexact, and a paste
staying open across a chunk boundary.

`sequence_tests.nv` is one case per spelling: the SS3 keypad, the tilde
numbers, the kitty protocol's functional key numbers, the three mouse
encodings with the inputs each of them refuses, the bytes of a
codepoint, and the sequences that are reported rather than read.
`model_tests.nv` is the two arithmetic modules, every entry of their
tables in both directions. `surface_tests.nv` calls every published
function once, from outside its own module.

No test reads a descriptor or consults a clock. Every line of `src/` is
executed by the suites; `bash tests/coverage.sh` measures it and prints
the number.

## Licence

Apache-2.0. See `LICENSE`.

<!-- docs/writing-a-readme.md is the style guide for this page. -->
