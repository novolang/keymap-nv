# keymap-nv

**Status: NOT IMPLEMENTED — interface only.**

Every public function below is published with its signature and its
effect row, and every body is `todo()`. Installing this package works;
calling it panics with `not implemented`.

## What this is

Keys and mouse reports decoded from the bytes a terminal sends, with
**no terminal attached**. A terminal does not send keys; it sends
bytes, and the same keystroke has three or four spellings depending on
what the terminal negotiated. This package is the value all of them
decode to, and the state machine that gets there.

- the key model — a named key, a character or a keypad key, plus
  modifiers and a press/repeat/release motion;
- the legacy escape forms, xterm's `modifyOtherKeys`, and the kitty
  keyboard protocol, all recognised at once;
- mouse reports in the X10, SGR and urxvt encodings;
- bracketed paste, streamed a byte at a time;
- and **`flush`** — the answer to the one question a decoder cannot
  answer on its own.

```
novo pkg add keymap-nv
novo pkg build
novo test
```

## The one example that will work

A host's read loop. The two branches are the whole interface: read
blocking when the decoder is settled, read with a timeout when it is
pending, and `flush` when that read times out.

```novo
use keydecode

fn main() [io]
    var d = keydecode.decoder_new()
    loop
        // The host reads.  Which read it does is what the decoder's
        // state decides, and it is the only decision this package asks
        // a caller to make.
        let chunk = if keydecode.is_pending(d)
            read_with_timeout(keydecode.ESCAPE_TIMEOUT_MS)
        else
            read_blocking()

        if list.len(chunk) == 0
            // The read timed out.  Only the host could have known
            // that, so only the host can say so.
            let done = keydecode.flush(d)
            d = done.decoder
            for e in done.events
                handle(e)
        else
            let out = keydecode.feed(d, chunk)
            d = out.decoder
            for e in out.events
                handle(e)
```

## The load-bearing interface

```novo ignore
pub fn feed_byte(d: KeyDecoder, b: Int) -> KeyStep
pub fn flush(d: KeyDecoder) -> KeyDrained
pub fn is_pending(d: KeyDecoder) -> Bool
pub const ESCAPE_TIMEOUT_MS = 25
```

**The lone ESC is the whole problem, and the caller owns the clock.**

A byte 0x1B arrives. It is the Escape key, or the first byte of an
arrow key, or the first byte of `Alt+x` — and **nothing in the byte
stream distinguishes them**. What distinguishes them is time: another
byte within a few milliseconds means a sequence; silence means the user
pressed Escape.

A `core` package has no clock, and that turns out to be the right
constraint rather than an obstacle:

- `feed_byte` **never** resolves a lone ESC, however long ago it
  arrived — it has no idea how long ago that was. It holds the byte and
  reports `is_pending`.
- `flush` resolves whatever is held, on the caller's word that no more
  bytes are coming. It returns a **list**, because `ESC [` that never
  finished is two events: Escape, then `[`.
- `flush` on a settled decoder produces nothing and is harmless, so a
  host may call it after every timed-out read without checking first.
- `ESCAPE_TIMEOUT_MS` is a **number, not a timer**. 25 is what vim,
  tmux and crossterm converge on. A host on a high-latency link wants
  more, and it is the host that knows.

The alternative designs, and why not:

| | why not |
| --- | --- |
| the decoder takes a timestamp per byte | `[time]` is a host effect, and the caller would be passing a clock reading into a package that only ever compares two of them |
| the decoder starts a timer | a `core` package has no timer, and a package that could start one would decide the timeout for every program that embeds it |
| resolve ESC eagerly, undo it if a byte follows | an event already handed to the caller cannot be taken back; this is the design that makes Escape flicker |
| never resolve — report a raw byte and let the caller decide | it moves the whole decoder into the caller, which is the package |

`is_pending` is the other half and is what a read loop switches on. A
host that always used a timeout would spin; one that always blocked
would leave the Escape key stuck until the next keystroke, which is the
bug every terminal program has shipped at least once.

## The protocols, and the one that is refused

| | |
| --- | --- |
| legacy forms | ✓ C0 bytes, `ESC [ A`, `ESC O P`, `ESC [ 1 5 ~`, `ESC [ 1 ; 5 A` |
| xterm `modifyOtherKeys` | ✓ `CSI 27 ; <mods> ; <codepoint> ~` — how Ctrl+Shift+letter becomes sayable at all |
| kitty keyboard | ✓ `CSI <codepoint> ; <mods> : <event> u`, with press, repeat and release |
| win32-input-mode | ✗ refused, with a reason |

`protocol_supported` and `protocol_refusal` are functions rather than a
paragraph, so a program can ask. win32-input-mode is six parameters
describing a Windows console `KEY_EVENT_RECORD`, virtual key code and
scan code included; mapping those onto this model needs a Windows
keyboard-layout table, which is not arithmetic and does not belong in a
`core` package.

**Which protocol is in use is not a setting.** All three are recognised
at once, because their sequences do not collide and a decoder that had
to be told would be wrong every time the negotiation was. What *is* a
setting is whether the kitty forms are recognised at all
(`legacy_limits()`), for a program running against a terminal it has
not negotiated with.

