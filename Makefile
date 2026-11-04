#---------------------------------------------------------------------
# Makefile for Verilog Simulation (Xcelium) & Synthesis (Genus)

# Source: VNCHIP Talent Program
# Reference: https://vnchip-inc.com/
#---------------------------------------------------------------------
SHELL := /bin/bash

# Num Core
CORE       ?= 4
USE_LSF    ?= 1

# Top-level modules
TOP_TB     ?= tb_RISCV_Pipeline_AXI4
TOP_SYN    ?= RISCV_Pipeline_AXI4

# Directories
LIB_DIR    := ./libraries/TIMING/CUSTOM ./libraries/TIMING/STDCELL ./libraries/LEF/STDCELL ./libraries/LEF/CUSTOM ./libraries/LEF/IO
RTL_DIR    := ./rtl
TB_DIR     := ./tb
MEM_DIR    := ./mem
SW_DIR     := ./sw
BUILD_DIR  := ./build_xcelium
LOG_DIR    := ./log
OUT_DIR    := ./output
RPT_DIR    := ./report
SCRIPT_DIR := ./scripts

# Files
LIB_FILE   := ss_g_1v08_125c.lib ss_hvt_1v08_125c.lib ram_256x16A_slow_syn.lib rom_512x16A_slow_syn.lib pllclk_slow.lib
RTL_LIST   := ALU.v ALU_decoder.v axi4_master_bridge.v axi4_slave_mem.v axi4_subsystem.v Branch_Comp.v Branch_Resolve.v \
			  control_unit.v EX_MEM_reg.v forward_unit.v hazard_detect.v ID_EX_reg.v IF_ID_reg.v IMEM.v Imm_Gen.v main_decoder.v \ 
			  MEM_WB_reg.v Program_Counter.v RegisterFile.v RISCV_Pipeline_AXI4.v
RTL_SRCS   := $(addprefix $(RTL_DIR)/,$(RTL_LIST))
TB_FILE    := $(TB_DIR)/tb_RISCV_Pipeline.v
SRCS       := $(RTL_SRCS) $(TB_FILE)
SNAPSHOT   := simv
VCD        := $(TOP_TB).vcd
WAVE_DB    := $(BUILD_DIR)/waves.shm
GENUS_SCRIPT     := $(SCRIPT_DIR)/run_syn.tcl
XMSIM_SCRIPT     := $(SCRIPT_DIR)/run_xmsim.tcl
RESTORE_DB_NAME  := syn.db

# Software files
RISCV_HOME   ?= /opt/riscv32
RISCV_PREFIX ?= riscv32-unknown-elf-
CC           := $(RISCV_PREFIX)gcc
OBJCOPY      := $(RISCV_PREFIX)objcopy
OBJDUMP      := $(RISCV_PREFIX)objdump
SIZE         := $(RISCV_PREFIX)size
READELF      := $(RISCV_PREFIX)readelf

export PATH  := $(RISCV_HOME)/bin:$(RISCV_HOME)/riscv32-unknown-elf/bin:$(PATH)

ARCH_FLAGS   := -march=rv32i -mabi=ilp32
CFLAGS       := $(ARCH_FLAGS) -O1 -ffreestanding -fno-builtin -fno-pic -msmall-data-limit=0 -ffunction-sections -fdata-sections
ASFLAGS      := $(ARCH_FLAGS) -ffreestanding

TEST_CANDIDATES := $(wildcard $(SW_DIR)/test.c $(SW_DIR)/test.S)
TEST_SRC        := $(firstword $(TEST_CANDIDATES))
STARTUP_SRC     := $(SW_DIR)/crt0.S
LINKER_SRC      := $(SW_DIR)/linker.ld
TEST_OBJ        := $(BUILD_DIR)/test.o
STARTUP_OBJ     := $(BUILD_DIR)/crt0.o
ELF             := $(BUILD_DIR)/test.elf
MAP             := $(BUILD_DIR)/test.map
DISASM          := $(BUILD_DIR)/test.dis
IMEM_BIN        := $(BUILD_DIR)/imem.bin
DMEM_BIN        := $(BUILD_DIR)/dmem.bin
IMEM_FULL       := $(BUILD_DIR)/imem_full.bin
DMEM_FULL       := $(BUILD_DIR)/dmem_full.bin
IMEM_HEX        := $(MEM_DIR)/imem.hex
DMEM_HEX        := $(MEM_DIR)/dmem_init.hex

