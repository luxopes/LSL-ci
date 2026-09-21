# Capability sandbox a paměťová bezpečnost v LSL 0.7

LSL 0.7 přidává dvě oddělené vrstvy: compilerovou `unsafe` hranici proti
náhodnému použití raw memory ABI a procesový `lsl sandbox` proti dopadu
nedůvěryhodného programu na hostitele. Ani jedna vrstva není náhradou za
bezpečný kernel a správně spravovaný host.

## Bezpečný překlad a `unsafe:`

`lsl`, stdin režim a `lsl compile` standardně odmítnou přímé `__lsl_*`,
`native_*` a `thread_spawn` operace mimo lexikální blok:

```lsl
unsafe:
    process_id = __lsl_syscall(39, 0, 0, 0, 0)
end
```

Bezpečný linker kontroluje také všechny uživatelské importy. Built-in stdlib
moduly jsou důvěryhodná část runtime a své privátní intrinsics používat mohou.
Direktiva `# lsl: unchecked-intarray` vyžaduje celý překlad
`lsl compile --unsafe SOURCE OUTPUT`, protože její efekt nelze omezit na blok.

`unsafe:` znamená pouze „autor zde ručně přebírá invarianty paměti a ABI“.
Není to try/catch a nemění oprávnění OS. Nízkoúrovňový vývojářský compiler
`lslc` zůstává explicitní trust-core nástroj a bezpečnostní policy CLI na něj
není aplikována.

## Spuštění v sandboxu

### Inicializace proměnných

Ve vydání 0.8.3 byla opravena memory-safety chyba: lokál přiřazený až
později dostal slot i statický typ, ale jeho dřívější čtení používalo obsah
zásobníku. Referenční typ tak mohl způsobit SIGSEGV i bez `unsafe`.

Compiler nyní před generováním kódu provádí definite-assignment analýzu
včetně větví, návratů, smyček, výjimek a `del`. Porušení odmítne E2002 v
režimu spuštění i při `lsl compile`; `safe` neopravuje neplatný tok programu.
Lokály nepotřebují nulování ani běhové příznaky. Čtení globálů z funkcí
navíc kontroluje inicializační příznak v místě čtení, protože funkce nebo
callback může být zavolán před inicializací modulu. Chyba je `NameError`
zachytitelný v `safe`/`try`. To nepředstavuje důkaz absence jiných chyb
compileru ani synchronizaci sdílených dat mezi vlákny.

### Procesové spuštění

```text
lsl sandbox program.lsl
lsl sandbox --timeout 10 --memory 536870912 program.lsl arg1
lsl sandbox --read model.bin --read prompt.txt program.lsl
lsl sandbox --write results program.lsl
lsl sandbox --profile server web-worker.lsl
```

`--read PATH` zpřístupňuje kanonizovanou host cestu read-only jako
`/input/0`, `/input/1`, …; `--write PATH` ji bind-mountne jako `/output/N`.
Program si cesty může sestavit přes `sandbox.input_path(n)` a
`sandbox.output_path(n)`.

Výchozí `strict` profil má vlastní user, mount, PID, IPC, UTS, cgroup a network
namespace. Profil `server` jako jedinou výjimku sdílí host network namespace,
aby se mohl bindnout na TCP port. Oba profily:

- mají prázdný tmpfs root, minimální `/proc` a `/dev`, read-only program a
  privátní `/tmp`;
- zahazují capabilities, zakazují vytváření dalších user namespaces, používají
  `no_new_privs`, nové session a parent-death vazbu;
- předávají programu čisté prostředí pouze s `LSL_SANDBOX=1` a názvem profilu;
- používají systemd user cgroup `TasksMax=64`, `MemoryMax` a `MemorySwapMax=0`;
- navíc nastaví wall/CPU timeout, `RLIMIT_AS`, nulové core dumpy, limit výstupního
  souboru, descriptorů a stacku.

Výchozí timeout je 30 s a address-space limit 1 GiB. Povolený rozsah je
1–3600 s a 64 MiB–8 GiB.

Sandbox vyžaduje Linux s `bubblewrap`, systemd user session, `timeout`,
`prlimit`, `realpath` a `env`. Chybějící vrstva způsobí chybu; příkaz nespadne
do neizolovaného režimu. Sandbox compiler navíc odmítá každý `unsafe:` blok a
unchecked IntArray direktivu.

## API z programu

```lsl
load sandbox

policy = {
    "profile": "strict",
    "timeout": 15,
    "memory": 536870912,
    "read": ["input.json"],
    "write": ["results"]
}
status = sandbox.run("./worker", ["job-1"], policy)
```

`sandbox.is_active()` zjistí, zda aktuální proces běží uvnitř sandboxu, a
`sandbox.profile()` vrátí `strict`, `server`, nebo `None` mimo sandbox.

Explicitně udělený writable bind je skutečná host capability a program jej
může libovolně měnit. `server` profil má skutečný síťový přístup. Do sandboxu
proto dávejte jen minimální cesty, žádné secrets, root filesystem ani socket
control plane.
