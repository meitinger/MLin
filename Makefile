# Copyright (C) 2021 Manuel Meitinger
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

bin ::= $(abspath $(if ${BIN},${BIN},bin))
obj ::= $(abspath $(if ${OBJ},${OBJ},obj))
src ::= $(abspath $(if ${SRC},${SRC},.))
pkg ::= $(src)/_pkgs

classes ::= $(notdir $(patsubst %/,%,$(dir $(wildcard ${src}/*/cpio_list))))
gen_init_cpio ::= ${obj}/gen_init_cpio


.DELETE_ON_ERROR:

.PHONY: all clean


all: ${classes}

clean:
	rm --recursive --force ${bin}/*
	rm --recursive --force ${obj}/*

${gen_init_cpio}: ${src}/gen_init_cpio.c
	${CC} ${CFLAGS} -Wall -Werror -O2 -o $@ $+


_files = $(shell grep '^\s*file\s' $1 | cut --delimiter=' ' --fields=3) # (cpio_file)
_deps = $(addprefix $2,$(addsuffix $3,$(file < ${src}/$1/deps))) # (class, prefix, suffix)


define _class # (class, variants, kernel)

$(if $3,,$(error No kernel package specified))
$(if $(word 2,$3),$(error Multiple kernel packages specified),)
$(if $2,$(foreach variant,$2,$(call _variant,$1,${variant},$3)),$(call _targets,$1,$1,src,$3))

endef


define _targets # (subpath, class, filesroot, kernel)

.PHONY: $1

$1: $${bin}/$1.vhdx

$${bin}/$1.vhdx: $${src}/makevhdx.sh $${obj}/$1/kernel/arch/x86/boot/bzImage
	mkdir --parents $$(dir $$@)
	$$^ $$@

$${obj}/$1/initramfs.cpio: $${gen_init_cpio} $${$3}/$1/cpio_list $(call _deps,$2,$${,_cpio_list})
	mkdir --parents $$(dir $$@)
	$$^ > $$@

$${obj}/$1/initramfs.cpio: .EXTRA_PREREQS = $(addprefix $${$3}/$1/,$(call _files,${src}/$2/cpio_list)) $(call _deps,$2,$${,_cpio_deps})

$${obj}/$1/kernel/.config: $${pkg}/$4/config
	mkdir --parents $$(dir $$@)
	cp --force $$< $$@

$${obj}/$1/kernel/arch/x86/boot/bzImage: $${$4_source} $${obj}/$1/initramfs.cpio $${obj}/$1/kernel/.config
	KCONFIG_CONFIG=$${obj}/$1/kernel/.config INITRAMFS=$${obj}/$1/initramfs.cpio $${MAKE} --directory=$${obj}/$4 O=$${obj}/$1/kernel bzImage
	touch --no-create $$@

endef


define _variant # (class, variant, kernel)

.PHONY: $1

$1: $1/$2

$(call _targets,$1/$2,$1,obj,$3)

$(foreach file,$(call _files,${src}/$1/cpio_list),$(call _variant_file,$1,$2,${file}))

$${obj}/$1/$2/cpio_list: $${src}/$1/cpio_list
	mkdir --parents $$(dir $$@)
	cp --force $$< $$@

endef


define _variant_file # (class, variant, file)

$${obj}/$1/$2/$3: $${src}/substvar.sh $${src}/$1/$2.var $${src}/$1/$3
	mkdir --parents $$(dir $$@)
	$$^ $$@

endef


define _source_package # (name)

$1_cpio_list = $${pkg}/$1/cpio_list
$1_cpio_deps = $(addprefix $${pkg}/$1/,$(call _files,${pkg}/$1/cpio_list))

endef


define _extract_package # (name, url, sha)

$1_source = $${obj}/$1/.sourced

$${$1_source}: $${obj}/$(notdir $2)
	test $3 = `sha256sum $$< | cut --delimiter=' ' --fields=1`
	rm --recursive --force $${obj}/$(basename $(basename $(notdir $2))) $${obj}/$1
	tar --extract --directory=$${obj} --file=$$<
	mv --force $${obj}/$(basename $(basename $(notdir $2))) $${obj}/$1
	touch $$@

$${obj}/$(notdir $2):
	mkdir --parents $$(dir $$@)
	wget --output-document=$$@ $2
	test $3 = `sha256sum $$@ | cut --delimiter=' ' --fields=1`
	touch --no-create $$@

endef


define _harvest_package # (name)

$1_build = $${obj}/$1/.built
$1_cpio_list = $${obj}/$1/.cpio_list
$1_cpio_deps = $${$1_build}

$${$1_cpio_list}: $${pkg}/$1/cpio_list $${$1_build}
	cp --force $$< $$@

endef


define _kconfig_package # (name, url, sha)

$(call _extract_package,$1,$2,$3)
$(call _harvest_package,$1)

$${$1_build}: $${pkg}/$1/config $${$1_source}
	cp --force $$< $${obj}/$1/.config
	$${MAKE} --directory=$${obj}/$1
	touch $$@

endef


define _configure_package # (name, url, sha, flags)

$(call _extract_package,$1,$2,$3)
$(call _harvest_package,$1)

$${$1_build}: $${$1_source}
	cd $${obj}/$1 && LDFLAGS='$${LDFLAGS} --static' ./configure --prefix=/ $4
	$${MAKE} --directory=$${obj}/$1
	touch $$@

endef


define _kernel_package # (name, url, sha)

$(call _extract_package,$1,$2,$3)

$1_kernel = $1

endef


package-name = $(notdir $(patsubst %/Makefile,%,$(lastword ${MAKEFILE_LIST})))
source-package = $(eval $(call _source_package,${package-name})) # ()
kconfig-package = $(eval $(call _kconfig_package,${package-name},$(strip $1),$(strip $2))) # (url, sha)
configure-package = $(eval $(call _configure_package,${package-name},$(strip $1),$(strip $2),$(strip $3))) # (url, sha, [flags])
kernel-package = $(eval $(call _kernel_package,${package-name},$(strip $1),$(strip $2))) # (url, sha)
include $(wildcard ${pkg}/*/Makefile)


$(foreach class,${classes},$(eval $(call _class,${class},$(notdir $(basename $(wildcard ${src}/${class}/*.var))),$(strip $(foreach kernel,$(call _deps,${class},,_kernel),$(value ${kernel}))))))