ifeq ($(suffix $(TEST_SRC)),.c)
TEST_FLAGS      := $(CFLAGS)
else
TEST_FLAGS      := $(ASFLAGS)
endif

LDFLAGS         := $(ARCH_FLAGS) -nostdlib -nostartfiles -Wl,--gc-sections -Wl,-T,$(LINKER_SRC) -Wl,-Map,$(MAP)

# GUI settings (1: enable, 0: disable)
GENUS_GUI_ENABLE ?= 1

# Synthesis constraints
CLOCK_NAME            ?= clk
INPUT_DELAY_RATIO     ?= 0.3
OUTPUT_DELAY_RATIO    ?= 0.2
CUSTOM_CONSTRAINT_FILE ?=
IS_COMBINATIONAL      ?= 0

# Clock-period sweep (ns)
START_PERIOD ?= 1
END_PERIOD   ?= 6
STEP         ?= 0.1

# Tools
BSUB     := $(if $(filter 1,$(USE_LSF)),bsub -Is -R "span[hosts=1]" -n $(CORE),)
XMVLOG   := $(BSUB) xmvlog
XMELAB   := $(BSUB) xmelab
XMSIM    := $(BSUB) xmsim
SIMVISION := $(BSUB) simvision
GENUS    := $(BSUB) genus

# Flags
XMVLOG_FLAGS        := -sv -message -log $(LOG_DIR)/xmvlog.log
XMELAB_FLAGS        := -access +rwc -TIMESCALE 1ns/1ps -message -log $(LOG_DIR)/xmelab.log
XMSIM_FLAGS         := -message -log $(LOG_DIR)/xmsim.log
GENUS_SYN_FLAGS     := -log $(LOG_DIR)/genus_syn.log $(if $(filter 1,$(GENUS_GUI_ENABLE)),-gui,)
GENUS_RESTORE_FLAGS := -log $(LOG_DIR)/genus_restore.log $(if $(filter 1,$(GENUS_GUI_ENABLE)),-gui,)

# Default target
all: clean hex wave syn

# Software / HEX generation
sw: hex

hex: $(IMEM_HEX) $(DMEM_HEX)

elf: $(ELF)

disasm: $(DISASM)

analyze: $(ELF)
	$(SIZE) $(ELF)
	$(READELF) -S $(ELF)

check_sw:
	@command -v $(CC) >/dev/null 2>&1 || { echo "Missing $(CC)."; exit 1; }
	@command -v $(OBJCOPY) >/dev/null 2>&1 || { echo "Missing $(OBJCOPY)."; exit 1; }
	@command -v hexdump >/dev/null 2>&1 || { echo "Missing hexdump."; exit 1; }
	@command -v dd >/dev/null 2>&1 || { echo "Missing dd."; exit 1; }

$(BUILD_DIR) $(MEM_DIR) $(LOG_DIR) $(OUT_DIR) $(RPT_DIR):
	mkdir -p $@

$(TEST_OBJ): $(TEST_SRC) | $(BUILD_DIR)
	@test "$(words $(TEST_CANDIDATES))" -eq 1 || { \
		echo "Expected exactly one source: $(SW_DIR)/test.c or $(SW_DIR)/test.S"; \
		exit 1; \
	}
	$(CC) $(TEST_FLAGS) -c "$(TEST_SRC)" -o $@

$(STARTUP_OBJ): $(STARTUP_SRC) | $(BUILD_DIR)
	$(CC) $(ASFLAGS) -c $< -o $@

$(ELF): check_sw $(STARTUP_OBJ) $(TEST_OBJ) $(LINKER_SRC)
	$(CC) $(LDFLAGS) $(STARTUP_OBJ) $(TEST_OBJ) -o $@
	$(SIZE) $@

$(DISASM): $(ELF)
	$(OBJDUMP) -d -S $< > $@

$(IMEM_BIN): $(ELF)
	$(OBJCOPY) -O binary --only-section=.text $< $@

$(DMEM_BIN): $(ELF)
	$(OBJCOPY) -O binary --only-section=.data $< $@

$(IMEM_FULL): $(IMEM_BIN)
	dd if=/dev/zero of=$@ bs=1024 count=1 status=none
	dd if=$< of=$@ conv=notrunc status=none

