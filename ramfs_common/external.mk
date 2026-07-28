# Ramfs builds intentionally avoid system_common packages. Flavours may add
# their own package trees later through GRISP_RAMFS_FLAVOUR_DIR.
-include $(sort $(wildcard $(GRISP_RAMFS_FLAVOUR_DIR)/package/*/*.mk))
