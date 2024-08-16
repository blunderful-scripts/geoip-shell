#!/bin/sh
# shellcheck disable=SC2086,SC1090,SC2154,SC2034

# geoip-shell-install.sh

# Copyright: antonk (antonk.d3v@gmail.com)
# github.com/friendly-bits

# Installer for geoip blocking suite of shell scripts

# Creates system folder structure for scripts, config and data.
# Copies the required scripts to /usr/sbin.
# Calls the *manage script to set up geoip-shell and then call the -run script.
# If an error occurs during installation, calls the uninstall script to revert any changes made to the system.

#### Initial setup
p_name="geoip-shell"
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)

export manmode=1 in_install=1 nolog=1

. "$script_dir/$p_name-geoinit.sh" &&
. "$_lib-setup.sh" &&
. "$_lib-uninstall.sh" || exit 1

san_args "$@"
newifs "$delim"
set -- $_args; oldifs


#### USAGE

usage() {
cat <<EOF

Usage: $me [-m $mode_syn] [-c $ccodes_syn] [-f $fam_syn] [-u $srcs_syn]
${sp8}[-s $sch_syn] [-i $if_syn] [-l $lan_syn] [-t $tr_syn]
${sp8}[-p $ports_syn] [-r $user_ccode_syn] [-o <true|false>] [-a <"path">] [-w $fw_be_syn]
${sp8}[-O $nft_p_syn] [-n] [-N] [-z] [-d] [-V] [-h]

Installer for $p_name.
Supports interactive setup which doesn't require any options.

Core Options:

  -m $geomode_usage

  -c $ccodes_usage

  -f $families_usage

  -u $sources_usage

  -s $schedule_usage

  -i $ifaces_usage

  -l $lan_ips_usage

  -t $trusted_ips_usage

  -p $ports_usage

  -r $user_ccode_usage

  -o $nobackup_usage

  -a $datadir_usage

  -w $fw_be_usage

  -O $nft_perf_usage

  -n <true|false> : No persistence. Geoip blocking may not work after reboot. Default is false.
  -N <true|false> : No Block: Skip creating the rule which redirects traffic to the geoip blocking chain.
        Everything will be installed and configured but geoip blocking will not be enabled. Default is false.

Extra Options:
  -z : $nointeract_usage
  -d : Debug
  -V : Version
  -h : This help

EOF
}

#### PARSE ARGUMENTS

while getopts ":c:m:s:f:u:i:l:t:p:r:a:o:w:O:n:N:zdVh" opt; do
	case $opt in
		c) ccodes_arg=$OPTARG ;;
		m) geomode_arg=$OPTARG ;;
		s) schedule_arg=$OPTARG ;;
		f) families_arg=$OPTARG ;;
		u) geosource_arg=$OPTARG ;;
		i) ifaces_arg=$OPTARG ;;
		l) lan_ips_arg=$OPTARG ;;
		t) trusted_arg=$OPTARG ;;
		p) ports_arg="$ports_arg$OPTARG$_nl" ;;
		r) user_ccode_arg=$OPTARG ;;
		a) datadir_arg="$OPTARG" ;;
		o) nobackup_arg=$OPTARG ;;
		w) _fw_backend_arg=$OPTARG ;;
		O) nft_perf_arg=$OPTARG ;;
		n) no_persist_arg=$OPTARG ;;
		N) noblock_arg=$OPTARG ;;

		z) nointeract_arg=1 ;;
		d) debugmode=1 ;;
		V) echo "$curr_ver"; exit 0 ;;
		h) usage; exit 0 ;;
		*) unknownopt
	esac
done
shift $((OPTIND-1))
extra_args "$@"

# inst_root_gs is set by an external packaging script
[ ! "$inst_root_gs" ] && is_root_ok
debugentermsg


#### FUNCTIONS

check_files() {
	missing_files=
	err=0
	for dep_file in $1; do
		[ ! "$dep_file" ] && continue
		if [ ! -s "$script_dir/$dep_file" ]; then
			missing_files="${missing_files}'$dep_file', "
			err=$((err+1))
		fi
	done
	missing_files="${missing_files%, }"
	return "$err"
}

copyscripts() {
	[ "$1" = '-n' ] && { _mod=444; shift; } || _mod=555
	for f in $1; do
		dest="$inst_root_gs$install_dir/${f##*/}"
		[ "$2" ] && dest="$inst_root_gs$2/${f##*/}"
		prep_script "$script_dir/$f" > "$dest" || install_failed "$FAIL install file '$f' in '$dest'."
		[ ! "$inst_root_gs" ] && {
			chown root:root "${dest}" && chmod "$_mod" "$dest" || install_failed "$FAIL set permissions for file '${dest}${f}'."
		}
	done
}

