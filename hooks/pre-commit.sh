#!/usr/bin/env bash
#
# A hook script to verify what is about to be committed.
# Called by "git commit" with no arguments.  The hook should
# exit with non-zero status after issuing an appropriate message if
# it wants to stop the commit.
#
# To enable this hook, rename this file to "pre-commit".

DEPLOYMENT_CONFIG="${DEPLOYMENT_CONFIG:-config/k8s/deployment.yaml}"
REGO_POLICY="${REGO_POLICY:-config/opa/trustedregistries.rego}"

print-error-and-exit() {
  echo "$0: ERROR: ${1} not found."
  exit 1
}

if [[ ! -f ${DEPLOYMENT_CONFIG} ]]; then
  print-error-and-exit "DEPLOYMENT_CONFIG=${DEPLOYMENT_CONFIG}"
elif [[ ! -f ${REGO_POLICY} ]]; then
  print-error-and-exit "REGO_POLICY=${REGO_POLICY}"
fi

# Ignore stuff that isn't being committed
committing=$(git diff --cached --name-status | awk -v pat="${DEPLOYMENT_CONFIG}" '$0 ~ pat {print $1}')

if [[ ! ${committing} ]]; then
  exit 0
fi

# Test prospective commit
docker run --rm -v $(pwd):/project:Z instrumenta/conftest:v0.17.0 test "${DEPLOYMENT_CONFIG}" -p "${REGO_POLICY}"
