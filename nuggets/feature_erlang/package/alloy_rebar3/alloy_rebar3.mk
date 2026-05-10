#############################################################
#
# alloy_rebar3
#
#############################################################

ALLOY_REBAR3_VERSION = 3.25.0
ALLOY_REBAR3_SITE = $(call github,erlang,rebar3,$(ALLOY_REBAR3_VERSION))
ALLOY_REBAR3_LICENSE = Apache-2.0
ALLOY_REBAR3_LICENSE_FILES = LICENSE
ALLOY_REBAR3_DEPENDENCIES = host-alloy_erlang

define HOST_ALLOY_REBAR3_BUILD_CMDS
	cd $(@D) && $(HOST_DIR)/bin/escript ./bootstrap
endef

define HOST_ALLOY_REBAR3_INSTALL_CMDS
	$(INSTALL) -m 0755 -d $(HOST_DIR)/bin
	$(INSTALL) -m 0755 $(@D)/rebar3 $(HOST_DIR)/bin
	$(INSTALL) -m 0755 -d $(HOST_DIR)/usr/bin
	ln -sf ../../bin/rebar3 $(HOST_DIR)/usr/bin/rebar3
endef

$(eval $(host-generic-package))
