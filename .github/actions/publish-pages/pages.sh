#!/usr/bin/env bash
#
# Publish a directory into the Pages branch, at the site root or in a
# subdirectory, leaving everything else on the branch alone.
#
# The branch holds the whole site: the released build at the root and one
# directory per open pull request. That is why this cannot use
# actions/deploy-pages, which replaces the entire site on every deployment.
#
# Usage:
#   publish.sh publish <source-dir> <target-path|""> <commit-message>
#   publish.sh remove  <target-path>                <commit-message>
#
#   PAGES_BRANCH   branch to publish to (default: gh-pages)
#   PAGES_ATTEMPTS push attempts before giving up (default: 4)

set -euo pipefail

ACTION="${1:?action required: publish or remove}"
case "$ACTION" in
	publish)
		SOURCE="${2:?source directory required}"
		TARGET="${3-}"
		MESSAGE="${4:?commit message required}"
		;;
	remove)
		SOURCE=""
		TARGET="${2-}"
		MESSAGE="${3:?commit message required}"
		;;
	*)
		echo "Unknown action '$ACTION': expected publish or remove" >&2
		exit 1
		;;
esac
BRANCH="${PAGES_BRANCH:-gh-pages}"
ATTEMPTS="${PAGES_ATTEMPTS:-4}"
WORK="${RUNNER_TEMP:-/tmp}/pages-publish"

case "$TARGET" in
	/*|*..*) echo "Refusing to publish to '$TARGET': must be a relative path" >&2; exit 1 ;;
esac

if [ "$ACTION" = "publish" ]; then
	if [ ! -s "$SOURCE/index.html" ]; then
		echo "No usable build in '$SOURCE': index.html is missing or empty" >&2
		exit 1
	fi
	SOURCE="$(cd "$SOURCE" && pwd)"
fi

if [ "$ACTION" = "remove" ] && [ -z "$TARGET" ]; then
	echo "Refusing to remove the site root" >&2
	exit 1
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

## Everything the site keeps across a publish, whatever else changes.
keep() {
	case "$1" in
		.git|.nojekyll|pr-*) return 0 ;;
		*) return 1 ;;
	esac
}

publish_once() {
	rm -rf "$WORK"
	git worktree prune

	# Start from the branch as it is right now, or from an empty tree the first
	# time, so this works on a repository that has never published.
	local base
	if git fetch --depth=1 origin "$BRANCH" 2>/dev/null; then
		base=FETCH_HEAD
	else
		base="$(git commit-tree "$(git hash-object -t tree /dev/null)" -m "Initialise ${BRANCH}")"
		echo "Branch ${BRANCH} does not exist yet; starting it from an empty tree."
	fi
	git worktree add --force --detach "$WORK" "$base" >/dev/null

	if [ "$ACTION" = "remove" ]; then
		if [ ! -e "${WORK:?}/${TARGET}" ]; then
			echo "Nothing to remove at /${TARGET}."
			return 0
		fi
		rm -rf "${WORK:?}/${TARGET}"
	elif [ -n "$TARGET" ]; then
		rm -rf "${WORK:?}/${TARGET}"
		mkdir -p "${WORK}/${TARGET}"
		cp -R "$SOURCE"/. "${WORK}/${TARGET}/"
	else
		# Replacing the root must not take the pull-request previews with it.
		local entry
		for entry in "$WORK"/* "$WORK"/.[!.]*; do
			[ -e "$entry" ] || continue
			keep "$(basename "$entry")" || rm -rf "$entry"
		done
		cp -R "$SOURCE"/. "$WORK"/
	fi

	# GitHub Pages runs Jekyll over a branch unless told not to, which eats
	# files and directories beginning with an underscore.
	touch "$WORK/.nojekyll"

	git -C "$WORK" add --all
	if git -C "$WORK" diff --cached --quiet; then
		echo "Nothing changed; not pushing."
		return 0
	fi
	git -C "$WORK" commit --quiet -m "$MESSAGE"
	git -C "$WORK" push --quiet origin "HEAD:refs/heads/${BRANCH}"
}

for attempt in $(seq 1 "$ATTEMPTS"); do
	if publish_once; then
		if [ "$ACTION" = "remove" ]; then
			echo "Removed ${BRANCH}:/${TARGET}"
		else
			echo "Published ${SOURCE} to ${BRANCH}:/${TARGET}"
		fi
		rm -rf "$WORK"
		git worktree prune
		exit 0
	fi
	# A concurrent publish moved the branch: rebuild on the new tip and retry.
	echo "Publish attempt ${attempt} failed; retrying."
	sleep "$((2 ** attempt))"
done

echo "Could not publish to ${BRANCH} after ${ATTEMPTS} attempts" >&2
exit 1
