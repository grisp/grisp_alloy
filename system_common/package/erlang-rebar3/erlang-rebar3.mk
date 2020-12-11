#############################################################
#
# erlang-rebar3
#
#############################################################

ERLANG_REBAR3_VERSION = 3.14.3
ERLANG_REBAR3_SITE = $(call github,erlang,rebar3,$(ERLANG_REBAR3_VERSION))
ERLANG_REBAR3_LICENSE = Apache-2.0
ERLANG_REBAR3_LICENSE_FILES = LICENSE
ERLANG_REBAR3_DEPENDENCIES = host-erlang

define HOST_ERLANG_REBAR3_BUILD_CMDS
	cd $(@D); $(HOST_DIR)/bin/escript ./bootstrap
endef

define HOST_ERLANG_REBAR3_INSTALL_CMDS
	$(INSTALL) -m 0755 -d $(HOST_DIR)/bin
	$(INSTALL) -m 755 $(@D)/rebar3 $(HOST_DIR)/bin
endef

$(eval $(host-generic-package))
