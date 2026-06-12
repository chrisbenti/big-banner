BIN := $(shell pwd)/.build/release/banner
INSTALL_DIR := $(HOME)/bin

.PHONY: build run soft-install hard-install uninstall clean

build:
	swift build -c release

run: build
	$(BIN) $(TEXT)

soft-install: build
	mkdir -p $(INSTALL_DIR)
	ln -sf $(BIN) $(INSTALL_DIR)/banner

hard-install: build
	mkdir -p $(INSTALL_DIR)
	cp $(BIN) $(INSTALL_DIR)/banner

uninstall:
	rm -f $(INSTALL_DIR)/banner

clean:
	swift package clean
