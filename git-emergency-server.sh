#!/bin/bash

if ! eval "function a_bash_is_required () { :; }"; then
	echo >&2 "bash is required"
	exit 1
fi

export LC_ALL=C

CMD="${SSH_ORIGINAL_COMMAND:-"$*"}"

log() {
	printf '%s %s %s: %s -- %s\n' \
		"$(date -u +"%F %T")" "${SSH_CLIENT%% *}" "${USER:--}" "$1" "$CMD" >> "$LOG"
}

deny() {
	log "ERROR: $1: "
	printf >&2 "error: %s\n" "$1"
	exit 1
}

# deny Ctrl-C and unwanted chars
trap "deny 'BYE';kill -9 $$" 1 2 3 6 15


expr "$SSH_ORIGINAL_COMMAND$*" : '[-+ [:alnum:],'\''./_@=]*$' >/dev/null || deny "DON'T BE NAUGHTY"

require_admin_access() {
	[ -z "$SSH_CLIENT" ] || grep -q " USER=$USER GROUP=[^ ]*\badmin\b" "$KEYS" || deny 'Admin access denied'
}

is_secure() {
	expr "$1" : '.*\.\.' >/dev/null && deny "DON'T BE EVIL"
	expr "$1" : '[^[:alnum:]]' >/dev/null && deny "DON'T BE CRUEL"
}

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

#- Example usage:
#- 
update_hook() {
	case "$2" in
		('refs/tags/'*)
			access_check '(write|tag)$'
			[ "true" = "$(conf --bool tags.denyOverwrite)" ] && \
			git rev-parse --verify -q "$2" && deny "You can't overwrite an existing tag"
		;;
		('refs/heads/'*)
			BRANCH="${2#refs/heads/}"
			access_check "(write|write\.$BRANCH)$" "Repo $R Branch '$BRANCH' write denied for $USER"

			# The branch is new
			expr "$3" : '00*$' >/dev/null || {
				MO="$(conf branch.$BRANCH.mergeoptions)"
				if expr $4 : '00*$' >/dev/null; then
					[ "true" = "$(conf --bool branch.$BRANCH.denyDeletes)" ] && deny "Branch '$BRANCH' deletion denied"
				elif [ $3 = "$(cd $R>/dev/null; git-merge-base $3 $4)" ]; then
					# Update is fast-forward
					[ "--no-ff" = "$MO" ] && deny 'Fast-forward not allowed'
				else
					[ "--ff-only" = "$MO" ] && deny 'Only fast-forward are allowed'
				fi
			}
		;;
		(*)
			deny "Branch is not under refs/heads or refs/tags. What are you trying to do?"
		;;
	esac
}

