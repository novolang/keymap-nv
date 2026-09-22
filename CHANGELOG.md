# Changelog

All notable changes to keymap-nv are recorded here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the pre-1.0 rule that a breaking change bumps the MINOR number.

## 0.2.0 — 2026-09-22

A breaking release. The decoder builds and runs on a microcontroller
with no heap allocator, and the shape of every published value changed
to make that so. `novo build --target=nrf52-qemu
tests/embedded_probe.nv` produces a Cortex-M4 executable. Under QEMU it
decodes a control sequence with a modifier, an SGR mouse report and a
character outside ASCII, and resolves a lone ESC with a flush.

The decoding is unchanged: the same three protocols, the same three
mouse encodings, the same bracketed paste, and the same lone-ESC
contract, in which only the caller resolves the ambiguity.

- Every type is a `@value` struct, which is laid out inline and copied
  at each binding, argument and return rather than held in a heap cell
  (Novo specification, section 14). A decoder is 72 bytes on a 64-bit
  machine: two words of settings, five of held bytes, one cursor and one
  flag. Passing one copies those bytes.
- A `@value` struct's field may be a scalar, another `@value` struct or
  a fixed-size array of those, and nothing else. An enum therefore
  became a number with a table of `pub const` names. A variant that
  carried a payload became that number beside the payload's own fields.
  An optional became a named number, and the held bytes became a
  fixed-capacity buffer.
- The held bytes are four `u64` words inside the decoder, eight bytes to
  a word, so `SEQUENCE_BYTES_CAP` is 32 and `decoder_with` clamps
  `sequence_bytes_max` to it. The default was 64. The widest form any of
  the three protocols spells is 21 bytes, which is `CSI < 65535 ; 65535
  ; 65535 M`.
- `keychunk` is a new module and holds the three entry points that
  answer a list. A device build reaches every function of every module
  it compiles, a list is a heap cell, and the three modules a device
  needs are therefore the three it can have.
- `tests/embedded_probe.nv` is back, and `tests/alloc_scan.sh` is new:
  it reads the emitted LLVM and checks that none of the 109 functions of
  `keymodel`, `mousedecode` and `keydecode` calls the allocator, with a
  spliced allocation as the control that the scan and the compiler both
  still catch it.
- Five suites, 94 tests, and every line under `src/` executed by them.
  `bash tests/coverage.sh` merges the per-suite LCOV and prints the
  number, which is 100%.

### Migration

Each old spelling and what it becomes. The names are kept wherever the
shape allowed one, so the work is mechanical.

**Where a function lives**

| 0.1.0 | 0.2.0 |
| --- | --- |
| `keydecode.feed(d, chunk)` | `keychunk.feed(d, chunk)` |
| `keydecode.flush(d)` | `keychunk.flush(d)`, or `keydecode.flush_step(d)` for one event at a time |
| `keydecode.decode_one(seq, limits)` | `keychunk.decode_one(seq, limits)` |
| `keydecode.KeyDrained` | `keychunk.KeyDrained` |

**A keystroke**

| 0.1.0 | 0.2.0 |
| --- | --- |
| `KeyChar(c)` as a pattern | `press.kind == keymodel.KEY_PRESS_CHAR`, then `press.codepoint` |
| `KeyChar(c)` as a constructor | `keymodel.key_char(c)` |
| `KeyNamed(n)` as a pattern | `press.kind == keymodel.KEY_PRESS_NAMED`, then `press.name` |
| `KeyNamed(n)` as a constructor | `keymodel.key_named(n)` |
| `KeyPad(p)` as a pattern | `press.kind == keymodel.KEY_PRESS_PAD`, then `press.pad` |
| `KeyPad(p)` as a constructor | `keymodel.key_pad(p)` |
| `KeyFunction(n)` | `press.name == keymodel.KEY_FUNCTION` with `press.number`; built with `keymodel.key_function(n)` |
| `KeyPadDigit(n)` | `press.pad == keymodel.KEYPAD_DIGIT` with `press.number`; built with `keymodel.key_pad_digit(n)` |
| `KeyUp`, `KeyEnter`, `KeyEscape`, … | `keymodel.KEY_UP`, `keymodel.KEY_ENTER`, `keymodel.KEY_ESCAPE`, … |
| `KeyMediaPauseKey` | `keymodel.KEY_MEDIA_PAUSE` — the suffix is gone, because a number and a key name no longer share a namespace |
| `KeyPadStar`, `KeyPadBegin`, … | `keymodel.KEYPAD_STAR`, `keymodel.KEYPAD_BEGIN`, … |
| `KeyDownEvent`, `KeyRepeatEvent`, `KeyUpEvent` | `keymodel.KEY_DOWN_EVENT`, `keymodel.KEY_REPEAT_EVENT`, `keymodel.KEY_UP_EVENT`; `KeyStroke.motion` is an `Int` |
| `a == b` on a `KeyMods` or a `KeyStroke` | `keymodel.mods_eq(a, b)`, `keymodel.stroke_eq(a, b)`, `keymodel.press_eq(a, b)` |
| `keymodel.control_char(c) -> ?Int` | `-> Int`, answering `keymodel.NO_CODEPOINT` where there is none |
| `keymodel.char_of_control(b) -> ?Int` | `-> Int`, answering `keymodel.NO_CODEPOINT` where there is none |

