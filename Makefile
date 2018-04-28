GASNET_VERSION = GASNet-1.30.0

# these patches are applied to the unpacked GASNet source directory before
#  running configure
PATCHES =
# mpifix.patch not needed after 1.28.2
#PATCHES += patches/mpifix.patch

ifeq ($(findstring daint,$(shell uname -n)),daint)
CROSS_CONFIGURE = cross-configure-cray-aries-slurm
endif
ifeq ($(findstring excalibur,$(shell uname -n)),excalibur)
CROSS_CONFIGURE = cross-configure-cray-aries-slurm
endif
ifeq ($(findstring cori,$(shell uname -n)),cori)
CROSS_CONFIGURE = cross-configure-cray-aries-slurm
endif
ifeq ($(findstring titan,$(shell uname -n)),titan)
CROSS_CONFIGURE = cross-configure-cray-gemini-alps
endif

ifndef CONDUIT
$(error CONDUIT must be set to ibv, gemini, or aries)
endif

RELEASE_DIR ?= $(shell pwd)/release

RELEASE_CONFIG = configs/config.$(CONDUIT).release

.PHONY: release

release : $(RELEASE_DIR)/config.status
	make -C release install

$(RELEASE_DIR)/config.status : $(RELEASE_CONFIG) $(GASNET_VERSION)/configure
ifdef CROSS_CONFIGURE
# Cray systems require cross-compiling fun
	mkdir -p $(RELEASE_DIR)
	# WAH for issue with new Cray cc/CC not including PMI stuff
	echo '#!/bin/bash' > $(RELEASE_DIR)/cc.custom
	echo 'cc "$$@" $$CRAY_UGNI_POST_LINK_OPTS $$CRAY_PMI_POST_LINK_OPTS -Wl,--as-needed,-lugni,-lpmi,--no-as-needed' >> $(RELEASE_DIR)/cc.custom
	chmod a+x $(RELEASE_DIR)/cc.custom
	echo '#!/bin/bash' > $(RELEASE_DIR)/CC.custom
	echo 'CC "$$@" $$CRAY_UGNI_POST_LINK_OPTS $$CRAY_PMI_POST_LINK_OPTS -Wl,--as-needed,-lugni,-lpmi,--no-as-needed' >> $(RELEASE_DIR)/CC.custom
	chmod a+x $(RELEASE_DIR)/CC.custom
	# use our custom cc/CC wrappers and also force -fPIC
	/bin/sed "s/'\(cc\)'/'\1.custom -fPIC'/I" < $(GASNET_VERSION)/other/contrib/$(CROSS_CONFIGURE) > $(GASNET_VERSION)/cross-configure
	cd release; PATH=`pwd`:$$PATH /bin/sh ../$(GASNET_VERSION)/cross-configure --prefix=$(RELEASE_DIR) `cat $(realpath $(RELEASE_CONFIG))`
else
# normal configure path
	mkdir -p $(RELEASE_DIR)
	cd $(RELEASE_DIR); CC='mpicc -fPIC' CXX='mpicxx -fPIC' ../$(GASNET_VERSION)/configure --prefix=$(RELEASE_DIR) --with-mpi-cflags=-fPIC `cat $(realpath $(RELEASE_CONFIG))`
endif

$(GASNET_VERSION)/configure : $(GASNET_VERSION).tar.gz
	tar -zxf $<
	$(foreach p,$(PATCHES),patch -p1 -d$(GASNET_VERSION) < $p &&) /bin/true
	touch -c $@
