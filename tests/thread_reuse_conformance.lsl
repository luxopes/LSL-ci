# Joining a thread that exited long ago must still report success, even when
# a later spawn has taken over its table slot. The record of an exited but
# unjoined thread is what makes that possible.

done = IntArray()
done.append(0)

function signal_exit():
    call atomic_add(done, 0, 1)
    return None
end

first = thread_spawn(signal_exit)
while done[0] == 0:
    call atomic_pause()
end
# The worker has run its last statement; give the kernel time to reap it so
# the next spawn really does find its slot free.
spin = 0
while spin < 5000000:
    spin += 1
end

second = thread_spawn(signal_exit)
print thread_join(second)
print thread_join(first)
print done[0]
# A tid that never belonged to this process stays an error.
print thread_join(0)
