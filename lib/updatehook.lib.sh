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
