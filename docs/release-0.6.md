# LSL 0.6

Lokální self-hosted vydání 0.6 navazuje na první veřejnou self-hosted verzi
0.5. V této fázi není nasazené na Netlify.

## Jazyk

- Mocnina používá `^`; původní `**` je syntaktická chyba.
- `^` zůstává pravostranně asociativní.
- `l"text {expression}"` je first-class interpolovaný String.
- `{{` a `}}` v Lux Stringu zapisují doslovné závorky.
- `printl "..."` zůstává zpětně kompatibilní.
- Celý modul lze aliasovat přes `load test as t`.

## Výkon

- Konstantní String concat se skládá při překladu.
- Mocniny s konstantním exponentem 0 až 4 se emitují inline.
- Lux String s více poli používá vyvážený concat strom.
- Stávající constant folding, dead-code elimination, immediate aritmetika,
  magic division a leaf-register emission zůstávají aktivní.

## CUDA

- Nový modul `cuda` implementuje operace devices, sum, dot, axpy a matmul.
- Tensor tyto operace směruje automaticky přes CUDA nebo CPU fallback.
- Politiky `auto`, `required`, `off` a velikostní práh lze řídit environmentem.
- Worker ABI je testované v samostatném procesu i bez NVIDIA GPU.

## Toolchain

- `lsl --version`, `lsl version` a `lsl --help` hlásí 0.6.
- Compiler zůstává bitově reprodukovatelný ve fixed pointu.
- Standardní instalace nyní obsahuje také `stdlib/cuda.lsl`.
