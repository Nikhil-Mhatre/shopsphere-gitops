# ShopSphere GitOps Deployment

This document describes how application changes move from the ShopSphere source repository to the production Kubernetes cluster.

The deployment process follows a **GitOps-based Continuous Integration and Continuous Delivery model**:

```text
Source Repository
       │
       ▼
GitHub Actions
       │
       ▼
Docker Hub
       │
       ▼
GitOps Repository
       │
       ▼
Argo CD
       │
       ▼
Kubernetes / AKS
       │
       ▼
Production
```

The purpose of this document is to make the deployment lifecycle predictable and understandable for every developer working on ShopSphere.

---

# Deployment Principles

ShopSphere follows these deployment principles:

- Application source code and deployment configuration are stored separately.
- GitHub Actions is responsible for Continuous Integration and image publishing.
- Docker Hub stores versioned application images.
- The GitOps repository is the source of truth for Kubernetes desired state.
- Argo CD is responsible for reconciling Git state with Kubernetes.
- Each microservice is deployed independently.
- Production images use immutable image versions.
- Database migrations run separately from application container startup.
- Production changes are normally introduced through Git.
- Kubernetes resources should not be manually modified as part of normal deployment.
- Every production deployment should be traceable to a source-code revision.

---

# Repository Responsibilities

The deployment process uses two repositories.

## Application Repository

The application repository contains:

```text
Source code
Tests
Dockerfile
Prisma schema
Prisma migrations
GitHub Actions workflows
```

Its responsibility is to produce a deployable Docker image.

```text
Source Code
     │
     ▼
GitHub Actions
     │
     ▼
Docker Image
```

---

## GitOps Repository

The GitOps repository contains:

```text
Kubernetes manifests
Kustomize configuration
Argo CD configuration
Environment configuration
Ingress configuration
Application image versions
Migration Jobs
```

Its responsibility is to define what should be running in Kubernetes.

```text
GitOps Repository
       │
       ▼
Desired Kubernetes State
```

---

# Complete Deployment Lifecycle

A normal production deployment follows this lifecycle:

```text
Developer
    │
    ▼
Modify Microservice
    │
    ▼
Commit and Push
    │
    ▼
GitHub Actions
    │
    ├── Detect Changed Service
    ├── Install Dependencies
    ├── Lint
    ├── Test
    ├── Build Application
    ├── Build Docker Image
    └── Push Docker Image
            │
            ▼
        Docker Hub
            │
            ▼
    Update GitOps Repository
            │
            ▼
       GitOps Commit
            │
            ▼
          Argo CD
            │
            ▼
     Detect Desired-State Change
            │
            ▼
      Database Migration Job
            │
            ▼
     Kubernetes Deployment
            │
            ▼
       Rolling Update
            │
            ▼
       Health Verification
```

Each stage has a specific responsibility.

---

# Step 1 — Developer Changes Application Code

A developer modifies one of the ShopSphere microservices.

For example:

```text
services/
└── user-service/
```

The developer commits and pushes the change to the application repository.

The GitHub Actions workflow is configured to identify which microservice was affected.

---

# Step 2 — Path-Based CI Trigger

The application repository contains independent workflows for the microservices.

Conceptually:

```text
Change
 │
 ├── auth-service changed
 │       │
 │       ▼
 │   Auth workflow
 │
 ├── user-service changed
 │       │
 │       ▼
 │   User workflow
 │
 ├── product-service changed
 │       │
 │       ▼
 │   Product workflow
 │
 └── order-service changed
         │
         ▼
     Order workflow
```

A change to one microservice should not unnecessarily build unrelated services.

This keeps CI efficient and maintains independent deployment boundaries.

---

# Step 3 — GitHub Actions Validation

The affected service's workflow should validate the application before producing a production image.

The typical sequence is:

```text
Checkout
   │
   ▼
Install Dependencies
   │
   ▼
Lint
   │
   ▼
Test
   │
   ▼
Build
   │
   ▼
Docker Build
```

If any required validation step fails, the workflow should stop.

