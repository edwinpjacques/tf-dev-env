#!/bin/bash

: ${WORK_DIR:="${HOME}/work"}
STAGES_DIR="${WORK_DIR}/.stages"
: ${ROOT_CONTRAIL:="${HOME}/contrail"}

# Folders and artifacts which have to be symlinked in order to separate them from sources

declare -a work_folders=(build BUILDROOT BUILD RPMS SOURCES SRPMS SRPMSBUILD .sconf_temp  SPECS .stages)
declare -a work_files=(.sconsign.dblite)

function create_env_file() {
  # exports 'src_volume_name' as return result
  local tf_container_env_file=$1
  cat <<EOF > $tf_container_env_file
export DEBUG=${DEBUG}
export DEBUGINFO=${DEBUGINFO}
export LINUX_DISTR=${LINUX_DISTR}
export LINUX_DISTR_VER=${LINUX_DISTR_VER}
export BUILD_MODE=${BUILD_MODE}
export DEV_ENV_ROOT=${DEV_ENV_ROOT=/root/tf-dev-env}
export DEVENV_TAG=$DEVENV_TAG
export CONTRAIL_BUILD_FROM_SOURCE=${CONTRAIL_BUILD_FROM_SOURCE}
export SITE_MIRROR=${SITE_MIRROR}
export CONTRAIL_KEEP_LOG_FILES=${CONTRAIL_KEEP_LOG_FILES}
export CONTRAIL_BRANCH=${CONTRAIL_BRANCH}
export CONTRAIL_CONTAINER_TAG=${CONTRAIL_CONTAINER_TAG}
export CONTRAIL_REPOSITORY=http://localhost:${RPM_REPO_PORT}
export CONTRAIL_REGISTRY=${CONTAINER_REGISTRY}
export VENDOR_NAME=$VENDOR_NAME
export VENDOR_DOMAIN=$VENDOR_DOMAIN
export MULTI_KERNEL_BUILD=$MULTI_KERNEL_BUILD
export KERNEL_REPOSITORIES_RHEL8="$KERNEL_REPOSITORIES_RHEL8"
export WORK_DIR="$WORK_DIR"
export ROOT_CONTRAIL="$ROOT_CONTRAIL"
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export CONTRAIL_CONFIG_DIR="${CONTRAIL_CONFIG_DIR:-/config}"
export CONTRAIL_INPUT_DIR="${CONTRAIL_INPUT_DIR:-/input}"
export CONTRAIL_OUTPUT_DIR="${CONTRAIL_OUTPUT_DIR:-/output}"
EOF
  if [[ -n "$CONTRAIL_BUILD_FROM_SOURCE" && "$BIND_CONTRAIL_DIR" == 'false' ]] ; then
    export src_volume_name=ContrailSources
    echo "export CONTRAIL_SOURCE=${src_volume_name}" >> $tf_container_env_file
  else
    echo "export CONTRAIL_SOURCE=${CONTRAIL_DIR}" >> $tf_container_env_file
  fi
  if [[ -n "${GENERAL_EXTRA_RPMS+x}" ]] ; then
    echo "export GENERAL_EXTRA_RPMS=${GENERAL_EXTRA_RPMS}" >> $tf_container_env_file
  fi
  if [[ -n "${BASE_EXTRA_RPMS+x}" ]] ; then
    echo "export BASE_EXTRA_RPMS=${BASE_EXTRA_RPMS}" >> $tf_container_env_file
  fi
  if [[ -n "${RHEL_HOST_REPOS+x}" ]] ; then
    echo "export RHEL_HOST_REPOS=${RHEL_HOST_REPOS}" >> $tf_container_env_file
  fi

  # code review system options
  if [[ -n "$GERRIT_URL" ]]; then
    echo "export GERRIT_URL=${GERRIT_URL}" >> $tf_container_env_file
  fi
  if [[ -n "$GERRIT_BRANCH" ]]; then
    echo "export GERRIT_BRANCH=${GERRIT_BRANCH}" >> $tf_container_env_file
  fi
  if [[ -n "$GERRIT_PROJECT" ]]; then
    echo "export GERRIT_PROJECT=${GERRIT_PROJECT}" >> $tf_container_env_file
  fi

  # repo path overrides
  if [[ -n $REPO_INIT_MANIFEST_URL ]]; then
    echo "export REPO_INIT_MANIFEST_URL=${REPO_INIT_MANIFEST_URL}" >> $tf_container_env_file
  fi
  if [[ -n $VNC_ORGANIZATION ]]; then
    echo "export VNC_ORGANIZATION=${VNC_ORGANIZATION}" >> $tf_container_env_file
  fi
  if [[ -n $VNC_REPO ]]; then
    echo "export VNC_REPO=${VNC_REPO}" >> $tf_container_env_file
  fi
}

