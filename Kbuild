# uConsole Kernel Module Build Configuration
# Organized by platform and functionality

# =============================================================================
# Platform Selection via Environment Variables
# Platform is set by build_kernel.sh via PLATFORM variable
# =============================================================================

# Always include common drivers (AXP20X power management) - DISABLED FOR NOW
# These drivers have kernel API compatibility issues with 6.12.y and are not essential for display functionality
# obj-m += axp20x_ac_power.o
# obj-m += axp20x_adc.o  
# obj-m += ti-adc081c.o
# obj-m += axp20x_battery.o
# obj-m += axp20x_usb_power.o

# Platform-specific drivers
ifeq ($(PLATFORM),cm4)
obj-m += panel-cwu50.o
obj-m += ocp8178_bl.o
endif

ifeq ($(PLATFORM),cm5)  
obj-m += panel-clockwork-cwu50.o
obj-m += panel-cwu50-nova-cm5.o
obj-m += panel-cwu50-rex-cm5.o
obj-m += ocp8178_bl-nova-cm5.o
endif

# If no platform specified, include both (for compatibility)
ifndef PLATFORM
obj-m += panel-cwu50.o
obj-m += ocp8178_bl.o
obj-m += panel-clockwork-cwu50.o
obj-m += panel-cwu50-nova-cm5.o
obj-m += panel-cwu50-rex-cm5.o
obj-m += ocp8178_bl-nova-cm5.o
endif

# Source file mappings for common drivers - DISABLED FOR NOW
# axp20x_ac_power-objs := src/common/power/axp20x_ac_power.o
# axp20x_adc-objs := src/common/power/axp20x_adc.o
# ti-adc081c-objs := src/common/power/ti-adc081c.o
# axp20x_battery-objs := src/common/power/axp20x_battery.o
# axp20x_usb_power-objs := src/common/power/axp20x_usb_power.o

# Source file mappings for CM4 drivers
panel-cwu50-objs := src/cm4/display/panel-cwu50.o
ocp8178_bl-objs := src/cm4/backlight/ocp8178_bl.o

# Source file mappings for CM5 drivers
panel-clockwork-cwu50-objs := src/cm5/display/panel-clockwork-cwu50.o
panel-cwu50-nova-cm5-objs := src/cm5/display/panel-cwu50-nova-cm5.o
panel-cwu50-rex-cm5-objs := src/cm5/display/panel-cwu50-rex-cm5.o
ocp8178_bl-nova-cm5-objs := src/cm5/backlight/ocp8178_bl-nova-cm5.o

# Include header directories
ccflags-y := -I$(src)/include

# Device tree overlays (platform-agnostic)
subdir-y += overlays