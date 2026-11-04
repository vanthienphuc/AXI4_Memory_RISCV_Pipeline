.section .text
.global main

main:
    addi x1, x0, 64

    # 1. Test Back-to-Back Stores
    addi x2, x0, 300
    addi x3, x0, 400
    sw   x2, 0(x1)      # write 300 in addr 64
    sw   x3, 4(x1)      # write 400 in addr 68

    # 2. Test Read-After-Write (RAW) Hazard & Back-to-Back Loads
    lw   x4, 0(x1)      # Read immediately addr 64. Pipeline must stall
    lw   x5, 4(x1)      # Read addr 68

    # 3. Test Data Forwarding 
    add  x6, x4, x5     # x6 = 300 + 400 = 700
    addi x11, x0, 700
    bne  x6, x11, fail

    # 4. Test WSTRB Masking (Half-word write instruction - SH)
    li   x8, 0x1234
    sh   x8, 8(x1)      # Write 2 byte into addr 72
    lhu  x9, 8(x1)      # read back as Unsigned Halfword
    bne  x8, x9, fail

success:
    addi x7, x0, 1      # PASS
    beq  x0, x0, end

fail:
    addi x7, x0, -1     # FAIL

end:
    beq  x0, x0, end


.section .text
.global main

main:
    addi x1, x0, 64              # Base address for memory operations

    # ==========================================
    # [TC1] Basic Function
    # Verify isolated Store Word and Load Word
    # ==========================================
    addi x2, x0, 100
    sw   x2, 0(x1)               # Write 100 to addr 64
    addi x0, x0, 0               # Dummy delay to isolate from pipeline hazards
    lw   x3, 0(x1)               # Read back from addr 64
    bne  x2, x3, fail            # Compare: Jump to fail if mismatch

    # ==========================================
    # [TC2] Corner Case
    # Verify Half-word write (SH) and WSTRB masking
    # ==========================================
    li   x8, 0x1234
    sh   x8, 4(x1)               # Write 2 bytes (Half-word) to addr 68
    lhu  x9, 4(x1)               # Read back as Unsigned Half-word
    bne  x8, x9, fail            # Compare: Jump to fail if WSTRB failed

    # ==========================================
    # [TC3] Stress / Random
    # Verify continuous Array Loop (Burst-like)
    # ==========================================
    addi x12, x0, 10             # Loop counter = 10 iterations
    addi x13, x1, 100            # Array base address = 164 (64 + 100)
    addi x14, x0, 1              # Initial data payload = 1

write_loop:
    sw   x14, 0(x13)             # Write payload to memory
    addi x13, x13, 4             # Increment address by 4
    addi x14, x14, 1             # Increment payload
    addi x12, x12, -1            # Decrement counter
    bne  x12, x0, write_loop     # Loop until counter == 0

    addi x12, x0, 10             # Reset Loop counter = 10
    addi x13, x1, 100            # Reset Array base address
    addi x14, x0, 1              # Reset expected payload

read_loop:
    lw   x15, 0(x13)             # Read from memory
    bne  x15, x14, fail          # Compare: Jump to fail if mismatch
    addi x13, x13, 4
    addi x14, x14, 1
    addi x12, x12, -1
    bne  x12, x0, read_loop

    # ==========================================
    # [TC4] Protocol / Hazard
    # Verify Back-to-Back, RAW, Load-Use & Forwarding
    # ==========================================
    addi x16, x0, 300
    addi x17, x0, 400
    sw   x16, 20(x1)             # Back-to-back store 1 (addr 64+ 20=84)
    sw   x17, 24(x1)             # Back-to-back store 2 (addr 88)
    lw   x18, 20(x1)             # x18=300, RAW hazard & back-to-back load 1
    lw   x19, 24(x1)             # x17=400, Back-to-back load 2
    add  x20, x18, x19           # Load-use hazard & Data Forwarding
    addi x21, x0, 700            # Expected: 300 + 400 = 700
    bne  x20, x21, fail          # Compare final forwarded result

success:
    addi x7, x0, 1               # PASS flag
    beq  x0, x0, end

fail:
    addi x7, x0, -1              # FAIL flag

end:
    beq  x0, x0, end


