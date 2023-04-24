#############################################################
#
# cryptoauthlib
#
#############################################################

CRYPTOAUTHLIB_VERSION = v3.3.3
CRYPTOAUTHLIB_SITE = $(call github,MicrochipTech,cryptoauthlib,$(CRYPTOAUTHLIB_VERSION))
CRYPTOAUTHLIB_LICENSE = Apache-2.0
CRYPTOAUTHLIB_LICENSE_FILES = license.txt
CRYPTOAUTHLIB_INSTALL_STAGING = YES
CRYPTOAUTHLIB_CONF_OPTS += \
	-DATCA_HAL_I2C=ON \
	-DATCA_ATECC608_SUPPORT=ON \
	-DATCA_USE_ATCAB_FUNCTIONS=ON \
	-DUNIX=true

define CRYPTOAUTHLIB_ADD_MISSING_HEADERS
	$(INSTALL) -D -m 0644 $(CRYPTOAUTHLIB_PKGDIR)/files/atca_start_config.h $(STAGING_DIR)/usr/include/cryptoauthlib/hal/atca_start_config.h
	$(INSTALL) -D -m 0644 $(CRYPTOAUTHLIB_PKGDIR)/files/atca_start_iface.h $(STAGING_DIR)/usr/include/cryptoauthlib/hal/atca_start_iface.h
endef

CRYPTOAUTHLIB_POST_INSTALL_STAGING_HOOKS += CRYPTOAUTHLIB_ADD_MISSING_HEADERS

$(eval $(cmake-package))
