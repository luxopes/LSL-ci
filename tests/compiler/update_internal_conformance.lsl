# lsl: internal-abi
# The CLI uses this ABI. Public-only tests cannot detect raw zero/None casts.
load update
load update_install

function require(condition, message):
    if not condition:
        Error(TestFailure: message)
    end
end

data = __lsl_byte_zeros(512)
data[0] = 97
require(update.tar_string(data, 0, 100) == "a", "first tar header at raw offset zero")
require(update.tar_string(data, 100, 100) == "", "empty tar string")
require(update.digits("0", 0) == 0, "raw zero decimal bound")
require(update_install.little(data, 0, 0) == 0, "raw zero field width")
entry = {"size": 0}
size = __lsl_typed_int(entry["size"])
require(len(__lsl_byte_zeros(size)) == 0, "empty archive member")
print "internal ABI updater conformance passed"
