load _platform_linux_x86_64 as platform
load os

function stty_tool():
    command = os.which_trusted("stty")
    if command == None:
        Error(TUIError: "trusted stty executable is unavailable")
    end
    return command
end

function enter_state():
    command = stty_tool()
    saved = os.capture_argv_clean(command, ["-g"]).strip()
    if capture_status() != 0 or len(saved) == 0 or len(saved) > 4096 or chr(0) in saved:
        Error(TUIError: "cannot read terminal state")
    end
    if os.run_argv_clean(command, ["-echo", "-icanon", "-isig", "-ixon", "min", "1", "time", "0"]) != 0:
        Error(TUIError: "cannot enter terminal raw mode")
    end
    return saved
end

function restore_state(saved):
    if os.run_argv_clean(stty_tool(), [saved]) != 0:
        Error(TUIError: "cannot restore terminal state")
    end
end

function dimensions():
    size = os.capture_argv_clean(stty_tool(), ["size"]).strip()
    parts = size.split(" ")
    if capture_status() == 0 and len(parts) == 2:
        rows = Int(parts[0])
        cols = Int(parts[1])
        if rows >= 1 and rows <= 10000 and cols >= 1 and cols <= 10000:
            return [rows, cols]
        end
    end
    return []
end

function wait_readable(timeout):
    descriptor = __lsl_byte_zeros(platform.POLLFD_BYTES)
    descriptor[platform.POLLFD_EVENTS] = platform.POLLIN
    ready = __lsl_syscall(platform.SYS_POLL, __lsl_data_address(descriptor), 1, Int(timeout), 0)
    return ready
end
