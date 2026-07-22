print [1, 2, 3] == [1, 2, 3]
print [1, 2, 3] == [1, 2, 4]
print [1, 2] == [1, 2, 3]
print [] == []
print [1, [2, 3]] == [1, [2, 3]]
print [1, [2, 3]] == [1, [2, 4]]
print (1, 2, 3) == (1, 2, 3)
print (1, 2) == (1, 3)
print ![1.0, 2.0] == ![1.0, 2.0]
print ![1.0, 2.0] == ![1.0, 3.0]
print {"a": 1, "b": 2} == {"a": 1, "b": 2}
print {"a": 1, "b": 2} == {"a": 1, "b": 3}
print {"a": 1} == {"a": 1, "b": 2}
print {"a": [1, 2]} == {"a": [1, 2]}
print [1, "x", True, None] == [1, "x", True, None]
print [1, "x"] == [1, "y"]
print [1, 2, 3] != [1, 2, 4]
print [1, 2, 3] != [1, 2, 3]
print [[1], [2, [3]]] == [[1], [2, [3]]]
print 5 == 5, "a" == "a", 5 == 6, 1 == 2
same_cycle = [1]
same_cycle.append(same_cycle)
other_cycle = [1]
other_cycle.append(other_cycle)
different_cycle = [2]
different_cycle.append(different_cycle)
print same_cycle == same_cycle, same_cycle == other_cycle, same_cycle == different_cycle
left_dictionary = {}
left_dictionary["self"] = left_dictionary
right_dictionary = {}
right_dictionary["self"] = right_dictionary
print left_dictionary == right_dictionary
