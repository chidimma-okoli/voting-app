# Voting App DevOps Capstone

**Containerization | CI/CD | Container Security | Kubernetes | Helm | Terraform**

A hands-on DevOps project demonstrating how to build, scan, publish, deploy, troubleshoot, and recover a multi-service voting application. The project uses Docker, GitHub Actions, Trivy, GitHub Container Registry (GHCR), Kubernetes with Kind, Helm, and Terraform.

## Project Overview

The objective of this capstone was to take a multi-service application through a practical DevOps workflow, from container image builds and security scanning to Kubernetes deployment and release recovery.

I chose to run the Kubernetes workload locally using Kind rather than incur additional AWS infrastructure costs. The repository also contains Terraform configuration for AWS infrastructure and an S3 remote-state backend.

### What I implemented

- Built container images for Vote, Result, and Worker.
- Reviewed and improved Dockerfiles with a focus on image security.
- Scanned images with Trivy.
- Created a GitHub Actions workflow to build, scan, and publish images.
- Tagged images using Git commit SHA values.
- Published scanned images to GHCR.
- Deployed the application to a local Kind cluster with Helm.
- Verified Kubernetes pod readiness and application HTTP responses.
- Investigated a failed Helm rollback and restored a working release.
- Documented troubleshooting steps and operational lessons.

## Architecture

