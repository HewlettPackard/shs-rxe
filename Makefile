# SPDX-License-Identifier: GPL-2.0');
# Copyright 2021 Hewlett Packard Enterprise Development LP

export TOPDIR := $(if $(TOPDIR),$(TOPDIR),$(shell readlink -e .))

SUBDIRS = rxe
KDIR ?= /lib/modules/$(shell uname -r)/build
DIR=$(shell pwd)
PACKAGE = cray-rxe-driver
VERSION = $(shell cat cray-rxe-driver.spec  | grep Version | sed -e's/  */ /g' | cut -d' ' -f 2)

all: $(SUBDIRS)

clean::
	rm -rf rxe/ .pc/

$(SUBDIRS)::
	VER_STR=$(VERSION) ./setup_rxe.sh && $(MAKE) -C $(KDIR) M=$(DIR)/$@ $(MAKECMDGOALS)

DIST_FILES = \
	rxe-6.13.tar.gz \
	cray-rxe-driver.spec \
	setup_rxe.sh \
	rxe_versions \
	kmp_files \
	patches/compatibility/*/*.patch \
	patches/compatibility/*.series \
	patches/functionality/*.patch \
	patches/functionality/*.series \
	patches/upstream/*.patch \
	patches/upstream/*.series \
	scripts/rxe_init.sh \
	Makefile \
	dkms.conf.in \
	dkms.post_build.sh

.PHONY: dist

dist: $(DIST_FILES)
	tar czf $(PACKAGE)-$(VERSION).tar.gz --transform 's/^/$(PACKAGE)-$(VERSION)\//' $(DIST_FILES)

$(PACKAGE)-$(VERSION).tar.gz: dist

rpm: $(PACKAGE)-$(VERSION).tar.gz
	BUILD_METADATA='0' rpmbuild -ta $<

source::
	VER_STR=$(VERSION) ./setup_rxe.sh
