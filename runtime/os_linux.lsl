# lsl: runtime
# Vrstva OS pro Linux: jediné místo runtime se systémovými voláními Linuxu.
# Používá jen volání, která mají x86_64, arm64 i rv64 (openat místo open,
# pipe2, dup3, clone místo fork…); čísla dodá modul platformy cíle.
# Výsledek je surový výsledek jádra (záporné errno při chybě). Na 32bitových
# cílech (WORD_BYTES 4) se ukazatele ve strukturách jádra zapisují jako
# 32bitová slova a blok argumentů procesu se převede na 64bitová slova.
load _platform as platform

# Krok procházení kořenů GC (zásobníky, registry): kód pro 32bitový cíl
# smí uložit jen dolní půlku ukazatele, proto se tam čte po 4 bajtech.
ROOT_WORD_BYTES = platform.WORD_BYTES

# Značka adres haldy na 32bitových cílech: objekty mají v LSL adresu
# s bitem 40 (paměť i jádro vidí jen dolních 32 bitů), takže se celé číslo
# nespletete s adresou objektu ani v rozsahu 2^31..2^32 (32bitová slova
# SHA-256, mezivýsledky aritmetiky). 64bitové cíle mají haldu tak vysoko
# samy.
HEAP_ADDRESS_TAG = platform.HEAP_ADDRESS_TAG

# Slovo ukazatele ve struktuře jádra (šířka podle cíle).
function store_word(address, value):
    if platform.WORD_BYTES == 4:
        __lsl_qbe_store32(address, value)
    else:
        __lsl_qbe_store64(address, value)
    end
    return 0
end

function syscall6(number, a, b, c, d, e, f):
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, b, c, d, e, f)
end

function syscall3(number, a, b, c):
    return __lsl_qbe_call4(__lsl_symbol("lsl_arch_syscall3"), number, a, b, c)
end

# Soubory a paměť. Výsledek je hodnota jádra, chyba je záporné errno.
function openat(directory, path, flags, mode):
    return syscall6(platform.SYS_OPENAT, directory, path, flags, mode, 0, 0)
end

function lseek(descriptor, offset, whence):
    return syscall3(platform.SYS_LSEEK, descriptor, offset, whence)
end

function read(descriptor, buffer, count):
    return syscall3(platform.SYS_READ, descriptor, buffer, count)
end

function close(descriptor):
    return syscall3(platform.SYS_CLOSE, descriptor, 0, 0)
end

# 32bitový ARM: mmap2 bere posun ve 4KiB stránkách.
function mmap(address, length, protection, flags, descriptor, offset):
    return syscall6(platform.SYS_MMAP, address, length, protection, flags, descriptor, __lsl_qbe_lshr(offset, platform.MMAP_OFFSET_SHIFT))
end

function mprotect(address, length, protection):
    return syscall3(platform.SYS_MPROTECT, address, length, protection)
end

function munmap(address, length):
    return syscall3(platform.SYS_MUNMAP, address, length, 0)
end

# Procesy a deskriptory.
function pipe2(fds, flags):
    return syscall3(platform.SYS_PIPE2, fds, flags, 0)
end

# fork přes clone (arm64 ani rv64 fork nemají): v dítěti 0, v rodiči pid.
function fork():
    return syscall6(platform.SYS_CLONE, platform.SIGCHLD, 0, 0, 0, 0, 0)
end

function dup3(old, new, flags):
    return syscall3(platform.SYS_DUP3, old, new, flags)
end

function close_range(first, last, flags):
    return syscall3(platform.SYS_CLOSE_RANGE, first, last, flags)
end

function wait4(pid, status, options):
    return syscall6(platform.SYS_WAIT4, pid, status, options, 0, 0, 0)
end

function prctl(option, argument):
    return syscall6(platform.SYS_PRCTL, option, argument, 0, 0, 0, 0)
end

# Ukončí volající vlákno (exit, ne exit_group: povolí ho i strict seccomp).
function exit_thread(status):
    return syscall3(platform.SYS_EXIT, status, 0, 0)
end

