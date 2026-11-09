#!/usr/bin/env bash
set +x
set -euo pipefail
source ci/common.sh
# Maven verify includes the sample's tests. No skip-tests flags.
(cd complete; bash ./mvnw -B -ntp clean verify)
mapfile -t jars < <(find complete/target -maxdepth 1 -type f -name '*.jar' ! -name '*-sources.jar' ! -name '*-javadoc.jar')
[[ ${#jars[@]} == 1 ]] || { echo 'Expected exactly one executable JAR'; exit 1; }
mkdir -p bundle
cp "${jars[0]}" bundle/app.jar
# Reports are printed for dependency findings; a failed gate stops publication.
"$TRIVY_BIN" fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --timeout 15m bundle
# Source secret scan is separate from dependency scanning. No Java SAST is claimed.
"$TRIVY_BIN" fs --scanners secret --exit-code 1 --skip-dirs complete/target --skip-dirs .git .
"$TRIVY_BIN" fs --scanners vuln --format json --output bundle/dependencies.json --timeout 15m bundle/app.jar
cp Dockerfile bundle/Dockerfile
python3 - <<'META'
import hashlib,json,os,zipfile
from pathlib import Path
b=Path('bundle')
meta={'release_id':os.environ['RELEASE_ID'],'commit':os.environ['EXPECTED_COMMIT'],
      'jar_sha256':hashlib.sha256((b/'app.jar').read_bytes()).hexdigest()}
(b/'release.json').write_text(json.dumps(meta,indent=2)+'\n')
with zipfile.ZipFile('release.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(b.iterdir()): z.write(p,p.name)
p=Path('release.zip')
Path('release.zip.sha256').write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'  release.zip\n')
META
python3 ci/artifactory.py upload release.zip
python3 ci/artifactory.py upload release.zip.sha256
