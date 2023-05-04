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

if [[ $# -ne 3 ]]; then
    >&2 echo "USAGE: $0 <varfile> <infile> <outfile>"
    exit 1
fi

pattern='[A-Z][_A-Z0-9]*'
declare -A vars
while IFS= read -r line || [[ -n "${line}" ]]; do
    value=${line#${pattern}=}
    if [[ ${#value} -eq ${#line} ]]; then
        >&2 echo "invalid variable definition: ${line}"
        exit 1
    fi
    name=${line:0:$(( ${#line} - ${#value} - 1 ))}
    vars[${name}]=${value}
done < "$1"

content=$(cat "$2")
for tag in $(echo "${content}" | grep --only-matching "<${pattern}>" | sort --unique); do
    name=${tag:1:-1}
    value=${vars[${name}]?"undefined variable: ${name}"}
    content=${content//${tag}/${value}}
done
echo "${content}" > "$3"
