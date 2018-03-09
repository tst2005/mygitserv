#!/bin/bash

if ! eval "function a_bash_is_required () { :; }"; then
	echo >&2 "bash is required"
	exit 1
fi

export LC_ALL=C

CMD="${SSH_ORIGINAL_COMMAND:-"$*"}"

log() {
	printf '%s %s %s: %s -- %s\n'  "$(date -u +"%F %T")" "${SSH_CLIENT%% *}" "${USER:--}" "$1" "$CMD" >> "$LOG"
}

deny() {
	log "ERROR: $1: "
	printf >&2 "error: %s\n" "$1"
	exit 1
}

# deny Ctrl-C and unwanted chars
trap "deny 'BYE';kill -9 $$" 1 2 3 6 15

re_match() { expr >/dev/null "$2" : "$1"; }

if ! re_match '[-+ [:alnum:],'\''./_@=]*$' "$SSH_ORIGINAL_COMMAND$*"; then
	deny "DON'T BE NAUGHTY"
fi

is_secure() {
	if re_match '.*\.\.' "$1"; then
		deny "DON'T BE EVIL";
	fi
	if re_match '[^[:alnum:]]' "$1"; then
		deny "DON'T BE CRUEL";
	fi
}

require_admin_access() {
	[ -z "$SSH_CLIENT" ] || grep -q " USER=$USER GROUP=[^ ]*\badmin\b" "$KEYS" || deny 'Admin access denied'
}

# u=$user / Admin     / allrepo :
#	    Admin:Repo:Create
#	    Admin:Repo:Remove
#           Admin:Repo:CreateFromFork
#	    Admin:User:add/mod/del
#	    Admin:Group:new/rename/del
#	    Admin:UserInGroup:add/del
# u=$user / User:ReadWrite / repo=$repo : branch=master :
# u=$user / User:Create    / repo=$repo : anybranch : ~tag='^v[0-9]\+\.[0-9]\+\,[0-9]\+$'
# u=$user / User:ReadOnly  / allrepo

repo=foo		ReadOnly
repo=foo		ReadWriteBranches
repo=foo		ReadWriteBranch with branch=dev
repo=foo		CreateTag with branch=dev
repo=foo		DeleteTag with branch=dev


conf() {
	git config --file "${GIT_NAMESPACE:-$R/config}" "$@"
}

list_of_repos() {
	{
		grep -Ilr --include=*config '^\s*bare = true' * 2>/dev/null | sed -e 's,/config$,,'
		grep -Ir --include=*.git '^\s*master = .*' * 2>/dev/null | sed 's/:.*= / -> /'
	} | sort
}
list_of_repos2() {
	cd -- "$REPOS" && {
		#find -type f -name 'config' -path '*/*.git/config' ! -path '*.git/**.git/*' -exec grep -q '^\s*bare = true' {} \; -a -print
		#find -type f ! -name '.*' -name '*.git' ! -path '*.git/*' -exec grep '^\s*master = .*' {} \; -a -print

	for r in *.git; do
		if [ -d "$r" ] && [ -f "$r/config" ] && grep -q -- '^\s*bare = true'; then
			echo "$r"
		else
			grep -Ir --include=*.git '^\s*master = .*' * 2>/dev/null | sed 's/:.*= / -> /'
		fi
	done
	} | sort
}

list_of_users() {
	sed -E -e 's/^.* USER=([^ ]*) GROUP=([^ ]*) .*$/\1 \2/' "$KEYS"
}

acc_re() {
	sed -E -e 's/^.*USER='$1' GROUP=([^ ]*) .*$/ .*\\b('$1'|\1)\\b/;ta' -e d -e :a -e 's/,/|/g' "$KEYS"
}

access_check() {
	case "$1" in
		('read'|'write') ;;
		('(write|tag)$') ;;
		('(write|write.'*')') ;;
		(*) deny "internal error for access_check" ;;
	esac
	conf --get-regexp "^access\.$1" | \
	grep -E -q "$(acc_re $USER)" || deny "${2-"Repository not found"}"
}

. ./lib/updatehook.lib.sh
. ./lib/repo.lib.sh
. ./lib/user-group.lib.sh
. ./lib/showhelp.lib.sh


SELF="$0"
case "$SELF" in
	(/*) ;;
	(*) SELF="$(pwd)/$SELF" ;;
esac

cd -- "$(dirname -- "$SELF")"
#SELF="$PWD/${0##*/}"

LOG="$(pwd)/access.log"
REPOS="$(pwd)/repositories"
USERS="$(pwd)/users"
USERDISABLED="$(pwd)/users-disabled"
KEYS="$HOME/.ssh/authorized_keys.gitserv"
XTRAKEYS="$HOME/.ssh/authorized_keys.local"

[ -d "$REPOS" ] || mkdir -- "$REPOS"
( cd -- "$REPOS" 2>/dev/null ) || deny "no such repository"

if [ $# -eq 0 ]; then
	echo >2& "DEBUG: arg empty, use SSH_ORIGINAL_COMMAND !"
	set -- $SSH_ORIGINAL_COMMAND
fi

read_reponame() {
	# unquoted repo name
	R=${SSH_ORIGINAL_COMMAND:-"$1"}
	R=${R%\'};R=${R#*\'}
	is_secure "$R"
	case "$R" in
		(*.git) ;;
		(*) R="${R}.git";;
	esac

	# When repo is a file then it is a fork
	if [ -f "$R" ]; then
		GIT_NAMESPACE="$R"
		R="$(conf fork.master)" && is_secure "$R"
	fi
}

case "$1" in
	(git-*)   # git pull and push
		read_reponame "$2"
		access_check read
		if [ "$1" = "git-receive-pack" ]; then
			access_check write "WRITE ACCESS DENIED"
		fi
		(
		cd -- "$REPOS" && \
		env GIT_NAMESPACE=$GIT_NAMESPACE git shell -c "$1 '$R'"
		)
	;;
	(update-hook)         # branch based access control
		shift;read_reponame "$1"
		echo >&2 "#DEBUG: receive update-hook $*"
		#shift;update_hook update-hook "$R" "$@"
		exit 0
	;;
	(repo)	shift;repo _	"$@" ;;
	(user)	shift;user	"$@" ;;
	(users)	shift;users	"$@" ;;
	(*)	show_help ;;
esac

log

exit 0


