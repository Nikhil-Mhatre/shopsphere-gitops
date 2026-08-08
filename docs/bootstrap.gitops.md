# ShopSphere GitOps Bootstrap Guide

This document is the implementation guide for building the ShopSphere GitOps repository and production deployment platform from scratch.

It is written for a DevOps engineer or platform engineer who is starting with an empty GitOps repository and needs to build the complete deployment system step by step.

This document is intentionally procedural.

The other documentation files explain what the architecture is and why specific decisions were made.

This document explains:

```text
What to build
     ↓
In what order to build it
     ↓
What to configure
     ↓
How to validate it
     ↓
When to move to the next phase
```

The implementation should follow the phases in order.

---

# 1. Target Architecture

The final production platform should look like:

```text
                         GitHub
                           │
                           │ Application Source
                           ▼
                  Application Repository
                           │
                           ▼
                    GitHub Actions
                           │
                    Build Docker Image
                           │
                           ▼
                       Docker Hub
                           │
                           │ Image Tag
                           ▼
                    GitOps Repository
                           │
                           ▼
                         Argo CD
                           │
                           ▼
                    Kubernetes / AKS
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
           NGINX        Services      Jobs
              │            │            │
              │            ▼            ▼
              │          Pods       DB Migrations
              │            │            │
              └────────────┼────────────┘
                           │
                           ▼
                    Managed PostgreSQL
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
           auth_db       user_db    product_db
                                         │
                                         ▼
                                      order_db
```

The GitOps repository is responsible for the Kubernetes desired state.

The application repositories remain responsible for application source code, Docker image creation, Prisma schemas, and Prisma migration definitions.

---

# 2. Implementation Philosophy

The implementation should follow five principles.

## 2.1 Build incrementally

Do not attempt to build the entire platform in one step.

Build one layer, validate it, and then move to the next.

```text
Infrastructure
     ↓
Kubernetes
     ↓
Argo CD
     ↓
NGINX
     ↓
One application
     ↓
Database
     ↓
Remaining applications
```

---

## 2.2 Start with one microservice

Although ShopSphere currently contains four microservices, the platform should initially deploy only one.

For example:

```text
user-service
```

Once the complete deployment path works:

```text
Git
 → GitHub Actions
 → Docker Hub
 → GitOps
 → Argo CD
 → Kubernetes
 → NGINX
 → PostgreSQL
```

the same pattern can be replicated for the remaining services.

This prevents four simultaneous sources of failure during the initial implementation.

---

## 2.3 Git remains the source of truth

The normal production workflow is:

```text
Git change
   ↓
Pull Request
   ↓
Review
   ↓
Merge
   ↓
Argo CD
   ↓
Kubernetes
```

Manual Kubernetes changes should not become the normal deployment mechanism.

---

## 2.4 Keep application and platform responsibilities separate

Application repositories:

```text
Source code
Dockerfile
Tests
Prisma schema
Prisma migrations
GitHub Actions
```

GitOps repository:

```text
Kubernetes manifests
Kustomize
Argo CD
NGINX
Environment configuration
Image versions
Deployment configuration
```

Managed infrastructure:

```text
AKS
PostgreSQL
Networking
DNS
Cloud resources
```

---

## 2.5 Do not implement future requirements prematurely

The initial platform has only:

```text
Production
```

Do not build complete development/staging infrastructure just because the repository is designed to support it later.

The architecture should be extensible, but the implementation should remain minimal.

---

# 3. Implementation Phases

The complete implementation is divided into these phases:

```text
Phase 0  — Define prerequisites
Phase 1  — Create GitOps repository
Phase 2  — Establish repository structure
Phase 3  — Provision Kubernetes infrastructure
Phase 4  — Configure production namespace
Phase 5  — Install Argo CD
Phase 6  — Configure Argo CD project
Phase 7  — Configure Kustomize base
Phase 8  — Deploy one microservice
Phase 9  — Configure PostgreSQL
Phase 10 — Configure database migrations
Phase 11 — Configure NGINX
Phase 12 — Connect CI to GitOps
Phase 13 — Deploy remaining services
Phase 14 — Add production hardening
Phase 15 — Validate the complete platform
Phase 16 — Document operations and handoff
```

