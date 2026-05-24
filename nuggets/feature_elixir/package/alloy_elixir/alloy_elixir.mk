################################################################################
#
# alloy_elixir
#
################################################################################

ALLOY_ELIXIR_VERSION = 1.18.4
ALLOY_ELIXIR_SITE = $(call github,elixir-lang,elixir,v$(ALLOY_ELIXIR_VERSION))
ALLOY_ELIXIR_LICENSE = Apache-2.0
ALLOY_ELIXIR_LICENSE_FILES = LICENSE
ALLOY_ELIXIR_DEPENDENCIES = alloy_erlang host-alloy_erlang
ALLOY_ELIXIR_INSTALL_STAGING = YES
ALLOY_ELIXIR_INSTALL_TARGET = $(if $(BR2_PACKAGE_ALLOY_ELIXIR_GLOBAL_RUNTIME),YES,NO)

define ALLOY_ELIXIR_BUILD_CMDS
	cd $(@D) && PATH=$(HOST_DIR)/bin:$$PATH make clean compile
endef

define HOST_ALLOY_ELIXIR_BUILD_CMDS
	cd $(@D) && PATH=$(HOST_DIR)/bin:$$PATH make clean compile
endef

define ALLOY_ELIXIR_INSTALL_STAGING_CMDS
	mkdir -p $(STAGING_DIR)/usr/lib
	cp -a $(@D)/lib $(STAGING_DIR)/usr/lib/elixir
endef

ifeq ($(BR2_PACKAGE_ALLOY_ELIXIR_GLOBAL_RUNTIME),y)
define ALLOY_ELIXIR_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/lib
	cp -a $(@D)/lib $(TARGET_DIR)/usr/lib/elixir
endef
endif

define HOST_ALLOY_ELIXIR_INSTALL_CMDS
	mkdir -p $(HOST_DIR)/usr/lib $(HOST_DIR)/usr/bin
	rm -rf $(HOST_DIR)/usr/lib/elixir
	cp -a $(@D)/lib/. $(HOST_DIR)/usr/lib/
	for tool in elixir iex mix mix.bat; do \
		if [ -f $(@D)/bin/$$tool ]; then \
			install -m 0755 $(@D)/bin/$$tool $(HOST_DIR)/usr/bin/$$tool; \
		fi; \
	done
endef

$(eval $(generic-package))
$(eval $(host-generic-package))
