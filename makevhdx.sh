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
    >&2 echo "USAGE: $0 <kernel> <vhdx>"
    exit 1
fi

fatsectors=$(( 2048 + $(stat --dereference --format=%s "$1") / 512 ))

img=
fat=
function cleanup {
    ${img+rm --force "${img}"}
    ${fat+rm --force "${fat}"}
}
trap cleanup EXIT
img=$(mktemp)
fat=$(mktemp)

truncate --size=$(( ${fatsectors} * 512 )) "${fat}"
mformat -i "${fat}" -v EFI ::
mmd -i "${fat}" ::/EFI
mmd -i "${fat}" ::/EFI/BOOT
mcopy -i "${fat}" "$1" ::/EFI/BOOT/BOOTX64.EFI

truncate --size=$(( ( 34 + ${fatsectors} + 34 ) * 512 )) "${img}"
parted --script "${img}" mklabel gpt mkpart EFI fat16 34s $(( 34 + ${fatsectors}))s set 1 esp
dd bs=512 if="${fat}" of="${img}" seek=34 status=none

qemu-img convert -f raw -O vhdx "${img}" "$2"
