GASNET_VERSION ?= GASNet-2022.9.2

# these patches are applied to the unpacked GASNet source directory before
#  running configure
PATCHES =
ifneq ($(findstring GASNet-2022.9,$(GASNET_VERSION)),)
# ofi-warning.patch silences a harmless warning for ofi-conduit/Omni-Path on 2022.9.[02]
PATCHES += patches/ofi-warning.patch
endif

ifeq ($(findstring daint,$(shell uname -n)),daint)
CROSS_CONFIGURE ?= cross-configure-cray-aries-slurm
endif
ifeq ($(findstring excalibur,$(shell uname -n)),excalibur)
CROSS_CONFIGURE ?= cross-configure-cray-aries-slurm
endif
ifeq ($(findstring cori,$(shell uname -n)),cori)
CROSS_CONFIGURE ?= cross-configure-cray-aries-slurm
endif
ifeq ($(origin CROSS_CONFIGURE),undefined)
  # try to detect appropriate cross-configure for Cray systems
  ifdef CRAYPE_NETWORK_TARGET
    ifneq ($(CRAYPE_NETWORK_TARGET), ofi)
      ifneq (,$(shell which srun 2> /dev/null))
        CROSS_CONFIGURE = cross-configure-cray-$(CRAYPE_NETWORK_TARGET)-slurm
      else ifneq (,$(shell which aprun 2> /dev/null))
        CROSS_CONFIGURE = cross-configure-cray-$(CRAYPE_NETWORK_TARGET)-alps
      endif
    endif
  endif
  # if we did set something, tell the user so they can override if needed
  ifdef CROSS_CONFIGURE
    $(info # auto-detected Cray cross-configure script: $(CROSS_CONFIGURE))
    $(info # set CROSS_CONFIGURE to override this selection)
  endif
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
GASNET_CXXFLAGS ?= -fPIC

.PHONY: install

install : $(GASNET_BUILD_DIR)/config.status
	make -C $(GASNET_BUILD_DIR) install

$(GASNET_BUILD_DIR)/config.status : $(GASNET_CONFIG) $(CONFIGURE)
	mkdir -p $(GASNET_BUILD_DIR)
	cd $(GASNET_BUILD_DIR); $(CONFIGURE) --prefix=$(GASNET_INSTALL_DIR) --with-cflags="$(GASNET_CFLAGS)" --with-mpi-cflags="$(GASNET_CFLAGS)" --with-cxxflags="$(GASNET_CXXFLAGS)" `cat $(realpath $(GASNET_CONFIG))` $(GASNET_EXTRA_CONFIGURE_ARGS)

$(GASNET_SOURCE_DIR)/configure : $(GASNET_VERSION).tar.gz
	mkdir -p $(GASNET_SOURCE_DIR)
	# make sure tar unpacks to the right directory even if the root directory name does not match
	tar -zxf $< --strip-components=1 -C $(GASNET_SOURCE_DIR)
	$(foreach p,$(PATCHES),patch -p1 -d$(GASNET_SOURCE_DIR) < $p &&) true
	touch -c $@

$(GASNET_SOURCE_DIR)/cross-configure : $(GASNET_SOURCE_DIR)/configure
	ln -sf $(GASNET_SOURCE_DIR)/other/contrib/$(CROSS_CONFIGURE) $@

# the GASNet-EX team makes prerelease snapshots available if you ask nicely -
#  this rule is a helper to automatically download one of those
GASNet-EX-snapshot.tar.gz :
	echo 'Downloading GASNet-EX snapshot tarball...'
	@wget -q -O $@ $(GASNETEX_SNAPSHOT_SOURCE_URL)
