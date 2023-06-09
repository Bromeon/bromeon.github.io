#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e

repo="$1"
num="$2"
#date=$3

# Find main crate name
case $repo in
	"gdnative")
		mainCrate="gdnative"
		features="--features async,serde,inventory"
		;;
	"gdext")
		mainCrate="godot"
		features=""
		;;
	*)
		echo "Invalid repo '$repo'; abort."
		exit 1
		;;
esac

PRE="Docs | $repo/$num |"
echo "$PRE start PUT operation (crate '$mainCrate')."

if [[ "$num" == "master" ]]; then
	gitRef="master"
	dir="$repo/master"
	prettyNum="Latest master"
else
	gitRef="pull/$num/head"
	dir="$repo/pr-$num"
	prettyNum="Pull Request #$num"
fi

# Checkout PR branch
if [[ -d "$dir" ]]; then
    # Note: this doesn't happen in CI, maybe locally
	echo "$PRE already deployed, update..."
else
	echo "$PRE initial deployment, create..."
	git clone "https://github.com/godot-rust/$repo.git" --depth 1 --no-checkout cloned
fi

# Update to latest commit
cd cloned
git fetch origin "$gitRef"

git reset --hard FETCH_HEAD --quiet
echo "----------------------------------------"
git log -n 1
echo "========================================"

# Build docs
echo "$PRE build Rust docs of crate '$mainCrate' ($features)..."
up=".."
# shellcheck disable=SC2086
cargo doc -p $mainCrate $features --no-deps --target-dir $up/target
#mkdir -p "$up/target/doc"
cd $up

# Write HTML redirect page (dir = "$repo/pr-$num" or "$repo/master")
htmlFile="target/doc/index.html"
repoHtmlFile="repo-index.html"
redirectUrl="/docs/$dir/$mainCrate"

echo "$PRE write HTML branch redirect: /docs/$dir -> $redirectUrl"

# Note: cache control not reliable through meta. The below redirection may remain cached in browsers.
# Alternatively, use JS. Also, consider https://github.com/rust-lang/cargo/issues/739 in the future.
cat > "$htmlFile" <<- HEREDOC
<html>
  <head>
    <meta http-equiv="refresh" content="0; url=$redirectUrl" />
  </head>
</html>
HEREDOC

# If this is master, also put one in /docs/$repo, which also links to the master page
if [[ "$num" == "master" ]]; then
    echo "$PRE write HTML repo redirect:   /docs/$repo -> $redirectUrl"
    cat > "$repoHtmlFile" <<- HEREDOC
<html>
  <head>
    <meta http-equiv="refresh" content="0; url=/docs/$repo/master/$mainCrate" />
  </head>
</html>
HEREDOC
fi

# Recognize min crate version, replace with current PR/master version
libVersion=$(grep -Po '^version = "\K[^"]*' "cloned/$mainCrate/Cargo.toml")
echo "$PRE detected crate: $mainCrate v$libVersion."
find "target/doc/$mainCrate" -name .html -o -type f -print0 | xargs -0 sed -i 's/'"Version $libVersion"'/'"$prettyNum"'/g'

# Copy docs
echo "$PRE deploy docs for #$num..."

if [[ -d "docs/$dir" ]]; then
    echo "$PRE docs already exist, update..."
    echo "PUT_STATUS=Update" >> "$GITHUB_ENV"
    rm -rf "docs/$dir"
else
    echo "$PRE docs are new, create..."
    echo "PUT_STATUS=Create" >> "$GITHUB_ENV"
fi

mkdir -p "docs/$dir"
mv target/doc/* "docs/$dir"
if [[ "$num" == "master" ]]; then
    mv $repoHtmlFile "docs/$repo/index.html"
fi

echo "$PRE PUT operation completed."
