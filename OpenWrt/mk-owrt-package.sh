#!/bin/sh
# shellcheck disable=SC2046,SC2034,SC2016,SC2044

# mk-owrt-package.sh

# Copyright: antonk (antonk.d3v@gmail.com)
# github.com/friendly-bits

# Creates Openwrt-specific packages for geoip-shell and compiles the packages.

# *** BEFORE USING THIS SCRIPT ***
# NOTE: I've had all sorts of unresolvable problems when not doing things exactly in this order, so better to stick to it.
# 1) install dependencies for the OpenWrt build system:
# https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
# 2) cd into your home directory:
# 	run: cd ~
# 3) clone openwrt git repo:
# run: git clone https://git.openwrt.org/openwrt/openwrt.git
# 3a) if building ipk packages, run: mv openwrt openwrt-opkg
# 4) run: 'cd openwrt' or 'cd openwrt-opkg'
# NOTE: this script expects the openwrt build directory in the above paths.
# It won't work if you have it in a different path or under a different name.

# 5) run: 'git checkout master' to build apk packages, or git 'checkout openwrt-23.05' to build ipk packages
# 6) update feeds:
# run: ./scripts/feeds update -a && ./scripts/feeds install -a
# 7) run: make menuconfig
# 8) select Target system --> [X] x86
#     (probably this doesn't matter but it may? build faster if you select the same architecture as your CPU)
# 9) select Subtarget --> X86-64 (same comment as above)
#     don't change Target and Subtarget later to avoid problems
# 10) Exit and save

# 11) run: make -j9 tools/install && make -j9 toolchain/install && make -j9 target/linux/compile
#     (assuming your machine has 8 physical or logical cores)
#     If this is the first time you are running these commands, this may take a long while.
#     If errors are encountered, solve them - all commands should succeed before proceeding

# To build both APK and IPK packages, repeat the steps above twice, for each package type

# 12) now you are ready to run this script
# 13) cross your fingers
# 14) cd into geoip-shell/OpenWrt
# 15) run: sh mk_owrt_package.sh


# if you want to make an updated package later, make sure that the '$curr_ver' value changed in the -geoinit script
# or change the '$pkg_ver' value in the prep-owrt-package.sh script
# then run the script again (no need for the above preparation anymore)

# in some cases after updating the master, you will need to rebuild tools and toolchain

# command-line options:
# -p <apk|ipk> : only build this package type
# -f <3|4|all>: build only for firewall3+iptables or firewall4+nftables, or both (all)
# -r : build a specific version fetched from the releases repo (otherwise builds from local source). requies to specify version with '-v'
# -v : specify version to fetch and build from the releases repo. only use with '-r'
# -u : upload: only relevant if you are authorized to upload to the geoip-shell releases repo (most likely you are not)
# -t : troubleshoot: if make fails, use this option to run make with '-j1 V=s'

die_mk() {
	# if first arg is a number, assume it's the exit code
	case "$1" in
		''|*[!0-9]*) die_rv="1" ;;
		*) die_rv="$1"; shift
	esac
	: "${die_rv:=1}"
	unset die_args
	for die_arg in "$@"; do
		die_args="$die_args$die_arg$_nl"
	done

	[ "$die_args" ] && {
		IFS="$_nl"
		for arg in $die_args; do
			printf '%s\n' "$arg" >&2
		done
	}

	exit "$die_rv"
}


# initial setup
p_name=geoip-shell
pkg_ver=r1

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)

unset build_from_remote troubleshoot upload pkg_paths extra_args

#### PARSE ARGUMENTS
_OWRTFW=
while getopts ":p:v:f:rudt" opt; do
	case $opt in
		p) pkg_types=$OPTARG ;;
		f) _OWRTFW=$OPTARG ;;
		v) curr_ver_arg="$OPTARG"; curr_ver="$curr_ver_arg" ;;
		r) build_from_remote=1 ;;
		u) upload=1 ;;
		d) export debugmode=1 ;;
		t) troubleshoot=1 ;;
		*) printf '%s\n' "Unexpected argument '$arg'."; exit 1 ;;
	esac
done
shift $((OPTIND-1))

# validate options
[ "$build_from_remote" ] && [ "$upload" ] && die_mk "*** Incompatible options: -r and -u. **"
[ "$curr_ver_arg" ] && { [ "$upload" ] || [ ! "$build_from_remote" ]; } && die_mk "*** Options don't make sense. ***"
[ "$build_from_remote" ] && [ ! "$curr_ver_arg" ] && die_mk "*** Specify version for build from remote. ***"

_nl='
'
apk_cap=APK
ipk_cap=IPK

