#!/usr/bin/env python3
"""Vygeneruje moduly platformy pro Linux s obecnou tabulkou systémových
volání (arm64, riscv64) z modulu x86_64 a z hlaviček jádra
dané architektury (<triplet>/asm/unistd_64.h, včetně podmíněných volání
jako renameat). Volání, která architektura nemá (open, stat, fork, dup2,
poll, …), dostanou hodnotu -1; runtime ani knihovny je nesmí volat.

Použití: gen_linux_generic.py [--include /usr/include]
"""
import argparse, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[2]
ALIAS = {}
# Rozdíly proti x86_64 (obecné struktury jádra, fcntl, signály).
GENERIC = {
    'STAT_BYTES': 128, 'STAT_MODE': 16, 'STAT_NLINK': 20, 'STAT_NLINK_BYTES': 4, 'STAT_UID': 24, 'STAT_SIZE': 48,
}
ARCH = {
    'arm64': {'NAME': '"linux-arm64"', 'RUNTIME': '"lsl-runtime-linux-arm64-v1"', 'ELF_MACHINE': 183,
              'O_DIRECTORY': 16384, 'O_NOFOLLOW': 32768},
    'riscv64': {'NAME': '"linux-riscv64"', 'RUNTIME': '"lsl-runtime-linux-riscv64-v1"', 'ELF_MACHINE': 243,
                # Bez SA_RESTORER: jádro vrací ze signálu přes vDSO; struct
                # sigaction nemá pole restorer.
                'SA_RESTORER': 0, 'SIGACTION_BYTES': 24, 'SIGACTION_RESTORER': -1, 'SIGACTION_MASK': 16},
}

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--include', default='/usr/include')
    a = ap.parse_args()
    source = (ROOT / 'stdlib/_platform_linux_x86_64.lsl').read_text().splitlines()
    for arch, overrides in ARCH.items():
        triplet = {'arm64': 'aarch64-linux-gnu', 'riscv64': 'riscv64-linux-gnu'}[arch]
        header = pathlib.Path(a.include) / triplet / 'asm/unistd_64.h'
        table = {m.group(1): int(m.group(2)) for m in
                 re.finditer(r'#define __NR_(\w+)\s+(\d+)', header.read_text())}
        out = [f'# Linux {arch}: čísla syscallů (obecná tabulka jádra), konstanty a rozložení',
               '# kernelových struktur. Generováno tools/platform/gen_linux_generic.py.', '']
        for line in source[2:]:
            m = re.match(r'^(\w+) = (.*)$', line)
            if not m:
                if line.startswith('#') or not line.strip():
                    out.append(line)
                continue
            name, value = m.groups()
            if name.startswith('SYS_'):
                key = ALIAS.get(name[4:], name[4:].lower())
                # Volání, které architektura nemá: -1 (jádro vrátí ENOSYS);
                # jméno zůstává kvůli veřejným konstantám modulů.
                value = str(table.get(key, -1))
            elif name in overrides:
                value = str(overrides[name])
            elif name in GENERIC:
                value = str(GENERIC[name])
            elif name == 'ARCH_SET_FS':
                value = '-1'  # arch_prctl je jen na x86_64
            out.append(f'{name} = {value}')
        (ROOT / f'stdlib/_platform_linux_{arch}.lsl').write_text('\n'.join(out) + '\n')
        print(arch, sum(1 for l in out if l.startswith('SYS_') and not l.endswith('= -1')), 'syscalls')

if __name__ == '__main__':
    main()