# SIGALRM za seconds sekund (alarm přes setitimer, arm64 ani rv64 alarm nemají).
function alarm(seconds):
    timer = __lsl_qbe_alloc(platform.ITIMERVAL_BYTES)
    __lsl_qbe_zero(timer, 32)
    __lsl_qbe_store64(timer + platform.ITIMERVAL_VALUE_SECONDS, seconds)
    return syscall3(platform.SYS_SETITIMER, platform.ITIMER_REAL, timer, 0)
end

function syscall4(number, a, b, c, d):
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, b, c, d, 0, 0)
end

# Soubory: cesta je C řetězec (adresa bajtů zakončených nulou).
function open(path, flags, mode):
    return syscall4(platform.SYS_OPENAT, platform.AT_FDCWD, path, flags, mode)
end

function write(fd, buffer, count):
    return syscall3(platform.SYS_WRITE, fd, buffer, count)
end

# 32bitové cíle: 64bitový posun jako dvojice slov (1 = ARM EABI s výplní,
# pár r4:r5; 2 = i386, esi:edi bez výplně).
function pread(fd, buffer, count, offset):
    if platform.PREAD64_PAIR == 1:
        return syscall6(platform.SYS_PREAD64, fd, buffer, count, 0, offset & 4294967295, __lsl_qbe_lshr(offset, 32))
    elif platform.PREAD64_PAIR == 2:
        return syscall6(platform.SYS_PREAD64, fd, buffer, count, offset & 4294967295, __lsl_qbe_lshr(offset, 32), 0)
    end
    return syscall4(platform.SYS_PREAD64, fd, buffer, count, offset)
end

function ioctl(fd, request, argument):
    return syscall3(platform.SYS_IOCTL, fd, request, argument)
end

# Druh souboru deskriptoru (S_IFMT >> 12: 8 soubor, 1 roura, 2 znakové
# zařízení), nebo záporné errno. fstat jako newfstatat(fd, "", AT_EMPTY_PATH).
function file_kind(fd):
    status = __lsl_qbe_alloc(platform.STAT_BYTES + 8)
    # Prázdná cesta: nulový bajt za strukturou.
    empty = status + platform.STAT_BYTES
    __lsl_qbe_store64(empty, 0)
    result = syscall4(platform.SYS_NEWFSTATAT, fd, empty, status, platform.AT_EMPTY_PATH)
    if result < 0:
        return result
    end
    return __lsl_qbe_lshr(__lsl_qbe_load32(status + platform.STAT_MODE), 12) & 15
end

# Úspěch ioctl(TCGETS) pozná terminál bez libc.
function is_terminal(fd):
    termios = __lsl_qbe_alloc(64)
    return syscall3(platform.SYS_IOCTL, fd, platform.TCGETS, termios) >= 0
end

function make_directory(path, mode):
    return syscall3(platform.SYS_MKDIRAT, platform.AT_FDCWD, path, mode)
end

function remove_file(path):
    return syscall3(platform.SYS_UNLINKAT, platform.AT_FDCWD, path, 0)
end

function remove_directory(path):
    return syscall3(platform.SYS_UNLINKAT, platform.AT_FDCWD, path, platform.AT_REMOVEDIR)
end

# Přejmenování bez přepsání cíle (renameat2, RENAME_NOREPLACE).
function rename_path(source, destination):
    return syscall6(platform.SYS_RENAMEAT2, platform.AT_FDCWD, source, platform.AT_FDCWD, destination, 1, 0)
end

# 0, když cesta existuje (F_OK).
function access(path):
    return syscall4(platform.SYS_FACCESSAT, platform.AT_FDCWD, path, 0, 0)
end

function socket(domain, kind, protocol):
    return syscall3(platform.SYS_SOCKET, domain, kind, protocol)
end

function connect(fd, address, length):
    return syscall3(platform.SYS_CONNECT, fd, address, length)
end

# Paměť: adresa, nebo záporné errno.
function map_shared(fd, length, offset):
    return mmap(0, length, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_SHARED, fd, offset)
end

function unmap(address, length):
    return syscall3(platform.SYS_MUNMAP, address, length, 0)
