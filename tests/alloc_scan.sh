#!/usr/bin/env bash
# tests/alloc_scan.sh — nothing on the path a device drives allocates,
# as a check that can fail.
#
# `keymodel`, `mousedecode` and `keydecode` are the three modules a
# device build reaches.  What makes them usable there is not that they
# avoid a list, which the compiler decides at the embedded tier, but
# that they put nothing on the heap at all.  Nothing in the language
# enforces that on a host build, and the emitted LLVM is where it is
# true or false, so this reads it.
#
# There are three runs, because a check that cannot fail is not a check.
#
#   1. Every function of the three modules appears in the IR of
#      `tests/alloc_probe.nv` at `--opt=0`, and none of them calls the
#      allocator, directly or through a runtime entry point that
#      allocates on the caller's behalf.
#   2. The scan still sees an allocation.  A heap list literal is
#      spliced into `keymodel.mods_of` on a copy of the tree, and the
#      scan has to name it.  Without this run, a scan that quietly
#      stopped matching would pass forever.
#   3. The device build still refuses the same splice.  A tier check
#      that stopped being enforced looks exactly like one that passes.
#
# The reading of the IR is `tests/alloc_scan.py`, a file of its own
# rather than a here-document.  It is run twice, on two different IR
# files, and it holds the two things a maintainer edits: the runtime
# entry points that put a cell on the heap on the caller's behalf, and
# how many functions the three modules hold.  It takes one path and can
# be run by hand on any emitted `.ll`.
#
# Run from anywhere:  bash tests/alloc_scan.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"
NOVO="${NOVO:-$HOME/.novo/bin/novo}"
SCAN="$HERE/alloc_scan.py"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/      /'; FAIL=$((FAIL + 1)); }

echo ""
echo "════════════════════════════════════════════════"
echo "  keymap-nv — the decoder puts nothing on the heap"
echo "════════════════════════════════════════════════"

[ -x "$NOVO" ] || { fail "novo present at $NOVO"; echo "pass=$PASS fail=$FAIL"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/keymap-nv-alloc.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# The splice is a heap list literal bound in `mods_of`, and read, so it
# cannot be folded away.  `mods_of` is on the path of every modified
# sequence, so both the probe and the device build reach it.
splice() {  # splice <src/keymodel.nv>
  python3 - "$1" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
anchor = ("pub fn mods_of(param: Int) -> KeyMods\n"
          "    if param < 2\n"
          "        return no_mods()\n")
if anchor not in s:
    sys.exit("anchor not found — alloc_scan.sh's splice is measuring nothing")
new = ("pub fn mods_of(param: Int) -> KeyMods\n"
       "    let probe = [1, 2, 3]\n"
       "    if param < 2 or probe[0] > 99\n"
       "        return no_mods()\n")
open(path, 'w').write(s.replace(anchor, new))
PY
}

build_probe() {  # build_probe <tree>
  ( cd "$1" && NOVO_LEAK_CHECK=0 timeout 900 "$NOVO" build --opt=0 \
      -o "$1/probe.bin" tests/alloc_probe.nv ) >"$1/build.log" 2>&1
}

build_device() {  # build_device <tree>
  ( cd "$1" && timeout 900 "$NOVO" build --target=nrf52-qemu \
      -o "$1/probe.elf" tests/embedded_probe.nv ) >"$1/device.log" 2>&1
}

# ── 1. nothing the decoder does allocates ────────────────────────────

cp -r "$PKG" "$WORK/ok" 2>/dev/null
rm -rf "$WORK/ok/_novo"
if build_probe "$WORK/ok"; then
  IR="$WORK/ok/_novo/alloc_probe.ll"
  if [ -s "$IR" ]; then
    report="$(python3 "$SCAN" "$IR")"
    if [ "${report#OK}" != "$report" ]; then
      pass "nothing on the decoder's path allocates — ${report#OK }"
    else
      fail "nothing on the decoder's path allocates" "${report#FAIL }"
    fi
  else
    fail "nothing on the decoder's path allocates" "no _novo/alloc_probe.ll emitted"
  fi
else
  fail "the allocation probe builds" "$(grep -E 'error' "$WORK/ok/build.log" | head -5)"
fi

# ── 2. the scan still sees an allocation ─────────────────────────────

cp -r "$PKG" "$WORK/neg" 2>/dev/null
rm -rf "$WORK/neg/_novo"
if splice "$WORK/neg/src/keymodel.nv" >"$WORK/splice.log" 2>&1 \
   && build_probe "$WORK/neg"; then
  neg="$(python3 "$SCAN" "$WORK/neg/_novo/alloc_probe.ll")"
  if [ "${neg#FAIL}" != "$neg" ] && printf '%s' "$neg" | grep -q 'mods_of'; then
    pass "the scan still sees an allocation spliced into the model"
  else
    fail "the scan still sees an allocation spliced into the model" \
         "expected a finding naming mods_of; got: $neg"
  fi
else
  fail "the negative control builds" \
       "$(cat "$WORK/splice.log"; grep -E 'error' "$WORK/neg/build.log" | head -5)"
fi

# ── 3. the device build still refuses the splice ─────────────────────

cp -r "$PKG" "$WORK/tier" 2>/dev/null
rm -rf "$WORK/tier/_novo"
splice "$WORK/tier/src/keymodel.nv" >"$WORK/tsplice.log" 2>&1
if build_device "$WORK/tier"; then
  fail "the embedded tier still refuses a heap list literal" \
       "the device build succeeded with a list literal in keymodel.mods_of"
else
  pass "the embedded tier still refuses a heap list literal in the model"
fi

echo ""
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
