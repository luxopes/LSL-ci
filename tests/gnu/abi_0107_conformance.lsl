# lsl: internal-abi
# lsl: link libgtk-3.so.0 libgobject-2.0.so.0 libc.so.6
# Opravy 0.10.7 v interním ABI cíle gnu: výsledek C int (icall), parametr C
# float (__lsl_qbe_f32), glib.pump a verze symbolů glibc (realpath s NULL).
load glib
load gtk

path = "/nonexistent/lsl-abi-0107"
raw = __lsl_qbe_call3(__lsl_symbol("open"), __lsl_address(path) + 16, 524288, 0)
handle = __lsl_qbe_icall3(__lsl_symbol("open"), __lsl_address(path) + 16, 524288, 0)
print "open raw word:", raw, "icall:", handle, handle < 0

# realpath(path, NULL) je platné jen ve verzi GLIBC_2.3 (stará 2.2.5 vrací EINVAL).
directory = "/tmp"
resolved = __lsl_qbe_call2(__lsl_symbol("realpath"), __lsl_address(directory) + 16, 0)
print "realpath NULL:", glib.from_c(resolved) != ""
call __lsl_qbe_call1(__lsl_symbol("free"), resolved)

ticks = []
function once():
    ticks.append(1)
    return False
end
call glib.idle_add(once)
call glib.pump()
print "pump:", len(ticks)

call gtk.init()
label = gtk.label_new("x")
call gtk.label_set_xalign(label, 0.5)
call gtk.label_set_yalign(label, 0.25)
holder = __lsl_byte_zeros(24)
gvalue = __lsl_qbe_load64(__lsl_address(holder) + 24)
call __lsl_qbe_call2(__lsl_symbol("g_value_init"), gvalue, 60)
name = "xalign"
call __lsl_qbe_call3(__lsl_symbol("g_object_get_property"), label, __lsl_address(name) + 16, gvalue)
xalign = __lsl_qbe_fcall1(__lsl_symbol("g_value_get_double"), gvalue)
call __lsl_qbe_call1(__lsl_symbol("g_value_unset"), gvalue)
call __lsl_qbe_call2(__lsl_symbol("g_value_init"), gvalue, 60)
name = "yalign"
call __lsl_qbe_call3(__lsl_symbol("g_object_get_property"), label, __lsl_address(name) + 16, gvalue)
yalign = __lsl_qbe_fcall1(__lsl_symbol("g_value_get_double"), gvalue)
print "float parameters:", xalign, yalign
