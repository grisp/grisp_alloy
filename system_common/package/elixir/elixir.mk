################################################################################
#
# Elixir
#
################################################################################

ELIXIR_VERSION = 1.18.4
ELIXIR_SITE = https://github.com/elixir-lang/elixir/archive/refs/tags
ELIXIR_SOURCE = v$(ELIXIR_VERSION).tar.gz
ELIXIR_SUBDIR = elixir-$(ELIXIR_VERSION)
ELIXIR_LICENSE = Apache-2.0
ELIXIR_LICENSE_FILES = LICENSE

# Elixir builds to BEAM bytecode and requires a working Erlang toolchain to
# compile. We force using the host Erlang tools even for target builds to avoid
# running target binaries on the build host.
ELIXIR_DEPENDENCIES = erlang

ELIXIR_MAKE_ENV = \
	ERL=$(HOST_DIR)/usr/bin/erl \
	ERLC=$(HOST_DIR)/usr/bin/erlc \
	ELIXIR_ERL_OPTIONS=+fnu \
	PATH="$(HOST_DIR)/usr/bin:$$PATH"

define ELIXIR_BUILD_CMDS
	$(ELIXIR_MAKE_ENV) $(MAKE) -C $(@D)
endef

# Do not install Elixir to the target rootfs by default.
define ELIXIR_INSTALL_TARGET_CMDS
	true
endef

# Install Elixir into the staging dir so that release assembly can reference it
# if needed. This does not place Elixir into the final rootfs.
define ELIXIR_INSTALL_STAGING_CMDS
	$(ELIXIR_MAKE_ENV) $(MAKE) -C $(@D) DESTDIR=$(STAGING_DIR) PREFIX=/usr install
endef

################################################################################
# Host variant (for SDK/toolchain)
################################################################################

HOST_ELIXIR_DEPENDENCIES = host-erlang

define HOST_ELIXIR_BUILD_CMDS
	$(ELIXIR_MAKE_ENV) $(MAKE) -C $(@D)
endef

define HOST_ELIXIR_INSTALL_CMDS
	$(ELIXIR_MAKE_ENV) $(MAKE) -C $(@D) DESTDIR=$(HOST_DIR) PREFIX=/usr install
endef

$(eval $(generic-package))
$(eval $(host-generic-package))
