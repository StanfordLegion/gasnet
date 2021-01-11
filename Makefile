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

# there are three relevant directories for a build:
#  GASNET_SOURCE_DIR - directory in which the tarball is unpacked
#  GASNET_BUILD_DIR  - directory in which configure is run and build performed
#  GASNET_INSTALL_DIR - directory where finished build is installed
#
# it is possible (and the default) to have the build and install directories
#  be the same
GASNET_SOURCE_DIR := $(shell pwd)/$(GASNET_VERSION)
GASNET_BUILD_DIR ?= $(GASNET_INSTALL_DIR)

ifeq ($(GASNET_DEBUG),1)
GASNET_INSTALL_DIR ?= $(shell pwd)/debug
GASNET_EXTRA_CONFIGURE_ARGS += --enable-debug
else
GASNET_INSTALL_DIR ?= $(shell pwd)/release
GASNET_EXTRA_CONFIGURE_ARGS +=
endif

GASNET_CONFIG ?= configs/config.$(CONDUIT).release

# extra CFLAGS needed (e.g. -fPIC if gasnet will be linked into a shared lib)
GASNET_CFLAGS ?= -fPIC

.PHONY: install

install : $(GASNET_BUILD_DIR)/config.status
	make -C $(GASNET_BUILD_DIR) install

$(GASNET_BUILD_DIR)/config.status : $(GASNET_CONFIG) $(GASNET_SOURCE_DIR)/configure
ifdef CROSS_CONFIGURE
# Cray systems require cross-compiling fun
	mkdir -p $(GASNET_BUILD_DIR)
	# WAH for issue with new Cray cc/CC not including PMI stuff
	echo '#!/bin/bash' > $(GASNET_BUILD_DIR)/cc.custom
	echo 'cc "$$@" $$CRAY_UGNI_POST_LINK_OPTS $$CRAY_PMI_POST_LINK_OPTS -Wl,--as-needed,-lugni,-lpmi,--no-as-needed' >> $(GASNET_BUILD_DIR)/cc.custom
	chmod a+x $(GASNET_BUILD_DIR)/cc.custom
	echo '#!/bin/bash' > $(GASNET_BUILD_DIR)/CC.custom
	echo 'CC "$$@" $$CRAY_UGNI_POST_LINK_OPTS $$CRAY_PMI_POST_LINK_OPTS -Wl,--as-needed,-lugni,-lpmi,--no-as-needed' >> $(GASNET_BUILD_DIR)/CC.custom
	chmod a+x $(GASNET_BUILD_DIR)/CC.custom
	# use our custom cc/CC wrappers and also force GASNET_CFLAGS
	/bin/sed "s/'\(cc\)'/'\1.custom $(GASNET_CFLAGS)'/I" < $(GASNET_SOURCE_DIR)/other/contrib/$(CROSS_CONFIGURE) > $(GASNET_SOURCE_DIR)/cross-configure
	cd $(GASNET_BUILD_DIR); PATH=`pwd`:$$PATH /bin/sh $(GASNET_SOURCE_DIR)/cross-configure --prefix=$(GASNET_INSTALL_DIR) `cat $(realpath $(GASNET_CONFIG))` $(GASNET_EXTRA_CONFIGURE_ARGS)
else
# normal configure path
	mkdir -p $(GASNET_BUILD_DIR)
ifeq ($(OVERRIDE_CC_AND_CXX),1)
	cd $(GASNET_BUILD_DIR); CC='mpicc $(GASNET_CFLAGS)' CXX='mpicxx $(GASNET_CFLAGS)' $(GASNET_SOURCE_DIR)/configure --prefix=$(GASNET_INSTALL_DIR) --with-mpi-cflags="$(GASNET_CFLAGS)" `cat $(realpath $(GASNET_CONFIG))` $(GASNET_EXTRA_CONFIGURE_ARGS)
else
	cd $(GASNET_BUILD_DIR); $(GASNET_SOURCE_DIR)/configure --prefix=$(GASNET_INSTALL_DIR) --with-cflags="$(GASNET_CFLAGS)" --with-mpi-cflags="$(GASNET_CFLAGS)" `cat $(realpath $(GASNET_CONFIG))` $(GASNET_EXTRA_CONFIGURE_ARGS)
endif
endif

$(GASNET_SOURCE_DIR)/configure : $(GASNET_VERSION).tar.gz
	mkdir -p $(GASNET_SOURCE_DIR)
	# make sure tar unpacks to the right directory even if the root directory name does not match
	tar -zxf $< --strip-components=1 -C $(GASNET_SOURCE_DIR)
	$(foreach p,$(PATCHES),patch -p1 -d$(GASNET_SOURCE_DIR) < $p &&) /bin/true
	touch -c $@

# the GASNet-EX team makes prerelease snapshots available if you ask nicely -
#  this rule is a helper to automatically download one of those
GASNet-EX-snapshot.tar.gz :
	echo 'Downloading GASNet-EX snapshot tarball...'
	@wget -q -O $@ $(GASNETEX_SNAPSHOT_SOURCE_URL)
