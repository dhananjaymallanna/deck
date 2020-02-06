#!/bin/bash
# Usage: assert_pacakge_bumps_standalone [target branch]
# Use [target branch] to change the branch the script checks for changes against
# (default: origin/master if running in a Github Action, master otherwise)

# Reports if package bumps are combined with other changes (not allowed). Package bumps must be standalone.
if [[ $GITHUB_ACTIONS == "true" && ( $GITHUB_BASE_REF != "master" || $GITHUB_REPOSITORY != 'spinnaker/deck' ) ]] ; then
  echo "Not a pull request to master, exiting"
  exit 0
fi


if [[ $GITHUB_ACTIONS == "true" ]] ; then
  echo "Fetching tags..." && git fetch -q
  GHA_TARGET=origin/master
  cd app/scripts/modules || exit 1;
else
  cd "$(dirname "$0")" || exit 1;
fi

# Use the command line argument, origin/master (if running on GHA) or master (in that order)
TARGET_BRANCH=${1}
TARGET_BRANCH=${TARGET_BRANCH:-${GHA_TARGET}}
TARGET_BRANCH=${TARGET_BRANCH:-master}

PKGJSONCHANGED="Version change detected in package.json"
ONLYVERSIONCHANGED="Version change must be the only line changed in package.json"
ONLYPKGJSONCHANGED="package.json (in app/scripts/modules) must be the only files changed in a pull request with version bumps"

echo "TARGET_BRANCH=$TARGET_BRANCH"

# Tests are run against an ephemeral merge commit so we don't have to merge in $TARGET_BRANCH

PUREBUMP=none
for PKGJSON in */package.json ; do
  MODULE=$(basename "$(dirname "$PKGJSON")")
  echo "::group::Checking $MODULE"

  echo "==================================================="
  echo "Checking $MODULE"
  echo "==================================================="
  HAS_PKG_BUMP=$(git diff "$TARGET_BRANCH" -- "$PKGJSON" | grep '"version"' | wc -l)
  [[ $? -ne 0 ]] && exit 2
  if [ "$HAS_PKG_BUMP" -ne 0 ] ; then
    echo " [ YES  ] $PKGJSONCHANGED"

    # Ensuring that the version change is the only change in package.json
    PKG_JSON_OTHER_CHANGES=$(git diff --numstat "$TARGET_BRANCH" -- "$PKGJSON" | cut -f 1)
    if [ "$PKG_JSON_OTHER_CHANGES" -ne 1 ] ; then
      echo " [ FAIL ] $ONLYVERSIONCHANGED"
      echo ""
      echo "=========================================="
      echo "Failure details (git diff of package.json)"
      echo "=========================================="
      echo ""
      git diff "$TARGET_BRANCH" -- "$PKGJSON"
      echo ""
      echo "=========================================="
      exit 3
    fi

    echo " [ PASS ] $ONLYVERSIONCHANGED"

    # checking that the only files changed are app/scripts/modules/*/package.json
    OTHER_FILES_CHANGED=$(git diff --name-only "$TARGET_BRANCH" | grep -v "app/scripts/modules/.*/package.json" | wc -l)
    [[ $? -ne 0 ]] && exit 4
    if [ "$OTHER_FILES_CHANGED" -ne 0 ] ; then
      echo " [ FAIL ] $ONLYPKGJSONCHANGED"
      echo ""
      echo "==========================================="
      echo "Failure details (list of all files changed)"
      echo "==========================================="
      echo ""
      git diff --name-only "$TARGET_BRANCH"
      echo ""
      echo "==========================================="
      exit 5
    fi
    # at least one pure bump found
    PUREBUMP=true
    echo " [ PASS ] $ONLYPKGJSONCHANGED"
    echo "::endgroup::"
  else
    echo " [  NO  ] $PKGJSONCHANGED"
    echo " [  N/A ] $ONLYVERSIONCHANGED"
    echo " [  N/A ] $ONLYPKGJSONCHANGED"
  fi
  echo ""
done

export PUREBUMP
