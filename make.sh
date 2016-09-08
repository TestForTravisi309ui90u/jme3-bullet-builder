#!/bin/bash
REPO_NAME="jmonkeyengine"
BRANCH="master"
ROOT_GITHUB_USER="TestForTravisi309ui90u"

rm -Rf root_tmp
mkdir -p root_tmp
wget  -q https://raw.githubusercontent.com/$ROOT_GITHUB_USER/jme3-bullet-builder/root/make.sh -O root_tmp/root.sh
source root_tmp/root.sh

main $@