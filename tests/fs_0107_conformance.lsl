# Opravy 0.10.7: vestavěné args, cwd, chdir a remove_path z manuálu
# (Linux a macOS; Windows má cesty s písmenem jednotky, WASI a bare metal
# nemají pracovní adresář procesu).
print type(args), len(args) == arg_count(), args[0] == arg(0)
function uses_local(args):
    return len(args)
end
print uses_local([1, 2, 3])
start_directory = cwd()
call chdir("/")
print cwd()
call chdir(start_directory)
print cwd() == start_directory
probe = "/tmp/lsl-fixes-0107-" + String(len(start_directory))
call writefile(probe, "x")
call remove_path(probe)
call mkdir(probe)
call remove_path(probe)
print exists(probe)
try:
    call remove_path(probe)
else:
    print String(last_error()).startswith("FileError: cannot remove")
end
