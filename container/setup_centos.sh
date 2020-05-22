#!/bin/bash -e

: ${CONTRAIL:=$HOME/contrail}

append_if_missing() {
  line="$1"
  file="$2"
  grep -qF "$line" "$file" || echo "$line" >>"$file"
}

# NOTE: we have to remove /usr/local/bin/virtualenv after installing tox by python3 because it has python3 as shebang and masked
# /usr/bin/virtualenv with python2 shebang. it can be removed later when all code will be ready for python3
if ! yum info jq ; then yum -y install epel-release ; fi && \
yum -y update && \
yum -y install python3 iproute \
               autoconf automake createrepo docker-client docker-python gcc gdb git git-review jq libtool \
               make python-devel python-pip python-lxml rpm-build vim wget yum-utils redhat-lsb-core \
               rpmdevtools sudo gcc-c++ net-tools httpd \
               python-virtualenv python-future python-tox \
               google-chrome-stable && \
yum clean all && \
rm -rf /var/cache/yum && \
pip3 install --retries=10 --timeout 200 --upgrade tox setuptools lxml jinja2 && \
rm -f /usr/local/bin/virtualenv && \
if [[ "$USER" != 'root' ]] ; then \
    groupadd --gid $DEVENV_GID $DEVENV_GROUP && \
    useradd -md $HOME --uid $DEVENV_UID --gid $DEVENV_GID $USER && \
    echo '%wheel        ALL=(ALL)       NOPASSWD: ALL' >> /etc/sudoers && \
    usermod -aG wheel $USER && \
    chown -R $DEVENV_UID:$DEVENV_GID $HOME || exit 1; \
fi

append_if_missing "export CONTRAIL=$CONTRAIL"                  $HOME/.bashrc
append_if_missing "export LD_LIBRARY_PATH=$CONTRAIL/build/lib" $HOME/.bashrc