[[https://drive.google.com/file/d/1kUGcmHyL66RKzctsvpCKm2tv9pExHBMP/view?usp=sharing](https://drive.google.com/file/d/1kUGcmHyL66RKzctsvpCKm2tv9pExHBMP/view?usp=sharing)]

The application data flow is:

**Vote → Redis → Worker → PostgreSQL → Result**

The CI/CD workflow is separate from the application runtime:

**GitHub → GitHub Actions → Docker image builds → Trivy → GHCR → Kubernetes deployment**

See [`docs/architecture.mmd`](docs/architecture.mmd) for the editable Mermaid architecture diagram.

## Technology Stack

| Technology                | Purpose                                              |
| ------------------------- | ---------------------------------------------------- |
| Git and GitHub            | Version control and source repository                |
| Docker and Docker Compose | Containerization and local application testing       |
| GitHub Actions            | Automated build, scan, and publishing pipeline       |
| Trivy                     | Container vulnerability scanning                     |
| GHCR                      | Container image registry                             |
| Kubernetes and Kind       | Local orchestration                                  |
| Helm                      | Kubernetes deployment, release history, and rollback |
| Terraform                 | Infrastructure as code                               |
| Redis                     | Vote queue                                           |
| PostgreSQL                | Persistent vote data during the running environment  |

## Repository Structure

```text
voting-app/
├── .github/
│   └── workflows/                  # CI workflow
├── docs/
│   └── architecture.mmd            # Architecture diagram source
├── helm/
│   └── voting-app/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-capstone.yaml
│       └── templates/
├── k8s-specifications/
│   └── db-deployment.yaml
├── vote/
│   └── Dockerfile
├── result/
│   └── Dockerfile
├── worker/
│   └── Dockerfile
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── backend.tf
│   └── .terraform.lock.hcl
├── docker-compose.yml
├── docker-compose.security-test.yml
├── docker-stack.yml
└── README.md
```

This is the intended documentation structure. Verify the actual committed filenames and chart files before publishing.

---

## 1. Containerization and Local Testing

I used Docker Compose to build and run the multi-service voting application locally.

### Commands used

```bash
docker compose up --build -d
docker compose ps
docker compose logs --tail=100
```

The application consists of Vote, Result, Worker, Redis, and PostgreSQL.

### Issue encountered: Docker Hub TLS error

During an image pull, Docker returned:

```text
failed to authorize: failed to fetch oauth token
remote error: tls: bad record MAC
```

I tested connectivity to the Docker Hub authentication endpoint:

```bash
curl -Iv https://auth.docker.io/token
```

The request completed its TLS handshake and returned HTTP 405 to the HEAD request. This indicated that the endpoint was reachable from that request, although it did not prove Docker's separate image-pull connection was healthy.

I retried the image pull:

```bash
docker pull python:3.11-slim-bookworm
```

The image pull succeeded.

**Lesson learned:** A TLS error during an image pull may be a connection issue rather than a Dockerfile defect. Test connectivity and retry before making unnecessary changes to application code.

## 2. Container Security with Trivy

I used Trivy to scan the Vote image for HIGH and CRITICAL vulnerabilities.

### Command used

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --ignore-unfixed \
  voting-app-vote:nonroot-test
```

The policy fails the scan when matching HIGH or CRITICAL findings with available fixes are reported.

### Issues encountered

Earlier scans reported operating-system and Python package vulnerabilities. Some operating-system findings had no fixed version available in the scan results. Python packaging dependencies also required attention.

I updated the Vote Dockerfile to upgrade packaging tools in the build stage, removed selected packaging-tool files from the final image, and pinned the Python base image by digest.

I then rebuilt and rescanned the image. The latest local scan was reported as clean under the configured HIGH/CRITICAL policy with `--ignore-unfixed`.

### Security limitations

A clean result under this policy does not mean the image has zero vulnerabilities. The policy excludes unfixed findings and does not report lower-severity findings.

I also learned to distinguish the image I intended to scan from the image actually tagged locally. Rebuilding an image does not automatically prove that a subsequent scan used the newly built image; the image tag and digest should be verified.

### Evidence

Useful evidence includes:

- The Trivy command and scan output.
- The exact image tag or digest scanned.
- The Dockerfile changes.
- The successful GitHub Actions run.

Scan reports should be regenerated when needed and clearly associated with the image version they describe.

## 3. GitHub Actions CI/CD

I created a GitHub Actions workflow named **Voting App CI**.

### Workflow stages

1. Check out the repository.
2. Configure Docker Buildx.
3. Build Vote, Result, and Worker images.
4. Tag images with the Git commit SHA.
5. Install Trivy.
6. Scan each image for HIGH and CRITICAL vulnerabilities.
7. Save scanned images as workflow artifacts.
8. Publish the images to GHCR after all build-and-scan jobs succeed on a push to `main`.

### Security gate command

```bash
trivy image \
  --ignore-unfixed \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  "$IMAGE"
```

The `publish` job depends on the `build-and-scan` job. This prevents publishing through that workflow when a required build or scan fails.

### Image naming

```text
ghcr.io/chidimma-okoli/voting-app-vote:<commit-sha>
ghcr.io/chidimma-okoli/voting-app-result:<commit-sha>
ghcr.io/chidimma-okoli/voting-app-worker:<commit-sha>
```

### Recorded result

My latest reported GitHub Actions run passed all jobs, including publishing to GHCR.

This confirms the reported outcome of that run. It does not mean every possible vulnerability has been eliminated, and it does not mean GitHub Actions directly deploys to my local Kind cluster.

## 4. Kubernetes Deployment with Kind

I used a local Kind cluster to avoid additional AWS running costs.

### Verify the cluster

```bash
kubectl config current-context
kubectl get nodes
```

The cluster node was:

```text
voting-capstone-control-plane
```

The node reported `Ready` and Kubernetes version `v1.34.0`.

### Verify pods and services

```bash
kubectl get pods -n default
kubectl get services -n default
```

The application components were:

- `vote`
- `result`
- `worker`
- `redis`
- `db`

The Vote and Result services were exposed through NodePort services, while Redis and PostgreSQL were internal ClusterIP services.

### Access the Vote application

```bash
kubectl port-forward service/vote 8080:8080
```

Then open:

```text
http://localhost:8080
```

### Access the Result application

In a separate terminal:

```bash
kubectl port-forward service/result 8081:8081
```

Then open:

```text
http://localhost:8081
```

Both endpoints returned HTTP 200 OK during the recorded test.

**Testing limitation:** An HTTP 200 response confirms that the endpoint responded successfully. A complete functional test should also submit a vote and verify that the result changes.

## 5. Helm Deployment and Release Management

I used Helm to manage the Kubernetes application through the release `voting-app` in the `default` namespace.

### Inspect the release

```bash
helm list -n default
helm status voting-app -n default
helm history voting-app -n default
helm get values voting-app -n default
```

The release initially showed revision 2 as deployed.

### Issue encountered: Failed rollback

[[https://drive.google.com/file/d/1MuAoE1Rz5SlOGCajDh6FR56_iD2xzRaN/view?usp=sharing](https://drive.google.com/file/d/1MuAoE1Rz5SlOGCajDh6FR56_iD2xzRaN/view?usp=sharing)]

I attempted to roll back to revision 1:

```bash
helm rollback voting-app 1 -n default --wait
```

The command timed out:

```text
Error: release voting-app failed: context deadline exceeded
```

The new Vote pod entered `CrashLoopBackOff`, while the other application pods remained running.

### Diagnosis

I inspected the pod:

```bash
kubectl describe pod vote-596d68688b-l4tqx -n default
```

The container runtime reported:

```text
exec: "gunicorn": executable file not found in $PATH
```

This showed that the older Vote image could not start because the configured executable was missing from its execution path.

The image was available locally, but availability did not guarantee that the container could start successfully.

### Recovery

I restored revision 2:

```bash
helm rollback voting-app 2 -n default --wait --timeout 3m
```

Helm reported:

```text
Rollback was a success! Happy Helming!
```

I then checked the pods:

```bash
kubectl get pods -n default
```

All five application pods returned to `1/1 Ready`.

I also verified the restored Vote image:

```bash
kubectl get deployment vote -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

The image tag was:

```text
eb366d27f3ae90b8fb47691032baec09fa8c72c6
```

### Lessons learned

- A successful image pull does not guarantee successful container startup.
- Pod events can reveal startup errors even when container logs are empty.
- A failed rollback should be diagnosed before attempting further changes.
- Helm release history provides a record of deployments and recovery operations.
- Recovery must be verified by checking both pod readiness and application behavior.

The older image that failed to start still requires separate investigation before it should be reused.

## 6. Terraform and Infrastructure as Code

The repository contains Terraform source files:

- `main.tf`
- `variables.tf`
- `outputs.tf`
- `versions.tf`
- `backend.tf`

The backend configuration references an S3 bucket in `eu-west-2` and enables encryption and S3 state locking.

Terraform configuration is maintained separately from the current local Kind workload.

**Important distinction:** The application deployment verified in this project is running on local Kind. The presence of Terraform files and an AWS S3 backend configuration does not mean the current Kubernetes workload was created by Terraform or is running on AWS.

I excluded generated Terraform state and the local `.terraform` directory from Git tracking. Credentials, private variable files, and state files should not be committed.

## 7. Challenges and Solutions Summary

| Challenge                        | Investigation or solution                                            | Outcome                                                  |
| -------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------- |
| Docker Hub TLS error             | Tested endpoint connectivity and retried image pull                  | Pull succeeded                                           |
| Container vulnerability findings | Updated packaging dependencies, refined the final image, and rebuilt | Latest reported scan passed the configured policy        |
| Helm rollback timeout            | Inspected the Vote pod and found the missing `gunicorn` executable   | Root cause of the old image's startup failure identified |
| Failed application revision      | Rolled back to revision 2                                            | Five pods returned to ready status                       |
| Avoiding AWS costs               | Used an existing local Kind cluster                                  | Kubernetes deployment continued locally                  |

## 8. Final Validation Checklist

- [x] GitHub Actions build-and-scan workflow reported successful.
- [x] GHCR publishing reported successful.
- [x] Local Kind node reported `Ready`.
- [x] Five application pods returned to `1/1 Ready` after recovery.
- [x] Vote and Result endpoints returned HTTP 200 OK.
- [x] Helm rollback to revision 2 completed successfully.
- [x] Restored Vote image tag verified.
- [x] Full end-to-end voting and result-update test recorded.
- [ ] Failed revision's missing `gunicorn` issue corrected and retested.
- [x] Final architecture diagram and README committed to GitHub.

The unchecked items are remaining work, not claims of completed testing.

## 9. Future Improvements

- Add automated functional tests to CI.
- Test the complete vote-to-result flow.
- Investigate and fix the older Vote image's startup configuration.
- Add health checks and improve observability.
- Capture a repeatable Helm rollback demonstration.
- Expand security checks while documenting the scan policy.
- Improve deployment automation without requiring a paid cloud environment.

## Author

**Chidimma Calista Okoli**

DevOps learning portfolio project focused on containerization, CI/CD, container security, Kubernetes, Helm, and infrastructure as code.
