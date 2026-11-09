# Spring Boot: GitHub → Jenkins → CodeBuild → Artifactory → ECR → EKS

A learning starter for your requested workflow, prepared November 6, 2026. It uses Spring's official sample https://github.com/spring-guides/gs-spring-boot, specifically `complete/` (Maven, Java 17, HTTP port 8080). The source inspected for this guide used Spring Boot 4.0.9. The sample's main branch can change; your fork and the Jenkins commit SHA determine exactly what is built.

This ZIP is an **overlay**, not a copy of the upstream application. Copy its files to the ROOT of your fork. Keep the upstream `complete/`, Maven wrapper, application source, tests and licenses. No upstream code or license is replaced. The starter does not create an EKS cluster or deploy anything merely by being downloaded.

## What runs where

1. GitHub webhook starts the Jenkins pipeline for your trusted branch.
2. Jenkins checks out one commit and supplies that exact SHA to both CodeBuild jobs.
3. `spring-backend-build` runs Maven verify, tests, dependency vulnerability and source secret scans.
4. After the gates pass it creates a ZIP containing app.jar, Dockerfile, release metadata and a dependency report. It uploads the ZIP and checksum to JFrog.
5. `spring-image-build` downloads that same versioned ZIP from JFrog, validates checksums and commit identity, and builds the container using the downloaded JAR. It does not recompile Java.
6. An additional container vulnerability gate runs before pushing to private ECR.
7. Jenkins retrieves the ECR digest, applies Kubernetes resources, waits for rollout, and checks the application through a public NLB.
8. The end user opens the printed URL and sees `Greetings from Spring Boot!`.

Jenkins orchestrates; CodeBuild performs the builds. No CodePipeline is required. JFrog holds the ZIP; ECR holds the container. Artifactory is a **Generic local repository** here because the requested output is a ZIP, not a Maven-coordinate deployment. Maven dependencies still come from the sample's configured repositories; routing dependencies through a Maven Artifactory virtual repository is a separate optional enhancement.

## 1. Fork the sample and add this overlay

In GitHub open https://github.com/spring-guides/gs-spring-boot and click Fork. Then on your workstation (replace YOUR_USER):

```bash
git clone https://github.com/YOUR_USER/gs-spring-boot.git
cd gs-spring-boot
# Extract this starter ZIP somewhere outside the clone, then copy all files
# INSIDE pipeline-starter/ into this directory. Merge .gitignore with yours.
git add Jenkinsfile Dockerfile buildspec-backend.yml buildspec-image.yml ci k8s infra docs tests README.md .gitignore
git commit -m "Add Jenkins CodeBuild Artifactory ECR EKS lab"
git push origin main
```

The provided README replaces the root README.md only if one exists; the upstream README.adoc is preserved. Forks intended for this lab must be public for the supplied CloudFormation source configuration. Private repositories require configuring a supported CodeBuild source credential/connection and updating the template's Source Auth configuration. Jenkins needs its own GitHub checkout credential for private source.

Optional local smoke test before AWS, with Java 17 or later:

```bash
cd complete
./mvnw -B clean verify
java -jar target/spring-boot-complete-0.0.1-SNAPSHOT.jar
# Separate terminal:
curl --fail http://localhost:8080/
```

If upstream changes the Maven artifact name/version, use its generated executable JAR. CI discovers the single JAR automatically.

## 2. Create JFrog repository and a secret

In Artifactory create a **Local**, **Generic** repository named `spring-release-local`. Use the JFrog platform base URL such as `https://yourtenant.jfrog.io` (no `/ui` or `/artifactory`). Give a dedicated CI token read and deploy permission limited to this repository. For a shared/team system use separate publishing and read-only identities for the two CodeBuild projects; the lab uses one secret for simplicity.

In AWS Secrets Manager in Mumbai (`ap-south-1`), create an **Other type of secret**, using the default Secrets Manager encryption key, with:

```json
{"access_token": "YOUR_JFROG_ACCESS_TOKEN"}
```

Name it `pipeline/jfrog`. Record the complete secret ARN. Enter the token in Secrets Manager; do not put it in GitHub, this README, a Jenkins parameter, or a shell command. The CloudFormation template retrieves `access_token` into a secret environment variable. Customer-managed encryption keys additionally require the build role to have `kms:Decrypt` and permission in the key policy.

After one successful backend build, expect:

```text
spring-release-local/spring-demo/<commit-prefix>-<jenkins-build-number>/release.zip
spring-release-local/spring-demo/<commit-prefix>-<jenkins-build-number>/release.zip.sha256
```

ZIP format:

```text
app.jar
Dockerfile
release.json
dependencies.json
```

Hashes detect transfer/content mismatches; they are not a replacement for artifact signing or trust controls on the repository.

## 3. Create the CodeBuild projects and ECR repository

Use AWS CloudFormation → Create stack → Upload template → select `infra/cloudformation.json`. Supply:

