#!/usr/bin/env bash
set +x
set -euo pipefail
: "${RELEASE_ID:?Jenkins must supply RELEASE_ID}"
: "${EXPECTED_COMMIT:?Jenkins must supply EXPECTED_COMMIT}"
[[ "$RELEASE_ID" =~ ^[0-9a-f]{12}-[0-9]+$ ]] || { echo 'Invalid RELEASE_ID'; exit 1; }
[[ "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid commit'; exit 1; }
[[ "${CODEBUILD_RESOLVED_SOURCE_VERSION:-}" == "$EXPECTED_COMMIT" ]] || {
  echo 'CodeBuild checked out a different commit from Jenkins'; exit 1;
}
export TRIVY_VERSION="${TRIVY_VERSION:-0.76.2}"
tool_dir="${PIPELINE_TOOLS_DIR:-/tmp/pipeline-trivy}"
export TRIVY_BIN="$tool_dir/trivy"
mkdir -p "$tool_dir" reports
if [[ ! -x "$TRIVY_BIN" ]]; then
  asset="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
  base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
  curl --fail --silent --show-error --location "$base/$asset" -o "$tool_dir/$asset"
  curl --fail --silent --show-error --location "$base/trivy_${TRIVY_VERSION}_checksums.txt" -o "$tool_dir/checksums.txt"
  (cd "$tool_dir"; awk -v f="$asset" '$2 == f { print }' checksums.txt > selected.sha256;
   test -s selected.sha256; sha256sum -c selected.sha256; tar -xzf "$asset" trivy)
fi
"$TRIVY_BIN" --version
