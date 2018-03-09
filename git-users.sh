#!/bin/bash

if ! eval "function a_bash_is_required () { :; }"; then
	echo >&2 "bash is required"
	exit 1
fi

#set -e

export LC_ALL=C

STARTDIR="$(pwd)"
SELF="$0"
case "$SELF" in
	(/*) ;;
	(*) SELF="$(pwd)/$SELF" ;;
esac
SELFDIR="${SELF%/*}"

. "${SELFDIR:-.}/user-group.lib.sh"

#CMD="${SSH_ORIGINAL_COMMAND:-"$*"}"
#
#log() {
#	printf '%s %s %s: %s -- %s\n' \
#		"$(date -u +"%F %T")" "${SSH_CLIENT%% *}" "${USER:--}" "$1" "$CMD" >> "$LOG"
#}

deny() {
	#log "ERROR: $1: "
	printf >&2 "error: %s\n" "$1"
	exit 1
}

# deny Ctrl-C and unwanted chars
trap "deny 'BYE';kill -9 $$" 1 2 3 6 15

re_match() { expr >/dev/null "$2" : "$1"; }

if ! re_match '[-+ [:alnum:],'"'"'./_@=]*$' "$SSH_ORIGINAL_COMMAND$*"; then
	( eval "set -- $SSH_ORIGINAL_COMMAND" ; printf '%s\n' "$2" ) 1>&2
	deny "DON'T BE NAUGHTY"
fi

is_secure() {
	if re_match '.*\.\.' "$1"; then
		deny "DON'T BE EVIL";
	fi
	if ! re_match '[^[:alnum:]]' "$1"; then
		deny "DON'T BE CRUEL";
	fi
}

# perms managment #

access_check() {
	case "$1" in
		('read'|'write') ;;
		('(write|tag)$') ;;
		('(write|write.'*')') ;;
		(*) deny "internal error for access_check" ;;
	esac

	# TODO
	case "$1" in ('read') return 0;; esac; return 0;

	#conf --get-regexp "^access\.$1" | \
	#grep -E -q "$(acc_re $USER)" || deny "${2-"Repository not found"}"
}

require_admin_access() { return 0; }


#list_of_users() {
#	sed -E -e 's/^.* USER=([^ ]*) GROUP=([^ ]*) .*$/\1 \2/' "$KEYS"
#}

#acc_re() {
#	sed -E -e 's/^.*USER='$1' GROUP=([^ ]*) .*$/ .*\\b('$1'|\1)\\b/;ta' -e d -e :a -e 's/,/|/g' "$KEYS"
#}

read_reponame() {
	local x="$(
		eval "set -- "$SSH_ORIGINAL_COMMAND
		echo "$2"
	)"
	# unquoted repo name
	R=${SSH_ORIGINAL_COMMAND:-"$1"}
echo >&2 "read_reponame R=$R (x=$x)"
	R=${R%\'};R=${R#*\'}
echo >&2 "read_reponame R=$R"
	is_secure "$R"

	case "$R" in
		(*.git);;
		(*) R="${R}.git";;
	esac

	# When repo is a file then it is a fork
	if [ -f "$R" ]; then
		echo >&2 "not-implemented-yet: fork repo is not supported"
		exit 1
		#GIT_NAMESPACE="$R"
		#R="$(conf fork.master)" && is_secure "$R"
	fi
}


LOG="$SELFDIR/access.log"
REPOS="$SELFDIR/repositories"
USERS="$SELFDIR/users"
USERDISABLED="$SELFDIR/users-disabled"
KEYS="$HOME/.ssh/authorized_keys.gitserv"
XTRAKEYS="$HOME/.ssh/authorized_keys.local"

#( USERS=$(pwd)/users gu_user_catkeys titi )
#exit $?
#gu	"$@"
#users	"$@"

[ -d "$REPOS" ] || mkdir -- "$REPOS"
cd -- "$REPOS" 2>/dev/null

if [ $# -eq 0 ] && [ -n "$USER" ] && [ -n "$SSH_ORIGINAL_COMMAND" ]; then
        eval "set -- $SSH_ORIGINAL_COMMAND"
elif [ $# -eq 1 ] && [ -z "$USER" ] && [ -n "$SSH_ORIGINAL_COMMAND" ]; then
	USER="$1"
	eval "set -- $SSH_ORIGINAL_COMMAND"
fi

case "$1" in
        (git-*)   # git pull and push
		read_reponame "$2"
		access_check read
#		echo >&2 "# $*"
		if [ "$1" = "git-receive-pack" ]; then
			access_check write "WRITE ACCESS DENIED"
		fi
		# always got a relative path (relative to $REPOS)
		case "$R" in
			(/*) R="./${R#/}" ;;
			(./*) ;;
			(*) R="./$R" ;;
		esac
		( cd -- "$REPOS" && [ -d "$R" ] ) || echo >&2 "No such directory $R"
#		echo >&2 "# ($(pwd)) R=$R GIT_NAMESPACE=$GIT_NAMESPACE"
		#[ -d "$R" ] || mkdir -- "$R"
		echo >&2 "($(pwd)) git shell -c \"$1 '$R'\""
		cd -- "$REPOS" && \
		env GIT_NAMESPACE="$GIT_NAMESPACE" git shell -c "$1 '$R'"
        ;;
	(update-hook)         # branch based access control
		shift;read_reponame "$1"
#		echo "#DEBUG: receive update-hook[$#]: $*"
		#shift;update_hook update-hook "$R" "$@"
		exit 0
        ;;
#	(repo)  shift;repo _    "$@" ;;
#	(user)  shift;user      "$@" ;;
#	(users) shift;users     "$@" ;;
#	(*)     show_help ;;
	(*) echo >&2 "Unknown command $1" ;;
esac

#log

exit 0


