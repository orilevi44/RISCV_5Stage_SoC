"""
RV32I Assembler
---------------
Usage:
    python assembler.py <test_name>

    Reads  : sim/asm/<test_name>.asm
    Writes : sim/hex/<test_name>.hex

Example:
    python assembler.py alu_test   →  sim/asm/alu_test.asm  →  sim/hex/alu_test.hex
    python assembler.py echo_test  →  sim/asm/echo_test.asm →  sim/hex/echo_test.hex
"""

import os, sys

# ABI register name → register number
ABI_MAP = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    't0': 5, 't1': 6, 't2': 7, 's0': 8, 'fp': 8, 's1': 9,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14, 'a5': 15, 'a6': 16, 'a7': 17,
    's2': 18, 's3': 19, 's4': 20, 's5': 21, 's6': 22, 's7': 23,
    's8': 24, 's9': 25, 's10': 26, 's11': 27,
    't3': 28, 't4': 29, 't5': 30, 't6': 31
}

# ── helpers ──────────────────────────────────────────────────────────────────

def parse_reg(r):
    r = r.replace(',', '').strip().lower()
    n = ABI_MAP[r] if r in ABI_MAP else int(r.replace('x', ''))
    return format(n, '05b')

def parse_imm(s, bits):
    s = s.replace(',', '').strip()
    v = int(s, 16) if s.startswith(('0x', '-0x')) else int(s)
    if v < 0:
        v = (1 << bits) + v
    return format(v & ((1 << bits) - 1), f'0{bits}b')

def parse_mem(mem_str):
    imm_str, reg_str = mem_str.split('(')
    return parse_imm(imm_str, 12), parse_reg(reg_str.replace(')', ''))

# ── encoders ─────────────────────────────────────────────────────────────────

def r_type(parts, op, f3, f7):
    rd, rs1, rs2 = parse_reg(parts[1]), parse_reg(parts[2]), parse_reg(parts[3])
    return fmt(f7 + rs2 + rs1 + f3 + rd + op)

def i_type(parts, op, f3):
    rd, rs1, imm = parse_reg(parts[1]), parse_reg(parts[2]), parse_imm(parts[3], 12)
    return fmt(imm + rs1 + f3 + rd + op)

def i_shift(parts, op, f3, f7):
    rd, rs1 = parse_reg(parts[1]), parse_reg(parts[2])
    shamt = parse_imm(parts[3], 5)
    return fmt(f7 + shamt + rs1 + f3 + rd + op)

def i_load(parts, op, f3):
    rd = parse_reg(parts[1])
    imm, rs1 = parse_mem(parts[2])
    return fmt(imm + rs1 + f3 + rd + op)

def s_type(parts, op, f3):
    rs2 = parse_reg(parts[1])
    imm, rs1 = parse_mem(parts[2])
    return fmt(imm[0:7] + rs2 + rs1 + f3 + imm[7:12] + op)

def b_type(parts, op, f3, pc, labels):
    rs1, rs2 = parse_reg(parts[1]), parse_reg(parts[2])
    target = parts[3]
    offset = (labels[target] - pc) if target in labels else int(target)
    imm = parse_imm(str(offset), 13)
    binary = imm[0] + imm[2:8] + rs2 + rs1 + f3 + imm[8:12] + imm[1] + op
    return fmt(binary)

def u_type(parts, op):
    rd, imm = parse_reg(parts[1]), parse_imm(parts[2], 20)
    return fmt(imm + rd + op)

def j_type(parts, op, pc, labels):
    rd = parse_reg(parts[1])
    target = parts[2]
    offset = (labels[target] - pc) if target in labels else int(target)
    imm = parse_imm(str(offset), 21)
    binary = imm[0] + imm[10:20] + imm[9] + imm[1:9] + rd + op
    return fmt(binary)

def fmt(binary_str):
    return format(int(binary_str, 2), '08x')

# ── instruction table ─────────────────────────────────────────────────────────