No production image should be promoted from a failed build.

---

# Step 4 — Build the Docker Image

After application validation succeeds, GitHub Actions builds the Docker image.

For example:

```text
shopsphere/user-service:7f3a91c
```

The image should contain the application version associated with the source revision.

The production deployment must not use mutable tags such as:

```text
latest
production
stable
current
```

Immutable image versions make deployments traceable and rollback predictable.

---

# Step 5 — Push Image to Docker Hub

After the image is successfully built, GitHub Actions pushes it to Docker Hub.

Conceptually:

```text
GitHub Actions
      │
      ▼
Docker Build
      │
      ▼
shopsphere/user-service:7f3a91c
      │
      ▼
Docker Hub
```

The image must exist in the registry before the GitOps repository is updated to reference it.

This prevents the GitOps repository from declaring a version that Kubernetes cannot pull.

---

# Step 6 — Update the GitOps Repository

Once the Docker image has been published successfully, GitHub Actions updates the corresponding GitOps configuration.

For example, the production overlay may contain:

```yaml
images:
  - name: shopsphere/user-service
    newTag: 7f3a91c
```

A new application build may change this to:

```yaml
images:
  - name: shopsphere/user-service
    newTag: 81ab320
```

The GitOps repository now declares that:

```text
user-service version 81ab320
```

is the desired production version.

---

# Step 7 — Commit the GitOps Change

The image-version change must be committed to the GitOps repository.

For example:

```text
chore: update user-service image to 81ab320
```

The commit becomes part of the deployment history.

This is an important property of GitOps.

The production deployment can be traced through:

```text
Source Commit
      │
      ▼
Docker Image
      │
      ▼
GitOps Commit
      │
      ▼
Kubernetes Deployment
```

---

# Step 8 — Argo CD Detects the Change

Argo CD continuously monitors the GitOps repository.

When the GitOps repository changes:

```text
GitOps Repository
       │
       ▼
New image version
       │
       ▼
Argo CD detects difference
       │
       ▼
Desired State ≠ Actual State
```

Argo CD then synchronizes the affected application.

For example:

```text
shopsphere-user
```

is synchronized without requiring the other microservices to be redeployed.

---

# Step 9 — Argo CD Synchronization

The synchronization process applies the Kubernetes resources defined by the production overlay.

Conceptually:

```text
GitOps
  │
  ▼
Kustomize
  │
  ▼
Rendered Kubernetes Resources
  │
  ▼
Argo CD
  │
  ▼
Kubernetes
```

Argo CD should be the component responsible for applying the desired deployment state.

The GitHub Actions workflow should not directly execute production deployment commands such as:

```bash
kubectl apply
```

The CI system publishes the artifact and updates Git.

Argo CD performs the deployment.

---

# Step 10 — Database Migration

If the new application version contains database changes, the corresponding Prisma migration must be executed before the new application version becomes active.

The preferred lifecycle is:

```text
Argo CD Sync
      │
      ▼
Migration Job
      │
      ▼
prisma migrate deploy
      │
      ├── Failure
      │      │
      │      ▼
      │   Deployment stops
      │
      └── Success
             │
             ▼
      Application Deployment
```

The migration must not normally run inside the application container's startup command.

This avoids multiple application replicas attempting to perform the same migration.

---

# Migration Ownership

The application repository owns the database migration files.

For example:

```text
user-service
    │
    ├── prisma/
    │   ├── schema.prisma
    │   └── migrations/
    │
    └── Dockerfile
```

The GitOps repository owns the Kubernetes Job responsible for executing the migration.

This creates a clean responsibility boundary:

```text
Application Repository
        │
        └── Migration Definition

GitOps Repository
        │
        └── Migration Execution
```

---

# Migration and Application Compatibility

Database migrations should be designed so that the deployment remains safe during the transition from the old application version to the new version.

The preferred approach is to make schema changes compatible with both versions where necessary.

For example:

```text
Old Application
      │
      ▼
Migration
      │
      ▼
New Application
```

