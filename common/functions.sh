#!/bin/bash

function is_container_created() {
  local container=$1
  if ! mysudo docker ps -a --format '{{ .Names }}' | grep -x "$container" > /dev/null 2>&1 ; then
    return 1
  fi
}

function is_container_up() {
  local container=$1
  if ! mysudo docker inspect --format '{{ .State.Status }}' $container | grep -q "running" > /dev/null 2>&1 ; then
    return 1
  fi
}

function ensure_root() {
  local me=$(whoami)
  if [ "$me" != 'root' ] ; then
    echo "ERROR: this script requires root:"
    echo "       mysudo -E $0"
    return 1
  fi
}

function ensure_port_free() {
  local port=$1
  if mysudo lsof -Pn -sTCP:LISTEN -i :$port ; then
    echo "ERROR: Port $port is already opened by another process"
    return 1
  fi
}

function setup_httpd() {
  RPM_REPO_PORT='6667'

  mkdir -p $HOME/contrail/RPMS
  sudo mkdir -p /run/httpd # For some reason it's not created automatically

  sudo sed -i "s/Listen 80/Listen $RPM_REPO_PORT/" /etc/httpd/conf/httpd.conf
  sudo sed -i "s/\/var\/www\/html\"/\/var\/www\/html\/repo\"/" /etc/httpd/conf/httpd.conf
  sudo ln -s $HOME/contrail/RPMS /var/www/html/repo

  # The following is a workaround for when tf-dev-env is run as root (which shouldn't usually happen)
  sudo chmod 755 -R /var/www/html/repo
  sudo chmod 755 /root

  sudo /usr/sbin/httpd
}

function mysudo() {
  if [[ $DISTRO == "macosx" ]]; then
	  "$@"
  else
	  sudo "$@"
  fi
}

function save_tf_devenv_profile() {
  local file=${1:-$TF_DEVENV_PROFILE}
  echo
  echo '[update tf devenv configuration]'
  mkdir -p "$(dirname $file)"
  cat <<EOF > $file
# dev env options
CONTRAIL_CONTAINER_TAG=\${CONTRAIL_CONTAINER_TAG:-${CONTRAIL_CONTAINER_TAG}}
CONTAINER_REGISTRY=\${CONTAINER_REGISTRY:-${CONTAINER_REGISTRY}}
RPM_REPO_IP='localhost'
RPM_REPO_PORT=\${RPM_REPO_PORT:-${RPM_REPO_PORT}}

# others
VENDOR_NAME="\${VENDOR_NAME:-${VENDOR_NAME}}"
VENDOR_DOMAIN="\${VENDOR_DOMAIN:-${VENDOR_DOMAIN}}"
EOF
  echo "tf setup profile $file"
  cat ${file}
}

function load_tf_devenv_profile() {
  if [ -e "$TF_DEVENV_PROFILE" ] ; then
    echo
    echo '[load tf devenv configuration]'
    source "$TF_DEVENV_PROFILE"
  else
    echo
    echo '[there is no tf devenv configuration to load]'
  fi
}

function install_prerequisites_centos() {
  local pkgs=""
  which lsof || pkgs+=" lsof"
  which python || pkgs+=" python"
  if [ -n "$pkgs" ] ; then
    mysudo yum install -y $pkgs
  fi

  # determine if we're building locally
  if [[ "$CONTRAIL_BUILD_LOCAL" == 1 ]]; then
    if [[ "$USER" != "root" ]]; then
      die "run_local.sh MUST be run as root."
    fi
    echo
    echo "INFO: Local build setup (outside of docker)"
    # Make installation lighter-weight by default for a developer
    export CONTRAIL_SETUP_DOCKER=${CONTRAIL_SETUP_DOCKER:-0}
    export CONTRAIL_DEPLOY_REGISTRY=${CONTRAIL_DEPLOY_REGISTRY:-0}
    export CONTRAIL_DEPLOY_RPM_REPO=${CONTRAIL_DEPLOY_RPM_REPO:-0}
    # Setting up some mounts for the build
    export CONTRAIL_DEV_ENV=/root/tf-dev-env
    if [[ "$scriptdir" != "${CONTRAIL_DEV_ENV}" ]] && ! (mount | grep -qF " on ${CONTRAIL_DEV_ENV} "); then
      mkdir -p "${CONTRAIL_DEV_ENV}" || die "Could not create directory"
      append_if_missing "${scriptdir} ${CONTRAIL_DEV_ENV} none bind,rw 0 0" /etc/fstab || die "Could not edit /etc/fstab"
      mount ${CONTRAIL_DEV_ENV} || die "Could not mount ${CONTRAIL_DEV_ENV}"
    fi
    ln -nsf "$scriptdir"/contrail /root/contrail
    # also makes vscode available
    cp "$scriptdir"/*.repo /etc/yum.repos.d/

    # be nice to developers
    yum -y install bash-completion-extras
    # enable and start docker in case is was just installed
    systemctl enable docker
    # disable selinux right now
    setenforce 0 || true
    # keep selinux disabled after reboot
    sed -i 's:^SELINUX=.*:SELINUX=disabled:' /etc/selinux/config
    # disable firewalld to avoid test execution problems
    systemctl disable firewalld
  fi  
}

function install_prerequisites_rhel() {
  install_prerequisites_centos
}

function install_prerequisites_ubuntu() {
  local pkgs=""
  which lsof || pkgs+=" lsof"
  which python || pkgs+=" python-minimal"
  if [ -n "$pkgs" ] ; then
    export DEBIAN_FRONTEND=noninteractive
    mysudo -E apt-get install -y $pkgs
  fi
}

function install_prerequisites_macosx() {
  local pkgs=""
  which lsof || pkgs+=" lsof"
  which python || pkgs+=" python"
  if [ -n "$pkgs" ] ; then
    brew install $pkgs
  fi
}

function die() {
  echo
  echo "ERROR: $*"
  exit 1
}

function append_if_missing() {
  line="$1"
  file="$2"
  grep -qF "$line" "$file" || echo "$line" >>"$file"
}
