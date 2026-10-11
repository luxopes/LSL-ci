n = Int(arg(1))
x = "x" * n
count = 0
if arg(2) == "bytes":
    for i in rang(__lsl_text_byte_length(x)):
        count += __lsl_text_byte(x, i) // 120
    end
else:
    for c in x:
        count += 1
    end
end
print count