Each phase should be completed before moving to the next.

---

# Phase 0 — Define Prerequisites

Before creating the GitOps repository, verify that the required external systems exist.

Required:

```text
GitHub
Docker Hub
Azure
AKS
Managed PostgreSQL
Domain / DNS
```

Development tools:

```text
Git
kubectl
Kustomize
Azure CLI
Docker
```

Optional but useful:

```text
Argo CD CLI
Helm
jq
```

Verify:

```bash
git --version
kubectl version --client
az version
docker --version
```

---

## Phase 0 Completion Criteria

Do not continue until:

- [ ] Azure access works.
- [ ] Docker Hub access works.
- [ ] GitHub repository access works.
- [ ] Kubernetes tooling is installed.
- [ ] DNS/domain ownership is understood.
- [ ] Managed PostgreSQL provisioning strategy is decided.

---

# Phase 1 — Create the GitOps Repository

Create a dedicated repository.

Example:

```text
shopsphere-gitops
```

Do not put GitOps configuration inside one of the application repositories.

The repository should have a single responsibility:

```text
Desired Kubernetes state for ShopSphere
```

---

# Phase 2 — Create the Repository Structure

Start with the following structure:

```text
shopsphere-gitops/
│
├── README.md
├── architecture.md
├── conventions.md
├── deployment.md
├── infrastructure.md
├── database.md
├── environment.md
├── operations.md
├── bootstrap.md
│
├── apps/
│   ├── auth-service/
│   ├── user-service/
│   ├── product-service/
│   └── order-service/
│
├── infrastructure/
│   ├── namespaces/
│   └── ingress/
│       └── nginx/
│
└── argocd/
    ├── project/
    ├── applications/
    └── applicationsets/
```

Do not populate every directory immediately.

Create the structure progressively as each component is implemented.

---

# Phase 3 — Provision Kubernetes Infrastructure

Create or provision the production AKS cluster.

The initial target is:

```text
Azure
 │
 └── AKS
      │
      └── Production
```

The cluster should be capable of running:

```text
Argo CD
NGINX
ShopSphere applications
```

At this stage, do not deploy ShopSphere applications.

First verify that Kubernetes itself works.

---

## Verify Cluster Access

Authenticate with Azure and configure Kubernetes access.

Then verify:

```bash
kubectl config current-context
```

and:

```bash
kubectl get nodes
```

Expected:

```text
NAME       STATUS   ROLES
node-...   Ready    ...
```

---

## Phase 3 Completion Criteria

- [ ] AKS cluster exists.
- [ ] Kubernetes API is reachable.
- [ ] Nodes are Ready.
- [ ] `kubectl` can communicate with the cluster.
- [ ] Production cluster context is clearly identifiable.

---

# Phase 4 — Create Production Namespace

Create:

```text
shopsphere-production
```

The namespace is the initial boundary for ShopSphere production workloads.

Create the namespace through GitOps rather than relying on a permanently manual resource.

Example location:

```text
infrastructure/
└── namespaces/
    └── production.yaml
```

The resulting structure should be:

```text
AKS
└── shopsphere-production
```

---

## Phase 4 Completion Criteria

- [ ] Namespace exists.
- [ ] Namespace manifest is committed to Git.
- [ ] Namespace naming follows conventions.
- [ ] No application workloads have been deployed yet.

---

# Phase 5 — Install Argo CD

Install Argo CD into the Kubernetes cluster.

Argo CD is the component responsible for continuously reconciling:

```text
Git
 ↓
Desired State

Kubernetes
 ↓
Actual State
```

The initial Argo CD installation is platform infrastructure.

After installation, verify that Argo CD components are healthy.

---

## Argo CD Responsibilities

Argo CD should:

- Read the GitOps repository.
- Render Kustomize configuration.
- Apply Kubernetes resources.
- Monitor resource health.
- Detect drift.
- Reconcile changes.