## The layer, and why

`core` — no effects, and `flush` is the reason it can be. Nothing here
reads, waits, or consults a clock.

**The device claim is made and built.**
`tests/embedded_probe.nv` links for `--target=nrf52-qemu`; the audit's
`core-embedded` row is green. A device with a serial console takes
keystrokes off a UART and the bytes are the same bytes; its read loop
already has a timer, and `flush` is how it hands the answer back.

One honest qualification: what links today is the **signatures**,
because every body is a `todo()`. `KeyDecoder.held` is a `[u8]` and
will have to become a fixed-capacity buffer — heapless-nv's — before
any of it runs on a device.

## Why this does not depend on ansi-nv

Both are `core`, so `dep-layer` would have allowed it. Three cases say
the input stream is a different state machine from the output one:

1. **X10 mouse.** `CSI M Cb Cx Cy` carries three **raw** bytes after
   the final byte — bytes a conforming CSI parser has already stopped
   collecting, and one of which can be `;` (column 27) or `M` itself.
   `mousedecode.report_x10` exists because of this.
2. **The kitty forms** put the key event in a CSI's *sub-parameters*
   (`99 ; 1 : 3`), which a decoder reads as a shape rather than as a
   parameter list.
3. **The lone ESC is not ambiguous on output at all.** The whole of
   `flush` has no counterpart in an output parser.

A decoder that borrowed a CSI scanner would special-case its way around
all three, and every consumer would pay for an SGR model and a writer
it never calls. The one place the two packages do meet is a terminal's
**reply** to a query — `CSI 12 ; 40 R` arrives on this stream and looks
like a key — and that is handled by reporting it as
`KeyUnknownSequence` rather than guessing: ansi-nv's `vtquery.reply_of`
is what knows.

## Where the names come from, and the ones that were taken

Public type and variant names are unique across the whole assembly.

| here | the obvious name | why not |
| --- | --- | --- |
| `KeyStroke`, `KeyPress`, `KeyMods` | `Key`, `Press`, `Modifiers` | `Key` is the noun three packages will want; `KeyPair`, `KeyError`, `KeyOrigin` are already published by p256-nv and smp-nv |
| `KeyEvent` | `Event` | gof-patterns declares `Event`, and `EventKind` is a standard-library enum |
| `KeymapError` — none needed | `Error` | `Error` is a standard-library trait; in the end nothing here needs an error type at all |
| `KeyBackspace`, `KeyEscape`, … | `Backspace`, `Escape`, … | `Backspace` is a `std.window` **variant**, and variants collide by bare name |
| `KeyMediaPauseKey` | `KeyMediaPause` | reads worse, and is the honest consequence of the rule: `Pause` is taken by `KeyPause` next to it, and the media one needed a suffix rather than a collision |
| `MouseReport` | `MouseEvent` | novomux declares `MouseEvent`; naming it that would refuse any multiplexer that took this package |
| `MousePressed`, `MouseMoved`, `MouseReleased` | `Press`, `Motion`, `Release` | `Motion` and `Release` are `std.window` variants; `Click` is too |
| `KeyDownEvent`, `KeyUpEvent` | `Down`, `Up` | they would collide with `KeyDown`/`KeyUp`, the arrow keys, inside this package |
| module `keydecode`, `keymodel`, `mousedecode` | `decode`, `key`, `mouse` | all three are names another package will want, and no module may be named after a standard-library one |

## The reference implementations

**crossterm** for the key model — the named/character split, the
modifier set, and the decision to report `Ctrl+c` as the letter with a
modifier rather than as byte 0x03. **The kitty keyboard protocol
specification** for the `CSI u` forms, the event types and the
disambiguation flags. **xterm's `ctlseqs`** for `modifyOtherKeys`, the
legacy sequences, and the three mouse encodings. **tmux** and **vim**
for the escape-timeout number and for the observation that it is the
reader's decision and not the decoder's.

Deliberately left out, and where it went instead:

- **Bindings, chords, leader keys and modes.** A keymap in the editor
  sense is a program's configuration, and a package that shipped one
  would be shipping somebody's taste. What this package owes a program
  is an unambiguous value to look up.
- **Turning the protocols on.** Asking a terminal for bracketed paste
  or the kitty protocol means writing `CSI ? 2004 h` — the output
  direction, which is `ansi-nv`'s `seqwrite.set_mode`.
- **Reading, timing and raw mode.** All three are the host's:
  termios-nv for raw mode, and the program's own loop for the read.
- **Query replies.** They arrive on this stream and are reported as
  `KeyUnknownSequence`; `ansi-nv`'s `vtquery` is what reads them.

## Status

Every function is `todo()`. Two suites, both red, both for the same
reason — every assertion reaches `not implemented: keymap-nv.<fn>`,
which is the expected result until the bodies land.

```
novo test --isolate tests/keydecode_tests.nv   # the state machine, the ESC ambiguity included
novo test --isolate tests/surface_tests.nv     # the rest of the surface, called once each
```

`novo doc` renders and its four examples compile.