install_failed() {
	printf '%s\n\n%s\n' "$*" "Installation failed." >&2
	[ ! "$inst_root_gs" ] && {
		echo "Uninstalling ${p_name}..." >&2
		call_script "$p_script-uninstall.sh"
	}
	exit 1
}

pick_shell() {
	unset sh_msg f_shs_avail s_shs_avail
	curr_sh_g_b="${curr_sh_g##*"/"}"
	is_included "$curr_sh_g_b" "$fast_sh" "|" && return 0
	newifs "|" psh
	for ___sh in $fast_sh; do
		checkutil "$___sh" && add2list f_shs_avail "$___sh"
	done
	oldifs psh
	[ -z "$f_shs_avail" ] && [ -n "$ok_sh" ] && return 0
	newifs "|" psh
	for ___sh in $slow_sh; do
		checkutil "$___sh" && add2list s_shs_avail "$___sh"
	done
	oldifs psh
	[ -z "$s_shs_avail" ] && return 0
	is_included "$curr_sh_g_b" "$slow_sh" "|" &&
		sh_msg="${blue}Your shell '$curr_sh_g_b' is supported by $p_name" msg_nc="$n_c" ||
		sh_msg="I'm running under an unsupported/unknown shell '$curr_sh_g_b'"
	if [ -n "$f_shs_avail" ]; then
		recomm_sh="${f_shs_avail%% *}"
		rec_sh_type="faster"
	elif [ -n "$s_shs_avail" ]; then
		recomm_sh="${s_shs_avail%% *}"
		rec_sh_type="supported"
	fi
	[ "$recomm_sh" = busybox ] && recomm_sh="busybox sh"
	printf '\n%s\n%s\n' \
		"$sh_msg but a $rec_sh_type shell '$recomm_sh' is available in this system, using it instead is recommended.$msg_nc" \
		"Would you like to use '$recomm_sh' with $p_name? [y|n] or [a] to abort installation."
	pick_opt "y|n|a"
	case "$REPLY" in
		a) exit 0 ;;
		y) newifs "$delim"; set -- $_args; unset curr_sh_g; eval "$recomm_sh \"$me\" $*"; exit ;;
		n) if [ -n "$bad_sh" ]; then exit 1; fi
	esac
}

# detects the init system and sources the OWRT -common script if needed
detect_init() {
	[ "$_OWRTFW" ] && return 0
	# check /run/systemd/system/
	[ -d "/run/systemd/system/" ] && { initsys=systemd; return 0; }
	# check /sbin/init strings
	initsys="$(awk 'match($0, /(upstart|systemd|procd|sysvinit|busybox)/) \
		{ print substr($0, RSTART, RLENGTH);exit; }' /sbin/init 2>/dev/null | grep .)" ||
		# check process with pid 1
		{
			_pid1="$(ls -l /proc/1/exe)"
			for initsys in systemd procd busybox upstart initctl unknown; do
					case "$_pid1" in *"$initsys"* ) break; esac
			done
		}
	case "$initsys" in
        busybox) grep 'sysinit:/sbin/openrc sysinit' /etc/inittab 1>/dev/null 2>/dev/null && initsys="openrc" ;;
		initctl) initsys=sysvinit ;;
		unknown) die "Failed to detect the init system. Please notify the developer." ;;
		procd) . "$script_dir/OpenWrt/${p_name}-lib-owrt-common.sh" || exit 1
	esac
	:
}

# 1 - (optional) input filename, otherwise reads from STDIN
# (optional) -n - skip adding the shebang and the version
prep_script() {
	unset noshebang prep_args
	for i in "$@"; do
		[ "$i" = '-n' ] && noshebang=1 || prep_args="$prep_args$i "
	done
	set -- $prep_args

	# print new shebang, version and copyright
	[ ! "$noshebang" ] &&
	cat <<- EOF
		#!${curr_sh_g:-/bin/sh}

		curr_ver=$curr_ver

		# Copyright: antonk (antonk.d3v@gmail.com)
		# github.com/friendly-bits

	EOF

	# filter pattern
	if [ "$_OWRTFW" ]; then
		# remove the shebang and comments, leave debug markers
		p="^[[:space:]]*#[^@].*$"
	else
		# remove the shebang, copyright and shellcheck directives
		p="^[[:space:]]*#(!/|[[:space:]]*(shellcheck|Copyright|github)).*$"
	fi

	# apply the filter, condense empty lines
	if [ "$1" ]; then grep -vxE "$p" "$1"; else grep -vxE "$p"; fi | grep -vA1 '^[[:blank:]]*$' | grep -v '^--$'
}


#### Detect the init system
detect_init

