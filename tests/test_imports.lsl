load os as test
from os load run

safe:
	call run("ls -al")
	call test.run("ls -al")
	print "Working"
end
