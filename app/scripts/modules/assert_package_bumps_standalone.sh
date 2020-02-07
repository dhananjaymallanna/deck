#!/bin/bash
# Usage: assert_package_bumps_standalone [target branch]
# Use [target branch] to change the branch the script checks for changes against
# (default: origin/master if running in a Github Action, master otherwise)

error() {
  echo $* >&2
}

verbose() {
  [[ $VERBOSE == "true" ]] && echo $*
}

# Reports if package bumps are combined with other changes (not allowed). Package bumps must be standalone.
if [[ $GITHUB_ACTIONS == "true" && ( $GITHUB_BASE_REF != "master" || $GITHUB_REPOSITORY != 'spinnaker/deck' ) ]] ; then
  error "Not a pull request to master -- exiting"
  exit 0
fi

if [[ "$1" == "--verbose" ]] ; then
  VERBOSE=true
  shift;
fi

if [[ $GITHUB_ACTIONS == "true" ]] ; then
  verbose "Fetching tags..." && git fetch -q
  GHA_TARGET=origin/master
  cd app/scripts/modules || exit 1;
else
  cd "$(dirname "$0")" || exit 1;
fi

# Use the command line argument, origin/master (if running on GHA) or master (in that order)
TARGET_BRANCH=${1}
TARGET_BRANCH=${TARGET_BRANCH:-${GHA_TARGET}}
TARGET_BRANCH=${TARGET_BRANCH:-master}


PKGJSONCHANGED="Version change found"
error "TARGET_BRANCH=$TARGET_BRANCH"

# Tests are run against an ephemeral merge commit so we don't have to merge in $TARGET_BRANCH

PUREBUMPS=""
NOTBUMPED=""
for PKGJSON in */package.json ; do
  error "checking $PKGJSON"
  MODULE=$(basename "$(dirname "$PKGJSON")")

  # Run once outside of pipe so it will exit with any failure code
  git diff "$TARGET_BRANCH" -- "$PKGJSON" >/dev/null;
  HAS_PKG_BUMP=$(git diff "$TARGET_BRANCH" -- "$PKGJSON" | grep -c '"version"')
  if [ "$HAS_PKG_BUMP" -ne 0 ] ; then
    # Ensuring that the version change is the only change in package.json
    PKG_JSON_OTHER_CHANGES=$(git diff --numstat "$TARGET_BRANCH" -- "$PKGJSON" | cut -f 1)
    if [ "$PKG_JSON_OTHER_CHANGES" -ne 1 ] ; then
      error "==================================================="
      error "$PKGJSONCHANGED in $MODULE/package.json"
      error "However, other changes were found in package.json"
      error ""
      error "Version change:"
      git diff -u "$TARGET_BRANCH" -- "$PKGJSON" | grep '"version"' >&2
      error ""
      error "git diff of package.json:"
      error "=========================================="
      git diff "$TARGET_BRANCH" -- "$PKGJSON" >&2
      error "=========================================="
      exit 3
    fi


    # checking that the only files changed are app/scripts/modules/*/package.json
    # Run once outside of pipe so it will exit with any failure code
    git diff --name-only "$TARGET_BRANCH" >/dev/null
    OTHER_FILES_CHANGED=$(git diff --name-only "$TARGET_BRANCH" | grep -v "app/scripts/modules/.*/package.json" | wc -l)
    [[ $? -ne 0 ]] && exit 4
    if [ "$OTHER_FILES_CHANGED" -ne 0 ] ; then
      error "==================================================="
      error "$PKGJSONCHANGED in $MODULE/package.json"
      error "However, other files were also changed"
      error ""
      error "Version change:"
      git diff -u "$TARGET_BRANCH" -- "$PKGJSON" | grep '"version"' >&2
      error ""
      error "List of all files changed:"
      error "=========================================="
      git diff --name-only "$TARGET_BRANCH" >&2
      error "=========================================="
      exit 5
    fi

    PUREBUMPS="$PUREBUMPS $MODULE"
  else
    NOTBUMPED="$NOTBUMPED $MODULE"
  fi
done

if [[ $VERBOSE == "true" ]] ; then
  [[ -n $PUREBUMPS ]] && verbose "Pure Package Bumps: $PUREBUMPS"
  [[ -n $NOTBUMPED ]] && verbose "Packages not bumped: $NOTBUMPED"
else
  [[ -n $PUREBUMPS ]] && echo "pure" || echo "nobump";
fi
