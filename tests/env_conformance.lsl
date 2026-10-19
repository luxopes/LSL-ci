load env

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

source = chr(65279) + "# komentář" + chr(13) + chr(10)
source += "export LSL_ENV_SIMPLE = first=second # poznámka" + chr(13) + chr(10)
source += "LSL_ENV_EMPTY=" + chr(10) + "LSL_ENV_HASH=abc#def" + chr(10)
source += "LSL_ENV_SINGLE=' $TOKEN $(command) # text '" + chr(10)
source += "LSL_ENV_DOUBLE=" + chr(34) + "český" + chr(92) + "n" + chr(92) + "t" + chr(92) + chr(34) + chr(92) + chr(92) + chr(34) + " # konec" + chr(10)
source += "LSL_ENV_DUP=old" + chr(10) + "LSL_ENV_DUP=new" + chr(10)
values = env._parse_dotenv(source, "fixture.env")
call require(values["LSL_ENV_SIMPLE"] == "first=second", "dotenv export, CRLF and inline comment")
call require(values["LSL_ENV_EMPTY"] == "", "dotenv empty value")
call require(values["LSL_ENV_HASH"] == "abc#def", "dotenv literal hash")
call require(values["LSL_ENV_SINGLE"] == " $TOKEN $(command) # text ", "dotenv does not expand shell syntax")
call require(values["LSL_ENV_DOUBLE"] == "český" + chr(10) + chr(9) + chr(34) + chr(92), "dotenv Unicode and quoted escapes")
call require(values["LSL_ENV_DUP"] == "new", "dotenv last duplicate wins")

for invalid in ["NO_EQUALS", "1BAD=secret", "BAD NAME=secret", "A='secret", "A=\"secret", "A='secret' trailing", "A=" + chr(0), "A" * 256 + "=secret"]:
    caught = ""
    try:
        call env._parse_dotenv("OK=first" + chr(10) + invalid, "fixture.env")
    else:
        caught = last_error()
    end
    call require(caught == "EnvironmentError: invalid .env entry at fixture.env:2", "dotenv invalid entry and secret-free diagnostic")
end

path = arg(1) + "/explicit.env"
call writefile(path, "LSL_ENV_EXPLICIT_089=loaded" + chr(10) + "LSL_ENV_EMPTY_089=" + chr(10))
call require(env.load_dotenv(path), "explicit dotenv load")
call require(env.require("LSL_ENV_EXPLICIT_089") == "loaded", "dotenv require")
call require(env.has("LSL_ENV_EMPTY_089") and env.get("LSL_ENV_EMPTY_089", "fallback") == "", "empty dotenv value is present")
call writefile(path, "LSL_ENV_EXPLICIT_089=partial" + chr(10) + "INVALID")
caught = ""
try:
    call env.load_dotenv(path)
else:
    caught = last_error()
end
call require(caught.startswith("EnvironmentError:") and env.require("LSL_ENV_EXPLICIT_089") == "loaded", "invalid dotenv load is atomic")
call require(not env.load_dotenv(path + ".missing"), "missing dotenv is optional")
call require(not env.has("LSL_ENV_ABSENT_089") and env.get("LSL_ENV_ABSENT_089", 42) == 42, "missing dotenv default keeps type")
call require(env.get("LSL_ENV_ABSENT_089") == None, "missing variable without a default is None")
caught = ""
try:
    call env.require("LSL_ENV_ABSENT_089")
else:
    caught = last_error()
end
call require(caught == "EnvironmentError: missing environment variable LSL_ENV_ABSENT_089", "require missing variable")
for invalid in ["", "BAD=NAME", chr(0), "A" * 256, 12]:
    caught = ""
    try:
        call env.has(invalid)
    else:
        caught = last_error()
    end
    call require(caught.startswith("EnvironmentError:"), "invalid process variable name")
end
print "env conformance passed"
