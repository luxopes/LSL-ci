#!/usr/bin/env python3
"""Compare the QBE C public-header LP64 layouts with the Python type engine.

The oracle is the host C compiler: this emits a temporary translation unit
including the vendored all.h, asks cc for sizeof/_Alignof/offsetof and checks
the results against c_types.Types. No generated project files are changed.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import inventory
from c_types import Types
from pycparser import c_ast


def main():
    header = ROOT / 'vendor/qbe-1.3/all.h'
    include = Path(__file__).resolve().parent / 'include'
    with tempfile.TemporaryDirectory(prefix='qbe-layout-') as td:
        td = Path(td)
        src = td / 'layout.c'
        extras = '''\nstruct Vec {\n\tulong mag; Pool pool; size_t esz; ulong cap;\n\tunion { long long ll; long double ld; void *ptr; } align[];\n};\ntypedef long double LayoutLongDouble;\n'''
        src.write_text('#include "all.h"\n' + extras)
        pre = subprocess.run(['cc', '-E', '-std=c99', '-nostdinc',
            '-I', str(include), '-I', str(header.parent),
            '-D__attribute__(x)=', str(src)], check=True, text=True,
            capture_output=True).stdout
        # The same parser normalization used by the production inventory.
        import re
        pre = re.sub(r'(\([A-Za-z_][^;\n{}]*\[[^\n{}]*\]\)\{[^{}]+\})(?=\[)', r'(\1)', pre)
        ast = inventory.c_parser.CParser().parse(pre, filename=str(header))
        types = Types()
        tags = {}
        typedefs = []
        for node in ast.ext:
            if isinstance(node, (c_ast.Typedef, c_ast.Decl)):
                types.declaration(node)
                if isinstance(node, c_ast.Typedef):
                    typedefs.append(node.name)
            # Collect definitions including anonymous typedef targets.
            class Gather(c_ast.NodeVisitor):
                def visit_Struct(self, n):
                    if n.name and n.decls is not None:
                        tags[('struct', n.name)] = n
                    self.generic_visit(n)
                def visit_Union(self, n):
                    if n.name and n.decls is not None:
                        tags[('union', n.name)] = n
                    self.generic_visit(n)
            Gather().visit(node)

        checks = []
        lines = ['#include <stddef.h>', '#include <stdio.h>', '#include "all.h"', extras,
                 'typedef char require_lp64[(sizeof(long)==8 && sizeof(void*)==8)?1:-1];',
                 'int main(void) {']
        for kind, name in sorted(tags):
            tag = f'{kind} {name}'
            label = f'{kind}_{name}'
            lines += [f'printf("T {label} %zu %zu\\n", sizeof({tag}), _Alignof({tag}));']
            node = tags[(kind, name)]
            for field in node.decls or []:
                if field.name and field.bitsize is None:
                    lines += [f'printf("F {kind}_{name} {field.name} %zu\\n", offsetof({tag}, {field.name}));']
        # Public typedefs are checked for size and alignment too; function
        # typedefs are not object types and are excluded by C's sizeof rules.
        for name in sorted(set(typedefs)):
            t = types.aliases.get(name)
            if t and t.kind != 'function' and not (t.kind in ('struct', 'union') and not t.defined):
                lines += [f'printf("Y {name} %zu %zu\\n", sizeof({name}), _Alignof({name}));']
        # Ref bitfield allocation is implementation-defined, so compare the
        # actual bytes from designated initializers against field bit offsets.
        lines += ['{ Ref r = {.type=5, .val=0x1234567}; unsigned char *p=(unsigned char *)&r; printf("B Ref"); for (size_t i=0;i<sizeof r;i++) printf(" %02x", p[i]); puts(""); }', 'return 0;', '}']
        cfile = td / 'oracle.c'
        cfile.write_text('\n'.join(lines) + '\n')
        exe = td / 'oracle'
        subprocess.run(['cc', '-std=c11', '-fno-builtin', '-I', str(include), '-I', str(header.parent), str(cfile), '-o', str(exe)], check=True)
        output = subprocess.run([str(exe)], check=True, text=True, capture_output=True).stdout

    actual = {}
    ref_bytes = None
    for line in output.splitlines():
        a = line.split()
        if a[0] == 'B':
            ref_bytes = bytes.fromhex(''.join(a[2:]))
        elif a[0] == 'F':
            actual[('field', *a[1].split('_', 1), a[2])] = int(a[3])
        else:
            actual[(a[0], a[1])] = (int(a[2]), int(a[3]))
    errors = []
    for key, node in tags.items():
        kind, name = key
        t = types.tags.get((kind, name))
        if t is None:
            errors.append(f'missing parsed tag {kind} {name}')
            continue
        size, align = actual[('T', f'{kind}_{name}')]
        if (t.size, t.align) != (size, align):
            errors.append(f'{kind} {name}: engine size/align {t.size}/{t.align}, cc {size}/{align}')
        for f in t.fields:
            if f.width is None and f.name:
                off = actual.get(('field', kind, name, f.name))
                if off is not None and f.offset != off:
                    errors.append(f'{kind} {name}.{f.name}: engine offset {f.offset}, cc {off}')
    for name in sorted(set(typedefs)):
        t = types.aliases.get(name)
        if not t or t.kind == 'function' or (t.kind in ('struct', 'union') and not t.defined):
            continue
        size, align = actual[('Y', name)]
        if (t.size, t.align) != (size, align):
            errors.append(f'typedef {name}: engine size/align {t.size}/{t.align}, cc {size}/{align}')
    ref = types.tags.get(('struct', 'Ref'))
    if ref and ref_bytes is not None:
        # LP64 little endian is required by this port. Verify the bit offsets
        # reported by the engine against the compiler-generated object bytes.
        observed = int.from_bytes(ref_bytes[:4], 'little')
        for f in ref.fields:
            mask = (1 << (f.width or 0)) - 1
            value = (observed >> f.bit) & mask
            expected = 5 if f.name == 'type' else 0x1234567 if f.name == 'val' else 0
            if value != expected:
                errors.append(f'Ref.{f.name}: engine bit offset {f.bit} decodes {value:#x}, C object gives {expected:#x}')
    print(f'checked {len(tags)} struct/union tags (including util Vec), {len(set(typedefs))-1} all.h typedefs, long-double alignment, Ref bitfield bytes')
    if errors:
        print('\n'.join(errors))
        return 1
    print('LP64 C layouts match c_types.Types')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
