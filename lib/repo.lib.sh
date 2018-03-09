
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
			cd -- "$R" >/dev/null && \
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