**A mouse report**

| 0.1.0 | 0.2.0 |
| --- | --- |
| `MouseLeft`, `MouseWheelUp`, … | `mousedecode.MOUSE_LEFT`, `mousedecode.MOUSE_WHEEL_UP`, … |
| `MouseExtraButton(n)` | `report.button == mousedecode.MOUSE_EXTRA_BUTTON` with `report.button_number` |
| `MousePressed`, `MouseReleased`, `MouseMoved` | `mousedecode.MOUSE_PRESSED`, `mousedecode.MOUSE_RELEASED`, `mousedecode.MOUSE_MOVED` |
| `MouseX10Encoding`, `MouseSgrEncoding`, `MouseUrxvtEncoding` | `mousedecode.MOUSE_X10_ENCODING`, `mousedecode.MOUSE_SGR_ENCODING`, `mousedecode.MOUSE_URXVT_ENCODING` |
| `report_x10`, `report_sgr`, `report_urxvt` answering `?MouseReport` | answering `MouseReport`; `mousedecode.is_report(r)` is the question, and `mousedecode.no_report()` is the answer for bytes that are not one |
| `mousedecode.decode_button(code) -> MouseButtonKind` | `-> Int`, with `mousedecode.decode_button_number(code)` for buttons 8 to 11 |
| `mousedecode.button_code(button, mods, motion)` | `button_code(button, number, mods, motion)` — `number` is which of buttons 8 to 11 and is ignored for every other button |

**An event**

| 0.1.0 | 0.2.0 |
| --- | --- |
| `KeyPressed(k)` | `e.kind == keydecode.KEY_EVENT_PRESSED`, then `e.stroke`; built with `keydecode.pressed_event(k)` |
| `KeyMouse(r)` | `e.kind == keydecode.KEY_EVENT_MOUSE`, then `e.mouse`; built with `keydecode.mouse_event(r)` |
| `KeyPasteByte(b)` | `e.kind == keydecode.KEY_EVENT_PASTE_BYTE`, then `e.byte`; built with `keydecode.byte_event(kind, b)` |
| `KeyUnknownSequence(f)` | `e.kind == keydecode.KEY_EVENT_UNKNOWN_SEQUENCE`, then `e.byte` |
| `KeyPasteStart`, `KeyPasteEnd`, `KeyFocusGained`, `KeyFocusLost` | `keydecode.KEY_EVENT_PASTE_START` and the other three; built with `keydecode.marker_event(kind)` |
| `KeyStep.event` as `?KeyEvent` | a `KeyEvent` whose kind is `keydecode.KEY_EVENT_NONE` where the step completed none |
| `decode_one` answering `?KeyEvent` | answering a `KeyEvent` whose kind is `keydecode.KEY_EVENT_NONE` |

**The decoder and the protocols**

| 0.1.0 | 0.2.0 |
| --- | --- |
| `KeyDecoder.held` as `[u8]` | `KeyHeld`, a fixed-capacity buffer; `keydecode.held_at(d.held, i)` reads byte `i` and `d.held.len` is how many |
| `KeyLegacyForms`, `KeyWin32Input`, … | `keydecode.KEY_LEGACY_FORMS`, `keydecode.KEY_WIN32_INPUT`, … |
| `keydecode.protocol_refusal(p) -> ?Str` | `-> Str`, answering the empty string for a protocol that is read |
| `sequence_bytes_max` of 64 by default | 32, which is `keydecode.SEQUENCE_BYTES_CAP`, and `decoder_with` clamps a larger number down to it |

