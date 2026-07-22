# Minimal auditable x86_64 encoder. Every instruction is emitted as List[Int];
# no textual assembly and no external assembler are involved.

load bytes

function rex(w, r, x, b):
    return 64 + Bool(w) * 8 + Bool(r) * 4 + Bool(x) * 2 + Bool(b)
end

function modrm(mod, reg, rm):
    return mod * 64 + (reg % 8) * 8 + (rm % 8)
end

function mov_imm64(register, value):
    result = [rex(True, False, False, register >= 8), 184 + register % 8]
    result.extend(bytes.little(value, 8))
    return result
end

function mov_imm32(register, value):
    result = []
    if register >= 8:
        result.append(rex(False, False, False, True))
    end
    result.append(184 + register % 8)
    result.extend(bytes.little(value, 4))
    return result
end

function lea_rip_prefix(register):
    return [rex(True, register >= 8, False, False), 141, modrm(0, register, 5)]
end

function lea_rip(register, displacement):
    result = lea_rip_prefix(register)
    result.extend(bytes.little(displacement, 4))
    return result
end

function syscall():
    return [15, 5]
end

function ret():
    return [195]
end

function push(register):
    result = []
    if register >= 8:
        result.append(65)
    end
    result.append(80 + register % 8)
    return result
end

function pop(register):
    result = []
    if register >= 8:
        result.append(65)
    end
    result.append(88 + register % 8)
    return result
end

function add_reg_reg(destination, source):
    return [rex(True, source >= 8, False, destination >= 8), 1, modrm(3, source, destination)]
end

function sub_reg_reg(destination, source):
    return [rex(True, source >= 8, False, destination >= 8), 41, modrm(3, source, destination)]
end

function imul_reg_reg(destination, source):
    return [rex(True, destination >= 8, False, source >= 8), 15, 175, modrm(3, destination, source)]
end

function cmp_reg_reg(left, right):
    return [rex(True, right >= 8, False, left >= 8), 57, modrm(3, right, left)]
end

function test_reg_reg(left, right):
    return [rex(True, right >= 8, False, left >= 8), 133, modrm(3, right, left)]
end

function xor_reg_reg(destination, source):
    return [rex(True, source >= 8, False, destination >= 8), 49, modrm(3, source, destination)]
end

function and_reg_reg(destination, source):
    return [rex(True, source >= 8, False, destination >= 8), 33, modrm(3, source, destination)]
end

function or_reg_reg(destination, source):
    return [rex(True, source >= 8, False, destination >= 8), 9, modrm(3, source, destination)]
end

function call_relative(displacement):
    result = [232]
    result.extend(bytes.little(displacement, 4))
    return result
end

function call_reg(register):
    return [rex(True, False, False, register >= 8), 255, modrm(3, 2, register)]
end

function movq_xmm_from_reg(xmm_register, integer_register):
    return [102, rex(True, xmm_register >= 8, False, integer_register >= 8), 15, 110, modrm(3, xmm_register, integer_register)]
end

function movq_reg_from_xmm(integer_register, xmm_register):
    return [102, rex(True, xmm_register >= 8, False, integer_register >= 8), 15, 126, modrm(3, xmm_register, integer_register)]
end

function scalar_double(operation, destination, source):
    return [242, rex(False, destination >= 8, False, source >= 8), 15, operation, modrm(3, destination, source)]
end

function add_double(destination, source):
    return scalar_double(88, destination, source)
end

function sub_double(destination, source):
    return scalar_double(92, destination, source)
end

function mul_double(destination, source):
    return scalar_double(89, destination, source)
end

function div_double(destination, source):
    return scalar_double(94, destination, source)
end

function compare_double(left, right):
    return [102, rex(False, left >= 8, False, right >= 8), 15, 46, modrm(3, left, right)]
end

function int_to_double(xmm_register, integer_register):
    return [242, rex(True, xmm_register >= 8, False, integer_register >= 8), 15, 42, modrm(3, xmm_register, integer_register)]
end

function double_to_int(integer_register, xmm_register):
    return [242, rex(True, integer_register >= 8, False, xmm_register >= 8), 15, 44, modrm(3, integer_register, xmm_register)]
end

function jump_relative(displacement):
    result = [233]
    result.extend(bytes.little(displacement, 4))
    return result
end

function jump_condition(condition_opcode, displacement):
    result = [15, condition_opcode]
    result.extend(bytes.little(displacement, 4))
    return result
end

function move_reg_reg(destination, source):
    return [rex(True, source >= 8, False, destination >= 8), 137, modrm(3, source, destination)]
end

function load_stack(register, displacement):
    # mov register, [rbp + disp32]
    result = [rex(True, register >= 8, False, False), 139, modrm(2, register, 5)]
    result.extend(bytes.little(displacement, 4))
    return result
end

function store_stack(displacement, register):
    # mov [rbp + disp32], register
    result = [rex(True, register >= 8, False, False), 137, modrm(2, register, 5)]
    result.extend(bytes.little(displacement, 4))
    return result
end

function function_prologue(frame_size):
    result = [85, 72, 137, 229]
    if frame_size > 0:
        result.extend([72, 129, 236])
        result.extend(bytes.little(frame_size, 4))
    end
    return result
end

function function_epilogue():
    return [201, 195]
end

function add_reg_imm8(register, value):
    return [rex(True, False, False, register >= 8), 131, modrm(3, 0, register), value % 256]
end

function add_reg_imm32(register, value):
    result = [rex(True, False, False, register >= 8), 129, modrm(3, 0, register)]
    result.extend(bytes.little(value, 4))
    return result
end

