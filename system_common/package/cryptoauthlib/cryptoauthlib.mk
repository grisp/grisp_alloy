#############################################################
#
# cryptoauthlib
#
#############################################################

CRYPTOAUTHLIB_VERSION = v3.3.0
CRYPTOAUTHLIB_SITE = $(call github,MicrochipTech,cryptoauthlib,$(CRYPTOAUTHLIB_VERSION))
CRYPTOAUTHLIB_LICENSE = Apache-2.0
CRYPTOAUTHLIB_LICENSE_FILES = license.txt
CRYPTOAUTHLIB_INSTALL_STAGING = YES
CRYPTOAUTHLIB_CONF_OPTS += \
	-DATCA_HAL_I2C=ON \
	-DATCA_PKCS11=ON \
	-DATCA_OPENSSL=ON \
	-DATCA_ATECC508A_SUPPORT=ON \
	-DATCA_ATECC608_SUPPORT=ON \
	-DATCA_BUILD_SHARED_LIBS=ON \
	-DATCA_USE_ATCAB_FUNCTIONS=ON

define CRYPTOAUTHLIB_ADD_DEVICE_CONF
	$(RM) -rf $(TARGET_DIR)/var/lib/cryptoauthlib/slot.conf.tmpl
	$(INSTALL) -D -m 0644 $(CRYPTOAUTHLIB_PKGDIR)/files/0.conf $(TARGET_DIR)/var/lib/cryptoauthlib/0.conf
endef

define CRYPTOAUTHLIB_ADD_MISSING_HEADERS
	$(INSTALL) -D -m 0644 $(CRYPTOAUTHLIB_PKGDIR)/files/atca_start_config.h $(STAGING_DIR)/usr/include/cryptoauthlib/hal/atca_start_config.h
	$(INSTALL) -D -m 0644 $(CRYPTOAUTHLIB_PKGDIR)/files/atca_start_iface.h $(STAGING_DIR)/usr/include/cryptoauthlib/hal/atca_start_iface.h
endef

CRYPTOAUTHLIB_POST_INSTALL_STAGING_HOOKS += CRYPTOAUTHLIB_ADD_MISSING_HEADERS
CRYPTOAUTHLIB_POST_INSTALL_TARGET_HOOKS += CRYPTOAUTHLIB_ADD_DEVICE_CONF

$(eval $(cmake-package))
