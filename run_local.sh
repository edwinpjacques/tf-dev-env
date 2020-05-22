#!/bin/bash
scriptdir=$(realpath $(dirname "$0"))
export CONTRAIL_BUILD_LOCAL=1
$scriptdir/run.sh "$@"