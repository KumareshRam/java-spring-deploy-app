#!/usr/bin/env bash
set +x
set -euo pipefail
source ci/common.sh
: "${ECR_REPOSITORY:?Set ECR_REPOSITORY in the image CodeBuild project}"
: "${AWS_DEFAULT_REGION:?CodeBuild AWS_DEFAULT_REGION is required}"
python3 ci/artifactory.py download release.zip
python3 ci/artifactory.py download release.zip.sha256
sha256sum -c release.zip.sha256
python3 - <<'UNZIP'
import hashlib,json,os,zipfile
from pathlib import Path
b=Path('image-context'); b.mkdir()
expected={'app.jar','Dockerfile','release.json','dependencies.json'}
with zipfile.ZipFile('release.zip') as z:
    if set(z.namelist())!=expected or len(z.namelist())!=len(expected):
        raise ValueError('Unexpected ZIP contents')
    for name in sorted(expected): (b/name).write_bytes(z.read(name))
meta=json.loads((b/'release.json').read_text())
if meta['commit']!=os.environ['EXPECTED_COMMIT'] or meta['release_id']!=os.environ['RELEASE_ID']:
    raise ValueError('Wrong release in Artifactory')
if meta['jar_sha256']!=hashlib.sha256((b/'app.jar').read_bytes()).hexdigest():
    raise ValueError('JAR checksum mismatch')
UNZIP
account=$(aws sts get-caller-identity --query Account --output text)
registry="$account.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
image="$registry/$ECR_REPOSITORY:$RELEASE_ID"
# No Maven command here: the image contains the exact downloaded JAR.
docker build --pull --platform linux/amd64 -t "$image" image-context
"$TRIVY_BIN" image --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --timeout 15m "$image"
aws ecr get-login-password --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin "$registry"
docker push "$image"
echo "Published $image"
