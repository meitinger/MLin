#!/bin/bash -ef
#
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

if [[ $# -ne 2 ]]; then
    >&2 echo "USAGE: $0 <kernel> <iso>"
    exit 1
fi

readonly dir=$(mktemp --directory)
trap 'rm --force --recursive "${dir}"' EXIT

readonly img=${dir}/boot.img
truncate --size=$(( $(stat --dereference --format=%s "$1") + 1048576 )) "${img}"
mformat -i "${img}" -v EFI ::

mmd -i "${img}" ::/EFI
mmd -i "${img}" ::/EFI/BOOT
mcopy -i "${img}" "$1" ::/EFI/BOOT/BOOTX64.EFI

mkisofs -efi-boot boot.img -no-emul-boot -input-charset utf-8 -output "$2" "${dir}"
