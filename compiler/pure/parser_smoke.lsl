load parser

path = arg(1)
program = parser.parse(path, readfile(path))
for statement in program:
    print statement["kind"], statement["line"], statement["column"], statement["end_column"]
end