### Fixed elsewhere

One toolchain defect was found writing this release and is filed
against the compiler rather than designed around:
`types-values/module-qualified-value-type-refused-as-a-value-field`. A
`@value` struct's field and a flat buffer's element type are refused
when the type is written with its module prefix, and accepted when the
same type is written bare. Three sites name the filing and write the
bare name.

The `list.fold` in `paste_bytes` that named
`memory-perceus/list-map-leaks-a-box-per-element-when-the-lambda-builds-an-enum-variant`
is gone with the function it was in. Pasted bytes are reported one at a
time by `flush_step`, there is no enum variant left for the lambda to
build, and no list operation in the three modules a device reaches.

### Known

- **win32-input-mode is not covered**, and `protocol_refusal` says so
  with a reason rather than by silence.
- **The kitty protocol's remaining names have no number here.** The
  modifier keys themselves, ten keypad keys that duplicate a named key,
  and three media keys arrive as `KEY_EVENT_UNKNOWN_SEQUENCE`, which
  carries the final byte and not the number.
- **A mouse report's bit 3 is reported as `meta`**, which is the name
  xterm's `ctlseqs` gives it. A program that treats the same bit as alt
  reads `mods.meta`.
- **An event is 128 bytes and a step is 200.** A `KeyEvent` carries a
  keystroke and a mouse report side by side, and a copy of it crosses
  every call. They are stack bytes on a host and on a device alike.

## 0.1.0 — 2026-09-18

The bodies.  Bytes in, key and mouse events out, over the legacy escape
forms, xterm's modifyOtherKeys, the kitty keyboard protocol, the three
mouse encodings, bracketed paste, focus events and UTF-8 — and no
signature changed.

- The decoder is the held bytes and nothing else.  Every byte re-reads
  what is held from the start, so one buffer serves an escape sequence,
  a codepoint that arrived a byte at a time, and the end marker of a
  paste.  The work per byte is bounded by `sequence_bytes_max`.
- A lone ESC is held, and `flush` is what resolves it.  An ESC in front
  of anything else is the alt prefix, so `ESC x` is Alt and `x` and
  `ESC ESC [ A` is Alt and the up arrow.  A run of escapes that never
  resolves comes back from `flush` as one Escape key per byte.
- A character outside ASCII arrives as its UTF-8 bytes and is assembled
  into one `KeyChar`.  The bytes are held the way a sequence's bytes
  are, so a codepoint split across two reads costs nothing.  The
  continuation bytes are taken as the lead byte promises them, without
  a check; the README says so under what is not included.
- Tab, Enter and Backspace are keys.  Every other C0 byte is its letter
  with ctrl held, which is crossterm's reading, so 0x08 is Ctrl and `h`
  and 0x0A is Ctrl and `j`.
- `CSI Z` is Shift and Tab, which is the only spelling `KeyBackTab` has;
  `CSI R` is left unread, because it is the reply to a cursor position
  query and a program that asked for one has to be able to see it.
- A bracketed paste reports every byte it was given, in order.  During
  one the decoder holds at most the five bytes of a half-arrived end
  marker, and reports them as pasted text as soon as a byte proves they
  were not the marker.  A `flush` inside a paste reports what is held
  and leaves the paste open.
- One parameter stops growing at 65535 rather than wrapping.  A
  sequence carrying a longer run of digits reaches a number no form
  here claims and is reported by its final byte.
- Four suites, 81 tests, and every line under `src/` executed by them.
  `bash tests/coverage.sh` merges the per-suite LCOV and prints the
  number, which is 100%.

### Changed

- **The device claim is withdrawn, and `tests/embedded_probe.nv` is
  gone.**  The interface release linked for `--target=nrf52-qemu`
  because every body was a `todo()` and nothing was constructed.  With
  bodies, `novo build --target=nrf52-qemu` refuses the package:
  `KeyMods`, `KeyStroke` and `MouseReport` are boxed structs, and
  `KeyPress`, `KeyName`, `KeyPadKey`, `MouseButtonKind` and `KeyEvent`
  each carry a variant with a payload, all of which are heap cells at
  that tier.  A device build needs `@value` structs and a discriminant
  field in place of each payload-carrying variant, which is a different
  published interface rather than a different implementation.  The
  README says what it would take.