end

# Ukončí celý proces (všechna vlákna).
function exit_process(status):
    return syscall3(platform.SYS_EXIT_GROUP, status, 0, 0)
end

# Anonymní paměť přesně na adrese address, bez přepsání existujícího
# mapování: 1 = hotovo, 0 = místo je obsazené. Jádra před 4.17 příznak
# NOREPLACE neznají a berou adresu jen jako nápovědu, proto se výsledek
# vždy porovná a jinde vytvořené mapování se vrátí.
function map_at(address, size):
    if platform.WORD_BYTES == 4:
        address = address & 4294967295
    end
    result = syscall6(platform.SYS_MMAP, address, size, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_PRIVATE | platform.MAP_ANONYMOUS | platform.MAP_FIXED_NOREPLACE, -1, 0)
    if result == address:
        return 1
    end
    if result >= 0:
        call munmap(result, size)
    end
    return 0
end

# Anonymní soukromé mapování paměti (čtení a zápis); záporné = chyba.
function map_anonymous(size, extra_flags):
    return syscall6(platform.SYS_MMAP, 0, size, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_PRIVATE | platform.MAP_ANONYMOUS | extra_flags, -1, 0)
end

function futex_wait(address, expected):
    return syscall6(platform.SYS_FUTEX, address, platform.FUTEX_WAIT, expected, 0, 0, 0)
end

function futex_wake(address, count):
    return syscall6(platform.SYS_FUTEX, address, platform.FUTEX_WAKE, count, 0, 0, 0)
end

function getpid():
    return syscall3(platform.SYS_GETPID, 0, 0, 0)
end

function tgkill(process, thread, signal):
    return syscall3(platform.SYS_TGKILL, process, thread, signal)
end

function sched_yield():
    return syscall3(platform.SYS_SCHED_YIELD, 0, 0, 0)
end

function syscall1(number, a):
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), number, a, 0, 0, 0, 0, 0)
end

function os_read(fd, buffer, count):
    return syscall3(platform.SYS_READ, fd, buffer, count)
end

function os_close(fd):
    return syscall1(platform.SYS_CLOSE, fd)
end

function os_lseek(fd, offset, whence):
    return syscall3(platform.SYS_LSEEK, fd, offset, whence)
end

# Zapíše všechny bajty (částečné zápisy, EINTR znovu); 0, nebo -1 při chybě.
function os_write_all(fd, buffer, count):
    while count > 0:
        written = write(fd, buffer, count)
        if written > 0:
            buffer += written
            count -= written
        elif written != -platform.EINTR:
            return -1
        end
    end
    return 0
end

# Anonymní soubor v paměti s O_CLOEXEC (stderr a stdin pro capture).
function os_memfd(name):
    return syscall3(platform.SYS_MEMFD_CREATE, name + 16, platform.MFD_CLOEXEC, 0)
end

# Roura s O_CLOEXEC: fds dostane dvě 32bitová čísla (čtení, zápis).
function os_pipe(fds):
    return syscall3(platform.SYS_PIPE2, fds, platform.O_CLOEXEC, 0)
end

# timespec (sekundy, nanosekundy) hodin CLOCK_MONOTONIC nebo CLOCK_REALTIME.
function os_clock_gettime(clock, timespec):
    return syscall3(platform.SYS_CLOCK_GETTIME, clock, timespec, 0)
end

# 32bitové cíle bez nanosleep s 64bitovým časem: clock_nanosleep_time64.
function os_nanosleep(request, remaining):
    if platform.NANOSLEEP_CLOCK:
        return syscall6(platform.SYS_NANOSLEEP, platform.CLOCK_MONOTONIC, 0, request, remaining, 0, 0)
    end
    return syscall3(platform.SYS_NANOSLEEP, request, remaining, 0)
end

# Cesta ke spuštěnému programu (bez NUL), délka nebo záporná chyba.
function os_executable_path(buffer, size):
    name = __lsl_address("/proc/self/exe") + 16
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_READLINKAT, platform.AT_FDCWD, name, buffer, size, 0, 0)
end

