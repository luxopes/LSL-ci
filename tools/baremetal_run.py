#!/usr/bin/env python3
"""Spustí program LSL pro baremetal-riscv64 v qemu (deska virt, M-mód):
python3 tools/baremetal_run.py PROGRAM [ARGUMENTY...]

Vstup a výstup jde přes semihosting: stdin, stdout a stderr tohoto procesu,
soubory hostitele (relativně k aktuálnímu adresáři) a návratový kód
programu. Argumenty program dostane oddělené mezerami (semihosting předává
jeden řádek), mezera uvnitř argumentu se tedy nezachová.
"""
import os
import sys

QEMU = os.environ.get('LSL_QEMU_RISCV64', 'qemu-system-riscv64')


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    program, arguments = sys.argv[1], sys.argv[2:]
    config = 'enable=on,target=native'
    for argument in [os.path.basename(program), *arguments]:
        # Čárka odděluje volby qemu; zdvojená je doslovná.
        config += ',arg=' + argument.replace(',', ',,')
    # CPU s Zkr (CSR seed jako zdroj entropie).
    # 4 harty: vlákna běží paralelně (preemptivní plánovač runtime).
    command = [QEMU, '-M', 'virt', '-smp', os.environ.get('LSL_QEMU_SMP', '4'), '-cpu', 'rv64,zkr=true', '-m', os.environ.get('LSL_QEMU_MEMORY', '1G'), '-bios', 'none',
               '-display', 'none', '-serial', 'null', '-monitor', 'none',
               '-semihosting-config', config, '-kernel', program]
    os.execvp(command[0], command)


if __name__ == '__main__':
    main()