### Paths
gsh_dir="$HOME/geoip-shell"
build_dir="$gsh_dir/owrt-build"
files_dir="$build_dir/files"
owrt_releases_dir="$gsh_dir/geoip-shell-openwrt"
owrt_dist_dir_apk="$HOME/openwrt"
owrt_dist_dir_ipk="$HOME/openwrt-opkg"
: "${pkg_types:=apk ipk}"

releases_url="https://github.com/friendly-bits/geoip-shell-openwrt"
releases_url_api="https://api.github.com/repos/friendly-bits/geoip-shell-openwrt"

rm -rf "$build_dir" 2>/dev/null

### prepare the build
case "$pkg_types" in
	apk) _OWRTFW=4 ;; # OpenWrt systems with apk can not have FW3
	*) : "${_OWRTFW:=all}"
esac
[ "$_OWRTFW" = all ] && _OWRTFW="4 3"

[ ! "$build_from_remote" ] && { . "$script_dir/prep-owrt-package.sh" || exit 1; }

mkdir -p "$files_dir"

if [ "$build_from_remote" ]; then
	printf '\n%s\n' "*** Fetching the Makefile... ***"
	curl -L "$(curl -s "$releases_url_api/releases" | \
		grep -m1 -o "$releases_url/releases/download/v$curr_ver.*/Makefile")" > "$build_dir/Makefile"; rv=$?
	[ $rv != 0 ] || [ ! -s "$build_dir/Makefile" ] && die_mk "*** Failed to fetch the Makefile. ***"
	pkg_ver="$(grep -o "PKG_RELEASE:=.*" < "$build_dir/Makefile" | cut -d'=' -f2)"
	[ ! "$pkg_ver" ] && die_mk "*** Failed to determine package version from the downloaded Makefile. ***"
	pkg_ver="r$pkg_ver"
	curr_ver="${curr_ver%-r*}"

	printf '\n%s\n' "*** Fetching the release... ***"
	curl -L "$(curl -s $releases_url_api/releases | \
		grep -m1 -o "$releases_url_api/tarball/[^\"]*")" > /tmp/geoip-shell.tar.gz &&
			tar --strip=1 -xvf /tmp/geoip-shell.tar.gz -C "$files_dir/" >/dev/null; rv=$?
	rm -rf /tmp/geoip-shell.tar.gz 2>/dev/null
	[ $rv != 0 ] && die_mk "Failed to fetch the release from Github."

elif [ ! "$upload" ]; then
	printf '\n%s\n' "*** Building packages from local source. ***"
	new_makefile="$(grep -vE 'PKG_(SOURCE_PROTO|SOURCE_VERSION|SOURCE_URL|MIRROR_HASH)' "$build_dir/Makefile")"
	printf '%s\n' "$new_makefile" > "$build_dir/Makefile"
fi

# Sanity check
[ -n "$curr_ver" ] || die_mk "\$curr_ver is unset!"