function prepare_infra()
{
  # Do nothing if directories are the same (dev case)
  if [[ "$WORK_DIR" == "$ROOT_CONTRAIL" ]]; then
    return 0
  fi
  echo "INFO: create symlinks to work directories with artifacts  $(date)"
  mkdir -p "$WORK_DIR" "$ROOT_CONTRAIL"
  # "$ROOT_CONTRAIL" will be defined later as REPODIR
  for folder in "${work_folders[@]}" ; do
    [[ -e "$WORK_DIR/$folder" ]] || mkdir "$WORK_DIR/$folder"
    [[ -e "$ROOT_CONTRAIL/$folder" ]] || ln -sf "$WORK_DIR/$folder" "$ROOT_CONTRAIL/$folder"
  done
  for file in "${work_files[@]}" ; do
    touch "$WORK_DIR/$file"
    [[ -e "$ROOT_CONTRAIL/$file" ]] || ln -sf "$WORK_DIR/$file" "$ROOT_CONTRAIL/$file"
  done
}

function get_current_container_tag()
{
  echo $(curl -s "http://tf-nexus.progmaticlab.com:8082/frozen/tag")
}

# Classification of TF projects dealing with containers.
# TODO: use vnc/default.xml for this information later (loaded to .repo/manifest.xml)
deployers_projects=("tf-charms" "tf-helm-deployer" "tf-ansible-deployer" \
  "tf-kolla-ansible" "tf-tripleo-heat-templates" "tf-container-builder" "tf-openshift-ansible")
containers_projects=("tf-container-builder")
tests_projects=("tf-test" "tf-deployment-test")
vrouter_dpdk=("tf-dpdk")
infra_projects=("tf-dev-env")

changed_projects=()
changed_containers_projects=()
changed_deployers_projects=()
changed_tests_projects=()
changed_product_projects=()
unchanged_containers=()

# Check patchset and fill changed_projects, also collect containers NOT to build
function patches_exist() {
  if [[ -e "/input/patchsets-info.json" ]] ; then
    # First fetch existing containers list
    frozen_containers=($(curl http://$FROZEN_REGISTRY/v2/_catalog | jq -r '.repositories | .[]'))
    # Next initialize projects lists and look for changes
    changed_projects=()
    changed_containers_projects=()
    changed_deployers_projects=()
    changed_tests_projects=()
    changed_product_projects=()
    projects=$(jq '.[].project' "/input/patchsets-info.json")
    for project in ${projects[@]}; do
      project=$(echo $project | cut -f 2 -d "/" | tr -d '"')
      changed_projects+=($project)
      non_container_project=true
      if [[ ${infra_projects[@]} =~ $project ]] ; then
        continue
      fi
      if [[ ${containers_projects[@]} =~ $project ]] ; then
        changed_containers_projects+=($project)
        non_container_project=false
      fi
      if [[ ${deployers_projects[@]} =~ $project ]] ; then
        changed_deployers_projects+=($project)
        non_container_project=false
      fi
      if [[ ${tests_projects[@]} =~ $project ]] ; then
        changed_tests_projects+=($project)
        non_container_project=false
      fi
      if $non_container_project ; then
        changed_product_projects+=($project)
        # No containers are reused in this case - all should be rebuilt
        frozen_containers=()
      fi
    done

    # Now scan through frozen containers and remove ones to rebuild
    for container in ${frozen_containers[@]}; do
      if [[ $container == *-test ]] ; then
        if [[ -z $changed_tests_projects ]] ; then
          unchanged_containers+=($container)
        fi
      elif [[ $container == *-src ]] ; then
        if [[ -z $changed_deployers_projects ]] ; then
          unchanged_containers+=($container)
        fi
      else
        if [[ $container != *-sandbox ]] && [[ -z $changed_containers_projects ]] ; then
          unchanged_containers+=($container)
        fi
      fi
    done

    return 0
  fi
  return 1
}
