BUILD_DIR := build
NASM ?= nasm

STAGE1_SRC := boot/stage1.asm
STAGE2_SRC := boot/stage2.asm
STAGE1_BIN := $(BUILD_DIR)/stage1.bin
STAGE2_BIN := $(BUILD_DIR)/stage2.bin
STAGE2_INC := $(BUILD_DIR)/stage2.inc
IMAGE      := $(BUILD_DIR)/novaos.img

.PHONY: all clean

all: $(IMAGE)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(STAGE2_BIN): $(STAGE2_SRC) | $(BUILD_DIR)
	$(NASM) -f bin $< -o $@

$(STAGE2_INC): $(STAGE2_BIN)
	scripts/gen_stage2_inc.sh $< $@

$(STAGE1_BIN): $(STAGE1_SRC) $(STAGE2_INC) | $(BUILD_DIR)
	$(NASM) -f bin -I$(BUILD_DIR) $< -o $@

$(IMAGE): $(STAGE1_BIN) $(STAGE2_BIN)
	cat $(STAGE1_BIN) $(STAGE2_BIN) > $@

clean:
	rm -rf $(BUILD_DIR)
