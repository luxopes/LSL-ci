# Wall-clock, monotonic timing and syscall-only sleeping.

function time():
    return __lsl_wall_time()
end

function now():
    return __lsl_wall_time()
end

function monotonic():
    return clock()
end

function perf_counter():
    return clock()
end

function sleep(seconds):
    duration = Float(seconds)
    if duration < 0.0:
        Error(ValueError: "sleep duration cannot be negative")
    end
    call __lsl_sleep(duration)
    return None
end
