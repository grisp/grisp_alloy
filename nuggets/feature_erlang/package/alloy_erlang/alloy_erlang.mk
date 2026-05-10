################################################################################
#
# alloy_erlang
#
################################################################################

ALLOY_ERLANG_VERSION = 28.4
ALLOY_ERLANG_RELEASE = $(firstword $(subst ., ,$(ALLOY_ERLANG_VERSION)))
ALLOY_ERLANG_SITE = https://github.com/erlang/otp/releases/download/OTP-$(ALLOY_ERLANG_VERSION)
ALLOY_ERLANG_SOURCE = otp_src_$(ALLOY_ERLANG_VERSION).tar.gz
ALLOY_ERLANG_DEPENDENCIES = host-alloy_erlang

ALLOY_ERLANG_LICENSE = Apache-2.0
ALLOY_ERLANG_LICENSE_FILES = LICENSE.txt
ALLOY_ERLANG_CPE_ID_VENDOR = erlang
ALLOY_ERLANG_CPE_ID_PRODUCT = erlang\/otp
ALLOY_ERLANG_INSTALL_STAGING = YES
ALLOY_ERLANG_INSTALL_TARGET = $(if $(BR2_PACKAGE_ALLOY_ERLANG_GLOBAL_RUNTIME),YES,NO)

# Return EI_VSN value from installed_application_versions.
alloy_erlang_ei_vsn = `sed -r -e '/^erl_interface-(.+)/!d; s//\1/' $(firstword $(wildcard $(1)/lib/erlang/releases/*/installed_application_versions))`

define ALLOY_ERLANG_FIX_AUTOCONF_VERSION
	$(SED) "s/USE_AUTOCONF_VERSION=.*/USE_AUTOCONF_VERSION=$(AUTOCONF_VERSION)/" $(@D)/otp_build
endef

define ALLOY_ERLANG_RUN_AUTOCONF
	cd $(@D) && PATH=$(BR_PATH) ./otp_build update_configure --no-commit
endef
ALLOY_ERLANG_DEPENDENCIES += host-autoconf
ALLOY_ERLANG_PRE_CONFIGURE_HOOKS += ALLOY_ERLANG_FIX_AUTOCONF_VERSION ALLOY_ERLANG_RUN_AUTOCONF
HOST_ALLOY_ERLANG_DEPENDENCIES += host-autoconf
HOST_ALLOY_ERLANG_PRE_CONFIGURE_HOOKS += ALLOY_ERLANG_FIX_AUTOCONF_VERSION ALLOY_ERLANG_RUN_AUTOCONF

ALLOY_ERLANG_CONF_ENV = ac_cv_func_isnan=yes ac_cv_func_isinf=yes
ALLOY_ERLANG_CONF_ENV += erl_xcomp_sysroot=$(STAGING_DIR)
ALLOY_ERLANG_CONF_ENV += erl_xcomp_clock_gettime_cpu_time=$(if $(BR2_PACKAGE_ALLOY_ERLANG_XCOMP_CLOCK_GETTIME_CPU_TIME),yes,no)
ALLOY_ERLANG_CONF_ENV += i_cv_posix_fallocate_works=$(if $(BR2_PACKAGE_ALLOY_ERLANG_POSIX_FALLOCATE_WORKS),yes,no)
ALLOY_ERLANG_CONF_OPTS = --without-javac
ALLOY_ERLANG_CONF_ENV += ERL_TOP=$(@D)
HOST_ALLOY_ERLANG_CONF_ENV += ERL_TOP=$(@D)

HOST_ALLOY_ERLANG_DEPENDENCIES += host-openssl
HOST_ALLOY_ERLANG_CONF_OPTS = --without-javac --with-ssl=$(HOST_DIR) --without-termcap

ifeq ($(BR2_PACKAGE_NCURSES),y)
ALLOY_ERLANG_CONF_OPTS += --with-termcap
ALLOY_ERLANG_DEPENDENCIES += ncurses
else
ALLOY_ERLANG_CONF_OPTS += --without-termcap
endif

ifeq ($(BR2_PACKAGE_OPENSSL),y)
ALLOY_ERLANG_CONF_OPTS += --with-ssl
ALLOY_ERLANG_DEPENDENCIES += openssl
else
ALLOY_ERLANG_CONF_OPTS += --without-ssl
endif

ifeq ($(BR2_PACKAGE_UNIXODBC),y)
ALLOY_ERLANG_DEPENDENCIES += unixodbc
ALLOY_ERLANG_CONF_OPTS += --with-odbc
else
ALLOY_ERLANG_CONF_OPTS += --without-odbc
endif

ALLOY_ERLANG_CONF_OPTS += --disable-builtin-zlib
ALLOY_ERLANG_DEPENDENCIES += zlib

ALLOY_ERLANG_REMOVE_PACKAGES = gs wx megaco

define ALLOY_ERLANG_REMOVE_STAGING_UNUSED
	for package in $(ALLOY_ERLANG_REMOVE_PACKAGES); do \
		rm -rf $(STAGING_DIR)/usr/lib/erlang/lib/$${package}-*; \
	done
endef

ifeq ($(BR2_PACKAGE_ALLOY_ERLANG_GLOBAL_RUNTIME),y)
define ALLOY_ERLANG_REMOVE_TARGET_UNUSED
	find $(TARGET_DIR)/usr/lib/erlang -type d -name src -prune -exec rm -rf {} \;
	find $(TARGET_DIR)/usr/lib/erlang -type d -name examples -prune -exec rm -rf {} \;
	for package in $(ALLOY_ERLANG_REMOVE_PACKAGES); do \
		rm -rf $(TARGET_DIR)/usr/lib/erlang/lib/$${package}-*; \
	done
endef
ALLOY_ERLANG_POST_INSTALL_TARGET_HOOKS += ALLOY_ERLANG_REMOVE_TARGET_UNUSED
endif

ALLOY_ERLANG_POST_INSTALL_STAGING_HOOKS += ALLOY_ERLANG_REMOVE_STAGING_UNUSED

$(eval $(autotools-package))
$(eval $(host-autotools-package))
