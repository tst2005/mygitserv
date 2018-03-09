show_help() {
	sed -n "/^#- /s///p" "$SELF" >&2
}
#FIXME: sed ... "$SELF" "$(dirname "$SELF")/lib/*.lib.sh"

