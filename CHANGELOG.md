# Changelog

All notable changes to keymap-nv are recorded here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the pre-1.0 rule that a breaking change bumps the MINOR number.

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
