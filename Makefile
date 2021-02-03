GASNET_VERSION ?= GASNet-2020.11.0-memory_kinds_prototype

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

ifeq ($(CROSS_CONFIGURE),)
CONFIGURE ?= $(GASNET_SOURCE_DIR)/configure
else
CONFIGURE ?= $(GASNET_SOURCE_DIR)/cross-configure
endif

GASNET_CONFIG ?= configs/config.$(CONDUIT).release

# extra CFLAGS needed (e.g. -fPIC if gasnet will be linked into a shared lib)
GASNET_CFLAGS ?= -fPIC
GASNET_CPPFLAGS ?= -fPIC

.PHONY: install

install : $(GASNET_BUILD_DIR)/config.status
	make -C $(GASNET_BUILD_DIR) install

$(GASNET_BUILD_DIR)/config.status : $(GASNET_CONFIG) $(CONFIGURE)
	mkdir -p $(GASNET_BUILD_DIR)
	cd $(GASNET_BUILD_DIR); $(CONFIGURE) --prefix=$(GASNET_INSTALL_DIR) --with-cflags="$(GASNET_CFLAGS)" --with-mpi-cflags="$(GASNET_CFLAGS)" --with-cppflags="$(GASNET_CPPFLAGS)" `cat $(realpath $(GASNET_CONFIG))` $(GASNET_EXTRA_CONFIGURE_ARGS)

$(GASNET_SOURCE_DIR)/configure : $(GASNET_VERSION).tar.gz
	mkdir -p $(GASNET_SOURCE_DIR)
	# make sure tar unpacks to the right directory even if the root directory name does not match
	tar -zxf $< --strip-components=1 -C $(GASNET_SOURCE_DIR)
	$(foreach p,$(PATCHES),patch -p1 -d$(GASNET_SOURCE_DIR) < $p &&) /bin/true
	touch -c $@

$(GASNET_SOURCE_DIR)/cross-configure : $(GASNET_SOURCE_DIR)/configure
	ln -sf $(GASNET_SOURCE_DIR)/other/contrib/$(CROSS_CONFIGURE) $@

# the GASNet-EX team makes prerelease snapshots available if you ask nicely -
#  this rule is a helper to automatically download one of those
GASNet-EX-snapshot.tar.gz :
	echo 'Downloading GASNet-EX snapshot tarball...'
	@wget -q -O $@ $(GASNETEX_SNAPSHOT_SOURCE_URL)
