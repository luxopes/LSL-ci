load lexer

path = arg(1)
tokens = lexer.tokenize(path, readfile(path))
for item in tokens:
    print item["kind"], item["value"], item["line"], item["column"], item["end_column"]
end
