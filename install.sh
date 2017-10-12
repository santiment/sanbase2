#!/bin/bash

if [ -z "$1" ]; then
  echo "No project name specified"
  echo "Usage: bash <(curl -s https://raw.githubusercontent.com/valo/phoenix_with_nextjs/add_install_script/install.sh) <PROJECT_NAME>"
  exit 1
fi

set -e

GITHUB_SRC='git@github.com:valo/phoenix_with_nextjs.git'
SKELETON_MODULE_NAME="PhoenixWithNextjs"
SKELETON_PROJECT_NAME="phoenix_with_nextjs"

NEW_PROJECT_NAME=$1
NEW_MODULE_NAME=`elixir -e "Macro.camelize(\"$NEW_PROJECT_NAME\") |> IO.puts"`

mkdir $NEW_PROJECT_NAME
git clone $GITHUB_SRC $NEW_PROJECT_NAME

cd $NEW_PROJECT_NAME

grep -lr $SKELETON_MODULE_NAME . | LC_ALL=C xargs sed -i '' -e "s/$SKELETON_MODULE_NAME/$NEW_MODULE_NAME/g"
grep -lr $SKELETON_PROJECT_NAME . | LC_ALL=C xargs sed -i '' -e "s/$SKELETON_PROJECT_NAME/$NEW_PROJECT_NAME/g"
mv lib/$SKELETON_PROJECT_NAME lib/$NEW_PROJECT_NAME
mv lib/$SKELETON_PROJECT_NAME\_web lib/$NEW_PROJECT_NAME\_web
mv lib/$SKELETON_PROJECT_NAME\_web.ex lib/$NEW_PROJECT_NAME\_web.ex
mv lib/$SKELETON_PROJECT_NAME.ex lib/$NEW_PROJECT_NAME.ex
mv test/$SKELETON_PROJECT_NAME\_web test/$NEW_PROJECT_NAME\_web

rm -fr .git/

mix deps.get
cd app && yarn && cd ..

cd ..
