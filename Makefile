GASNET_VERSION ?= GASNet-2024.5.0

# these patches are applied to the unpacked GASNet source directory before
#  running configure
PATCHES =
ifneq ($(findstring GASNet-2024.5,$(GASNET_VERSION)),)
# hwloc.patch fixes an issue with core binding that appears on the OFI CXI provider
PATCHES += patches/hwloc.patch
# The following two patches address GASNet bugs 4752 and 4753 on the OFI conduit
PATCHES += patches/ofi-recvmsg-retry.patch
PATCHES += patches/ofi-race.patch
PATCHES += patches/cumemmap.patch
endif
ifneq ($(findstring GASNet-2022.9,$(GASNET_VERSION)),)
# ofi-warning.patch silences a harmless warning for ofi-conduit/Omni-Path on 2022.9.[02]
PATCHES += patches/ofi-warning.patch
# ofi-old-psm2.patch fixes support for libfabric < 1.10 for ofi-conduit/Omni-Path on 2022.9.[02]
PATCHES += patches/ofi-old-psm2.patch
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

LEGION_GASNET_CONDUIT ?= $(CONDUIT)
ifndef LEGION_GASNET_CONDUIT
$(error LEGION_GASNET_CONDUIT must be set to a supported GASNet conduit name)
endif

ifeq ($(LEGION_GASNET_CONDUIT),ofi)
ifndef LEGION_GASNET_SYSTEM
$(error LEGION_GASNET_CONDUIT=ofi requires that LEGION_GASNET_SYSTEM must be set)
endif
endif

# detect desired GPU based on Legion configuration
ifeq ($(origin GASNET_GPU_CONFIGURE_ARGS),undefined)
  # memory kinds are supported only in certain conduits
  ifeq ($(findstring ibv,$(LEGION_GASNET_CONDUIT)),ibv)
    ifeq ($(strip $(USE_CUDA)),1)
      GASNET_GPU_CONFIGURE_ARGS += --enable-kind-cuda-uva
    endif
    ifeq ($(strip $(USE_HIP)),1)
      GASNET_GPU_CONFIGURE_ARGS += --enable-kind-hip
    endif
  endif
  ifeq ($(findstring ofi,$(LEGION_GASNET_CONDUIT)),ofi)
    ifeq ($(strip $(USE_CUDA)),1)
      GASNET_GPU_CONFIGURE_ARGS += --enable-kind-cuda-uva
    endif
    ifeq ($(strip $(USE_HIP)),1)
      GASNET_GPU_CONFIGURE_ARGS += --enable-kind-hip
    endif
  endif
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

ifndef LEGION_GASNET_SYSTEM
GASNET_CONFIG ?= configs/config.$(LEGION_GASNET_CONDUIT).release
else
GASNET_CONFIG ?= configs/config.$(LEGION_GASNET_CONDUIT)-$(LEGION_GASNET_SYSTEM).release
endif

# extra CFLAGS needed (e.g. -fPIC if gasnet will be linked into a shared lib)
GASNET_CFLAGS ?= -fPIC
GASNET_CXXFLAGS ?= -fPIC

.PHONY: install

install : $(GASNET_BUILD_DIR)/config.status
	make -C $(GASNET_BUILD_DIR) install

$(GASNET_BUILD_DIR)/config.status : $(GASNET_CONFIG) $(CONFIGURE)
	mkdir -p $(GASNET_BUILD_DIR)
	cd $(GASNET_BUILD_DIR); $(CONFIGURE) --prefix=$(GASNET_INSTALL_DIR) --with-cflags="$(GASNET_CFLAGS)" --with-mpi-cflags="$(GASNET_CFLAGS)" --with-cxxflags="$(GASNET_CXXFLAGS)" `cat $(realpath $(GASNET_CONFIG))` $(GASNET_GPU_CONFIGURE_ARGS) $(GASNET_EXTRA_CONFIGURE_ARGS)

$(GASNET_SOURCE_DIR)/configure : $(GASNET_VERSION).tar.gz
	mkdir -p $(GASNET_SOURCE_DIR)
	# make sure tar unpacks to the right directory even if the root directory name does not match
	tar -zxf $< --strip-components=1 -C $(GASNET_SOURCE_DIR)
	$(foreach p,$(PATCHES),patch -p1 -d$(GASNET_SOURCE_DIR) < $p &&) true
	touch -c $@

$(GASNET_SOURCE_DIR)/cross-configure : $(GASNET_SOURCE_DIR)/configure
	ln -sf $(GASNET_SOURCE_DIR)/other/contrib/$(CROSS_CONFIGURE) $@

# The GASNet stable branch tracks work that is (sometimes) unreleased, and advances from time to time (relative to releases)
GASNET_STABLE_SOURCE_URL ?= https://bitbucket.org/berkeleylab/gasnet/downloads/GASNet-stable.tar.gz
GASNet-stable.tar.gz :
	echo 'Downloading GASNet stable tarball...'
	@wget -q -O $@ $(GASNET_STABLE_SOURCE_URL)
