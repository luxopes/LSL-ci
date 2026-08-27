server = arg(1)

# Force pipe2/memfd_create to allocate descriptors 0, 1 and 2 directly. The
# capture child must clear CLOEXEC even when dup2(source, target) is skipped
# because source already equals target.
call __lsl_fd_close(0)
call __lsl_fd_close(1)
call __lsl_fd_close(2)

output = capture_input_clean(server, [], "")
if capture_status() != 0 or output != "alpha" + chr(10) + "beta" + chr(10):
    exit(1)
end
exit(0)