Avoid migrations that immediately remove data or columns still required by the currently running application unless the deployment strategy explicitly accounts for that change.

Database schema evolution should therefore be considered part of the deployment design.

---

# Step 11 — Kubernetes Deployment

After a successful migration, Kubernetes updates the affected Deployment.

For example:

```text
Current:

user-service:7f3a91c
```

becomes:

```text
Desired:

user-service:81ab320
```

Kubernetes performs a rolling update according to the Deployment configuration.

Conceptually:

```text
Old Pods
  │
  ├── Pod 1
  ├── Pod 2
  └── Pod 3
        │
        ▼
Rolling Update
        │
        ▼
New Pods
  │
  ├── Pod 1
  ├── Pod 2
  └── Pod 3
```

The exact rollout behavior depends on the Deployment configuration and available cluster capacity.

---

# Step 12 — Health Verification

Kubernetes should use the application's health endpoints to determine whether the new Pods are ready.

The deployment should distinguish between:

```text
Liveness
Readiness
```

A readiness failure should prevent the Pod from receiving normal traffic.

A liveness failure may cause Kubernetes to restart the container.

The application health endpoints should therefore be designed to provide meaningful Kubernetes health information.

---

# NGINX During Deployment

NGINX continues routing traffic to healthy application Pods during a normal rolling update.

Conceptually:

```text
                    NGINX
                      │
                      ▼
              Kubernetes Service
                      │
              ┌───────┴───────┐
              │               │
              ▼               ▼
          Old Pod          New Pod
              │               │
              │         Readiness OK
              │               │
              └───────┬───────┘
                      ▼
                 New version
```

Once the new Pods become ready, traffic is gradually served by the updated workload according to Kubernetes Service and Deployment behavior.

---

# Deployment Failure

A deployment can fail at several stages.

```text
CI Failure
    │
    ▼
No image promotion
```

```text
Docker Push Failure
    │
    ▼
GitOps should not reference unavailable image
```

```text
Migration Failure
    │
    ▼
Application update should not proceed normally
```

```text
Pod Startup Failure
    │
    ▼
Kubernetes reports unhealthy workload
```

```text
Readiness Failure
    │
    ▼
Pod does not receive normal traffic
```

The first step in troubleshooting should always be to identify which stage failed.

---

# Deployment Status

The primary deployment status should be observed through Argo CD and Kubernetes.

The conceptual status flow is:

```text
GitOps Commit
      │
      ▼
Argo CD
      │
      ├── Synced
      ├── OutOfSync
      ├── Healthy
      ├── Progressing
      └── Degraded
```

Kubernetes should then be inspected when an application is not healthy.

Typical resources to inspect include:

```text
Deployment
ReplicaSet
Pod
Service
Job
```

Detailed troubleshooting procedures belong in `operations.md`.

---

# Rollback Strategy

The preferred rollback mechanism is a Git-based rollback.

Suppose production currently runs:

```text
user-service:81ab320
```

and the previous known-good version was:

```text
user-service:7f3a91c
```

The GitOps repository can be reverted to:

```text
user-service:7f3a91c
```

The process becomes:

```text
GitOps rollback
      │
      ▼
Git commit
      │
      ▼
Argo CD
      │
      ▼
Kubernetes
      │
      ▼
Previous application version
```

This preserves the GitOps source-of-truth model.

---

# Why Rollback Happens in Git

The GitOps repository represents the desired production state.

If production must return to a previous version, the desired state should therefore also return to that version.

Avoid making a temporary manual Kubernetes change that is not reflected in Git.

Otherwise:

```text
Git State
    ≠
Kubernetes State
```

This creates configuration drift.

The preferred state is always:

```text
Git State
    =
Kubernetes State
```

---

# Configuration Changes

Not every deployment requires a new application image.

Configuration changes may also be represented in the GitOps repository.

For example:

```text
Resource limits
Replica count
Environment configuration
Ingress configuration
Health probes
Kubernetes settings
```

A configuration-only change follows:

