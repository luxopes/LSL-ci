positive = 1.0 / 0.0
negative = -1.0 / 0.0
notnum = 0.0 / 0.0
print positive, negative, notnum
print String(positive), String(negative), String(notnum)
print 2.5, -3.5, 0.0
if positive > 1e300:
    print "inf is greater"
end
print notnum == notnum, notnum != notnum, notnum < positive
print positive > 1.0, positive == positive, negative < positive
print 1.5 == 1.5, 1.5 != 2.5, 2.5 <= 2.5
