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

CFLAGS += -fPIE -fcf-protection=full -fstack-clash-protection -fstack-protector-all -fzero-call-used-regs=used-gpr -fsanitize=bounds -fsanitize-undefined-trap-on-error -D_FORTIFY_SOURCE=3
LDFLAGS += -pie -z relro -z now

classes ::= $(notdir $(patsubst %/,%,$(dir $(wildcard ${src}/*/cpio_list))))
gen_init_cpio ::= ${obj}/gen_init_cpio
comma ::= ,
downloads ::=
mkdir ::= mkdir --parents $$(dir $$@)
touch ::= touch $$@


.DELETE_ON_ERROR:

.PHONY: all clean


all: ${classes}

clean:
	rm --recursive --force ${bin}/*
	rm --recursive --force ${obj}/*

${gen_init_cpio}: ${src}/gen_init_cpio.c
	${CC} -Wall -Werror -O2 -o $@ $+


_deps = $(addprefix $2,$(addsuffix $3,$(file < $1/deps))) # (deps_path, prefix, suffix)
_files = $(shell grep '^\s*file\s' $1/cpio_list | cut --delimiter=' ' --fields=3) # (cpio_list_path)
_files_deps = $(foreach file,$(call _files,$1),$(if $(filter-out /%,${file}),$2/${file},${file})) # (cpio_list_path, filesroot)
_sha256test = test $2 = $$$$(sha256sum $1 | cut --delimiter=' ' --fields=1) # (file, sha)


define _class # (class, variants, kernel)

$(if $3,,$(error $1: No kernel package specified))
$(if $(word 2,$3),$(error $1: Multiple kernel packages specified),)
$(foreach dep,$(call _deps,${src}/$1,,),$(if $(value ${dep}),,$(error $1: Dependency ${dep} not found)))
$(if $2,$(foreach variant,$2,$(call _variant,$1,${variant},$3)),$(call _targets,$1,$1,src,$3))

endef


define _targets # (subpath, class, filesroot, kernel)

.PHONY: $1

$1: $${bin}/$1.iso

$${bin}/$1.iso: $${src}/makeiso.sh $${obj}/$1/kernel/arch/x86/boot/bzImage
	${mkdir}
	$$^ $$@

$${obj}/$1/initramfs.cpio: $${gen_init_cpio} $(call _deps,${src}/$2,$${,_cpio_lists}) $${$3}/$1/cpio_list
	${mkdir}
	$$^ > $$@

$${obj}/$1/initramfs.cpio: .EXTRA_PREREQS = $(call _files_deps,${src}/$2,$${$3}/$1) $(call _deps,${src}/$2,$${,_deps})

$${obj}/$1/kernel/arch/x86/boot/bzImage: $${obj}/$1/initramfs.cpio $${$4}/.ready
	$${MAKE} --directory=$${$4} O=$${obj}/$1/kernel $4_defconfig
	$${MAKE} --directory=$${$4} O=$${obj}/$1/kernel bzImage

endef


define _variant # (class, variant, kernel)

.PHONY: $1

$1: $1/$2

$(call _targets,$1/$2,$1,obj,$3)

$(foreach file,$(call _files,${src}/$1),$(if $(filter-out /%,${file}),$(call _variant_file,$1,$2,${file})))

$${obj}/$1/$2/cpio_list: $${src}/$1/cpio_list
	${mkdir}
	cp --force $$< $$@

endef


define _variant_file # (class, variant, file)

$${obj}/$1/$2/$3: $${src}/substvar.sh $${src}/$1/$2.var $${src}/$1/$3
	${mkdir}
	$$^ $$@

endef


define _download # (url, sha)

downloads += $(notdir $1)

$${obj}/$(notdir $1):
	${mkdir}
	wget --output-document=$$@ $1
	$(call _sha256test,$$@,$2)
	${touch}

endef


define _extract # (name, url, sha)

$${$1}/.staged: $${obj}/$(notdir $2)
	${mkdir}
	$(call _sha256test,$$<,$3)
	rm --recursive --force $${obj}/$(basename $(basename $(notdir $2))) $${$1}
	tar --extract --directory=$${obj} --file=$$<
	mv --force $${obj}/$(basename $(basename $(notdir $2))) $${$1}
	${touch}

$(if $(filter $(notdir $2),${downloads}),,$(call _download,$2,$3))

endef


define _harvest # (name)

$1_cpio_lists += $${$1}/.cpio_list
$1_deps += $${$1}/.ready $(filter /%,$(call _files,${pkg}/$1))

$${$1}/.cpio_list: $${pkg}/$1/cpio_list $${$1}/.staged
	cp --force $$< $$@

endef


define _package # (name, location)

$1 = $2
$1_cpio_lists = $(call _deps,${pkg}/$1,$${,_cpio_lists})
$1_deps = $(call _deps,${pkg}/$1,$${,_deps})

endef


define _source_package # (name)

$(call _package,$1,$${pkg}/$1)
$1_cpio_lists += $${$1}/cpio_list
$1_deps += $(call _files_deps,${pkg}/$1,$${$1})

endef


define _kconfig_package # (name, url, sha)

$(call _package,$1,$${obj}/$1)
$(call _extract,$1,$2,$3)
$(call _harvest,$1)

$${$1}/.ready: $${pkg}/$1/config $${$1}/.staged
	cp --force $$< $${$1}/.config
	$${MAKE} --directory=$${$1} CFLAGS='$${CFLAGS}' LDFLAGS='$${LDFLAGS}'
	${touch}

endef


define _configure_package # (name, url, sha, [flags])

$(call _package,$1,$${obj}/$1)
$(call _extract,$1,$2,$3)
$(call _harvest,$1)

$${$1}/.ready: ${pkg}/$1/Makefile $${$1}/.staged
	cd $${$1} && ./configure CFLAGS='$${CFLAGS}' LDFLAGS='$${LDFLAGS}' --prefix=/ $4
	$${MAKE} --directory=$${$1}
	${touch}

endef


define _kernel_package # (name, url, sha)

$(call _package,$1,$${obj}/$1)
$(call _extract,$1,$2,$3)

$1_kernel = $1

$${$1}/.ready: $${pkg}/$1/defconfig $${$1}/.staged
	echo 'CONFIG_INITRAMFS_SOURCE="../initramfs.cpio"' | cat - $$< > $${$1}/arch/x86/configs/$1_defconfig
	${touch}

endef


package-name = $(notdir $(patsubst %/Makefile,%,$(lastword ${MAKEFILE_LIST})))
source-package = $(eval $(call _source_package,${package-name})) # ()
kconfig-package = $(eval $(call _kconfig_package,${package-name},$(strip $1),$(strip $2))) # (url, sha)
configure-package = $(eval $(call _configure_package,${package-name},$(strip $1),$(strip $2),$(strip $3))) # (url, sha, [flags])
kernel-package = $(eval $(call _kernel_package,${package-name},$(strip $1),$(strip $2))) # (url, sha)
include $(wildcard ${pkg}/*/Makefile)


$(foreach class,${classes},$(eval $(call _class,${class},$(notdir $(basename $(wildcard ${src}/${class}/*.var))),$(strip $(foreach kernel,$(call _deps,${class},,_kernel),$(value ${kernel}))))))