| Parameter | Value |
|---|---|
| GitHubRepoUrl | HTTPS clone URL of your fork |
| JFrogUrl | `https://yourtenant.jfrog.io` |
| JFrogRepo | `spring-release-local` |
| JFrogSecretArn | Full ARN from step 2 |
| BackendProjectName | `spring-backend-build` |
| ImageProjectName | `spring-image-build` |
| EcrRepositoryName | `spring-demo` |

Use unused CodeBuild project and ECR names; this template creates new resources and does not import an existing repository. Acknowledge creation of IAM resources, review, and create the stack. This provisions paid build resources when used and ECR storage. It creates two scoped CodeBuild roles, not administrator roles. The projects have no GitHub webhooks because Jenkins starts them.

Both projects use a managed Linux x86_64 CodeBuild image (`aws/codebuild/standard:7.0` default), Python 3 and network access to GitHub, Maven repositories, JFrog, Docker Hub, and Trivy databases. The backend selects Corretto 17 through its buildspec. The image project has **privileged mode enabled** for Docker. Backend privileged mode is disabled. Maven runs through the sample's checked-in wrapper.

The lab leaves CodeBuild outside a customer VPC so its normal outbound internet access works. If JFrog is private or you attach CodeBuild to a VPC, arrange appropriate routes/NAT/private endpoints/DNS before running. Neither build project needs EKS permissions.

Trivy is pinned to 0.76.2 and its downloaded release archive is checked against the release checksum list. Update the pin deliberately. A HIGH/CRITICAL dependency or image finding stops the pipeline, including unfixed findings. Fix/upgrade the dependency or image rather than disabling the gate. Secret findings also stop it. Trivy here supplies dependency/secret/image scanning, **not full Java SAST, DAST, Xray, or a compliance certification**. For production add those tools according to your actual requirements.

If scans fail, see their CodeBuild log output. Test reports appear in the CodeBuild Reports view. CodeBuild uses NO_ARTIFACTS because successful release output is in JFrog; failed-run JSON files inside an ephemeral build are not retained independently. For long-term evidence, add a restricted report bucket and an upload-in-finally mechanism.

## 4. Prepare Kubernetes (EKS Auto Mode default)

This starter assumes an EXISTING **EKS Auto Mode** cluster in the same AWS account and region as ECR, with usable amd64 compute, an accessible Kubernetes API endpoint, and correctly tagged public/private subnets. The public NLB Service specifically uses `eks.amazonaws.com/nlb`. Ensure node IAM roles can pull images from the private ECR repository and nodes have the necessary ECR/S3 network access.

EKS clusters, nodes, NLBs and networking can incur ongoing charges. This starter does not silently create a cluster. If you need a cluster, use the EKS console's Auto Mode create flow and review its IAM, network and pricing settings first. Record its name.

If you already have a standard EKS cluster with the AWS Load Balancer Controller, change `loadBalancerClass` to `service.k8s.aws/nlb` and use annotations supported by your controller. If using local Kubernetes, use a ClusterIP/NodePort or port-forward and change external verification accordingly. Do not apply the Auto Mode manifest unchanged to those cluster types.

As cluster administrator, create the namespace once:

```bash
aws eks update-kubeconfig --name YOUR_CLUSTER --region ap-south-1
kubectl apply -f k8s/namespace.yaml
```

For the Jenkins EC2 IAM role (use the IAM role ARN, not an STS assumed-role session ARN), create an EKS access entry. Associate `AmazonEKSEditPolicy` scoped to namespace **spring-demo** using EKS → cluster → Access. The cluster must support access entries (API or API_AND_CONFIG_MAP authentication mode). Do not grant cluster-wide admin to the pipeline. Namespace creation stays with the administrator.

The template uses one replica and the sample's stateless greeting endpoint. It has a non-root container, resource limits and health probes. It is a lab HTTP endpoint; production exposure needs an appropriate domain/TLS/access-control design.

## 5. Prepare the Jenkins agent

Use your existing Jenkins installation. On an EC2 agent:

- Install Git, Python 3, AWS CLI v2, curl, and kubectl compatible with the cluster version. Java for Jenkins itself remains an independent prerequisite.
- Give the agent the Jenkins label `aws-deploy`.
- Attach an EC2 instance profile containing a dedicated IAM role. Edit `infra/jenkins-iam-policy.json` to replace ACCOUNT_ID and CLUSTER_NAME, and adjust region/resource names if changed, then attach it as that role's policy.
- Complete the namespace-scoped EKS access entry above for that SAME role.
- Jenkins needs no JFrog token and no Docker daemon. It uses its instance role to start/poll/stop CodeBuild, describe the ECR digest, and authenticate to EKS.
- Verify the agent can reach the EKS API endpoint. For private endpoints it needs VPC connectivity. Test `aws sts get-caller-identity` on the agent without configured personal AWS access keys overriding the instance role.

