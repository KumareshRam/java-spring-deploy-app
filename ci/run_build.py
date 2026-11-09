"""Jenkins invokes this with an IAM role; no additional Jenkins AWS plugin needed."""
import json,os,re,signal,subprocess,sys,time
project,commit,release=sys.argv[1:]
if not re.fullmatch(r'[0-9a-f]{40}',commit) or not re.fullmatch(r'[0-9a-f]{12}-[0-9]+',release):
    raise ValueError('Invalid commit or release ID')
def aws(*args):
    return json.loads(subprocess.check_output(['aws',*args,'--output','json'],text=True))
build_id=None
try:
    def terminate(*_): raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM,terminate)
    overrides=[{'name':k,'value':v,'type':'PLAINTEXT'} for k,v in
               [('RELEASE_ID',release),('EXPECTED_COMMIT',commit)]]
    build=aws('codebuild','start-build','--project-name',project,'--source-version',commit,
              '--environment-variables-override',json.dumps(overrides))['build']
    build_id=build['id']; print('Started '+build_id,flush=True)
    deadline=time.monotonic()+2400
    while time.monotonic()<deadline:
        result=aws('codebuild','batch-get-builds','--ids',build_id)['builds'][0]
        status=result['buildStatus']
        print('CodeBuild: '+status,flush=True)
        if result.get('logs',{}).get('deepLink'): print(result['logs']['deepLink'],flush=True)
        if status!='IN_PROGRESS':
            if status!='SUCCEEDED':
                for phase in result.get('phases',[]):
                    for context in phase.get('contexts',[]): print(context.get('message',''))
                raise RuntimeError('Build failed: '+status)
            build_id=None
            break
        time.sleep(20)
    else: raise TimeoutError('CodeBuild exceeded 40 minutes')
finally:
    if build_id:
        subprocess.run(['aws','codebuild','stop-build','--id',build_id],check=False,stdout=subprocess.DEVNULL)
