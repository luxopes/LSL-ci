# macOS: identita vlákna pro knihovnu ai (pthread_t).

function thread_id():
    return Int(__lsl_qbe_call0(__lsl_symbol("pthread_self")))
end
