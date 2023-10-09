#!/usr/bin/env bash

set -e

# https://github.com/united-manufacturing-hub/MgmtIssues/issues/572
## Check if the user is root
if [ $(id -u) -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi