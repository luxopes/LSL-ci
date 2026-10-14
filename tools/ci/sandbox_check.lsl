# Izolace procesu (stdlib sandbox) pro test v CI: sandbox_check DÍTĚ ADRESÁŘ
load sandbox

child = arg(1)
root = arg(2)
call mkdir(root + "/in")
call mkdir(root + "/out")
call writefile(root + "/in/data.txt", "hello")
call writefile(root + "/secret.txt", "secret")
print "available", sandbox.available()
status = sandbox.run(child, ["read", root + "/secret.txt"], {"read": [root + "/in"], "write": [root + "/out"], "timeout": 20})
print "status", status
print "output", readfile(root + "/out/out.txt")
print "timeout", sandbox.run(child, ["sleep"], {"timeout": 1})
