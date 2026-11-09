"""Transfer a versioned generic artifact without printing the access token."""
import hashlib, os, re, sys, urllib.request
from pathlib import Path

def main():
    action,name=sys.argv[1:]
    if action not in ('upload','download') or name not in ('release.zip','release.zip.sha256'):
        raise ValueError('Unsupported transfer')
    base=os.environ['JFROG_URL'].rstrip('/')  # e.g. https://company.jfrog.io
    repo=os.environ['JFROG_REPO']
    release=os.environ['RELEASE_ID']
    if not base.startswith('https://') or not re.fullmatch(r'[A-Za-z0-9_.-]+',repo):
        raise ValueError('Use an HTTPS JFrog platform URL and a repository key')
    url=f'{base}/artifactory/{repo}/spring-demo/{release}/{name}'
    headers={'Authorization':'Bearer '+os.environ['JFROG_TOKEN']}
    data=None
    if action=='upload':
        data=Path(name).read_bytes()
        headers['X-Checksum-Sha256']=hashlib.sha256(data).hexdigest()
        headers['Content-Type']='application/octet-stream'
    req=urllib.request.Request(url,data=data,headers=headers,method='PUT' if data is not None else 'GET')
    with urllib.request.urlopen(req,timeout=300) as response:
        if action=='download': Path(name).write_bytes(response.read())
    print(f'{action}: spring-demo/{release}/{name}')

if __name__=='__main__': main()