Argo CD should not build Docker images.

Argo CD should not own application source code.

Argo CD should not replace GitHub Actions.

---

## Phase 5 Completion Criteria

- [ ] Argo CD installed.
- [ ] Argo CD components healthy.
- [ ] Argo CD can access the GitOps repository.
- [ ] Argo CD administrative access is secured.
- [ ] Argo CD is ready to manage applications.

---

# Phase 6 — Configure Argo CD Project

Create a dedicated Argo CD Project for ShopSphere.

Conceptually:

```text
Argo CD
   │
   └── ShopSphere Project
          │
          └── ShopSphere Applications
```

The project should define:

```text
Allowed source repository
Allowed destination cluster
Allowed namespace
Allowed resource types
```

Keep the project restrictive enough to establish boundaries without creating unnecessary complexity.

---

## Phase 6 Completion Criteria

- [ ] ShopSphere Argo CD Project exists.
- [ ] GitOps repository is allowed.
- [ ] Production cluster is allowed.
- [ ] `shopsphere-production` namespace is allowed.
- [ ] Required resource types are allowed.

---

# Phase 7 — Create the Kustomize Base

Start with one application.

Use:

```text
user-service
```

Create:

```text
apps/
└── user-service/
    ├── base/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── kustomization.yaml
    │
    └── overlays/
        └── production/
            └── kustomization.yaml
```

The base should contain configuration common to all environments.

The production overlay should contain production-specific configuration.

---

# Phase 8 — Deploy One Microservice

The first application should prove the entire deployment model.

Start with:

```text
user-service
```

The Deployment should define:

```text
Container image
Container port
Replicas
Resources
Environment configuration
Secret references
Readiness probe
Liveness probe
Security settings
```

The Service should provide:

```text
user-service
```

as an internal Kubernetes endpoint.

---

# 9. Connect the Docker Image

The application repository already produces an image through GitHub Actions.

For example:

```text
shopsphere/user-service:81ab320
```

The GitOps repository should reference the immutable image tag.

Do not use:

```text
latest
```

Use a version that identifies the exact application artifact.

---

# Phase 8 Completion Criteria

The first service should satisfy:

```text
GitOps
   ↓
Argo CD
   ↓
Deployment
   ↓
Pod
   ↓
Service
```

Verify:

- [ ] Image pulls successfully.
- [ ] Pod starts.
- [ ] Pod becomes Ready.
- [ ] Deployment becomes Available.
- [ ] Service exists.
- [ ] Application health endpoint works internally.

Do not proceed until this works.

---

# Phase 9 — Configure PostgreSQL

Provision the managed PostgreSQL infrastructure.

The initial architecture should use one managed PostgreSQL platform with separate logical databases:

```text
PostgreSQL
│
├── auth_db
├── user_db
├── product_db
└── order_db
```

Initially, only create what is necessary for the service being deployed.

For `user-service`:

```text
user_db
```

---

# Database Access Boundary

Create service-specific credentials.

The intended model is:

```text
user-service
     │
     ▼
user_db
```

and not:

```text
user-service
     │
     ▼
shopsphere_db
```

or:

```text
user-service
     │
     ├── user_db
     ├── auth_db
     └── product_db
```

The service should only have access to its own database.

---

# Phase 9 Completion Criteria

- [ ] Managed PostgreSQL is available.
- [ ] `user_db` exists.
- [ ] User-service credentials exist.
- [ ] Network access from AKS is configured.
- [ ] PostgreSQL is not publicly exposed unnecessarily.
- [ ] Credentials are stored securely.

---

# Phase 10 — Configure Database Migrations

The application repository contains:

```text
prisma/schema.prisma
prisma/migrations/
```

The GitOps repository should provide the Kubernetes mechanism for executing migrations.

Create:

```text
apps/
└── user-service/
    └── base/
        └── migration-job.yaml
```

The migration Job should use the same application image containing the required Prisma migrations.

Conceptually:

```text
user-service image
       │
       ├── Application
       └── Prisma migrations
```

The Job executes:

```bash
prisma migrate deploy
```

---

# Migration Ordering

The intended deployment order is:

```text
Migration Job
     │
     ▼
Migration Successful
     │
     ▼
Application Deployment
```

Do not make every application Pod execute migrations during startup.

This prevents multiple replicas from independently attempting the same deployment migration.

---

# Migration Failure

If the migration fails:

```text
Migration Job
     │
     X
Migration Failed
```

the deployment must be treated as unsuccessful.

Inspect:

```text
Migration logs
Database connectivity
Database permissions
Existing schema
Migration compatibility
```

---

# Phase 10 Completion Criteria

- [ ] Migration Job exists.
- [ ] Job can connect to PostgreSQL.
- [ ] `prisma migrate deploy` succeeds.
- [ ] Database schema is correct.
- [ ] Application starts successfully after migration.
- [ ] Migration failure is visible through Argo CD/Kubernetes.

---

# Phase 11 — Configure NGINX

Install and configure the NGINX Ingress Controller.

The desired traffic flow is:

```text
Internet
   │
   ▼
Azure Load Balancer
   │
   ▼
NGINX
   │
   ▼
Kubernetes Service
   │
   ▼
Application Pod
```

NGINX should be the single public entry point for the ShopSphere APIs.

---

# API Routing

Configure path-based routing.

Example:

```text
/api/v1/auth/*
        ↓
auth-service

/api/v1/users/*
        ↓
user-service

/api/v1/products/*
        ↓
product-service

/api/v1/orders/*
        ↓
order-service
```

Initially, only configure the route for the service currently being deployed.

For example:

```text
/api/v1/users/*
        ↓
user-service
```

---

# TLS

Configure HTTPS for the public API endpoint.

The intended architecture is:

```text
Client
  │
  ▼
HTTPS
  │
  ▼
NGINX
  │
  ▼
Internal Service
```

The application itself does not need to terminate public TLS if NGINX is responsible for ingress termination.

---

# Phase 11 Completion Criteria

- [ ] NGINX is running.
- [ ] External load balancer exists.
- [ ] DNS points to the ingress endpoint.
- [ ] HTTP routing works.
- [ ] HTTPS works.
- [ ] `/api/v1/users/*` reaches user-service.
- [ ] Application health endpoint is reachable through the expected public route.

---

# Phase 12 — Connect GitHub Actions to GitOps

At this point the Kubernetes platform should already be capable of deploying the application.

Now connect the application CI pipeline.

The intended flow is:

```text
Application Repository
        │
        ▼
GitHub Actions
        │
        ├── Test
        ├── Build
        ├── Docker Build
        └── Docker Push
                │
                ▼
            Docker Hub
                │
                ▼
        GitOps Repository
                │
                ▼
              Argo CD
```

GitHub Actions should update the image reference in the GitOps repository.

---

# Image Update Strategy

Suppose the application image changes from:

```text
shopsphere/user-service:7f3a91c
```

to:

```text
shopsphere/user-service:81ab320
```

GitHub Actions updates the GitOps repository.

The GitOps change might be:

```text
user-service:7f3a91c
        ↓
user-service:81ab320
```

Argo CD detects the Git change and deploys the new image.

---

# Important GitOps Rule

GitHub Actions should not directly run:

```text
kubectl apply
```

against production as part of the normal deployment path.

The preferred flow is:

```text
GitHub Actions
       │
       ▼
GitOps Commit
       │
       ▼
Argo CD
       │
       ▼
Kubernetes
```

This keeps Git as the deployment source of truth.

---

# Phase 12 Completion Criteria

Perform a real end-to-end deployment.

Change the application.

Then verify:

```text
Source Change
    ↓
GitHub Actions
    ↓
Docker Image
    ↓
Docker Hub
    ↓
GitOps Commit
    ↓
Argo CD Sync
    ↓
Kubernetes Rollout
    ↓
API Verification
```

Do not proceed until this complete flow works.

---

# Phase 13 — Deploy Remaining Microservices

Once one service works end-to-end, replicate the established pattern.

Deploy:

