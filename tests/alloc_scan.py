#!/usr/bin/env python3
"""Read the emitted LLVM for keymap-nv's allocation probe and say
whether any function in `keymodel`, `mousedecode` or `keydecode` can put
a cell on the heap.

Run by tests/alloc_scan.sh twice: once on the package as it stands, and
once on a copy with an allocation spliced into the model.  That copy is
what the scan has to catch, because a check that cannot fail is not a
check.

The IR is emitted at `--opt=0` on purpose.  At the default optimisation
level the whole probe inlines into `novo_main`, there is no function
left to attribute an allocation to, and the scan would pass over an
empty file.
"""
import re
import sys

# Every way a function can put a cell on the heap.  `novo_alloc*` is the
# direct one.  The other four allocate inside the runtime, so a search
# for the first alone would call a per-byte boxing loop allocation-free.
# `novo_str_byte_at` reaches `novo_some_int`, which reaches
# `novo_alloc_atomic`, and none of that is visible in the caller's IR.
BOXERS = ['novo_alloc', 'novo_some_int', 'novo_some_float',
          'novo_str_byte_at(', 'novo_bytes_byte_at(']

# `keychunk` is not matched.  It allocates, which is what it is for: a
# list of events out of a chunk.  The three modules a device build
# reaches are the ones this scan is about.
CORE = re.compile(r'^novo_user_(keydecode|keymodel|mousedecode)_')

FNS = re.compile(r'^define[^\n]*?@([A-Za-z0-9_.]+)\([^\n]*\{\n(.*?)\n\}',
                 re.S | re.M)

# The three modules hold 109 functions between them and the probe
# reaches every one.  Fewer than this in the IR means the probe or the
# name scheme moved, and that the scan is measuring nothing.
FLOOR = 109


def main(path):
    src = open(path).read()
    seen, offenders = 0, []
    for m in FNS.finditer(src):
        name, body = m.group(1), m.group(2)
        if not CORE.match(name):
            continue
        seen += 1
        for boxer in BOXERS:
            if 'call' in body and ('@' + boxer) in body:
                offenders.append('%s: %s' % (name, boxer.rstrip('(')))
    if seen < FLOOR:
        print('FAIL only %d decoder function(s) in the IR, expected at least '
              '%d — the probe or the name scheme moved, and this check was '
              'measuring nothing' % (seen, FLOOR))
    elif offenders:
        print('FAIL ' + '; '.join(sorted(set(offenders))))
    else:
        print('OK %d function(s) across keymodel, mousedecode and keydecode, '
              'zero heap cells' % seen)


if __name__ == '__main__':
    main(sys.argv[1])
