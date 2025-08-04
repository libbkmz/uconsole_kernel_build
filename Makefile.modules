# KDIR must be set by build_kernel.sh script
ifndef KDIR
$(error KDIR is not set. Use build_kernel.sh script to build.)
endif

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