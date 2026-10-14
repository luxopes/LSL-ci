# Windows: identita vlákna pro knihovnu ai.

function thread_id():
    return __lsl_qbe_call0(__lsl_symbol("GetCurrentThreadId")) & 4294967295
end
