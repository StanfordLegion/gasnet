GASNET_VERSION ?= GASNet-2020.11.0-memory_kinds_prototype

# these patches are applied to the unpacked GASNet source directory before
#  running configure
PATCHES =
# mpifix.patch not needed after 1.28.2
#PATCHES += patches/mpifix.patch

# overriding of CC and CXX should not be needed for 1.30.0 and later
OVERRIDE_CC_AND_CXX ?= 0

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
$(error CONDUIT must be set to a supported GASNet conduit name)
endif

BUILD_DIR := $(shell pwd)

ifeq ($(GASNET_DEBUG),1)
GASNET_INSTALL_DIR ?= $(shell pwd)/debug
GASNET_EXTRA_CONFIGURE_ARGS += --enable-debug
else
GASNET_INSTALL_DIR ?= $(shell pwd)/release
GASNET_EXTRA_CONFIGURE_ARGS +=
endif

GASNET_CONFIG ?= configs/config.$(CONDUIT).release

.PHONY: install

install : $(GASNET_INSTALL_DIR)/config.status
	make -C $(GASNET_INSTALL_DIR) install

$(GASNET_INSTALL_DIR)/config.status : $(GASNET_CONFIG) $(GASNET_VERSION)/configure
ifdef CROSS_CONFIGURE
# Cray systems require cross-compiling fun
	mkdir -p $(GASNET_INSTALL_DIR)
	# WAH for issue with new Cray cc/CC not including PMI stuff
	echo '#!/bin/bash' > $(GASNET_INSTALL_DIR)/cc.custom
	echo 'cc "$$@" $$CRAY_UGNI_POST_LINK_OPTS $$CRAY_PMI_POST_LINK_OPTS -Wl,--as-needed,-lugni,-lpmi,--no-as-needed' >> $(GASNET_INSTALL_DIR)/cc.custom
	chmod a+x $(GASNET_INSTALL_DIR)/cc.custom
	echo '#!/bin/bash' > $(GASNET_INSTALL_DIR)/CC.custom
	echo 'CC "$$@" $$CRAY_UGNI_POST_LINK_OPTS $$CRAY_PMI_POST_LINK_OPTS -Wl,--as-needed,-lugni,-lpmi,--no-as-needed' >> $(GASNET_INSTALL_DIR)/CC.custom
	chmod a+x $(GASNET_INSTALL_DIR)/CC.custom
	# use our custom cc/CC wrappers and also force -fPIC
	/bin/sed "s/'\(cc\)'/'\1.custom -fPIC'/I" < $(GASNET_VERSION)/other/contrib/$(CROSS_CONFIGURE) > $(GASNET_VERSION)/cross-configure
	cd $(GASNET_INSTALL_DIR); PATH=`pwd`:$$PATH /bin/sh $(BUILD_DIR)/$(GASNET_VERSION)/cross-configure --prefix=$(GASNET_INSTALL_DIR) `cat $(realpath $(GASNET_CONFIG))` $(GASNET_EXTRA_CONFIGURE_ARGS)
else
# normal configure path
	mkdir -p $(GASNET_INSTALL_DIR)
ifeq ($(OVERRIDE_CC_AND_CXX),1)
	cd $(GASNET_INSTALL_DIR); CC='mpicc -fPIC' CXX='mpicxx -fPIC' $(BUILD_DIR)/$(GASNET_VERSION)/configure --prefix=$(GASNET_INSTALL_DIR) --with-mpi-cflags=-fPIC `cat $(realpath $(GASNET_CONFIG))` $(GASNET_EXTRA_CONFIGURE_ARGS)
else
	cd $(GASNET_INSTALL_DIR); $(BUILD_DIR)/$(GASNET_VERSION)/configure --prefix=$(GASNET_INSTALL_DIR) --with-cflags=-fPIC --with-mpi-cflags=-fPIC `cat $(realpath $(GASNET_CONFIG))` $(GASNET_EXTRA_CONFIGURE_ARGS)
endif
endif

$(GASNET_VERSION)/configure : $(GASNET_VERSION).tar.gz
	mkdir -p $(GASNET_VERSION)
	# make sure tar unpacks to the right directory even if the root directory name does not match
	tar -zxf $< --strip-components=1 -C $(GASNET_VERSION)
	$(foreach p,$(PATCHES),patch -p1 -d$(GASNET_VERSION) < $p &&) /bin/true
	touch -c $@

# the GASNet-EX team makes prerelease snapshots available if you ask nicely -
#  this rule is a helper to automatically download one of those
GASNet-EX-snapshot.tar.gz :
	echo 'Downloading GASNet-EX snapshot tarball...'
	@wget -q -O $@ $(GASNETEX_SNAPSHOT_SOURCE_URL)
