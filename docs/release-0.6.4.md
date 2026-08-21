# LSL 0.6.4

LSL 0.6.4 přidává sdílená vlákna a ruční SSE2 vektorizaci FloatArray kernelů.
`thread_spawn(function)` spustí funkci bez parametrů jako worker se sdílenou
pamětí (Linux `clone` s `CLONE_VM|CLONE_THREAD|CLONE_CHILD_CLEARTID`, 8 MiB
mmap zásobník, až 127 současných workerů) a vrátí jeho tid; `thread_join(tid)`
na něj počká. Sdílené čítače a zámky pokrývají builtiny `atomic_add`,
`atomic_xchg`, `atomic_cas` a `atomic_pause` nad sloty `IntArray`.

Allokátor je chráněn tříhodnotovým futex mutexem, který se zapne až prvním
`thread_spawn`; jednovláknové programy platí jen načtení příznaku. `gc()` smí
volat pouze hlavní vlákno: zastaví workery signálem `SIGUSR1`, konzervativně
projde jejich živé zásobníky včetně registrů uložených v signal frame a po
sweepu je probudí přes futex gate.

Kernely `float_sum`, `float_dot`, `float_axpy`, `float_fill` a `float_matmul`
pracují nad dvěma SSE2 lane se skalárním ocasem. `float_matmul` běží v pořadí
i-k-j s vysíláním `A[i,k]` do obou lane a je bitově shodný se skalární verzí;
256×256 násobení je přibližně 4,5× rychlejší. `float_sum` a `float_dot`
sčítají sudé a liché prvky v oddělených akumulátorech.

Čistě výpočetní práce rozdělená mezi čtyři workery běžela na stejném stroji
přibližně 4× rychleji než v jednom vláknu. Compiler, runtime i výsledné
programy zůstávají pure LSL a výstupem je statický syscall-only Linux x86_64
ELF; self-hostovaný compiler je bitově reprodukovatelný ve fixed pointu.
