# Include common Grisp packages
include $(sort $(wildcard $(GRISP_COMMON_SYSTEM_DIR)/package/*/*.mk))

# Pull in any target-specific packages
-include $(GRISP_TARGET_SYSTEM_DIR)/external.mk

system:
	$(GRISP_COMMON_SYSTEM_DIR)/scripts/make-system.sh


.PHONY: system