# Prostředí procesu: pole ukazatelů na "JMÉNO=hodnota" zakončené nulou. Leží
# na původním zásobníku procesu (stav +120) za argc a argv s nulou.
function os_environment():
    stack = __lsl_qbe_load64(__lsl_qbe_load64(__lsl_symbol("lsl_state")) + 120)
    return stack + __lsl_qbe_shl(__lsl_qbe_load64(stack) + 2, 3)
end

# RLIMIT_NOFILE na limit (test vyčerpání deskriptorů).
function os_limit_descriptors(limit):
    rlimit = __lsl_qbe_alloc(16)
    __lsl_qbe_store64(rlimit, limit)
    __lsl_qbe_store64(rlimit + 8, limit)
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_PRLIMIT64, 0, platform.RLIMIT_NOFILE, rlimit, 0, 0, 0)
end

# Výsledek čekání na potomka: kód ukončení, nebo 128 + číslo signálu;
# záporná chyba wait4 (EINTR se opakuje).
function os_wait(pid):
    status = __lsl_qbe_alloc(8)
    while True:
        __lsl_qbe_store64(status, 0)
        result = __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_WAIT4, pid, status, 0, 0, 0, 0)
        if result != -platform.EINTR:
            break
        end
    end
    if result < 0:
        return result
    end
    return os_exit_code(__lsl_qbe_load64(status))
end

function os_exit_code(status):
    signal = status & 127
    if signal != 0:
        return signal + 128
    end
    return __lsl_qbe_ashr(status, 8) & 255
end

function os_kill(pid):
    return syscall3(platform.SYS_KILL, pid, platform.SIGKILL, 0)
end

# Spustí program bez shellu (clone se SIGCHLD = fork). argv je pole
# ukazatelů na C řetězce zakončené nulou, clean vybere prázdné prostředí.
# output < 0: potomek zdědí standardní deskriptory (run), jinak dostane
# input (< 0 zdědí stdin), output a error jako 0, 1, 2 a zavře parent_end
# (capture). Potomek zavře ostatní deskriptory a zakáže core dumpy. Vrací
# pid, nebo zápornou chybu clone.
function os_spawn(path, argv, clean, input, output, error, parent_end):
    rlimit = __lsl_qbe_alloc(16)
    pid = syscall6(platform.SYS_CLONE, platform.SIGCHLD, 0, 0, 0, 0, 0)
    if pid != 0:
        return pid
    end
    # Potomek: chyba přípravy končí 127 (run) nebo 126 (capture).
    failure = 127
    if output >= 0:
        failure = 126
        if not child_redirect(input, output, error, parent_end):
            call syscall1(platform.SYS_EXIT, failure)
        end
    end
    # Potomek nesmí zdědit sockety supervisoru, tajné memfd ani jiné
    # deskriptory rodiče.
    if syscall3(platform.SYS_CLOSE_RANGE, 3, 4294967295, 0) < 0:
        call syscall1(platform.SYS_EXIT, failure)
    end
    if output >= 0:
        # Omezí velikost zapisovaných souborů (i stderr memfd) na 128 MiB;
        # přísnější zděděný limit zůstane.
        if child_limit(rlimit, platform.RLIMIT_FSIZE, -1) < 0:
            call syscall1(platform.SYS_EXIT, failure)
        end
    end
    # Bez core dumpů: argv ani prostředí nesmí skončit na disku.
    if child_limit(rlimit, platform.RLIMIT_CORE, 0) < 0:
        call syscall1(platform.SYS_EXIT, failure)
    end
    environment = 0
    if clean:
        if __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_PRCTL, platform.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0, 0) < 0:
            call syscall1(platform.SYS_EXIT, failure)
        end
    else:
        environment = os_environment()
    end
    call syscall3(platform.SYS_EXECVE, path, narrow_vector(argv), narrow_vector(environment))
    call syscall1(platform.SYS_EXIT, 127)
    return 0
end

