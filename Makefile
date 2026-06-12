BIN := $(shell pwd)/.build/release/big-banner
INSTALL_DIR := $(HOME)/bin

.PHONY: build run soft-install hard-install uninstall clean

build:
	swift build -c release

run: build
	$(BIN) $(TEXT)

soft-install: build
	mkdir -p $(INSTALL_DIR)
	ln -sf $(BIN) $(INSTALL_DIR)/big-banner
	ln -sf $(BIN) $(INSTALL_DIR)/b

hard-install: build
	mkdir -p $(INSTALL_DIR)
	cp $(BIN) $(INSTALL_DIR)/big-banner
	ln -sf $(INSTALL_DIR)/big-banner $(INSTALL_DIR)/b

uninstall:
	rm -f $(INSTALL_DIR)/big-banner $(INSTALL_DIR)/b

clean:
	swift package clean
