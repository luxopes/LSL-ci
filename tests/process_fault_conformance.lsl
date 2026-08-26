slots = Int(arg(1))
opened = __lsl_test_fd_fault(slots)
if opened <= 0:
    Error(TestFailure: "could not install fd fault")
end
caught = ""
try:
    call capture(arg(2) + "/process-fault-child", [])
else:
    caught = last_error()
end
print slots, caught
print capture_status(), capture_stderr() == None