INST = {
    # R-type
    'add':  {'t': 'R', 'op': '0110011', 'f3': '000', 'f7': '0000000'},
    'sub':  {'t': 'R', 'op': '0110011', 'f3': '000', 'f7': '0100000'},
    'and':  {'t': 'R', 'op': '0110011', 'f3': '111', 'f7': '0000000'},
    'or':   {'t': 'R', 'op': '0110011', 'f3': '110', 'f7': '0000000'},
    'xor':  {'t': 'R', 'op': '0110011', 'f3': '100', 'f7': '0000000'},
    'sll':  {'t': 'R', 'op': '0110011', 'f3': '001', 'f7': '0000000'},
    'srl':  {'t': 'R', 'op': '0110011', 'f3': '101', 'f7': '0000000'},
    'sra':  {'t': 'R', 'op': '0110011', 'f3': '101', 'f7': '0100000'},
    'slt':  {'t': 'R', 'op': '0110011', 'f3': '010', 'f7': '0000000'},
    'sltu': {'t': 'R', 'op': '0110011', 'f3': '011', 'f7': '0000000'},
    # I-type ALU
    'addi': {'t': 'I', 'op': '0010011', 'f3': '000'},
    'andi': {'t': 'I', 'op': '0010011', 'f3': '111'},
    'ori':  {'t': 'I', 'op': '0010011', 'f3': '110'},
    'xori': {'t': 'I', 'op': '0010011', 'f3': '100'},
    'slti': {'t': 'I', 'op': '0010011', 'f3': '010'},
    # I-type shifts
    'slli': {'t': 'IS', 'op': '0010011', 'f3': '001', 'f7': '0000000'},
    'srli': {'t': 'IS', 'op': '0010011', 'f3': '101', 'f7': '0000000'},
    'srai': {'t': 'IS', 'op': '0010011', 'f3': '101', 'f7': '0100000'},
    # Loads
    'lw':   {'t': 'IL', 'op': '0000011', 'f3': '010'},
    'lh':   {'t': 'IL', 'op': '0000011', 'f3': '001'},
    'lb':   {'t': 'IL', 'op': '0000011', 'f3': '000'},
    'lhu':  {'t': 'IL', 'op': '0000011', 'f3': '101'},
    'lbu':  {'t': 'IL', 'op': '0000011', 'f3': '100'},
    # Stores
    'sw':   {'t': 'S', 'op': '0100011', 'f3': '010'},
    'sh':   {'t': 'S', 'op': '0100011', 'f3': '001'},
    'sb':   {'t': 'S', 'op': '0100011', 'f3': '000'},
    # Branches
    'beq':  {'t': 'B', 'op': '1100011', 'f3': '000'},
    'bne':  {'t': 'B', 'op': '1100011', 'f3': '001'},
    'blt':  {'t': 'B', 'op': '1100011', 'f3': '100'},
    'bge':  {'t': 'B', 'op': '1100011', 'f3': '101'},
    'bltu': {'t': 'B', 'op': '1100011', 'f3': '110'},
    'bgeu': {'t': 'B', 'op': '1100011', 'f3': '111'},
    # Upper immediate
    'lui':  {'t': 'U', 'op': '0110111'},
    'auipc':{'t': 'U', 'op': '0010111'},
    # Jumps
    'jal':  {'t': 'J', 'op': '1101111'},
    'jalr': {'t': 'IL', 'op': '1100111', 'f3': '000'},
    # System
    'nop':  {'t': 'NOP'},
}

# ── pseudo-instruction handler ────────────────────────────────────────────────