```text
auth-service
product-service
order-service
```

Each application should have:

```text
base/
overlay/
Deployment
Service
Migration Job
```

where applicable.

The resulting structure becomes:

```text
apps/
│
├── auth-service/
│   ├── base/
│   └── overlays/
│       └── production/
│
├── user-service/
│   ├── base/
│   └── overlays/
│       └── production/
│
├── product-service/
│   ├── base/
│   └── overlays/
│       └── production/
│
└── order-service/
    ├── base/
    └── overlays/
        └── production/
```

---

# Database Setup for Remaining Services

Create:

```text
auth_db
user_db
product_db
order_db
```

and ensure:

```text
Auth Service    → auth_db
User Service    → user_db
Product Service → product_db
Order Service   → order_db
```

Each service gets independent credentials.

---

# NGINX Routes for Remaining Services

Add:

```text
/api/v1/auth/*
/api/v1/users/*
/api/v1/products/*
/api/v1/orders/*
```

Each route should map to exactly one Kubernetes Service.

---

# Phase 13 Completion Criteria

All four services should satisfy:

- [ ] Docker image exists.
- [ ] GitOps configuration exists.
- [ ] Argo CD Application exists.
- [ ] Deployment is healthy.
- [ ] Service is healthy.
- [ ] Database exists.
- [ ] Migration works.
- [ ] Health endpoint works.
- [ ] NGINX routing works.
- [ ] Public API is reachable.

---

# Phase 14 — Production Hardening

Only after the basic platform works should production hardening be introduced.

The initial hardening should cover:

```text
Resource requests
Resource limits
Readiness probes
Liveness probes
Security contexts
Non-root containers
Secret management
TLS
Network restrictions
Pod disruption considerations
```

Do not introduce every Kubernetes security feature simply because it exists.

Each addition should solve a concrete requirement.

---

# Secrets

Verify that production credentials are not stored as plaintext in Git.

The intended flow is:

```text
Secret Store
     │
     ▼
Kubernetes Secret
     │
     ▼
Application
```

Sensitive values include:

```text
DATABASE_URL
JWT_SECRET
API credentials
Private keys
```

Never commit these values.

---

# Container Security

Application Pods should preferably:

```text
Run as non-root
Use minimal images
Avoid privileged mode
Use read-only filesystem where practical
Drop unnecessary Linux capabilities
```

The exact security configuration should be compatible with the application runtime.

---

# Resource Management

Each application should define realistic resource requests.

Example:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi

  limits:
    cpu: 500m
    memory: 512Mi
```

These values are examples, not mandatory production values.

Tune them based on actual application behavior.

---

# Phase 14 Completion Criteria

- [ ] Production secrets are protected.
- [ ] Containers run with appropriate security settings.
- [ ] Resource requests exist.
- [ ] Health probes exist.
- [ ] HTTPS is configured.
- [ ] Public exposure is limited.
- [ ] Database access is restricted.
- [ ] No unnecessary privileged workloads exist.

---

# Phase 15 — Validate the Complete Platform

Perform a complete production simulation.

Start with an application change.

```text
Developer
   │
   ▼
GitHub
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
Migration
   │
   ▼
Kubernetes
   │
   ▼
NGINX
   │
   ▼
Application
   │
   ▼