#-   $ ssh git@host repo
#-   $ ssh git@host repo test.git init
#-   $ ssh git@host repo test.git config access.read all
#-   $ ssh git@host repo test.git config access.write admin,richard
#-   $ ssh git@host repo test.git config access.write.devel all
#-   $ ssh git@host repo test.git config access.tag richard
#-   $ ssh git@host repo test.git config branch.master.denyDeletes true
#-   $ ssh git@host repo test.git config branch.master.mergeoptions "--ff-only"
#-   $ ssh git@host repo test.git config branch.devel.mergeoptions "--no-ff"
#-   $ ssh git@host repo test.git config tags.denyOverwrite true
#-   $ ssh git@host repo test.git desc "My cool repo"
#-   $ ssh git@host repo test.git fork new_repo.git
#-   $ ssh git@host repo test.git drop
#-   $ ssh git@host repo fooo.git import /tmp/oldfooo/
repo() {
	require_admin_access

	test -e "$R" -o "$1" = "init" -o -z "$1" || deny "Repository $R not found"
	case "$1" in
		(import)
			[ ! -d "$REPOS/$R" ] || deny "repo $R already exists"
			local idir="$2"
			[ -d "$idir" ] || deny "No such repo directory $idir"
			case "$idir" in
				(*/.git) idir="${idir%/.git}" ;;
			esac
			[ -d "$idir/.git" ] || deny "There is no .git directory into $idir"
			git clone --bare "$idir" "$REPOS/$R"
		;;
		(init)
			[ -e "$R" ] && deny "Repository exists"
			mkdir -- "$R" && \
			cd "$R" >/dev/null && \
			git init --bare -q && \
			printf '#!/bin/sh\n%s update-hook $@\n' "$SELF" > hooks/update && \
			chmod +x hooks/update
		;;
		(config)
			conf ${4:-'-l'} $5 >&2
		;;
		(desc*)
			# TODO:2012-10-18:lauriro: Add namespaces support for description
			if [ "$R" = "$2" ]; then
				shift 3
				printf '%s\n' "$*" > $R/description
			fi
		;;
		(drop)
			is_secure "$2"
			# Backup repo
			tar -czf "$2.$(date -u +'%Y%m%d%H%M%S').tar.gz" "$2"

			# TODO:2012-10-18:lauriro: Remove namespaced data from repo
			rm -rf -- "$2"
		;;
		(fork)
			is_secure "$4"
			[ -e "$4" ] && deny "Repository exists"
			GIT_NAMESPACE="$4"
			[ "${4%/*}" = "$4" ] || mkdir -p ${4%/*}
			conf fork.master "$R"
		;;
		(*)
			[ -n "$2" -a -e "$2" ] && {
				is_secure "$2"
				[ "$R" = "$2" ] && cat $R/description
				printf "\nDisk usage: %s\n\nRepo '%s' permissions:\n" "$(du -hs $2 | cut -f1)" "$2"
				conf --get-regexp '^access\.' | sed -e 's,^access\.,,' -e 's/,/|/g' | while read name RE;do
					printf "$name [$RE] - %s\n" "$(list_of_users | grep -E "\\b($RE)\\b" | cut -d" " -f1 | sort | tr "\n" " ")"
				done
			} >&2
			printf "\nLIST OF REPOSITORIES:\n%s\n" "$(list_of_repos)" >&2
		;;
	esac
}

#-   $ ssh git@host user
#-   $ ssh git@host user add richard 'ssh-rsa AAAAB3N...50i8Q== user@example.com'
#-   $ ssh git@host user add richard < richard.pub
#-   $ ssh git@host user group richard all,admin
#-   $ ssh git@host user show richard
#-   $ ssh git@host user del richard
#-

user() {
	require_admin_access

	case "$1" in
		(add)	shift
			local kfile=''
			if [ ! -d "$USERS/$1" ]; then
				mkdir "$USERS/$1" || return 1
				kfile="1.pub"
			else
				for n in $(seq 1 99); do
					[ -e "$USERS/$1/$n.pub" ] || continue
					kfile=$n.pub
					break
				done
				if [ -z "$kfile" ]; then
					deny "ERROR: max keys reached"
					return 1
				fi
			fi
			echo "kfile=$kfile"
			if [ $# -eq 1 ] || [ "$2" = "-" ]; then
				tmp="$(mktemp)"
				cat - > "$tmp"
				case "$(cat -- "$tmp")" in
					('ssh-'???*' AAA'*) ;; # ssh-rsa/ssh-dss/ssh-ed25519
					('ecdsa-'*'-'*' AAA'*) ;; # ecdsa
					(*) rm -f -- "$tmp"; deny "ERROR: invalid ssh key format" ;;
				esac
				cat "$tmp" > "$USERS/$1/$kfile"
				rm -f -- "$tmp"
			else
				local u="$1";shift;
				printf '%s' "$*" > "$USERS/$1/$kfile"
			fi
		;;
		(disable)
			if [ -d "$USERS/$1" ]; then
				if [ -d "$USERDISABLED/$1" ]; then
					rm -rf -- "USERDISABLED/$1"
				fi
				mv "$USERS/$1" "$USERDISABLED/$1"
			fi
		;;
		(enable)
			if [ ! -d "$USERDISABLED/$1" ]; then
				deny "No such disabled user $1"
			fi
			mv "$USERDISABLED/$1" "$USERS/$1"
		;;	
		(del)
			#rm -rf -- "${USERS:-missingUSERS}/${1:-missingUSER}"
			if [ -d "$USERS/$1" ] || [ -d "$USERDISABLED/$1" ]; then
				rm -rf -- "$USERS/$1" "$USERDISABLED/$1"
			else
				deny "Nothing to delete, no such user $1"
			if 
			#sed -ie "/ USER=$2 /d" "$KEYS"
		;;
		(show)
			: #list the user keys, show the ssh finger print and visual fingerprint ?
		;;
#		(group)
#			sed -ie "/ USER=$2 /s/GROUP=[^ ]*/GROUP=$4/" "$KEYS"
#		;;
#		(key)
#			sed -ie "/ USER=$2 /s/no-pty .*$/no-pty $4/" "$KEYS"
#		;;
		*)
			[ -n "$2" ] && {
				RE="$(acc_re $2)"
				if [ -n "$RE" ]; then
					printf "\nUser '%s' permissions:\n" "$2" >&2

					list_of_repos | while read -r R; do 
						NS=${R%% ->*}
						[ "$NS" != "$R" ] && GIT_NAMESPACE=$NS || GIT_NAMESPACE=""
						ACC=$(conf --get-regexp '^access\.' | grep -E "$RE" | sed -e 's,^access\.,,' -e 's, .*$,,')
						[ "$ACC" ] && echo "$R ["$ACC"]" >&2
					done
				else
					echo "ERROR: User '$2' do not exists" >&2
				fi
			}
			printf "\nLIST OF USERS:\n%s\n" "$(sed -nE -e 's,^.*USER=([^ ]*) GROUP=([^ ]*).*$,\1 [\2],p' $KEYS)" >&2
		;;
	esac
}

