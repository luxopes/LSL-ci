function inspect():
    left = "ab"
    right = "a" + "b"
    print left is right, left is not right
    first = 1.25
    second = Float("1.25")
    print first is second, first is not second, 1.0 is 1, 0.0 is -0.0
    nan = 0.0 / 0.0
    print nan is nan, nan is not nan
    values = [True, False, None, 37, 1.25, "ab"]
    print values[0] is True, values[1] is False, values[2] is None, values[3] is 37
    print values[4] is first, values[5] is left, True is 1, False is 0
    print 0 is 0, 0 is not 0, 0 == 0, 0 != 0
    print 0 is 1, 0 is not 1, 0 == 1, 0 != 1
    print 0 is False, 0 is not False, 0 == False, 0 != False
    print 0 is True, 0 is not True, 0 == True, 0 != True
    print 0 is None, 0 is not None, 0 == None, 0 != None
    print 1 is 0, 1 is not 0, 1 == 0, 1 != 0
    print 1 is 1, 1 is not 1, 1 == 1, 1 != 1
    print 1 is False, 1 is not False, 1 == False, 1 != False
    print 1 is True, 1 is not True, 1 == True, 1 != True
    print 1 is None, 1 is not None, 1 == None, 1 != None
    print False is 0, False is not 0, False == 0, False != 0
    print False is 1, False is not 1, False == 1, False != 1
    print False is False, False is not False, False == False, False != False
    print False is True, False is not True, False == True, False != True
    print False is None, False is not None, False == None, False != None
    print True is 0, True is not 0, True == 0, True != 0
    print True is 1, True is not 1, True == 1, True != 1
    print True is False, True is not False, True == False, True != False
    print True is True, True is not True, True == True, True != True
    print True is None, True is not None, True == None, True != None
    print None is 0, None is not 0, None == 0, None != 0
    print None is 1, None is not 1, None == 1, None != 1
    print None is False, None is not False, None == False, None != False
    print None is True, None is not True, None == True, None != True
    print None is None, None is not None, None == None, None != None
    print 0.0 is 0.0, 0.0 is not 0.0, 0.0 == 0.0, 0.0 != 0.0
    print 0.0 is -0.0, 0.0 is not -0.0, 0.0 == -0.0, 0.0 != -0.0
    print 0.0 is nan, 0.0 is not nan, 0.0 == nan, 0.0 != nan
    print 0.0 is 1.0, 0.0 is not 1.0, 0.0 == 1.0, 0.0 != 1.0
    print -0.0 is 0.0, -0.0 is not 0.0, -0.0 == 0.0, -0.0 != 0.0
    print -0.0 is -0.0, -0.0 is not -0.0, -0.0 == -0.0, -0.0 != -0.0
    print -0.0 is nan, -0.0 is not nan, -0.0 == nan, -0.0 != nan
    print -0.0 is 1.0, -0.0 is not 1.0, -0.0 == 1.0, -0.0 != 1.0
    print nan is 0.0, nan is not 0.0, nan == 0.0, nan != 0.0
    print nan is -0.0, nan is not -0.0, nan == -0.0, nan != -0.0
    print nan is nan, nan is not nan, nan == nan, nan != nan
    print nan is 1.0, nan is not 1.0, nan == 1.0, nan != 1.0
    print 1.0 is 0.0, 1.0 is not 0.0, 1.0 == 0.0, 1.0 != 0.0
    print 1.0 is -0.0, 1.0 is not -0.0, 1.0 == -0.0, 1.0 != -0.0
    print 1.0 is nan, 1.0 is not nan, 1.0 == nan, 1.0 != nan
    print 1.0 is 1.0, 1.0 is not 1.0, 1.0 == 1.0, 1.0 != 1.0
    a = [1]
    b = [1]
    alias = a
    print a is b, a is alias, a is not b, a is not alias, a == b
    wrapped = [a, b, alias]
    print wrapped[0] is wrapped[1], wrapped[0] is wrapped[2]
end
call inspect()