PostgreSQL
```

---

# Complete Deployment Test

For one service:

```text
1. Modify application.
2. Commit application change.
3. Push to GitHub.
4. GitHub Actions runs.
5. Docker image is built.
6. Docker image is pushed.
7. GitOps image tag is updated.
8. GitOps change is merged.
9. Argo CD detects the change.
10. Migration executes.
11. Deployment rolls out.
12. Pods become Ready.
13. NGINX routes traffic.
14. API responds.
15. Database operations succeed.
```

Every step should be observable.

---

# Test Failure Scenarios

Do not only test successful deployments.

Test at least:

```text
Invalid image tag
Failed application startup
Failed readiness probe
Failed migration
Database unavailable
Incorrect database credentials
Invalid NGINX route
Argo CD OutOfSync
Pod CrashLoopBackOff
Deployment rollback
```

The purpose is to verify that the operational procedures actually work.

---

# Phase 16 — Documentation and Handoff

Before considering the platform complete, verify that the documentation reflects the actual implementation.

Required documents:

```text
README.md
architecture.md
conventions.md
deployment.md
infrastructure.md
database.md
environment.md
operations.md
bootstrap.md
```

Documentation should describe the system that actually exists.

Do not document planned infrastructure as though it were already deployed.

---

# 17. Final Repository Structure

The completed repository should approximately resemble:

```text
shopsphere-gitops/
│
├── README.md
├── architecture.md
├── conventions.md
├── deployment.md
├── infrastructure.md
├── database.md
├── environment.md
├── operations.md
├── bootstrap.md
│
├── apps/
│   │
│   ├── auth-service/
│   │   ├── base/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── migration-job.yaml
│   │   │   └── kustomization.yaml
│   │   │
│   │   └── overlays/
│   │       └── production/
│   │           └── kustomization.yaml
│   │
│   ├── user-service/
│   │   ├── base/
│   │   └── overlays/
│   │       └── production/
│   │
│   ├── product-service/
│   │   ├── base/
│   │   └── overlays/
│   │       └── production/
│   │
│   └── order-service/
│       ├── base/
│       └── overlays/
│           └── production/
│
├── infrastructure/
│   │
│   ├── namespaces/
│   │   └── production.yaml
│   │
│   └── ingress/
│       └── nginx/
│
└── argocd/
    │
    ├── project/
    │   └── shopsphere-project.yaml
    │
    ├── applications/
    │
    └── applicationsets/
```

The exact file names can evolve according to the repository conventions.

---

# 18. Argo CD Application Model

After all services are deployed, Argo CD should conceptually contain:

```text
Argo CD
│
└── ShopSphere
    │
    ├── shopsphere-auth-production
    ├── shopsphere-user-production
    ├── shopsphere-product-production
    └── shopsphere-order-production
```

Each Application points to its production overlay.

---

# 19. ApplicationSet Introduction

An ApplicationSet should be introduced only after the individual Argo CD Application pattern is proven.

First establish:

```text
One service
    ↓
One Argo CD Application
```

Then generalize:

```text
ApplicationSet
    ↓
Auth
User
Product
Order
```

This avoids hiding problems behind automation before the underlying pattern is understood.

---

# 20. Future Environment Expansion

Once development or staging becomes necessary, extend:

```text
overlays/
└── production/
```

to:

```text
overlays/
├── development/
├── staging/
└── production/
```

Do not redesign the repository.

The existing base remains shared.

---

# 21. Future Promotion Flow

Once multiple environments exist, the deployment flow can become:

```text
Application Repository
        │
        ▼
GitHub Actions
        │
        ▼
Immutable Docker Image
        │
        ▼
Development
        │
        ▼
Validation
        │
        ▼
Staging
        │
        ▼
Validation
        │
        ▼
Production
```

The same immutable image should be promoted rather than rebuilding the application for every environment.

---

# 22. Implementation Order Summary

If the entire implementation must be reduced to a checklist, follow this exact order:

```text
01. Create GitOps repository
        │
02. Create documentation
        │
03. Create repository structure
        │
04. Provision AKS
        │
05. Verify Kubernetes
        │
06. Create production namespace
        │
07. Install Argo CD
        │
08. Configure Argo CD Project
        │
09. Create first Kustomize base
        │
10. Deploy user-service
        │
11. Verify Pod + Service
        │
12. Provision managed PostgreSQL
        │
13. Create user_db
        │
14. Configure database secret
        │
15. Create migration Job
        │
16. Verify migration
        │
17. Configure NGINX
        │
18. Configure DNS / TLS
        │
19. Verify public API
        │
20. Connect GitHub Actions
        │
21. Test image promotion
        │
22. Test Argo CD deployment
        │
23. Deploy auth-service
        │
24. Deploy product-service
        │
25. Deploy order-service
        │
26. Configure remaining databases
        │