# Pole ukazatelů pro jádro (argv, prostředí): na 32bitovém cíli z 64bitových
# slov runtime na 32bitová (nové mapování v potomkovi před execve).
function narrow_vector(vector):
    if platform.WORD_BYTES == 8 or vector == 0:
        return vector
    end
    count = 0
    while __lsl_qbe_load64(vector + __lsl_qbe_shl(count, 3)) != 0:
        count += 1
    end
    result = map_anonymous((__lsl_qbe_shl(count + 1, 2) + 4095) & -4096, 0)
    if result < 0:
        return vector
    end
    index = 0
    while index <= count:
        __lsl_qbe_store32(result + __lsl_qbe_shl(index, 2), __lsl_qbe_load64(vector + __lsl_qbe_shl(index, 3)))
        index += 1
    end
    return result
end

# Limit zdroje v potomkovi: value >= 0 nastaví oba limity, -1 jen sníží oba
# na nejvýš 128 MiB.
function child_limit(rlimit, resource, value):
    if value >= 0:
        __lsl_qbe_store64(rlimit, value)
        __lsl_qbe_store64(rlimit + 8, value)
    else:
        if __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_PRLIMIT64, 0, resource, 0, rlimit, 0, 0) < 0:
            return -1
        end
        if __lsl_qbe_ult(134217728, __lsl_qbe_load64(rlimit)):
            __lsl_qbe_store64(rlimit, 134217728)
        end
        if __lsl_qbe_ult(134217728, __lsl_qbe_load64(rlimit + 8)):
            __lsl_qbe_store64(rlimit + 8, 134217728)
        end
    end
    return __lsl_qbe_call7(__lsl_symbol("lsl_arch_syscall6"), platform.SYS_PRLIMIT64, 0, resource, rlimit, 0, 0, 0)
end

# Přesměrování v potomkovi capture. Nejdřív zavře rodičovský konec roury,
# aby dup3 nepřepsal stejné číslo (rodič mohl mít 0/1 zavřené).
function child_redirect(input, output, error, parent_end):
    call os_close(parent_end)
    if input > 0:
        if not child_move(input, 0):
            return 0
        end
    end
    if output != 1:
        if not child_move(output, 1):
            return 0
        end
    end
    if error != 2:
        if not child_move(error, 2):
            return 0
        end
    end
    # pipe2 a memfd mají CLOEXEC. dup3 ho na cíli ruší, ale deskriptor, který
    # už měl cílové číslo, se nepřesouvá: CLOEXEC se proto ruší výslovně.
    if input >= 0:
        if syscall3(platform.SYS_FCNTL, 0, platform.F_SETFD, 0) < 0:
            return 0
        end
    end
    if syscall3(platform.SYS_FCNTL, 1, platform.F_SETFD, 0) < 0:
        return 0
    end
    if syscall3(platform.SYS_FCNTL, 2, platform.F_SETFD, 0) < 0:
        return 0
    end
    return 1
end

function child_move(fd, target):
    if syscall3(platform.SYS_DUP3, fd, target, 0) < 0:
        return 0
    end
    call os_close(fd)
    return 1
end

function gettid():
    return syscall3(platform.SYS_GETTID, 0, 0, 0)
end

function sched_getaffinity(size, mask):
    return syscall3(platform.SYS_SCHED_GETAFFINITY, 0, size, mask)
end

# Čekání na futex nejvýš daný počet nanosekund (relativně).
function futex_wait_timeout(address, expected, timespec):
    return syscall6(platform.SYS_FUTEX, address, platform.FUTEX_WAIT, expected, timespec, 0, 0)
end

# Rozhraní pro start procesu, vlákna a GC (stejná jména v os_windows.lsl).

# Vlákno se zveřejňuje samo (lsl_thread_begin)? Linux: ne, spawn zná zásobník.
# Vlákno se zveřejní samo v lsl_thread_begin (vrchol zásobníku zná až ono):
# s pthready (vrstva s glibc) ano, s clone ne (zásobník mapuje rodič).
function thread_self_publish():
    return pthreads()
