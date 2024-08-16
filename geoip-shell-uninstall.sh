#!/bin/sh
# shellcheck disable=SC2154,SC2086,SC2034,SC1090

# geoip-shell-uninstall

# Copyright: antonk (antonk.d3v@gmail.com)
# github.com/friendly-bits

# uninstalls or resets geoip-shell

#### Initial setup
p_name="geoip-shell"
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)

manmode=1
nolog=1
in_uninstall=1

geoinit="${p_name}-geoinit.sh"
for geoinit_path in "$script_dir/$geoinit" "/usr/bin/$geoinit"; do
	[ -f "$geoinit_path" ] && break
done

[ ! "$geoinit_path" ] && die "Cannot uninstall $p_name because ${p_name}-geoinit.sh is missing."

. "$geoinit_path" &&
: "${_fw_backend:=$_fw_backend_def}" &&
. "$_lib-uninstall.sh" &&
{
	[ "$_fw_backend" ] && { . "$_lib-$_fw_backend.sh" || exit 1; } ||
	echolog -err "Firewall backend is unknown. Cannot remove firewall rules." \
		"Please restart the machine after uninstalling."
	:
} || exit 1

san_args "$@"
newifs "$delim"
set -- $_args; oldifs
debugentermsg

#### USAGE

usage() {
cat <<EOF
Usage: $me [-V] [-h]

1) Removes geoip firewall rules
2) Removes geoip cron jobs (and local.d script on openrc)
3) Deletes scripts' data folder (/var/lib/geoip-shell or /etc/geoip-shell/data on OpenWrt)
4) Deletes the scripts from /usr/sbin
5) Deletes the config folder /etc/geoip-shell

Options:
  -r  : Leave the config file and the backup files in place
  -V  : Version
  -h  : This help

EOF
}

rm_scripts() {
	printed=
	for script_name in fetch apply manage cronsetup run backup mk-fw-include fw-include detect-lan uninstall geoinit; do
		s_path="${install_dir}/${p_name}-$script_name.sh"
		[ -f "$s_path" ] && {
			[ ! "$printed" ] && { printf '%s\n' "Deleting $p_name main scripts from $install_dir..."; printed=1; }
			rm -f "$s_path"
		}
	done

	rm_geodir "$lib_dir" "library scripts"
	:
}

rm_local_d_script() {
	local_d_script="/etc/local.d/90-geoip-shell-restore.start"
	[ -f "$local_d_script" ] && {
		printf '%s\n' "Deleting $p_name local.d persistence script...";
		rm -f "$local_d_script"
	}
	:
}

#### PARSE ARGUMENTS

while getopts ":rVh" opt; do
	case $opt in
		r) keepdata="-r" ;;
		V) echo "$curr_ver"; exit 0 ;;
		h) usage; exit 0 ;;
		*) ;;
	esac
done
shift $((OPTIND-1))

is_root_ok || exit 1

lib_dir="/usr/lib/$p_name"
_lib="$lib_dir/$p_name-lib"


### VARIABLES
old_install_dir="$(command -v "$p_name")"
old_install_dir="${old_install_dir%/*}"
install_dir="${old_install_dir:-"$install_dir"}"

[ ! "$install_dir" ] && die "Can not determine installation directory. Try setting \$install_dir manually"

[ "$script_dir" != "$install_dir" ] && [ -f "$install_dir/${p_name}-uninstall.sh" ] && [ ! "$norecur" ] && {
	# prevents infinite loop
	export norecur=1
	call_script "$install_dir/${p_name}-uninstall.sh" "$keepdata" && exit 0
}

: "${conf_dir:=/etc/$p_name}"
[ -d "$conf_dir" ] && : "${conf_file:="$conf_dir/$p_name.conf"}"
[ -s "$conf_file" ] && nodie=1 getconfig datadir
: "${datadir:="/var/lib/geoip-shell"}"

#### MAIN

rm_setupdone
rm_iplists_rules
rm_cron_jobs
rm_local_d_script

# For OpenWrt
[ "$_OWRT_install" ] && {
	rm_owrt_init
	rm_owrt_fw_include
	restart_owrt_fw
}

rm_symlink
rm_scripts
[ ! "$keepdata" ] && { rm_config; rm_data; }

printf '%s\n\n' "Uninstall complete."
