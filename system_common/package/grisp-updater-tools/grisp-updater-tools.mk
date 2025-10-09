#############################################################
#
# grisp-updater-tools
#
#############################################################

GRISP_UPDATER_TOOLS_VERSION = main
GRISP_UPDATER_TOOLS_SITE = $(call github,grisp,grisp_updater_tools,$(GRISP_UPDATER_TOOLS_VERSION))
GRISP_UPDATER_TOOLS_LICENSE = Apache-2.0
GRISP_UPDATER_TOOLS_LICENSE_FILES = LICENSE
GRISP_UPDATER_TOOLS_DEPENDENCIES = host-erlang host-erlang-rebar3

define HOST_GRISP_UPDATER_TOOLS_BUILD_CMDS
	cd $(@D) && $(HOST_CONFIGURE_OPTS) env -u GIT_DIR rebar3 escriptize
endef

define HOST_GRISP_UPDATER_TOOLS_INSTALL_CMDS
	$(INSTALL) -m 0755 -d $(HOST_DIR)/bin
	$(INSTALL) -m 755 $(@D)/scripts/grisp_updater_tools $(HOST_DIR)/bin
endef

$(eval $(host-generic-package))