end
# Spouští GC zastavená vlákna sám (thread_resume)? Linux: ne, probudí je brána.
THREAD_RESUME = 0
# Jména proměnných prostředí rozlišují velikost písmen.
ENV_IGNORE_CASE = 0
# Registry zastaveného vlákna leží na jeho zásobníku (thread_registers 0).
THREAD_REGISTER_BYTES = 0
SIGUSR1 = 10

# Blok argumentů (argc, argv, 0, prostředí, 0) předalo jádro na zásobníku.
# Na 32bitovém cíli jsou to 32bitová slova: převedou se do nového bloku
# 64bitových slov (stejný tvar jako na 64bitových cílech).
function process_arguments(stack):
    if platform.WORD_BYTES == 8:
        return stack
    end
    count = __lsl_qbe_load32(stack)
    words = count + 2
    while __lsl_qbe_load32(stack + __lsl_qbe_shl(words, 2)) != 0:
        words += 1
    end
    words += 1
    block = map_anonymous((__lsl_qbe_shl(words, 3) + 4095) & -4096, 0)
    if block < 0:
        return 0
    end
    index = 0
    while index < words:
        __lsl_qbe_store64(block + __lsl_qbe_shl(index, 3), __lsl_qbe_load32(stack + __lsl_qbe_shl(index, 2)))
        index += 1
    end
    return block
end

# Obsluha SIGUSR1 pro zastavení světa; SA_RESTART: vnitřní GC nesmí vracet
# EINTR z I/O ani čekání na procesy. Záporné = chyba.
function install_thread_suspend():
    action = __lsl_qbe_alloc(32)
    __lsl_qbe_zero(action, 32)
    call store_word(action + platform.SIGACTION_HANDLER, __lsl_symbol("lsl_thread_signal"))
    call store_word(action + platform.SIGACTION_FLAGS, platform.SA_RESTORER | platform.SA_RESTART)
    # Bez pole restorer (riscv64) jádro vrací ze signálu přes vDSO.
    if platform.SIGACTION_RESTORER >= 0:
        call store_word(action + platform.SIGACTION_RESTORER, __lsl_symbol("lsl_arch_signal_restorer"))
    end
    __lsl_qbe_store64(action + platform.SIGACTION_MASK, 0)
    return syscall6(platform.SYS_RT_SIGACTION, SIGUSR1, action, 0, platform.SIGSET_BYTES, 0, 0)
end

# Vrstva s glibc (linux_gnu_x86_64.S): vlákna vytváří pthread_create se
# svým zásobníkem a vlákno se zveřejní samo v lsl_thread_begin.
function pthreads():
    return __lsl_qbe_load64(__lsl_symbol("lsl_arch_threads")) != 0
end

# Zásobník vlákna: dosavadní (top != 0) se použije znovu, jinak nové mapování
# se strážní stránkou na dně. Vrchol, nebo -1.
function thread_stack(top, size, guard):
    if pthreads():
        # Zásobník dá glibc; 0 = vlákno se zveřejní samo v lsl_thread_begin
        # (do té doby ho GC neprohledává), jako na macOS.
        return 0
    end
    if top != 0:
        return top
    end
    stack = mmap(0, size, 3, 131106, -1, 0)
    if stack < 0:
        return -1
    end
    if mprotect(stack, guard, 0) != 0:
        call munmap(stack, size)
        return -1
    end
    return stack + size
end

# clone se sdílenou pamětí. CLONE_CHILD_CLEARTID na stav: jádro ho vynuluje
# a probudí čekající až po úplném skončení vlákna; CLONE_SETTLS ukáže na
# blok vlákna. Potomek najde na zásobníku položku a funkci. tid, nebo -errno.
function thread_start(entry, top, function):
    if pthreads():
        # Volá se pod zámkem tabulky: funkce vlákna do položky (+24, čte ji
        # lsl_thread_begin), tid vrátí arch vrstva po startu vlákna.
        __lsl_qbe_store64(entry + 24, function)
        return __lsl_qbe_call1(__lsl_symbol("lsl_arch_thread_create"), entry)
    end
    __lsl_qbe_store64(top - 16, entry)
    __lsl_qbe_store64(top - 8, function)
    return __lsl_qbe_call4(__lsl_symbol("lsl_arch_clone_thread"), platform.THREAD_CLONE_FLAGS, top - 16, entry + 16, entry + 32)