users() {
	require_admin_access

	case "$1" in
		(list)
			(
				cd -- "$USERS" && \
				for u in *; do
					[ -d "$u" ] || continue
					case "$u" in
						('.'*) continue ;;
					esac
					echo "$u"
				done
			) | sort
		;;
		(diff)
			:
		;;
		(update)
			tmp="$(mktemp)"
			if [ -f "$XTRAKEYS" ]; then
				cat -- "$XTRAKEYS" > "$tmp"
			fi
			(
#    environment="NAME=value"
#             Specifies that the string is to be added to the environment when
#             logging in using this key.  Environment variables set this way
#             override other default environment values.  Multiple options of
#             this type are permitted.

# 'environment="USER='"$u"'",environment="GROUP='"$g"'",command="'"$cmd"'"'
# 'command="'"$cmd"'",environment="USER='"$u"'",environment="GROUP='"$g"'"'
# vieux sshd: no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty BUT ALSO: from="pattern-list"
#
				env=/usr/bin/env
				sshopts='no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty'
				echo "# $(basename "$0") start"
				cd -- "$USERS" && \
				for u in *; do
					[ -d "$u" ] || continue
					# get group for user $u
					g=all
					for k in "$u"/*'.pub'; do
						[ -f "$k" ] || continue
						key_comm="$(cat -- "$k")"
						case "$key_comm" in
							(ssh-*) ;;
							(*)
								echo >&2 "invalid ssh key format for $u ($k)"
								continue
							;;
						esac
						printf 'command="%s USER=%s GROUP=%s %s",%s %s\n' \
							"$env" "$u" "$g" "$SELF" "$sshopts" "$key_comm"
					done
				done
				echo "# $(basename "$0") end"
			) >> "$tmp"
			cat -- "$tmp"
			rm -f -- "$tmp"
		;;
		(*)
			echo >&2 "ERROR: unknown command"
			return 1
		;;
	esac
}

show_help() {
	sed -n "/^#- /s///p" "$SELF" >&2
}


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
cd -- "$REPOS" 2>/dev/null

if [ $# -eq 0 ]; then
	echo >2& "DEBUG: arg empty, use SSH_ORIGINAL_COMMAND !"
	set -- $SSH_ORIGINAL_COMMAND
fi

read_reponame() {
	# unquoted repo name
	R=${SSH_ORIGINAL_COMMAND:-"$1"}
	R=${R%\'};R=${R#*\'}
	is_secure "$R"

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
		env GIT_NAMESPACE=$GIT_NAMESPACE git shell -c "$1 '$R'"
	;;
	(update-hook)         # branch based access control
		shift;read_reponame "$1"
		shift;update_hook update-hook "$R" "$@"
		exit 0
	;;
	(repo)	shift;repo _	"$@" ;;
	(user)	shift;user	"$@" ;;
	(users)	shift;users	"$@" ;;
	(*)	show_help ;;
esac

log

exit 0


