# Changelog

All notable changes to keymap-nv are recorded here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the pre-1.0 rule that a breaking change bumps the MINOR number.

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
