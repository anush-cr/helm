#!/bin/bash -e

REPO_ROOT=$(git rev-parse --show-toplevel)
source ${REPO_ROOT}/wavefront/release/k8s-utils.sh
source ${REPO_ROOT}/wavefront/release/VERSION

function main() {

  # REQUIRED
  local WAVEFRONT_TOKEN=

  local WF_CLUSTER=nimba
  local VERSION=${CHART_VERSION}
  local CONFIG_CLUSTER_NAME=$(whoami)-${VERSION}-release-test

  while getopts ":c:t:n:p:" opt; do
    case $opt in
    c)
      WF_CLUSTER="$OPTARG"
      ;;
    t)
      WAVEFRONT_TOKEN="$OPTARG"
      ;;
    n)
      CONFIG_CLUSTER_NAME="$OPTARG"
      ;;
    p)
      PREVIOUSLY_RELEASED_CHART_VERSION="$OPTARG"
      ;;
    \?)
      print_usage_and_exit "Invalid option: -$OPTARG"
      ;;
    esac
  done

  if [[ -z ${WAVEFRONT_TOKEN} ]]; then
    print_msg_and_exit "wavefront token required"
  fi

  if [[ -z ${PREVIOUSLY_RELEASED_CHART_VERSION} ]]; then
    print_msg_and_exit "previously released chart version required"
  fi

  helm uninstall wavefront --namespace wavefront &>/dev/null || true

  kubectl create namespace wavefront &>/dev/null || true

  ${REPO_ROOT}/wavefront/release/run-local-helm-repo.sh > /dev/null

  echo "Testing fresh install of v${VERSION}"
  local FRESH_INSTALL_CLUSTER_NAME="${CONFIG_CLUSTER_NAME}-$(date +%Y%m%d%H%M%S)"
  helm install wavefront ${REPO_ROOT}/wavefront --namespace wavefront \
  --set clusterName=${FRESH_INSTALL_CLUSTER_NAME} \
  --set wavefront.url=https://${WF_CLUSTER}.wavefront.com \
  --set wavefront.token=${WAVEFRONT_TOKEN} \
  --set collector.cadvisor.enabled=true > /dev/null

  ${REPO_ROOT}/wavefront/release/test-e2e.sh -t ${WAVEFRONT_TOKEN} -n ${FRESH_INSTALL_CLUSTER_NAME}

  echo "Testing upgrading from v${PREVIOUSLY_RELEASED_CHART_VERSION} to v${VERSION}"
  helm uninstall wavefront --namespace wavefront > /dev/null

  local UPGRADE_CLUSTER_NAME=$(whoami)-${PREVIOUSLY_RELEASED_CHART_VERSION}-release-test-upgrade-$(date +%Y%m%d%H%M%S)

  helm install wavefront wavefront/wavefront --namespace wavefront \
  --version ${PREVIOUSLY_RELEASED_CHART_VERSION} \
  --set clusterName=${UPGRADE_CLUSTER_NAME} \
  --set wavefront.url=https://${WF_CLUSTER}.wavefront.com \
  --set wavefront.token=${WAVEFRONT_TOKEN} \
  --set collector.cadvisor.enabled=true > /dev/null

  helm upgrade wavefront ${REPO_ROOT}/wavefront --namespace wavefront \
  --set clusterName=${UPGRADE_CLUSTER_NAME} \
  --set wavefront.url=https://${WF_CLUSTER}.wavefront.com \
  --set wavefront.token=${WAVEFRONT_TOKEN} \
  --set collector.cadvisor.enabled=true > /dev/null

  ${REPO_ROOT}/wavefront/release/test-e2e.sh -t ${WAVEFRONT_TOKEN} -n ${UPGRADE_CLUSTER_NAME}

  echo "Testing downgrading from v${VERSION} to v${PREVIOUSLY_RELEASED_CHART_VERSION}"
  local DOWNGRADE_CLUSTER_NAME=$(whoami)-${PREVIOUSLY_RELEASED_CHART_VERSION}-release-test-downgrade-$(date +%Y%m%d%H%M%S)

  helm upgrade wavefront wavefront/wavefront --namespace wavefront \
    --version ${PREVIOUSLY_RELEASED_CHART_VERSION} \
    --set clusterName=${DOWNGRADE_CLUSTER_NAME} \
    --set wavefront.url=https://${WF_CLUSTER}.wavefront.com \
    --set wavefront.token=${WAVEFRONT_TOKEN} \
    --set collector.cadvisor.enabled=true > /dev/null

  local DOWNGRADE_COLLECTOR_VERSION=$(helm show chart wavefront/wavefront --version ${PREVIOUSLY_RELEASED_CHART_VERSION} | grep appVersion | cut -d' ' -f2)
  ${REPO_ROOT}/wavefront/release/test-e2e.sh -t ${WAVEFRONT_TOKEN} -n ${UPGRADE_CLUSTER_NAME} -v ${DOWNGRADE_COLLECTOR_VERSION}

  green "Success!"
}

main "$@"
