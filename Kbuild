#obj-m += axp20x_ac_power.o
#obj-m += axp20x_adc.o
#obj-m += ti-adc081c.o
#obj-m += axp20x_battery.o
#obj-m += axp20x_usb_power.o

obj-m += panel-cwu50.o
obj-m += panel-clockwork-cwu50.o
obj-m += panel-cwu50-nova-cm5.o
obj-m += panel-cwu50-rex-cm5.o
obj-m += ocp8178_bl.o
obj-m += ocp8178_bl-nova-cm5.o


#axp20x_ac_power-objs := src/axp20x_ac_power.o
#axp20x_adc-objs := src/axp20x_adc.o
#ti-adc081c-objs := src/ti-adc081c.o
#axp20x_battery-objs := src/axp20x_battery.o
#axp20x_usb_power-objs := src/axp20x_usb_power.o

panel-clockwork-cwu50-objs := src/panel-clockwork-cwu50.o
panel-cwu50-objs := src/panel-cwu50.o
ocp8178_bl-objs := src/ocp8178_bl.o
ocp8178_bl-nova-cm5-objs := src/ocp8178_bl-nova-cm5.o

panel-cwu50-rex-cm5-objs := src/panel-cwu50-rex-cm5.o
panel-cwu50-nova-cm5-objs := src/panel-cwu50-nova-cm5.o

ccflags-y := -I$(src)/include

subdir-y := overlays