load os as test
from os load run

safe:
	run("ls -al")
	test.run("ls -al")
	print "Working"
end
