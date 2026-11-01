# Standard Cargo settings work for both a local Linux build and cross builds.
# Cargo itself consumes CARGO_BUILD_TARGET; it is also needed to locate output.
CARGO ?= cargo
CARGO_PROFILE ?= release
CARGO_TARGET_DIR ?= $(CURDIR)/target
export CARGO_TARGET_DIR

PROFILE_DIR = $(if $(filter dev,$(CARGO_PROFILE)),debug,$(CARGO_PROFILE))
TARGET_DIR = $(CARGO_TARGET_DIR)$(if $(CARGO_BUILD_TARGET),/$(CARGO_BUILD_TARGET))
NIF = ../priv/hello_rust_nif.so

.PHONY: all clean
all:
	"$(CARGO)" build --locked --profile "$(CARGO_PROFILE)"
	mkdir -p ../priv
	cp "$(TARGET_DIR)/$(PROFILE_DIR)/libhello_rust_nif.so" "$(NIF)"

clean:
	"$(CARGO)" clean
	rm -f "$(NIF)"