27. Configure remaining NGINX routes
        │
28. Add production hardening
        │
29. Test failure scenarios
        │
30. Test rollback
        │
31. Review documentation
        │
32. Production readiness review
```

---

# 23. Definition of Done

The GitOps implementation is considered complete when:

## Repository

- [ ] GitOps repository has a clear structure.
- [ ] Documentation is complete.
- [ ] Kustomize bases and production overlays exist.
- [ ] No production secrets are committed.

## Kubernetes

- [ ] AKS is operational.
- [ ] Production namespace exists.
- [ ] Application Deployments are healthy.
- [ ] Kubernetes Services are healthy.
- [ ] Health probes work.

## Argo CD

- [ ] Argo CD is operational.
- [ ] ShopSphere Project exists.
- [ ] Applications are synchronized.
- [ ] Applications report healthy status.
- [ ] Git is the source of truth.

## Applications

- [ ] All four services can be deployed independently.
- [ ] Images are immutable.
- [ ] GitHub Actions publishes images.
- [ ] GitOps image updates trigger deployments.

## Database

- [ ] PostgreSQL is managed externally.
- [ ] Each service has its own database.
- [ ] Each service has service-specific credentials.
- [ ] Database migrations execute successfully.
- [ ] Database health checks work.
- [ ] PostgreSQL is not publicly exposed.

## Networking

- [ ] NGINX is operational.
- [ ] DNS is configured.
- [ ] TLS is configured.
- [ ] API routes reach the correct service.
- [ ] Internal services are not unnecessarily exposed.

## Operations

- [ ] Logs can be inspected.
- [ ] Failed deployments can be diagnosed.
- [ ] Failed migrations can be diagnosed.
- [ ] Application rollback procedure is understood.
- [ ] Database rollback implications are understood.
- [ ] Manual emergency changes can be reconciled back into Git.

---

# 24. Recommended Implementation Strategy

The most important recommendation is to resist the temptation to build everything simultaneously.

Build this:

```text
GitOps
  ↓
Argo CD
  ↓
One Service
  ↓
One Database
  ↓
NGINX
```

first.

Then prove:

```text
Change
  ↓
CI
  ↓
Image
  ↓
GitOps
  ↓
Argo CD
  ↓
Migration
  ↓
Deployment
  ↓
API
```

Only after that should the pattern be replicated.

The resulting implementation should look like:

```text
                    ┌─────────────────────┐
                    │ Application Repos   │
                    └──────────┬──────────┘
                               │
                               ▼
                       GitHub Actions
                               │
                               ▼
                          Docker Hub
                               │
                               ▼
                     ┌──────────────────┐
                     │ GitOps Repository│
                     └────────┬─────────┘
                              │
                              ▼
                           Argo CD
                              │
                              ▼
                             AKS
                              │
                ┌─────────────┼─────────────┐
                │             │             │
                ▼             ▼             ▼
             NGINX        Applications    Jobs
                              │             │
                ┌─────────────┼─────────────┘
                │             │
                ▼             ▼
             Services      Migrations
                │             │
                └──────┬──────┘
                       ▼
                Managed PostgreSQL
```

---

# 25. Final Guiding Principle

The entire platform can be understood through four responsibilities:

```text
GitHub Actions
    → Build the artifact.

Docker Hub
    → Store the artifact.

GitOps + Argo CD
    → Define and reconcile the desired deployment.

Kubernetes
    → Run the artifact.
```

Database infrastructure has a separate responsibility:

```text
Managed PostgreSQL
    → Persist application data.
```

And NGINX has a focused networking responsibility:

```text
NGINX
    → Route external HTTP traffic to the correct service.
```

The platform engineer's job is to connect these components without unnecessarily coupling them.

The final implementation should therefore follow:

```text
Build once.
Store immutably.
Declare desired state in Git.
Reconcile through Argo CD.
Run on Kubernetes.
Persist data in managed PostgreSQL.
Expose APIs through NGINX.
Keep service boundaries intact.
```

This is the implementation path for the ShopSphere GitOps platform.