def handle_pseudo(inst, parts, pc, labels):
    if inst == 'nop':
        return fmt('0' * 25 + '0010011')             # addi x0, x0, 0
    if inst == 'li':
        v = int(parts[2], 0)
        if -2048 <= v <= 2047:
            return i_type(['addi', parts[1], 'zero', str(v)], '0010011', '000')
        return u_type(['lui', parts[1], str(v >> 12)], '0110111')
    if inst == 'mv':
        return i_type(['addi', parts[1], parts[2], '0'], '0010011', '000')
    if inst == 'j':
        return j_type(['jal', 'zero', parts[1]], '1101111', pc, labels)
    if inst == 'jr':
        return fmt(parse_imm('0', 12) + parse_reg(parts[1]) + '000' + '00000' + '1100111')
    if inst == 'ret':
        return fmt(parse_imm('0', 12) + parse_reg('ra') + '000' + '00000' + '1100111')
    if inst == 'beqz':
        return b_type(['beq', parts[1], 'zero', parts[2]], '1100011', '000', pc, labels)
    if inst == 'bnez':
        return b_type(['bne', parts[1], 'zero', parts[2]], '1100011', '001', pc, labels)
    if inst == 'bltz':
        return b_type(['blt', parts[1], 'zero', parts[2]], '1100011', '100', pc, labels)
    if inst == 'bgez':
        return b_type(['bge', parts[1], 'zero', parts[2]], '1100011', '101', pc, labels)
    if inst == 'not':
        return i_type(['xori', parts[1], parts[2], '-1'], '0010011', '100')
    if inst == 'neg':
        return r_type(['sub', parts[1], 'zero', parts[2]], '0110011', '000', '0100000')

    # --- CSR & INTERRUPT INSTRUCTIONS ---
    
    # mret (Machine Return)
    if inst == 'mret':
        return fmt('00110000001000000000000001110011')
        
    # csrw (CSR Write): Translates to csrrw x0, csr, rs
    if inst == 'csrw':
        csr_addr = format(int(parts[1], 0), '012b')
        rs1      = parse_reg(parts[2])
        rd       = parse_reg('zero')
        return fmt(csr_addr + rs1 + '001' + rd + '1110011')
        
    # csrr (CSR Read): Translates to csrrs rd, csr, x0
    if inst == 'csrr':
        rd       = parse_reg(parts[1])
        csr_addr = format(int(parts[2], 0), '012b')
        rs1      = parse_reg('zero')
        return fmt(csr_addr + rs1 + '010' + rd + '1110011')

    return None

# ── main ──────────────────────────────────────────────────────────────────────

def main():
    # Determine input/output paths from command-line argument
    script_dir = os.path.dirname(os.path.abspath(__file__))

    if len(sys.argv) < 2:
        print("Usage: python assembler.py <test_name>")
        print("  Reads  sim/asm/<test_name>.asm")
        print("  Writes sim/hex/<test_name>.hex")
        sys.exit(1)

    test_name   = sys.argv[1]
    asm_dir     = os.path.join(script_dir, "asm")
    hex_dir     = os.path.join(script_dir, "hex")
    input_file  = os.path.join(asm_dir, f"{test_name}.asm")
    output_file = os.path.join(hex_dir,  f"{test_name}.hex")

    os.makedirs(asm_dir, exist_ok=True)
    os.makedirs(hex_dir,  exist_ok=True)

    if not os.path.exists(input_file):
        print(f"[ERROR] Assembly file not found: {input_file}")
        sys.exit(1)

    # Read and strip comments / blank lines
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = [line.split('#')[0].strip() for line in f if line.split('#')[0].strip()]

    # First pass — collect labels
    labels = {}
    clean  = []
    pc     = 0
    for line in lines:
        if line.endswith(':'):
            labels[line[:-1]] = pc
        else:
            clean.append((pc, line))
            pc += 4

    # Second pass — assemble
    hex_output = []
    print(f"\n--- RV32I Assembler: {test_name} ---")
    for pc, line in clean:
        parts = line.replace(',', ' ').split()
        inst  = parts[0].lower()
        code  = handle_pseudo(inst, parts, pc, labels)

        if code is None:
            if inst not in INST:
                print(f"[ERROR] Unknown instruction '{inst}' at PC=0x{pc:04x}")
                sys.exit(1)
            info = INST[inst]
            t = info['t']
            if   t == 'R':   code = r_type(parts, info['op'], info['f3'], info['f7'])
            elif t == 'I':   code = i_type(parts, info['op'], info['f3'])
            elif t == 'IS':  code = i_shift(parts, info['op'], info['f3'], info['f7'])
            elif t == 'IL':  code = i_load(parts, info['op'], info['f3'])
            elif t == 'S':   code = s_type(parts, info['op'], info['f3'])
            elif t == 'B':   code = b_type(parts, info['op'], info['f3'], pc, labels)
            elif t == 'U':   code = u_type(parts, info['op'])
            elif t == 'J':   code = j_type(parts, info['op'], pc, labels)

        print(f"  0x{pc:04x}  {line:<30}  ->  {code}")
        hex_output.append(code)

    with open(output_file, 'w') as f:
        f.write('\n'.join(hex_output))

    print(f"\n[OK] {len(hex_output)} instructions → {output_file}\n")

if __name__ == "__main__":
    main()