A remote Jenkins agent's role, not necessarily the controller's role, is the identity used by the scripts. The pipeline needs standard Pipeline/Git functionality; no AWS CodeBuild-specific Jenkins plugin is required because the starter uses AWS CLI directly.

## 6. Create and run the Jenkins pipeline

1. Create a **Pipeline** job in Jenkins.
2. Choose **Pipeline script from SCM**, Git, your fork URL, branch `*/main`, script path `Jenkinsfile`.
3. Run once to load parameters if necessary. In Build with Parameters set EKS_CLUSTER and confirm AWS_REGION, BACKEND_PROJECT, IMAGE_PROJECT and ECR_REPOSITORY match the stack.
4. Run the pipeline manually first and inspect the two CodeBuild log links printed in the Jenkins console.
5. After a successful manual run, enable your existing GitHub→Jenkins webhook trigger for this job. Use `https://YOUR_JENKINS/github-webhook/` with the GitHub plugin's push trigger configured. Run this privileged release job only for trusted main-branch commits; do not feed untrusted pull-request code to these IAM roles/secrets.

The starter disables simultaneous runs of the same job. Each release uses `<first-12-commit-characters>-<Jenkins-build-number>`. Two different Jenkins jobs sharing this naming space need an additional unique job identifier. Do not reset/reuse Jenkins build numbers for an existing release: ECR tags are immutable. For a retry start a new Jenkins build.

Jenkins waits for backend success before starting the image job, and waits for image success before deployment. On CodeBuild failure it fails the pipeline; when the polling helper receives termination it attempts StopBuild. Each remote job and local wait have bounded timeouts. Inspect remote build status after forcibly terminating a Jenkins node, since a disconnected node cannot guarantee cancellation.

Success means all of these happened:

- Maven tests passed, security gates passed, and the versioned ZIP exists in JFrog.
- Docker used that ZIP's JAR, the image gate passed, and an immutable tag exists in ECR.
- EKS rolled out a digest-pinned image and readiness probes passed.
- Jenkins printed `Application URL: http://...` and verified `Greetings from Spring Boot!` over HTTP.

Manual validation:

```bash
kubectl get pods,svc -n spring-demo
kubectl logs deployment/spring-demo -n spring-demo
kubectl rollout status deployment/spring-demo -n spring-demo
```

Failed readiness or HTTP verification fails Jenkins. Kubernetes keeps rollout history; this lab does not automatically undo a failed deployment. An authorized operator can investigate and use `kubectl rollout undo deployment/spring-demo -n spring-demo` where appropriate.

## Troubleshooting

| Symptom | Check |
|---|---|
| Source download fails | Public fork URL, commit pushed, GitHub connection if private |
| CodeBuild source commit mismatch | Both projects point to the SAME fork and Jenkins passes a reachable exact commit |
| Maven fails | complete/pom.xml Java requirements, wrapper permissions/network, tests; don't skip tests |
| Scan fails | Findings in CodeBuild logs; update dependencies/base image |
| JFrog 401/403 | Token expiry/scope, repository read/deploy permissions, secret access_token field |
| JFrog 404 | Base URL has no /ui or /artifactory, repo exists, backend succeeded for same release |
| Cannot get Secrets Manager value | Exact secret ARN permissions, customer-managed KMS policy if used |
| Docker daemon error | Image project privileged mode, supported managed CodeBuild image |
| ECR AccessDenied | Image project's role, correct repo/account/region |
| Kubernetes Unauthorized/Forbidden | Jenkins agent IAM role, EKS access entry, namespace scope |
| ImagePullBackOff | Node ECR pull permissions and networking; digest and amd64 node availability |
| Service EXTERNAL-IP stays pending | Auto Mode, public subnet tags, load-balancing IAM, Service events |
| Application URL not ready | NLB target health, security/network routes, pod probes, HTTP root response |

## Cleanup

Delete the Service first and wait for the load balancer to be removed before deleting the cluster/network. Delete the app Deployment/namespace when appropriate. Empty/delete the ECR repository before deleting this CloudFormation stack (CloudFormation does not force-delete images). Remove the lab's JFrog releases and token, secret, build report groups/log groups and Jenkins access entry/policy when no longer needed. Stop/delete any lab cluster and compute you created. Shared resources must be preserved.

## Verification boundary

The supplied files are starter configuration, not a deployed system. Local validation checks Python/Bash/YAML/JSON syntax and exercises build orchestration and artifact-transfer behavior with mocks. AWS credentials, your JFrog endpoint, Maven dependency downloads, vulnerability databases, Docker, EKS networking and a public endpoint cannot be validated here; run the manual pipeline in your environment before enabling the webhook.

References: see docs/SOURCES.md.

To rerun local mock verification (Python 3 and PyYAML required): `python3 tests/verify_starter.py`. Mock tests do not run Maven, scan real dependencies, build containers, or contact cloud services.