```text
GitOps Change
     │
     ▼
Pull Request
     │
     ▼
Merge
     │
     ▼
Argo CD
     │
     ▼
Kubernetes
```

The application image does not need to change unless the application itself changes.

---

# Infrastructure Changes

Infrastructure changes follow the same GitOps principle.

For example:

```text
NGINX configuration
Namespace configuration
Argo CD configuration
Kubernetes infrastructure
```

The normal process is:

```text
Developer
    │
    ▼
GitOps Change
    │
    ▼
Pull Request
    │
    ▼
Review
    │
    ▼
Merge
    │
    ▼
Argo CD
    │
    ▼
Kubernetes
```

Infrastructure changes should be reviewed separately from application changes when they have a wider production impact.

---

# Manual Kubernetes Changes

Manual changes are not part of the normal deployment process.

Avoid using:

```bash
kubectl edit
kubectl patch
kubectl apply
```

as a permanent deployment mechanism.

The preferred process is:

```text
Change
  │
  ▼
Git
  │
  ▼
Argo CD
  │
  ▼
Kubernetes
```

Emergency intervention may be necessary during incidents, but any permanent change must eventually be represented in Git.

---

# Deployment Traceability

Every production deployment should be traceable.

The desired relationship is:

```text
Source Commit
      │
      ▼
Docker Image Tag
      │
      ▼
GitOps Commit
      │
      ▼
Argo CD Application
      │
      ▼
Kubernetes Deployment
      │
      ▼
Running Pod
```

For example:

```text
Source Commit:
81ab320

Docker Image:
shopsphere/user-service:81ab320

GitOps:
newTag: 81ab320

Kubernetes:
shopsphere/user-service:81ab320
```

This allows developers to determine which source revision is currently running in production.

---

# Deployment Isolation

A change to one microservice should normally affect only that microservice.

For example:

```text
User Service Change
       │
       ▼
User Image
       │
       ▼
User GitOps Configuration
       │
       ▼
shopsphere-user
       │
       ▼
User Deployment
```

It should not automatically cause:

```text
Auth Service
Product Service
Order Service
```

to be redeployed.

This independent deployment model is one of the primary benefits of the microservice architecture.

---

# Deployment Ordering

The normal order for an application release is:

```text
1. Validate application
        │
        ▼
2. Build image
        │
        ▼
3. Publish image
        │
        ▼
4. Update GitOps
        │
        ▼
5. Argo CD synchronization
        │
        ▼
6. Database migration
        │
        ▼
7. Application rollout
        │
        ▼
8. Health verification
```

Infrastructure dependencies must be established before the application that requires them.

For example:

```text
Namespace
    │
    ▼
Infrastructure
    │
    ▼
Database / Secrets
    │
    ▼
Application
```

---

# Production Deployment Checklist

Before a normal application deployment:

### Application

- [ ] Source code has passed required CI checks.
- [ ] Tests have passed.
- [ ] Application build has succeeded.
- [ ] Docker image has been built successfully.
- [ ] Docker image has been pushed successfully.

### Image

- [ ] Image uses an immutable version.
- [ ] Image exists in Docker Hub.
- [ ] Image version maps to the expected source revision.

### GitOps

- [ ] Correct microservice image version is updated.
- [ ] Correct production overlay is modified.
- [ ] No unrelated services were changed.
- [ ] GitOps change is committed.
- [ ] GitOps change has passed review where required.

### Database

- [ ] Required Prisma migration exists.
- [ ] Migration is compatible with the deployment.
- [ ] Migration Job uses the correct application image.

### Kubernetes

- [ ] Correct namespace is targeted.
- [ ] Deployment configuration is valid.
- [ ] Health probes are configured.
- [ ] Resource configuration is reasonable.
- [ ] Required Secrets and ConfigMaps are available.

### Verification

- [ ] Argo CD reports the expected synchronization state.
- [ ] Application Pods become ready.
- [ ] Migration Job completes successfully.
- [ ] Application health endpoint is healthy.
- [ ] API traffic reaches the new version.

---

