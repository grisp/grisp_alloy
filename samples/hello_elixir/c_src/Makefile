ERL_EI_INCLUDE_DIR ?= $(ERL_INTERFACE_INCLUDE_DIR)
ERL_EI_LIBDIR ?= $(ERL_INTERFACE_LIB_DIR)
ERTS_INCLUDE_DIR ?= $(ERL_EI_INCLUDE_DIR)/..

CROSSCOMPILE ?=
CC ?= $(CROSSCOMPILE)gcc
STRIP ?= $(CROSSCOMPILE)strip

# Always append ERTS/EI include dirs, even if CFLAGS is set from the environment
CFLAGS ?= -O2 -fPIC
CFLAGS += -I$(ERTS_INCLUDE_DIR) -I$(ERL_EI_INCLUDE_DIR)

# Always ensure we build a shared object and can find EI libs even if LDFLAGS is preset
LDFLAGS += -shared -L$(ERL_EI_LIBDIR)
LIBS ?=

SRC = hello.c
TARGET = ../priv/hello.so

all: $(TARGET)

../priv:
	mkdir -p $@

$(TARGET): ../priv $(SRC)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDFLAGS) $(LIBS)
	$(STRIP) $@

clean:
	rm -f $(TARGET)

.PHONY: all clean
