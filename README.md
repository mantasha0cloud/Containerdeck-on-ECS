# ContainerDeck — ECS Fargate CI/CD Pipeline

**AWS Developer Tools Practical 2**
The same style of dashboard as Practical 1, but this time it's containerized with Docker, pushed to **Amazon ECR**, and deployed serverlessly to **ECS Fargate** behind an **Application Load Balancer**.

> New concepts vs Practical 1: Docker, ECR, ECS, Fargate, Task Definitions, ECS Services, ALB, container health checks, immutable image tags.
> Note: We do **not** use CodeDeploy here in the traditional EC2 sense — ECS has its own native rolling-deployment mechanism, triggered directly by CodePipeline's "Amazon ECS" deploy provider.

---

## 🏗️ Architecture

```
Developer (Windows laptop, Git)
        |
        v
   CodeCommit  (source)
        |
        v
   CodePipeline (orchestrator)
        |
        v
   CodeBuild
      |-- pre_build -> run tests/test.sh, ECR login
      |-- build     -> docker build + docker-test.sh (container smoke test)
      |-- post_build-> docker push to ECR + write imagedefinitions.json
        |
        v
   Amazon ECR (image registry)
        |
        v
   CodePipeline "Amazon ECS" Deploy action
        |
        v
   ECS Service (Fargate) -- rolling update using imagedefinitions.json
        |
        v
   Application Load Balancer
        |
        v
   Browser -> http://<ALB-DNS-Name>
```

---

## 📁 Project structure

```
containerdeck-ecs-cicd/
├── index.html
├── style.css
├── script.js
├── nginx.conf
├── Dockerfile
├── buildspec.yml
├── task-definition.json   (reference copy — you'll create the real one in console)
├── tests/
│   ├── test.sh
│   └── docker-test.sh
└── README.md
```

---

## ✅ Prerequisites

- Everything from Practical 1 (AWS account, Git for Windows, AWS CLI)
- **Docker is NOT required on your laptop** — CodeBuild builds the image in the cloud. (Optional: install Docker Desktop for Windows if you want to test the image locally first.)

---

## STEP 1 — Create the ECR repository

1. Go to **ECR → Repositories → Create repository**
2. Visibility: **Private**
3. Repository name: `containerdeck-frontend`
4. Leave scan-on-push enabled (nice to have)
5. Create repository
6. Copy the **repository URI** — looks like `1234567890.dkr.ecr.<region>.amazonaws.com/containerdeck-frontend`

---

## STEP 2 — IAM Roles

### 2.1 ECS Task Execution Role (lets Fargate pull images & write logs)
1. **IAM → Roles → Create role**
2. Trusted entity: **AWS service → Elastic Container Service → Elastic Container Service Task**
3. Attach policy: `AmazonECSTaskExecutionRolePolicy`
4. Name: `ecsTaskExecutionRole` (AWS may already have this pre-created — reuse it if so)
5. Create role

### 2.2 CodeBuild service role
1. **IAM → Roles → Create role → AWS service → CodeBuild**
2. Attach policies:
   - `AmazonEC2ContainerRegistryPowerUser` (push/pull to ECR)
   - `AWSCodeBuildDeveloperAccess`
   - `CloudWatchLogsFullAccess` (or scope down later)
3. Name: `ContainerDeck-CodeBuild-Role`
4. Create role

### 2.3 CodePipeline service role
- Let CodePipeline auto-create this in Step 7 — it will include ECS deploy permissions automatically when you pick "Amazon ECS" as the deploy provider.

---

## STEP 3 — Create the CodeCommit repository & push code

1. **CodeCommit → Create repository** → name: `containerdeck-ecs-cicd`
2. Clone it locally (reuse your HTTPS Git credentials from Practical 1, or generate new ones):
   ```bash
   git clone https://git-codecommit.<your-region>.amazonaws.com/v1/repos/containerdeck-ecs-cicd
   cd containerdeck-ecs-cicd
   ```
3. Copy in all the project files (`index.html`, `style.css`, `script.js`, `nginx.conf`, `Dockerfile`, `buildspec.yml`, `tests/`, `task-definition.json`).
4. Commit and push:
   ```bash
   git add .
   git commit -m "Initial commit - ContainerDeck app with Docker + ECS CI/CD configs"
   git push origin main
   ```

---

## STEP 4 — Create the ECS Cluster

1. Go to **ECS → Clusters → Create cluster**
2. Cluster name: `containerdeck-cluster`
3. Infrastructure: **AWS Fargate (serverless)**
4. Create

---

## STEP 5 — Create the Task Definition

1. **ECS → Task definitions → Create new task definition**
2. Task definition family: `containerdeck-task`
3. Launch type: **AWS Fargate**
4. OS/Architecture: Linux/X86_64
5. Task size: CPU `0.25 vCPU`, Memory `0.5 GB`
6. Task execution role: `ecsTaskExecutionRole` (from Step 2.1)
7. Container details:
   - Container name: `containerdeck-frontend` (**must exactly match** `CONTAINER_NAME` in `buildspec.yml`)
   - Image URI: paste your ECR repository URI + `:latest` (e.g. `1234567890.dkr.ecr.us-east-1.amazonaws.com/containerdeck-frontend:latest`) — it's fine that the image doesn't exist yet, the first pipeline run will create it
   - Container port: `80`
8. Logging: enable **awslogs**, log group `/ecs/containerdeck-task` (auto-created)
9. Create task definition