#### Variables

export ccodes_arg geomode_arg schedule_arg families_arg geosource_arg ifaces_arg lan_ips_arg trusted_arg ports_arg \
	user_ccode_arg datadir_arg nobackup_arg _fw_backend_arg nft_perf_arg no_persist_arg noblock_arg nointeract_arg \
	debugmode lib_dir="/usr/lib/$p_name" conf_dir="/etc/$p_name"
export conf_file="$conf_dir/$p_name.conf"

unset fw_libs ipt_libs nft_libs
ipt_fw_libs=ipt
nft_fw_libs=nft
all_fw_libs="ipt nft"

[ "$_OWRTFW" ] && {
	o_script="OpenWrt/${p_name}-owrt"
	owrt_init="$o_script-init.tpl"
	owrt_fw_include="$o_script-fw-include.tpl"
	owrt_mk_fw_inc="$o_script-mk-fw-include.tpl"
	owrt_comm="OpenWrt/${p_name}-lib-owrt-common.sh"
	case "$_OWRTFW" in
		3) _fw_backend=ipt ;;
		4) _fw_backend=nft ;;
		all) _fw_backend=all
	esac
	set_owrt_install="export _OWRT_install=1${_nl}. \"\${_lib}-owrt-common.sh\" || die"
	eval "fw_libs=\"\$${_fw_backend}_fw_libs\""
} || {
	check_compat="check-compat"
	init_check_compat_pt1=". \"\${_lib}-check-compat.sh\" || exit 1${_nl}check_common_deps${_nl}check_shell"
	init_check_compat_pt2="check_fw_backend \"\$_fw_backend\" || die"
	fw_libs="$all_fw_libs"
}

detect_lan="${p_name}-detect-lan.sh"

script_files=
for f in fetch apply manage cronsetup run uninstall backup; do
	script_files="$script_files${p_name}-$f.sh "
done

lib_files=
for f in uninstall common arrays status setup $check_compat $fw_libs; do
	[ "$f" ] && lib_files="${lib_files}lib/${p_name}-lib-$f.sh "
done
lib_files="$lib_files $owrt_comm"


#### CHECKS

check_files "$script_files $lib_files cca2.list $detect_lan $owrt_init $owrt_fw_include $owrt_mk_fw_inc" ||
	die "missing files: $missing_files."


#### MAIN

[ ! "$_OWRTFW" ] && [ ! "$nointeract_arg" ] && pick_shell

export _lib="$lib_dir/$p_name-lib" use_shell="$curr_sh_g"

if [ -s "$conf_file"  ] && nodie=1 get_config_vars; then
	export datadir
	tolower nobackup_arg
	[ "$nobackup_arg" != true ] && [ "$nobackup" != true ] && { call_script "$p_script-backup.sh" create-backup || rm_data; }
fi

## run the *uninstall script to reset associated cron jobs, firewall rules and ipsets
[ ! "$inst_root_gs" ] && {
	echolog "Cleaning up previous installation (if any)..."
	call_script "$p_script-uninstall.sh" -r || die "Pre-install cleanup failed."
}

## Copy scripts to $install_dir
printf %s "Copying scripts to $install_dir... "
copyscripts "$script_files $detect_lan"
OK

printf %s "Copying library scripts to $lib_dir... "
mkdir -p "$inst_root_gs$lib_dir" || install_failed "$FAIL create library directory '$inst_root_gs$lib_dir'."
copyscripts -n "$lib_files" "$lib_dir"
OK

## Create a symlink from ${p_name}-manage.sh to ${p_name}
[ ! "$inst_root_gs" ] && {
	rm -f "$i_script"
	ln -s "$i_script-manage.sh" "$i_script" || install_failed "$FAIL create symlink from ${p_name}-manage.sh to $p_name."
	# add $install_dir to $PATH
	add2list PATH "$install_dir" ':'
}

# Create the directory for config
mkdir -p "$inst_root_gs$conf_dir"


# create the .const file
cat <<- EOF > "$inst_root_gs$conf_dir/${p_name}.const" || install_failed "$FAIL set essential variables."
	export PATH="$PATH" initsys="$initsys" use_shell="$curr_sh_g"
EOF

. "$inst_root_gs$conf_dir/${p_name}.const"

