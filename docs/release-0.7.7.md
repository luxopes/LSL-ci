# LSL 0.7.7

LSL 0.7.7 rozšiřuje CUDA z jednorázových procesních kernelů na persistentní
výpočty s buffery na GPU. Compiler, CLI a host runtime zůstávají pure LSL,
statické Linux x86_64 PIE ELF bez libc a CUDA knihoven. Volitelný worker
v CUDA C++ zůstává explicitní procesovou hranicí.

## CUDA a Tensor

- `cuda.session()` drží jeden CUDA kontext a předává příkazy přímo po
  binárním Unix socketu. `upload`, `zeros`, `download`, `free` a `close`
  dávají aplikaci kontrolu nad přenosy a životností device paměti.
- Float64 buffery podporují sum, dot, AXPY, tiled matmul, add, subtract,
  multiply, divide, scale, fill, ReLU a transpozici. Mezivýsledky zůstávají
  na GPU. CPU session poskytuje stejné výsledky a rozhraní bez NVIDIA zařízení.
- `Tensor.to_device` a `DeviceTensor.to_host` propojují host a device data.
  DeviceTensor kontroluje tvary a nabízí numerické operace i sdílený reshape.
- `Tensor.sum`, `dot`, `axpy`, `matmul` a upload respektují offset a strides.
  Opraveny jsou necontiguous a prázdné pohledy, kontrola reshape a nulová
  vnitřní dimenze matmul.
- Výběr zařízení se předává přes izolované prázdné prostředí workeru;
  `set_device` invaliduje probe cache. Matmul porovnává velikosti polí
  odděleně od pracovních jednotek a plochý grid podporuje vysoké matice.
- Vadný binární výstup už nezpůsobí konverzi velkých polí do JSON. Legacy
  JSON se kontroluje před změnou dat aplikace. Binární transport zachovává
  signed zero, NaN a Infinity; numerické výsledky redukcí a FMA mají běžné
  rozdíly zaokrouhlení mezi CPU a GPU.

API, příklady, chyby a přesné limity jsou v [CUDA dokumentaci](cuda.md).
Kompletní příklad je [examples/cuda_session.lsl](../examples/cuda_session.lsl).

## Životnost a kompatibilita

ABI 1 a původní `sum_data`, `dot_data`, `axpy_data`, `matmul_data` zůstávají
dostupné s politikou `auto|required|off`. ABI 2 přidává privátní socket pro
jednoho klienta stejného UID, kontrolované session handly, limity celkového
počtu bufferů/paměti a 120sekundový limit příkazu. EOF uvolní device prostředky.
Session je vázaná na jedno host vlákno. Použití po free/close a míchání sessions
vyvolá chybu. U otevřené GPU session se chyby propagují i v `auto`, protože
host neuchovává kopie všech mezivýsledků.

Veřejný rozsah jsou dense Float64 operace uvedené v dokumentaci. Další dtype,
uživatelský CUDA C++ kód, sparse operace, autograd a kolektivní multi-GPU
operace nejsou součástí tohoto rozhraní.

Compiler navíc zachovává typ `self` při inferenci návratových hodnot metod,
stejně jako při generování kódu. Řetězení metod vracejících instanci funguje
i v programu, který vypnul call-site specializaci uniklým callbackem.

## Ověření a výkon

Ověřeno na NVIDIA GeForce GTX 1650 (CC 7.5), CUDA Runtime 13.3. Distribuovaný
worker používá `-arch=all-major`. CPU/GPU conformance porovnává stejné výstupy
pro numeriku, tvary, vlastnictví, prázdné buffery, nonfinite přenos a hranici
dvou milionů prvků. Testy pokrývají také vadné workery, chybný protokol,
neplatný výběr GPU, velký matmul, vysoký grid a bitově shodný self-host.

Medián pěti běhů 512×512: CPU 0,04325 s, persistentní CUDA včetně downloadu
0,02228 s (1,94×). Jednorázová inicializace a dva uploady 0,319 s. Každý
výsledek měl kontrolní součet 134217728; zdroj měření je
[cuda_session_benchmark.lsl](../tests/cuda_session_benchmark.lsl).

Plná sada vyžaduje 4 GiB virtuálního adresního prostoru kvůli staršímu
HTTP/GC stress testu, který používá přibližně 2,6 GiB. Jeho timeout klienta
je nyní 30 sekund a celý test má 180sekundový alarm, aby při chybě klienta
nezůstával neomezeně v accept. Sériové compiler buildy zůstávají pod 2 GiB.

SHA-256 compileru:
`5b5b3d89adf580e98fc7b042102b1489099ef44d22ddf46aa8686524947d9fa7`.
CLI: `ea86d1313917cec0e44ada41cdf534be96c17c363d41b09f5da67b5eaa6ee1ec`.
Worker: `e6822df1ceff1df15ab9b21502e1fb9a14038801638d0a0162b5ac8032c90016`.
