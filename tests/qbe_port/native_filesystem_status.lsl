# Filesystem statuses are Int, including zero, across public Any boundaries.
root = arg(1)
normal = root + "/normal"
private = root + "/private"
file = normal + "/payload"
call unlink(file)
call rmdir(normal)
call rmdir(private)
function identity(value):
    return value
end
status = mkdir(normal)
print type(status), status, identity(status) == 0
print mkdir(normal)
status = __lsl_mkdir_private(private)
print type(status), status, identity(status) == 0
print __lsl_mkdir_private(private)
call writefile(file, "payload")
status = unlink(file)
print type(status), status, identity(status) == 0
print unlink(file)
status = rmdir(normal)
print type(status), status, identity(status) == 0
print rmdir(normal)
print rmdir(private)
