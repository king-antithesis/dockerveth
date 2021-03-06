#!/usr/bin/env bash

# Copyright (c) 2017 Micah Culpepper
# Copyright (c) 2020 Jeremy King
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


####################
# DEFINE FUNCTIONS #
####################

usage () {
    printf %s \
"podmanveth.sh - Show which running podman containers are attached to which
\`veth\` interfaces.
Usage: podmanveth.sh [PODMAN PS OPTIONS] | [-h, --help]
Options:
    PODMAN PS OPTIONS   Pass any valid \`podman ps\` flags. Do not pass
                        a '--format' flag.
    -h, --help          Show this help and exit.
Output:
    If stdout is not a tty, column headers are omitted.
"
}

get_container_data () {
    # Get data about the running containers. Accepts arbitrary arguments, so you can pass
    # a filter to `podman ps` if desired.
    # Input: `podman ps` arguments (optional)
    # Output: A multi-line string where each line contains the container id, followed by
    # a colon, and then any friendly names.
    podman ps --format '{{.ID}}:{{.Names}}' "$@"
}

get_veth () {
    # Get the host veth interface attached to a container.
    # Input: podman container ID; also needs $podmanveth__link
    # Output: the veth name, like "veth6638cfa"
    c_if_index=$(get_container_if_index "$1")
    a="${podmanveth__link#*${c_if_index}: veth}"
    b="${a%%@if*}"
    c="veth${b%%:*}"
    printf "${c}"
}

get_container_if_index () {
    # Get the @if# number of a podman container's first veth interface (typically eth0)
    # Input: the container ID
    # Output: The @if# number, like "42"
    c_pid=$(get_pid "$1")
    ip_netns_export "$c_pid"
    ils=$(ip netns exec "ns-${c_pid}" ip link show type veth)
    ils="${ils%%: <*}"
    ils="${ils##*if}"
    printf "${ils%: *}"
}

ip_netns_export () {
    # Make a podman container's networking info available to `ip netns`
    # Input: the container's PID
    # Output: None (besides return code), but performs the set-up so that `ip netns` commands
    # can access this container's namespace.
    if [ ! -d /var/run/netns ]; then
        mkdir -p /var/run/netns
    fi
    ln  -sf "/proc/${1}/ns/net" "/var/run/netns/ns-${1}"
}

get_pid () {
    # Get the PID of a podman container
    # Input: the container ID
    # Output: The PID, like "2499"
    podman inspect --format '{{.State.Pid}}' "$1"
}

make_row () {
    # Produce a table row for output
    # Input:
    #     1 - The container ID
    #     2 - The container's friendly name
    # Output: A tab delimited row of data, like "1e8656e195ba	veth1ce04be	thirsty_meitner	10.0.0.2"
    id="${1}"
    name="${2}"
    veth=$(get_veth "$id")
    ip_addr="${3}"
    printf "${id}\t${veth}\t${name}\t${ip_addr}"
}

make_table () {
    # Produce a table for output
    # Input: raw data rows, like `c26682fe4545:friendly-name`
    # Output: A multi-line string consisting of rows from `make_row`. Does not
    # contain table column headers.
    for i in $@; do
        id="${i%%:*}"
        name="${i#*:}"
        ip_addr=`podman inspect --format {{.NetworkSettings.IPAddress}} $id`
        r=$(make_row "$id" "$name" "$ip_addr")
        printf "${r}\n"
    done
}


######################
# PARSE COMMAND LINE #
######################

case "$1" in
    -h|--help)
    usage
    exit 0
    ;;
    *)
    ;;
esac


##################
# EXECUTE SCRIPT #
##################

set -e
container_data=$(get_container_data "$@")
podmanveth__link="$(ip link show type veth)"
table=$(make_table $container_data)
if [ -t 1 ]; then
    printf "CONTAINER ID\tVETH       \tNAMES     \tIP\n"
fi
printf "${table}\n"
