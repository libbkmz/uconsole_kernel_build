# KDIR ?= /lib/modules/$(shell uname -r)/build
# KDIR ?= /lib/modules/6.6.62+rpt-rpi-v8/build
# KDIR ?= /home/bkmz/dev/uconsole/linux
KDIR ?= /mnt/git_repos/rpi_linux

# DTC ?= $(KDIR)/scripts/dtc/dtc

export KDIR

default:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
	$(MAKE) -C $(KDIR) M=$(PWD)/overlays KDIR=$(KDIR)
	# $(MAKE) -C $(PWD)/overlays
	

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	$(MAKE) -C $(KDIR) M=$(PWD)/overlays KDIR=$(KDIR) clean
	# $(MAKE) -C $(PWD)/overlays clean

install:
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install


# %.dtbo: %.dts
# 	$(DTC) -@ -I dts -O dtb -o $@ $<