# Configuration-Only Deployment Checklist

For a deployment that changes only Kubernetes configuration:

- [ ] Change is required.
- [ ] Correct resource is modified.
- [ ] Correct environment overlay is modified.
- [ ] No secrets are committed.
- [ ] Kustomize configuration validates successfully.
- [ ] Git diff has been reviewed.
- [ ] Change is committed.
- [ ] Argo CD synchronizes the change.
- [ ] Kubernetes resources become healthy.

---

# Rollback Checklist

Before or during rollback:

- [ ] Identify the last known-good version.
- [ ] Confirm the corresponding immutable image exists.
- [ ] Determine whether database schema changes were introduced.
- [ ] Determine whether the previous application version is compatible with the current database schema.
- [ ] Revert the GitOps image version.
- [ ] Commit the rollback.
- [ ] Allow Argo CD to synchronize.
- [ ] Verify application health.
- [ ] Verify API functionality.

Database compatibility must always be considered before rolling an application back.

An application rollback does not automatically roll back database migrations.

---

# Important Database Rollback Limitation

Application rollback and database rollback are different operations.

For example:

```text
Version A
    │
    ▼
Migration A
    │
    ▼
Version B
    │
    ▼
Migration B
```

Rolling the application back:

```text
Version B
    │
    ▼
Version A
```

does not automatically reverse:

```text
Migration B
```

Therefore, database migrations should preferably be designed to be backward compatible with the previous application version whenever practical.

Destructive schema changes require additional planning and should not be treated as ordinary image rollbacks.

---

# Future Deployment Environments

Only production is currently deployed.

The deployment structure is designed to support future environments.

Current:

```text
base/
└── ...

overlays/
└── production/
```

Future:

```text
base/
└── ...

overlays/
├── development/
├── staging/
└── production/
```

The deployment workflow can then be extended to promote application versions between environments according to the project's future requirements.

No additional promotion mechanism is required until those environments actually exist.

---

# CI/CD Responsibility Boundary

The final responsibility boundary is:

```text
GitHub Actions
│
├── Validate source
├── Test source
├── Build application
├── Build image
└── Publish image
```

```text
GitOps Repository
│
├── Define desired version
├── Define Kubernetes resources
├── Define environment configuration
└── Define deployment configuration
```

```text
Argo CD
│
├── Watch Git
├── Detect drift
├── Synchronize desired state
└── Report application health
```

```text
Kubernetes
│
├── Schedule Pods
├── Run containers
├── Manage Services
├── Perform rolling updates
└── Maintain workload state
```

Each component should remain focused on its responsibility.

---

# Deployment Philosophy

The deployment system is intentionally designed to be simple.

The goal is not:

```text
More automation
More controllers
More deployment tools
More infrastructure
```

The goal is:

```text
Predictable deployment
        +
Traceability
        +
Reproducibility
        +
Safe rollback
        +
Simple operations
```

When a new deployment technology or automation mechanism is proposed, it should solve a demonstrated problem rather than merely add another layer to the platform.

---

# Summary

ShopSphere uses a GitOps deployment model where application artifacts and deployment state are managed separately.

The complete lifecycle is:

```text
Developer
    │
    ▼
Source Repository
    │
    ▼
GitHub Actions
    │
    ├── Test
    ├── Build
    └── Publish
          │
          ▼
      Docker Hub
          │
          ▼
   GitOps Repository
          │
          ▼
        Argo CD
          │
          ▼
     Migration Job
          │
          ▼
 Kubernetes Deployment
          │
          ▼
     Health Checks
          │
          ▼
      Production
```

The key rule is:

```text
Build through CI.
Declare through Git.
Deploy through Argo CD.
Run through Kubernetes.
```

GitHub Actions creates the deployable artifact.

Docker Hub stores the artifact.

The GitOps repository declares which artifact should run.

Argo CD reconciles that declaration.

Kubernetes runs the application.

This separation keeps the deployment process traceable, reproducible, and understandable while allowing each ShopSphere microservice to evolve independently.