end

# Konec vlákna: stav vynuluje jádro (CLONE_CHILD_CLEARTID). Vlákno pthread
# napřed samo ohlásí konec (stav 1 -> 0, probudit join) jako na macOS.
function thread_exit(entry):
    if pthreads():
        while __lsl_qbe_call3(__lsl_symbol("lsl_arch_cas64"), entry + 16, 1, 0) != 1:
            call sched_yield()
        end
        call futex_wake(entry + 16, 2147483647)
        return __lsl_qbe_call0(__lsl_symbol("lsl_arch_thread_exit"))
    end
    return exit_thread(0)
end

# Zastavení pro GC: obsluha SIGUSR1 (entry.lsl) uloží registry a uspí se.
function thread_suspend(process, entry):
    return tgkill(process, __lsl_qbe_load64(entry), SIGUSR1)
end

function thread_resume(entry):
    return 0
end

# Registry zastaveného vlákna leží v rámci signálu na jeho zásobníku.
function thread_registers(entry):
    return 0
end

# Začátek haldy: 64bitové cíle od 2^44 (nad běžnými celými čísly, viz
# entry.lsl), posunutý o dolní bity nápovědy (ASLR obrazu), takže halda
# zůstává náhodně umístěná; 32bitové navržená adresa za obrazem (značku
# dodá HEAP_ADDRESS_TAG).
HIGH_HEAP = 17592186044416
HIGH_HEAP_SPREAD = 8796093022207

function heap_base(hint):
    if platform.WORD_BYTES == 8:
        return HIGH_HEAP + (hint & HIGH_HEAP_SPREAD)
    end
    return hint
end

# Časový limit potomka capture (interní builtin pro Windows a macOS; na
# Linuxu knihovny používají coreutils timeout): nedostupné, 0.
function process_deadline(pid, milliseconds):
    return 0
end

function process_deadline_cancel(watch):
    return 0
end

# Počká na skončení potomka bez jeho úklidu (s process_deadline; na Linuxu
# se nepoužívá).
function os_wait_exit(pid):
    return 0
end

# Vlákno běží samo od thread_start; nic nečeká na spuštění.
function thread_run_pending(entry):
    return 0
end

# Výpis adresáře (__lsl_list_directory): handle je blok stavu (+0 fd,
# +8 pozice, +16 počet bajtů, od +64 výsledek getdents64).
DIRECTORY_STATE = 65536

function directory_open(path):
    fd = open(path, platform.O_DIRECTORY | platform.O_CLOEXEC, 0)
    if fd < 0:
        return fd
    end
    state = map_anonymous(DIRECTORY_STATE, 0)
    if state < 0:
        call close(fd)
        return state
    end
    __lsl_qbe_store64(state, fd)
    __lsl_qbe_store64(state + 8, 0)
    __lsl_qbe_store64(state + 16, 0)
    return state
end

# Další jméno do buffer (bez NUL): délka, 0 konec, záporné errno.
function directory_next(state, buffer, size):
    while True:
        position = __lsl_qbe_load64(state + 8)
        if position >= __lsl_qbe_load64(state + 16):
            count = syscall6(platform.SYS_GETDENTS64, __lsl_qbe_load64(state), state + 64, DIRECTORY_STATE - 64, 0, 0, 0)
            if count <= 0:
                return count
            end
            __lsl_qbe_store64(state + 8, 0)
            __lsl_qbe_store64(state + 16, count)
            position = 0
        end
        record = state + 64 + position
        __lsl_qbe_store64(state + 8, position + __lsl_qbe_load16(record + 16))
        name = record + 19
        length = 0
        while __lsl_qbe_load8(name + length) != 0 and length < size:
            __lsl_qbe_store8(buffer + length, __lsl_qbe_load8(name + length))
            length += 1
        end
        if length > 0:
            return length
        end
    end
    return 0
end

function directory_close(state):
    call close(__lsl_qbe_load64(state))
    call unmap(state, DIRECTORY_STATE)
    return 0
end
