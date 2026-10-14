# Program v sandboxu pro test v CI: read ARGUMENT_TAJNÉHO_SOUBORU | sleep
load sandbox
load time

if arg(1) == "sleep":
    call time.sleep(30)
    exit(0)
end
print "input", readfile(sandbox.input_path(0) + "/data.txt").strip()
leaked = True
try:
    call readfile(arg(2))
else:
    leaked = False
end
print "secret readable", leaked
call writefile(sandbox.output_path(0) + "/out.txt", "written")
print "profile", sandbox.profile()