function cmp_reg_imm8(register, value):
    return [rex(True, False, False, register >= 8), 131, modrm(3, 7, register), value % 256]
end

function cmp_reg_imm32(register, value):
    result = [rex(True, False, False, register >= 8), 129, modrm(3, 7, register)]
    result.extend(bytes.little(value, 4))
    return result
end

function neg_reg(register):
    return [rex(True, False, False, register >= 8), 247, modrm(3, 3, register)]
end

function div_reg(register):
    return [rex(True, False, False, register >= 8), 247, modrm(3, 6, register)]
end

function idiv_reg(register):
    return [rex(True, False, False, register >= 8), 247, modrm(3, 7, register)]
end
function imul_high_reg(register):
    # one-operand IMUL: RDX:RAX = RAX * register (signed); high half in RDX.
    return [rex(True, False, False, register >= 8), 247, modrm(3, 5, register)]
end
function shift_right_logical_imm(register, amount):
    return [rex(True, False, False, register >= 8), 193, modrm(3, 5, register), amount]
end

function cqo():
    return [72, 153]
end

function increment(register):
    return [rex(True, False, False, register >= 8), 255, modrm(3, 0, register)]
end

function decrement(register):
    return [rex(True, False, False, register >= 8), 255, modrm(3, 1, register)]
end

function store_byte_imm(base_register, value):
    return [rex(False, False, False, base_register >= 8), 198, modrm(0, 0, base_register), value % 256]
end

function store_byte_reg(base_register, source_register):
    return [rex(False, source_register >= 8, False, base_register >= 8), 136, modrm(0, source_register, base_register)]
end

function set_condition(condition_opcode):
    # setcc al; movzx rax, al
    return [15, condition_opcode, 192, 72, 15, 182, 192]
end
function set_condition_ordered(condition_opcode):
    # setcc cl; setnp al; and al,cl; movzx rax,al -> true only if cc and ordered
    return [15, condition_opcode, 193, 15, 155, 192, 32, 200, 72, 15, 182, 192]
end
function set_condition_unordered(condition_opcode):
    # setcc cl; setp al; or al,cl; movzx rax,al -> true if cc or unordered (NaN)
    return [15, condition_opcode, 193, 15, 154, 192, 8, 200, 72, 15, 182, 192]
end

function and_reg_imm8(register, value):
    return [rex(True, False, False, register >= 8), 131, modrm(3, 4, register), value % 256]
end

function shift_left_imm(register, amount):
    return [rex(True, False, False, register >= 8), 193, modrm(3, 4, register), amount]
end

function shift_right_arithmetic_imm(register, amount):
    return [rex(True, False, False, register >= 8), 193, modrm(3, 7, register), amount]
end

function memory_tail(base_register, mode, reg_field):
    result = [modrm(mode, reg_field, base_register)]
    if base_register % 8 == 4:
        result.append(36)
    end
    return result
end

function load_memory(destination, base_register, displacement):
    result = [rex(True, destination >= 8, False, base_register >= 8), 139]
    result.extend(memory_tail(base_register, 2, destination))
    result.extend(bytes.little(displacement, 4))
    return result
end

function store_memory(base_register, displacement, source_register):
    result = [rex(True, source_register >= 8, False, base_register >= 8), 137]
    result.extend(memory_tail(base_register, 2, source_register))
    result.extend(bytes.little(displacement, 4))
    return result
end

function store_memory_imm32(base_register, displacement, value):
    result = [rex(True, False, False, base_register >= 8), 199]
    result.extend(memory_tail(base_register, 2, 0))
    result.extend(bytes.little(displacement, 4))
    result.extend(bytes.little(value, 4))
    return result
end

function lea_base(destination, base_register, displacement):
    result = [rex(True, destination >= 8, False, base_register >= 8), 141]
    result.extend(memory_tail(base_register, 2, destination))
    result.extend(bytes.little(displacement, 4))
    return result
end

function load_byte_zero_extend(destination, base_register, displacement):
    result = [rex(True, destination >= 8, False, base_register >= 8), 15, 182]
    result.extend(memory_tail(base_register, 2, destination))
    result.extend(bytes.little(displacement, 4))
    return result
end

function store_byte_reg_disp(base_register, displacement, source_register):
    result = [rex(False, source_register >= 8, False, base_register >= 8), 136]
    result.extend(memory_tail(base_register, 2, source_register))
    result.extend(bytes.little(displacement, 4))
    return result
end

function sib(scale, index_register, base_register):
    return scale * 64 + (index_register % 8) * 8 + (base_register % 8)
end

function load_indexed(destination, base_register, index_register, scale):
    return [rex(True, destination >= 8, index_register >= 8, base_register >= 8), 139, modrm(0, destination, 4), sib(scale, index_register, base_register)]
end

function store_indexed(base_register, index_register, scale, source_register):
    return [rex(True, source_register >= 8, index_register >= 8, base_register >= 8), 137, modrm(0, source_register, 4), sib(scale, index_register, base_register)]
end

function load_byte_indexed(destination, base_register, index_register):
    return [rex(True, destination >= 8, index_register >= 8, base_register >= 8), 15, 182, modrm(0, destination, 4), sib(0, index_register, base_register)]
end

function store_byte_indexed(base_register, index_register, source_register):
    return [rex(False, source_register >= 8, index_register >= 8, base_register >= 8), 136, modrm(0, source_register, 4), sib(0, index_register, base_register)]
end

function lea_indexed(destination, base_register, index_register, scale):
    return [rex(True, destination >= 8, index_register >= 8, base_register >= 8), 141, modrm(0, destination, 4), sib(scale, index_register, base_register)]
end