### Known

- **win32-input-mode is not covered**, and `protocol_refusal` says so
  with a reason rather than by silence.
- **The kitty protocol's remaining names have no variant here.**  The
  modifier keys themselves, ten keypad keys that duplicate a named key,
  and three media keys arrive as `KeyUnknownSequence`, which carries the
  final byte and not the number.
- **A mouse report's bit 3 is reported as `meta`**, which is the name
  xterm's `ctlseqs` gives it.  A program that treats the same bit as alt
  reads `mods.meta`.

### Fixed elsewhere

Three toolchain defects were found writing this release and are filed
against the compiler rather than worked around in the design:
`memory-perceus/nested-pattern-binding-returned-from-an-arm-aliases-the-next-result`,
`memory-perceus/call-returned-struct-in-a-match-scrutinee-is-never-released`
and
`memory-perceus/list-map-leaks-a-box-per-element-when-the-lambda-builds-an-enum-variant`.
The last one is named at the one site that avoids it.

## 0.0.2 — 2026-09-15

README rewritten to the package README style guide
(docs/writing-a-readme.md); no change to the interface.

## 0.0.1 — 2026-09-10

The **interface**: every signature and every effect row, and no bodies.
`stability = "draft"`, and the release is recorded `implemented = false`.

### Added

- `keymodel` — what a keystroke is, before any question of how it
  arrived: a named key, a character or a keypad key, four modifiers,
  and a press/repeat/release motion the kitty protocol can fill in and
  a legacy terminal cannot. `mods_of` reads xterm's modifier parameter,
  which is one plus a bitmask, and `char_of_control` knows that Tab and
  Ctrl+I are the same byte and that only one of them is a key.
- `mousedecode` — the three encodings as one value. The button byte's
  field layout written once, `coordinates_are_exact` as the question a
  program on a wide terminal has to be able to ask, and the fact that
  only the SGR encoding knows which button was released made visible in
  the value rather than guessed.
- `keydecode` — the input state machine, and `flush`. A lone ESC is
  never resolved by feeding a byte; it is held, `is_pending` says so,
  and the host — whose read timed out — resolves it. Bracketed paste
  streams a byte at a time. A sequence this package does not claim is
  reported rather than dropped, because a program that knows about it
  has to be able to see it.

### Known

- **The device claim covers the signatures, not yet the storage.**
  `tests/embedded_probe.nv` links for `--target=nrf52-qemu` today
  because every body is a `todo()`. `KeyDecoder.held` is a `[u8]` and
  will have to become a fixed-capacity buffer — heapless-nv's — before
  the implementation runs on a device.
- **win32-input-mode is not covered**, and `protocol_refusal` says so
  with a reason rather than by silence.
- **No `Result` anywhere.** An undecodable sequence is an event
  (`KeyUnknownSequence`), and every partial decode is `None`.
  `Result<T, E>` does not build at `@tier(embedded)`; shaping the
  package around `?T` costs nothing here, because a decoder does not
  fail — it either has an answer or is still waiting.

### Design notes

Public type and variant names are unique across a whole program, so a
package's names have to be unique across the registry too. `Key` was
unavailable as a bare name, `Event` is declared by gof-patterns,
`EventKind` is a standard-library enum, and `Error` is a standard-library
trait. Enum variants collide by their bare name, so `Backspace`,
`Motion`, `Release` and `Click` were all taken by `std.window`.
`MouseReport` rather than `MouseEvent`, because novomux declares the
latter and naming it that would refuse any multiplexer that took this
package. `KeyMediaPauseKey` carries its suffix because `KeyPause` beside
it already holds the shorter name. The modules are `keydecode`,
`keymodel` and `mousedecode` because no module may be named after a
standard-library one.

Three designs for the lone-ESC ambiguity were rejected. A timestamp per
byte would make the caller pass a clock reading into a package that only
ever compares two of them. A timer inside the decoder would decide the
timeout for every program that embeds it. Resolving ESC eagerly and
undoing it when a byte follows cannot work, because an event already
handed to the caller cannot be taken back; that is the design that makes
the Escape key flicker.