$(DMEM_FULL): $(DMEM_BIN)
	dd if=/dev/zero of=$@ bs=1024 count=1 status=none
	dd if=$< of=$@ conv=notrunc status=none

$(IMEM_HEX): $(IMEM_FULL) | $(MEM_DIR)
	hexdump -v -e '1/4 "%08x\n"' $< > $@
	@test "$$(wc -l < $@)" -eq 256

$(DMEM_HEX): $(DMEM_FULL) | $(MEM_DIR)
	hexdump -v -e '1/4 "%08x\n"' $< > $@
	@test "$$(wc -l < $@)" -eq 256

compile: hex
	@mkdir -p $(LOG_DIR)
	@echo "Compiling RTL files..."
	$(XMVLOG) $(XMVLOG_FLAGS) $(SRCS)

build: compile
	@echo "Elaborating top testbench..."
	$(XMELAB) $(XMELAB_FLAGS) -snapshot $(SNAPSHOT) $(TOP_TB)

run: build
	@echo "Running simulation..."
	$(XMSIM) $(XMSIM_FLAGS) -input $(XMSIM_SCRIPT) $(SNAPSHOT)

sim: run

wave: run
	@echo "Launching waveform viewer..."
	$(SIMVISION) $(WAVE_DB)

syn:
	@mkdir -p $(LOG_DIR) $(OUT_DIR) $(RPT_DIR)
	@echo "Running synthesis with Genus..."
	$(GENUS) $(GENUS_SYN_FLAGS) \
		-files $(GENUS_SCRIPT) \
		-execute "set TOP $(TOP_SYN); \
		set LIB_DIR {$(LIB_DIR)}; \
		set RTL_DIR {$(RTL_DIR)}; \
		set OUT_DIR {$(OUT_DIR)}; \
		set RPT_DIR {$(RPT_DIR)}; \
		set LIB_FILE {$(LIB_FILE)}; \
		set RTL_LIST {$(RTL_LIST)}; \
		set RESTORE_DB_NAME {$(RESTORE_DB_NAME)}; \
		set CLOCK_NAME {$(CLOCK_NAME)}; \
		set INPUT_DELAY_RATIO {$(INPUT_DELAY_RATIO)}; \
		set OUTPUT_DELAY_RATIO {$(OUTPUT_DELAY_RATIO)}; \
		set CUSTOM_CONSTRAINT_FILE {$(CUSTOM_CONSTRAINT_FILE)}; \
		set IS_COMBINATIONAL {$(IS_COMBINATIONAL)}; \
		set START_PERIOD {$(START_PERIOD)}; \
		set END_PERIOD {$(END_PERIOD)}; \
		set STEP {$(STEP)}; \
		set GENUS_GUI_ENABLE {$(GENUS_GUI_ENABLE)};"

restore_syn:
	@echo "Restoring Genus with synthesized design..."
	@mkdir -p $(LOG_DIR)
	$(GENUS) $(GENUS_RESTORE_FLAGS) \
		-execute "read_db -verbose {$(OUT_DIR)/$(RESTORE_DB_NAME)}"

help:
	@echo "Targets:"
	@echo "  make         Clean, build HEX, simulate and synthesize"
	@echo "  make hex     Build imem.hex and dmem_init.hex"
	@echo "  make disasm  Generate build_xcelium/test.dis"
	@echo "  make compile Compile RTL with xmvlog"
	@echo "  make build   Elaborate the testbench with xmelab"
	@echo "  make run     Run simulation with xmsim"
	@echo "  make sim     Alias of make run"
	@echo "  make wave    Open the SHM database in SimVision"
	@echo "  make syn     Synthesize and sweep clock periods with Genus"
	@echo "  make         Override with START_PERIOD=... END_PERIOD=... STEP=..."
	@echo "  make clean   Remove generated files"

clean:
	@echo "Cleaning up..."
	rm -rf *.vcd *.dsn *.trn xcelium.d fv tmp *tstamp xrun.history xrun.log \
		$(BUILD_DIR) $(LOG_DIR) $(OUT_DIR) $(RPT_DIR)
	rm -f $(IMEM_HEX) $(DMEM_HEX) genus.cmd genus.log

.PHONY: all help sw hex elf disasm analyze check_sw compile build \
        run sim wave syn restore_syn clean


		