for pkg_type in $pkg_types; do
	eval "pkg_type_cap=\"\${${pkg_type}_cap}\""
	printf '\n%s\n' "*** Preparing to build $pkg_type_cap packages... ***"

	eval "owrt_dist_dir=\"\${owrt_dist_dir_$pkg_type}\""
	owrt_dist_src_dir="$owrt_dist_dir/geoip_shell_owrt_src/net/network/$p_name"
	export PATH="$owrt_dist_dir/staging_dir/host/bin:$PATH"

	[ ! -d "$owrt_dist_dir" ] && die_mk "*** Openwrt distribution dir '$owrt_dist_dir' doesn't exist. ***"
	[ ! -f "$owrt_dist_dir/feeds.conf.default" ] && die_mk "*** feeds.conf.default not found in '$owrt_dist_dir'. ***"

	rm -rf "$owrt_dist_src_dir" 2>/dev/null
	mkdir -p "$owrt_dist_src_dir"

	### Configure owrt feeds
	printf '\n%s\n' "*** Preparing owrt feeds... ***"

	new_feed="src-link local $owrt_dist_dir/geoip_shell_owrt_src"

	cd "$owrt_dist_dir" || die_mk "*** Failed to cd into '$owrt_dist_dir' ***"

	[ ! "$build_from_remote" ] && {
		printf '\n%s\n' "*** Copying $p_name build into '$owrt_dist_src_dir'... ***"
		cp -r "$files_dir" "$owrt_dist_src_dir/" || die_mk "*** Copy failed ***"
	}

	printf '\n%s\n' "*** Copying the Makefile into '$owrt_dist_src_dir'... ***"
	cp "$build_dir/Makefile" "$owrt_dist_src_dir/" || die_mk "*** Copy failed ***"
	echo

	curr_feeds="$(grep -v "$new_feed" "$owrt_dist_dir/feeds.conf.default")" ||
		die_mk "*** Failed to grep '$owrt_dist_dir/feeds.conf.default' ***"
	echo "*** Prepending entry '$new_feed' to '$owrt_dist_dir/feeds.conf.default'... ***"
	printf '%s\n%s\n' "$new_feed" "$curr_feeds" > "$owrt_dist_dir/feeds.conf.default" || die_mk "*** Failed ***"

	printf '\n%s\n' "*** Installing feeds for $p_name... ***"
	[ -f ./feeds/local.index ] && grep -q -m1 "$p_name" ./feeds/local.index ||
		./scripts/feeds update local || die_mk "*** Failed to update local feeds. ***"
	errors="$(./scripts/feeds install $p_name 2>&1)" && [ -z "$errors" ] ||
		die_mk "*** Failed to install feeds for $p_name. ***${_nl}Errors:${_nl}$errors${_nl}"

	# printf '\n%s\n' "*** Updating the $p_name feed... ***"
	# ./scripts/feeds update "$p_name" || die_mk "*** Failed to update owrt feeds."

	### menuconfig
	for _fw_ver in $_OWRTFW; do
		_ipt=
		[ "$_fw_ver" = 3 ] && _ipt="-iptables"
		grep "$p_name$_ipt=m" "$owrt_dist_dir/.config" 1>/dev/null || {
			printf '\n%s\n' "*** Changing package for $p_name$_ipt to M in .config... ***"
			grep -m1 "CONFIG_PACKAGE_$p_name$_ipt" "$owrt_dist_dir/.config" 1>/dev/null ||
				die_mk "*** No entry for package $p_name$_ipt found in '.config'. ***"
			sed -i "s/^\s*#\s*CONFIG_PACKAGE_$p_name$_ipt\s.*/CONFIG_PACKAGE_$p_name$_ipt=m/" "$owrt_dist_dir/.config" ||
				die_mk "*** Failed to change package to M in '.config'. ***"
		}
	done

	### build packages

	printf '\n%s\n\n' "*** Building $pkg_type_cap packages for $p_name... ***"
	# echo "*** Running: make -j4 package/$p_name/clean ***"
	# make -j4 "package/$p_name/clean"

	rm -f "$owrt_dist_dir/dl/$p_name"*


	### upload to the Github releases repo
	[ "$upload" ] && {
		printf '\n%s\n' "*** Building package with upload to Github. ***"

		if [ ! "$upload_done" ]; then
			# [ -s "$token_path" ] || die_mk "*** Token file not found. ***"
			command -v gh 1>/dev/null || die_mk "*** 'gh' utility not found. ***"
			# printf '\n%s\n' "*** Authenticating to Github... ***"
			# gh auth login --with-token < "$token_path" || die_mk "*** Failed to authenticate with token. ***"


			# copy files
			printf '\n%s\n' "*** Copying files to '$owrt_releases_dir/'... ***"
			mkdir -p "$owrt_releases_dir"
			rm -rf "${owrt_releases_dir:?}/"*
			cp -r "$files_dir"/* "$owrt_releases_dir/" || die_mk "*** Failed to copy '$files_dir/*' to '$owrt_releases_dir/'. ***"
			cd "$owrt_releases_dir" || die_mk "*** Failed to cd into '$owrt_releases_dir'. ***"
			git push 1>/dev/null 2>/dev/null || die_mk "*** No permissions to push to the github repo. ***"

			# add all files in release directory
			printf '\n%s\n' "*** Pushing to Github... ***"
			git add $(find -- * -type f -print)
			git commit -a -m "v$curr_ver-$pkg_ver"

			GH_tag="v$curr_ver-$pkg_ver"
			# remove existing release and tag with the same name
			git tag -l | grep "$GH_tag" >/dev/null && {
				gh release delete "$GH_tag" -y
				git tag -d "$GH_tag"
				git push --delete origin "$GH_tag"
			}

			# add new tag
			git tag "$GH_tag" &&
			git push &&
			git push origin --tags || die_mk "*** Failed to to push to Github. ***"
			
			# Update the Makefile with PKG_SOURCE_VERSION etc
			last_commit="$(git rev-parse HEAD)"
			sed -i "s/\$pkg_source_version/$last_commit/g;
				s/\.\/files/\$(PKG_BUILD_DIR)/g" \
					"$owrt_dist_src_dir/Makefile"
		else
			case "$pkg_type" in
				apk) eval "updated_makefile_path=\"\${owrt_dist_dir_ipk}/geoip_shell_owrt_src/net/network/$p_name\"" ;;
				ipk) eval "updated_makefile_path=\"\${owrt_dist_dir_ipk}/geoip_shell_owrt_src/net/network/$p_name\""
			esac
			# copy updated Makefile
			# shellcheck disable=SC2154
			cp "$updated_makefile_path" "$owrt_dist_src_dir/Makefile"
		fi

		printf '\n%s\n\n' "*** Running: make package/$p_name/download V=s ***"
		cd "$owrt_dist_dir" || die_mk 1
		make package/$p_name/download V=s

		# printf '\n%s\n\n' "*** Running: package/$p_name/check FIXUP=1 ***"
		# make package/$p_name/check FIXUP=1

		# Update the Makefile with PKG_MIRROR_HASH
		pkg_mirror_hash="$(sha256sum -b "$owrt_dist_dir/dl/$p_name-$curr_ver.tar."*)" &&
		pkg_mirror_hash="$(printf '%s\n' "$pkg_mirror_hash" | cut -d' ' -f1 | head -n1)"; rv=$?
		[ $rv != 0 ] || [ ! "$pkg_mirror_hash" ] && die_mk "*** Failed to calculate PKG_MIRROR_HASH. ***"
		printf '\n%s\n\n' "*** Calculated PKG_MIRROR_HASH: $pkg_mirror_hash ***"
		sed -i "s/PKG_MIRROR_HASH:=skip/PKG_MIRROR_HASH:=$pkg_mirror_hash/" "$owrt_dist_src_dir/Makefile"

		if [ ! "$upload_done" ]; then
			# create new release
			printf '\n%s\n' "*** Creating Github release... ***"
			cd "$owrt_releases_dir" || die_mk "*** Failed to cd into '$owrt_releases_dir'. ***"
			gh release create "$GH_tag" --verify-tag --latest --target=main --notes "" ||
				die_mk "*** Failed to create Github release via the 'gh' utility. ***"

			# upload the Makefile
			printf '\n%s\n' "*** Attaching the Makefile to the Github release... ***"
			gh release upload --clobber "$GH_tag" "$owrt_dist_src_dir/Makefile" ||
				die_mk "*** Failed to upload the Makefile to Github via the 'gh' utility. ***"

			upload_done=1
		fi
	}

	# Delete old packages with matching version
	cd "$owrt_dist_dir" || die_mk 1
	for _fw_ver in $_OWRTFW; do
		_ipt=
		[ "$_fw_ver" = 3 ] && _ipt="-iptables"
		find ./bin/packages -type f -name "${p_name}${_ipt}[_-]$curr_ver*.$pkg_type" -exec rm -f {} \; 2>/dev/null
	done

	make_opts='-j9'
	[ "$troubleshoot" ] && make_opts='-j1 V=s'

	printf '\n%s\n\n' "*** Running: make $make_opts package/$p_name/compile ***"
	cd "$owrt_dist_dir" || die_mk 1
	make $make_opts "package/$p_name/compile" || die_mk "*** Make failed. ***"
done

### Find, move and report built packages
for pkg_type in $pkg_types; do
	eval "pkg_type_cap=\"\${${pkg_type}_cap}\""
	eval "owrt_dist_dir=\"\${owrt_dist_dir_$pkg_type}\""
	cd "$owrt_dist_dir" || die_mk 1

	for _fw_ver in $_OWRTFW; do
		_ipt=
		[ "$_fw_ver" = 3 ] && _ipt="-iptables"

		pkg_path=
		for pkg_path in $(find ./bin/packages -type f -name "${p_name}${_ipt}[_-]$curr_ver*.$pkg_type" -exec echo {} \;); do
			new_pkg_path="$build_dir/$p_name${_ipt}_$curr_ver-$pkg_ver.${pkg_type}"
			mv "$pkg_path" "$new_pkg_path" && pkg_paths="$pkg_paths$new_pkg_path$_nl" ||
				die_mk "*** Failed to move '$pkg_path' to '$new_pkg_path' ***"
		done
		[ "$pkg_path" ] || die_mk "*** Can not find $pkg_type_cap file matching '${p_name}${_ipt}_$curr_ver' ***"
	done
done

[ "$build_dir" ] && {
	printf '\n%s\n\n' "*** Copying the Makefile from '$owrt_dist_src_dir' to '$build_dir' ***"
	cp "$owrt_dist_src_dir/Makefile" "$build_dir/" || die_mk "*** Copy failed ***"
}


[ "$build_dir" ] && {
	printf '\n%s\n%s\n' "*** The new build is available here: ***" "$build_dir"
	echo
	[ "${pkg_paths%"$_nl"}" ] && printf '%s\n%s\n' "*** New packages are available here:" "${pkg_paths%"$_nl"}"
}

die_mk 0
