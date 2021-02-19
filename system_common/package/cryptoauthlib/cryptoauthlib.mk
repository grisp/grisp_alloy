#############################################################
#
# cryptoauthlib
#
#############################################################

CRYPTOAUTHLIB_VERSION = v3.3.0
CRYPTOAUTHLIB_SITE = $(call github,MicrochipTech,cryptoauthlib,$(CRYPTOAUTHLIB_VERSION))
CRYPTOAUTHLIB_LICENSE = Apache-2.0
CRYPTOAUTHLIB_LICENSE_FILES = license.txt
CRYPTOAUTHLIB_CONF_OPTS = -D ATCA_HAL_I2C=ON -D ATCA_PKCS11=ON -D ATCA_OPENSSL=ON -D ATCA_ATECC508A_SUPPORT=ON -D ATCA_ATECC608_SUPPORT=ON -D ATCA_BUILD_SHARED_LIBS=ON

define CRYPTOAUTHLIB_ADD_DEVICE_CONF
	$(RM) -rf $(TARGET_DIR)/var/lib/cryptoauthlib/slot.conf.tmpl
	$(INSTALL) -D -m 0644 $(CRYPTOAUTHLIB_PKGDIR)/files/0.conf $(TARGET_DIR)/var/lib/cryptoauthlib/0.conf
endef

CRYPTOAUTHLIB_POST_INSTALL_TARGET_HOOKS += CRYPTOAUTHLIB_ADD_DEVICE_CONF

$(eval $(cmake-package))