> 💡 You can instead use **task-definition.json** provided in this repo: in the console choose "Configure via JSON", paste the file contents, replace the placeholder ARNs/region/image, and create.

---

## STEP 6 — Create the ALB + ECS Service

### 6.1 Create the Application Load Balancer
1. **EC2 → Load Balancers → Create load balancer → Application Load Balancer**
2. Name: `containerdeck-alb`
3. Scheme: Internet-facing
4. Listeners: HTTP : 80
5. VPC: default VPC, select at least 2 subnets (different AZs)
6. Security group: create/select one allowing inbound **HTTP 80** from anywhere
7. Target group: **Create target group**
   - Type: **IP** (required for Fargate)
   - Name: `containerdeck-tg`
   - Protocol/Port: HTTP / 80
   - Health check path: `/health`
8. Create load balancer

### 6.2 Create the ECS Service
1. Go to your cluster `containerdeck-cluster` → **Create service**
2. Launch type: **Fargate**
3. Task definition: `containerdeck-task` (latest revision)
4. Service name: `containerdeck-service`
5. Desired tasks: `2`
6. Networking: select your VPC, at least 2 public subnets
7. Security group: allow inbound **port 80** from the ALB's security group
8. Load balancing: **Application Load Balancer**
   - Select `containerdeck-alb`
   - Container to load balance: `containerdeck-frontend:80`
   - Target group: `containerdeck-tg`
9. Create service

Wait for tasks to reach **RUNNING** and the target group to show **healthy** targets.

10. Copy the **ALB DNS name** (EC2 → Load Balancers → containerdeck-alb) — this is your app's URL.

---

## STEP 7 — Create the CodeBuild Project

1. **CodeBuild → Create build project**
2. Project name: `ContainerDeck-Build`
3. Source: **AWS CodeCommit** → repo `containerdeck-ecs-cicd`, branch `main`
4. Environment:
   - Managed image, OS: **Amazon Linux 2**
   - Runtime: **Standard**, latest image
   - ✅ **Enable this flag if you want to build Docker images** (Privileged mode) — **this is required**, don't skip it
   - Service role: existing role → `ContainerDeck-CodeBuild-Role`
5. Environment variables (Additional configuration → Environment variables):
   - `ECR_REPO_NAME` = `containerdeck-frontend`
6. Buildspec: **Use a buildspec file** (reads `buildspec.yml`)
7. Create build project

---

## STEP 8 — Create the CodePipeline

1. **CodePipeline → Create pipeline**
2. Name: `ContainerDeck-Pipeline`
3. Service role: **New service role**

### 8.1 Source stage
- Provider: **AWS CodeCommit**
- Repository: `containerdeck-ecs-cicd`, branch `main`

### 8.2 Build stage
- Provider: **AWS CodeBuild**
- Project: `ContainerDeck-Build`
- Output artifact: default (this includes `imagedefinitions.json`)

### 8.3 Deploy stage
- Provider: **Amazon ECS**
- Cluster: `containerdeck-cluster`
- Service: `containerdeck-service`
- Image definitions file: `imagedefinitions.json` (default name — matches what buildspec writes)

4. Create pipeline

It runs automatically. Watch **Source → Build → Deploy** turn green.

---

## STEP 9 — Verify

1. Open `http://<ALB-DNS-Name>` in your browser.
2. You should see the **ContainerDeck** dashboard.
3. In ECS console, confirm 2 tasks are running and the target group shows healthy targets.

---

## STEP 10 — Test the full loop

1. Edit `style.css` or `script.js` locally.
2. Commit and push:
   ```bash
   git add .
   git commit -m "Update ContainerDeck styling"
   git push origin main
   ```
3. Watch CodePipeline trigger automatically — a **new image tag** (short commit hash) is built, pushed to ECR, and ECS performs a rolling deployment with zero downtime.
4. Refresh the ALB URL — the change appears, and at no point did the site go down (ECS keeps old tasks running until new ones pass health checks).

---

## STEP 11 — Break it on purpose (teaching moment)

1. In `tests/docker-test.sh`, temporarily change the health check path to something invalid, e.g. `http://localhost:8080/does-not-exist`.
2. Push the change.
3. Watch the **Build** stage fail because the container smoke test fails — the bad image never reaches ECR or ECS.
4. Revert and push again.

This proves containers are tested **before** they ever reach your registry or your running service.

---

## 🧠 Concepts covered in this practical

- Writing a `Dockerfile` and building images in CI
- Pushing/pulling images with Amazon ECR
- ECS cluster, task definition, and service concepts
- Fargate serverless compute for containers
- Application Load Balancer + target groups + health checks
- `imagedefinitions.json` and the native CodePipeline → ECS deploy integration
- Immutable image tagging using commit hashes
- Why CodeDeploy isn't forced onto every compute platform — ECS has its own deployment mechanism

---

## Key difference from Practical 1

| | Practical 1 | Practical 2 |
|---|---|---|
| Compute | EC2 (VM) | ECS Fargate (serverless containers) |
| Artifact | Raw files | Docker image |
| Registry | S3 (pipeline artifact only) | Amazon ECR |
| Deploy mechanism | CodeDeploy + appspec.yml | Native ECS rolling deployment |
| Traffic entry | Public IP directly | Application Load Balancer |

---

## Next practical

**Practical 3 — `KubeVoyage: EKS CI/CD`** takes the same Docker image concept and deploys it to a Kubernetes cluster (EKS) using Deployments, Services, and `kubectl`.
