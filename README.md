# Voting App — DevOps Capstone Project

A containerized voting application deployed to a local Kubernetes cluster using Helm, with automated image building, security scanning, publishing, and deployment through GitHub Actions.

**Repository:** [chidimma-okoli/voting-app](https://github.com/chidimma-okoli/voting-app)

## Project Overview

This project demonstrates how I build, test, secure, deploy, and troubleshoot a multi-service application using DevOps tools.

The application consists of five services: Vote, Result, Worker, Redis, and PostgreSQL. I used Docker Compose for local execution and a local Kind Kubernetes cluster for the Kubernetes deployment. Helm manages the application release, while GitHub Actions automates the CI/CD workflow.

The project also explores container image security, deployment failures, Helm release history, and recovery through rollback.

## Architecture

[View the application architecture diagram](https://drive.google.com/file/d/1kUGcmHyL66RKzctsvpCKm2tv9pExHBMP/view?usp=sharing)

The application follows this flow:

1. A user submits a vote through the Vote service.
2. The vote is placed in Redis.
3. The Worker reads the vote from Redis and processes it.
4. The processed vote is stored in PostgreSQL.
5. The Result service reads the stored data and displays the updated results.

This separates vote submission, processing, storage, and result display into independent services.

## Technology Stack

| Area | Tools |
|---|---|
| Application containerization | Docker, Docker Compose |
| Container orchestration | Kubernetes, Kind |
| Deployment and release management | Helm |
| CI/CD | GitHub Actions |
| Image security scanning | Trivy |
| Container registry | GitHub Container Registry (GHCR) |
| Infrastructure as code | Terraform |
| Version control | Git, GitHub |

## Local Application and Kubernetes Deployment

I first ran the application locally and verified its core voting workflow. I then deployed the services to a local Kind Kubernetes cluster using Helm.

The Kubernetes environment contains deployments for Vote, Result, Worker, Redis, and PostgreSQL. Kubernetes manages the workloads, while Services provide network access between the application components.

### Accessing the application

With the cluster running, use port forwarding to access the services locally.

**Vote application**

```bash
kubectl port-forward service/vote 8080:8080
```

Open `http://localhost:8080`.

**Result application**

In a separate terminal, run:

```bash
kubectl port-forward service/result 8081:8081
```

Open `http://localhost:8081`.

Keep both port-forwarding terminals open while testing.

### Functional validation

I submitted a vote through the Vote page and checked the Result page. The result updated as expected, confirming that the main voting workflow worked across the application services.

The manual test execution recorded six test cases, with six passed and zero failed. These results represent the recorded functional and smoke tests; they do not claim exhaustive testing of every possible scenario.

## CI/CD Pipeline

The GitHub Actions workflow, **Voting App CI and CD**, automates the main delivery process.

### 1. Build and scan

The pipeline builds the Vote, Result, and Worker container images using the commit SHA as the image tag.

Trivy scans the images for HIGH and CRITICAL vulnerabilities. The workflow uses `--ignore-unfixed`, so the security gate fails on HIGH or CRITICAL findings that meet the scanner's applicable criteria after unfixed findings are excluded.

This makes the security scan part of the build process rather than relying only on manual checks.

### 2. Publish images

After the build-and-scan job succeeds, the pipeline publishes the scanned images to GitHub Container Registry.

The image tags use the triggering commit SHA to associate the published images with a specific source revision.

### 3. Deploy to local Kubernetes

The deployment job runs on a self-hosted Linux runner with access to the local Kind cluster.

It validates the Helm chart, upgrades or installs the release, waits for the deployment to complete, and checks the rollout status of the Vote, Result, and Worker deployments.

The deployment uses the image tag from the triggering commit rather than a manually hardcoded image version.

**Important distinction:** Terraform is part of the project's infrastructure-as-code work, but it did not create the current Kind cluster. The current CI/CD deployment reaches the local cluster through the self-hosted runner.

## Security and Image Scanning

I included Trivy in the delivery workflow to identify container image vulnerabilities before publishing and deploying images.

During testing, the scan reported HIGH-severity findings in the Debian-based image layer, while the Python section of the scan reported no HIGH or CRITICAL findings. The reported Debian findings were not all immediately fixable through the available package upgrades.

This highlighted an important distinction: a vulnerability report does not automatically mean that a newer, usable package version is available. The scan results must be examined to determine the affected package, installed version, available fix, and appropriate remediation.

The pipeline's use of `--ignore-unfixed` is a deliberate policy choice. It does not mean that the images contain zero vulnerabilities or that every reported finding has been resolved.

## Helm Release Management and Rollback

Helm manages the `voting-app` release in the `default` namespace. Release history makes it possible to inspect previous deployment attempts and recover from a failed upgrade.

During the project, I encountered a failure involving an older Vote image. After investigating the problem, I rolled back to a previously working release and verified that the application recovered. I later deployed a newer, working release.

The current release is Helm revision 5.

[View the rollback demonstration and evidence](https://drive.google.com/file/d/1MuAoE1Rz5SlOGCajDh6FR56_iD2xzRaN/view?usp=sharing)

I also retained snapshots of the Helm history and image information in the repository's evidence directory. These files document the state captured at the time they were created; they should not be treated as live output from the current cluster.

## Issues Encountered and Resolutions

Troubleshooting was an important part of this project. The following examples document the problems encountered, where they occurred, why they happened, and the actions taken.

### 1. Container image pull and network errors

**Where:** During the initial Docker Compose setup and attempts to retrieve container images.

**Issue:** Image retrieval encountered errors, including a Redis TLS handshake timeout and a `tls: bad record MAC` error during an alternative image pull attempt.

**Why it happened:** These errors indicated a problem during the image retrieval or network/TLS communication process. They did not, by themselves, prove that the application code was faulty.

**Resolution and outcome:** I continued working through the image retrieval and startup problems until the required application services could be built or pulled and the local environment could run. The errors were treated as image retrieval and connectivity problems rather than automatically attributed to the application logic.

### 2. Vote container failed because Gunicorn was not found

**Where:** During an earlier Helm rollback to revision 1.

**Issue:** The Vote pod entered `CrashLoopBackOff`. The container reported:

```text
exec: "gunicorn": executable file not found in $PATH
```

**Why it happened:** The older Vote image referenced by that release could not find the Gunicorn executable through the configured command and runtime environment. The application therefore failed to start correctly.

**Resolution:** I rolled back to Helm revision 2:

```bash
helm rollback voting-app 2 -n default --wait --timeout 3m
```

**Outcome:** The application recovered, and the five service pods returned to a ready state. I did not keep the faulty revision 1 as the active release.

This experience reinforced the importance of checking container startup commands, executable paths, image versions, and rollout status before considering a deployment successful.

### 3. Helm upgrade timed out

**Where:** During a later Helm upgrade.

**Issue:** Helm revision 3 failed because the upgrade timed out.

**Why it happened:** Kubernetes did not complete the rollout within the configured waiting period. A timeout alone does not identify the underlying cause, so it must be investigated alongside pod status, events, and container logs.

**Resolution:** I returned to the previously working release and subsequently completed a successful deployment.

**Outcome:** Revision 4 recorded the rollback, and revision 5 became the current deployed release. The working application was preserved rather than leaving the failed upgrade active.

### 4. Vulnerabilities remained in the container image scan

**Where:** During Trivy security testing.

**Issue:** Trivy reported HIGH-severity findings in the Debian-based image layer. Attempting to upgrade packages did not automatically eliminate all the reported findings because the available package candidates matched the installed versions.

**Why it happened:** A package upgrade can only remediate a finding when an appropriate fixed version is available and applicable. Repeating the same upgrade does not guarantee that a fix will become available.

**Resolution:** I examined the scan findings and used an explicit CI security gate that checks HIGH and CRITICAL findings while excluding findings classified as unfixed.

**Outcome:** Security scanning became part of the automated pipeline. The policy provides a defined gate, but it does not establish that every vulnerability has been eliminated. Findings without available fixes still require review and follow-up.

### 5. Resource pressure during Helm deployment

**Where:** During the earlier Helm-based Kubernetes work.

**Issue:** A Helm-managed workload was terminated with `OOMKilled`, including an attempt where the memory allocation had been increased.

**Why it happened:** `OOMKilled` means the container was terminated after exceeding its available memory limit or because of memory pressure. Increasing the limit alone may not solve the problem if the workload's memory demand remains too high or another resource constraint exists.

**Resolution and outcome:** This highlighted the need to examine pod status, container termination details, logs, resource requests and limits, and actual workload demand before making further changes. Memory-limit increases should be validated against observed usage rather than treated as a guaranteed fix.

This issue is documented as part of the troubleshooting experience; it should not be interpreted as evidence that the current five-service release is failing.

## Validation and Troubleshooting Commands

The following commands help inspect the deployed application and gather evidence when something goes wrong.

**Check pod readiness**

```bash
kubectl get pods
```

**Check Services**

```bash
kubectl get services
```

**Inspect Helm release history**

```bash
helm history voting-app -n default
```

**Inspect the release status**

```bash
helm status voting-app -n default
```

**Check a deployment rollout**

```bash
kubectl rollout status deployment/vote -n default
```

**Inspect pod details and events**

```bash
kubectl describe pod <pod-name> -n default
```

**Read container logs**

```bash
kubectl logs <pod-name> -n default
```

These checks help distinguish between image startup failures, unsuccessful rollouts, application errors, and resource-related terminations.

## Repository Structure

The repository contains the application source, container build files, Kubernetes deployment configuration, CI/CD workflow, and project documentation.

```text
voting-app/
├── .github/
│   └── workflows/
│       └── ci.yml
├── docs/
│   ├── architecture.mmd
│   └── evidence/
│       ├── helm-history-before-rollback.txt
│       └── images-before-rollback.txt
├── helm/
│   └── voting-app/
│       └── values-capstone.yaml
├── vote/
├── result/
├── worker/
├── docker-compose.yml
└── README.md
```

The exact contents may evolve as the project develops. The evidence files are snapshots captured during troubleshooting, not a replacement for checking the live cluster.

## Demonstration

The demonstrations and evidence show the application architecture, deployment behavior, and troubleshooting work.

- **Architecture:** [View the architecture diagram](https://drive.google.com/file/d/1kUGcmHyL66RKzctsvpCKm2tv9pExHBMP/view?usp=sharing)
- **Helm rollback:** [View the rollback demonstration](https://drive.google.com/file/d/1MuAoE1Rz5SlOGCajDh6FR56_iD2xzRaN/view?usp=sharing)
- **Source code and workflow:** [Open the GitHub repository](https://github.com/chidimma-okoli/voting-app)

For a live walkthrough, I demonstrate the vote submission, the corresponding result update, the Kubernetes workloads, the GitHub Actions workflow, and the Helm release history. I also explain the failed release, the reason for the rollback, and the evidence that the application recovered.

## Technical Demonstration: Questions and Answers

### 1. What does the application do?

The application allows users to submit votes and view the results. It uses separate services for voting, vote processing, data storage, and displaying results.

### 2. Explain the application's architecture.

The Vote service accepts a vote and sends it to Redis. The Worker processes the vote and stores it in PostgreSQL. The Result service reads the stored data and displays the results.

### 3. Why did you use Docker?

Docker packages applications and their dependencies into containers, helping services run consistently across environments.

### 4. Why Kubernetes?

Kubernetes manages containerized workloads, maintains the desired number of replicas, and supports service discovery, deployment updates, and recovery when containers fail.

### 5. Why did you use Kind instead of a cloud Kubernetes cluster?

Kind runs Kubernetes nodes in Docker containers. It allowed me to practice Kubernetes deployment locally without requiring a paid cloud environment for this capstone.

### 6. What is Helm, and why did you use it?

Helm manages Kubernetes applications through charts and releases. I used it to organize the application's Kubernetes configuration and manage installations, upgrades, release history, and rollback.

### 7. How does your CI/CD pipeline work?

The GitHub Actions workflow builds the Vote, Result, and Worker images, scans them with Trivy, publishes the images to GitHub Container Registry after the build-and-scan job succeeds, and deploys them to the local Kind cluster through a self-hosted runner.

### 8. Why do you tag images with the Git commit SHA?

A commit-SHA tag connects an image to a specific source revision. This makes it easier to identify which version was built and deployed and to investigate deployment problems.

### 9. Why did you use a self-hosted GitHub Actions runner?

The runner has access to my local Kubernetes environment. A standard hosted runner would not automatically have access to the Kind cluster running on my machine.

### 10. How did you test that the application works?

I submitted a vote through the Vote interface and checked the Result interface to confirm that the result updated. My recorded manual test execution contained six test cases, all of which passed.

### 11. What security checks did you implement?

I integrated Trivy into the image build workflow to scan for HIGH and CRITICAL vulnerabilities. The configured policy uses `--ignore-unfixed`, so it excludes findings classified as unfixed. This does not mean that every vulnerability has been eliminated.

### 12. What problem did you encounter during rollback?

An earlier rollback to Helm revision 1 resulted in a Vote container startup failure. The logs reported that `gunicorn` could not be found in the container's executable path.

I rolled back to revision 2, which restored the working application. I subsequently completed a successful deployment, and revision 5 is the current release documented in this project.

### 13. What did the Helm upgrade timeout teach you?

A Helm upgrade can fail when Kubernetes does not complete the rollout within the configured timeout. A timeout is a symptom, not a complete diagnosis. Pod status, events, logs, and rollout details are needed to investigate the underlying cause.

### 14. Does a successful Trivy scan mean the application has no vulnerabilities?

No. The pipeline applies a specific security policy. Because it uses `--ignore-unfixed`, findings without available fixes are excluded from the failure gate. The results must still be reviewed, and remaining risks should be tracked.

### 15. What does `OOMKilled` mean?

It means Kubernetes reports that a container was terminated because it exceeded its available memory limit or was affected by memory pressure. Increasing the memory limit may help, but the workload's actual memory usage and configuration must also be investigated.

### 16. What is the difference between Terraform and Helm in this project?

Terraform is an infrastructure-as-code tool, while Helm manages Kubernetes application releases. In this project, Helm manages the current application release in Kind. Terraform did not create the current Kind cluster.

### 17. How would you troubleshoot a pod that is not starting?

I would first inspect the pod status and events using `kubectl get pods` and `kubectl describe pod`. I would then check the container logs, image configuration, startup command, resource limits, and relevant Kubernetes configuration before changing anything.

### 18. How would you recover from a failed Helm deployment?

I would inspect the Helm history and status, identify a known-good release, and check the reason the new deployment failed. If rollback were appropriate, I would restore the known-good revision and verify the rollout and application functionality afterward.

### 19. What would you improve next?

I would expand automated functional testing, improve vulnerability remediation and reporting, strengthen monitoring and resource visibility, and continue improving infrastructure automation.

### 20. What is the most important lesson you learned?

A successful pipeline does not automatically prove that an application works correctly. The deployed application must be tested, failures must be investigated, and recovery must be verified with evidence.

## What I Learned

This project helped me connect individual DevOps tools into a working delivery workflow. I gained practical experience with:

- Containerizing and running a multi-service application.
- Deploying workloads to a local Kubernetes cluster.
- Managing deployments and release history with Helm.
- Automating image builds, security scans, publishing, and deployment.
- Investigating image retrieval, container startup, rollout, and resource issues.
- Using evidence and test results to verify application behavior.
- Distinguishing a successful deployment from a deployment that merely completed a command.

The most important lesson was that deployment does not end when a pipeline turns green. The application still needs to be checked, failures need to be understood, and recovery needs to be demonstrated.

## Future Improvements

Potential next steps include expanding automated functional tests, strengthening vulnerability remediation and reporting, improving monitoring and resource visibility, and extending infrastructure automation.

These improvements would build on the current working local deployment without overstating what has already been implemented.