# create the -geoinit script
cat <<- EOF > "${i_script}-geoinit.sh" || install_failed "$FAIL create the -geoinit script"
	#!$curr_sh_g

	# Copyright: antonk (antonk.d3v@gmail.com)
	# github.com/friendly-bits

	export conf_dir="/etc/$p_name" install_dir="/usr/bin" lib_dir="$lib_dir" iplist_dir="/tmp/$p_name" lock_file="/tmp/$p_name.lock" \
	excl_file="$conf_dir/iplist-exclusions.conf"
	export p_name="$p_name" conf_file="$conf_file" _lib="\$lib_dir/$p_name-lib" i_script="\$install_dir/$p_name" _nl='
	'
	export LC_ALL=C POSIXLY_CORRECT=yes default_IFS="	 \$_nl"

	$init_check_compat_pt1
	[ "\$root_ok" ] || { [ "\$(id -u)" = 0 ] && export root_ok="1"; }
	. "\${_lib}-common.sh" || exit 1
	$set_owrt_install
	[ "\$fwbe_ok" ] || [ ! "\$root_ok" ] && return 0
	[ -f "\$conf_dir/\${p_name}.const" ] && { . "\$conf_dir/\${p_name}.const" || die; } ||
		{ [ ! "\$in_uninstall" ] && die "\$conf_dir/\${p_name}.const is missing. Please reinstall \$p_name."; }

	[ -s "\$conf_file" ] && nodie=1 getconfig _fw_backend
	if [ ! "\$_fw_backend" ]; then
		rm -f "\$conf_dir/setupdone"
		[ "\$in_install" ] || [ "\$first_setup" ] && return 0
		case "\$me \$1" in "\$p_name configure"|"\${p_name}-manage.sh configure"|*" -h"*|*" -V"*) return 0; esac
		[ ! "\$in_uninstall" ] && die "Config file \$conf_file is missing or corrupted. Please run '\$p_name configure'."
		detect_fw_backend || die
		_fw_backend="\$_fw_backend_def"
	fi

	$init_check_compat_pt2
	export fwbe_ok=1 _fw_backend
	:
EOF

# copy cca2.list
cp "$script_dir/cca2.list" "$inst_root_gs$conf_dir/" || install_failed "$FAIL copy 'cca2.list' to '$conf_dir'."

# copy iplist-exclusions.conf
cp "$script_dir/iplist-exclusions.conf" "$inst_root_gs$conf_dir/" || install_failed "$FAIL copy 'iplist-exclusions.conf' to '$conf_dir'."

# OpenWrt-specific stuff
[ "$_OWRTFW" ] && {
	init_script="/etc/init.d/${p_name}-init"
	fw_include="$install_dir/${p_name}-fw-include.sh"
	mk_fw_inc="$i_script-mk-fw-include.sh"

	if [ "$no_persist_arg" ]; then
		echolog -warn "Installed without persistence functionality."
	else
		echo "Adding the init script... "
		{
			echo "#!/bin/sh /etc/rc.common"
			eval "printf '%s\n' \"$(cat "$script_dir/$owrt_init")\"" | prep_script -n
		} > "$inst_root_gs$init_script" || install_failed "$FAIL create the init script."

		echo "Preparing the firewall include... "
		eval "printf '%s\n' \"$(cat "$script_dir/$owrt_fw_include")\"" | prep_script > "$inst_root_gs$fw_include" &&
		{
			printf '%s\n%s\n%s\n%s\n%s\n%s\n' "#!/bin/sh" "p_name=$p_name" \
				"install_dir=\"$install_dir\"" "conf_dir=\"$conf_dir\"" "fw_include_path=\"$fw_include\"" "_lib=\"$_lib\""
			prep_script "$script_dir/$owrt_mk_fw_inc" -n
		} > "$mk_fw_inc" || install_failed "$FAIL prepare the firewall include."

		[ ! "$inst_root_gs" ] && {
			chmod +x "$init_script" && chmod 555 "$fw_include" "$mk_fw_inc" ||
				install_failed "$FAIL set permissions."
		}
	fi
}

# openrc local.d cron reboot replacement
[ "$initsys" = "openrc" ] && {
	local_d_script="/etc/local.d/90-geoip-shell-restore.start"
	if [ ! -f "$local_d_script" ]; then
		echo "Creating local.d startup script..."
        touch "$local_d_script" || install_failed "$FAIL create the local.d script."
        chmod +x "$local_d_script"
		{
			echo "#!/bin/sh"
			echo "\"$run_cmd\" restore -a 1>/dev/null 2>/dev/null # ${p_name}-persistence"
		} > "$local_d_script"
	fi
}

[ ! "$inst_root_gs" ] && {
	# only allow root to read the $conf_dir and files inside it
	chmod -R 600 "$conf_dir" && chown -R root:root "$conf_dir" ||
		install_failed "$FAIL set permissions for '$conf_dir'."

	### Add iplist(s) for $ccodes to managed iplists, then fetch and apply the iplist(s)
	call_script "$i_script-manage.sh" configure || die "$p_name-manage.sh exited with error code $?."
}

echo "Install done."
