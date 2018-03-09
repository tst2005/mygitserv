
#-   $ ssh git@host user
#-   $ ssh git@host user add richard 'ssh-rsa AAAAB3N...50i8Q== user@example.com'
#-   $ ssh git@host user add richard < richard.pub
#-   $ ssh git@host user group richard all,admin
#-   $ ssh git@host user show richard
#-   $ ssh git@host user del richard
#-
gu_user_catkeys() {
	(
		( cd -- "$USERS" || exit 1 ) || exit 1
		find "$USERS" -mindepth 1 -maxdepth 1 -type f \( -name "$1".pub -o -name "$1"'@*.pub' \)
		find "$USERS" -mindepth 1 -maxdepth 1 -type d -name "$1" -exec find {} -mindepth 1 -maxdepth 1 -type f \( -name '*.pub' -o -name '*@*.pub' \) \;
		#[ ! -d "$1" ] || find "$1" -type f -name '*.pub'
	)
}

gu() {
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
					('ssh-rsa AAAAB3NzaC1yc2EAAAA'*) ;; # rsa
					('ssh-dss AAAAB3NzaC1kc3MAAA'*) ;; # dsa
					('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA'*) ;; # ed25519
					('ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAA'*) ;; # ecdsa
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
			fi
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
		(list)
			users list
		;;
#		*)
#			[ -n "$2" ] && {
#				RE="$(acc_re $2)"
#				if [ -n "$RE" ]; then
#					printf "\nUser '%s' permissions:\n" "$2" >&2
#
#					list_of_repos | while read -r R; do 
#						NS=${R%% ->*}
#						[ "$NS" != "$R" ] && GIT_NAMESPACE=$NS || GIT_NAMESPACE=""
#						ACC=$(conf --get-regexp '^access\.' | grep -E "$RE" | sed -e 's,^access\.,,' -e 's, .*$,,')
#						[ "$ACC" ] && echo "$R ["$ACC"]" >&2
#					done
#				else
#					echo "ERROR: User '$2' do not exists" >&2
#				fi
#			}
#			printf "\nLIST OF USERS:\n%s\n" "$(sed -nE -e 's,^.*USER=([^ ]*) GROUP=([^ ]*).*$,\1 [\2],p' $KEYS)" >&2
#		;;
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
					echo "${u%%@*}"
				done
			) | sort -u
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
				echo "# $(basename "$0") begin"
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
