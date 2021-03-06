#!/bin/bash

set -o pipefail
[ -n "$DEBUG" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source ${my_dir}/../common/common.sh
source ${my_dir}/../common/functions.sh

echo "INFO: Build containers"
if [[ -z "${CONTAINER_BUILDER_DIR}" ]] ; then
  echo "ERROR: CONTAINER_BUILDER_DIR Must be set to build containers"
  exit 1
fi

res=0
${CONTAINER_BUILDER_DIR}/containers/build.sh | sed "s/^/containers: /" || res=1

mkdir -p /output/logs/container-builder
# do not fail script if logs files are absent
mv ${CONTAINER_BUILDER_DIR}/containers/*.log /output/logs/container-builder/ || /bin/true

exit $res
