# ShopSphere GitOps Conventions

This document defines the conventions and development rules for the **ShopSphere GitOps repository**.

These conventions apply to Kubernetes manifests, Kustomize configuration, Argo CD resources, infrastructure configuration, application deployment configuration, and future environments.

The goal is consistency.

A developer should be able to open any part of the repository and understand where a resource belongs, how it should be named, and how it should be changed.

---

# Guiding Principles

When working with the GitOps repository, follow these principles:

- Git is the source of truth.
- Kubernetes desired state belongs in Git.
- Application source code does not belong in this repository.
- Each microservice should remain independently deployable.
- Keep infrastructure configuration declarative.
- Prefer simple Kubernetes resources over unnecessary abstractions.
- Use immutable application image versions.
- Never use `latest` for production deployments.
- Keep production-specific configuration inside the production overlay.
- Do not commit plaintext secrets.
- Keep each microservice's database isolated.
- Avoid manually modifying production resources when the change should be represented in Git.
- Introduce new infrastructure only when it solves a real requirement.

---

# Repository Structure

The repository should follow this general structure:

```text
shopsphere-gitops/
│
├── bootstrap/
│   └── argocd/
│
├── argocd/
│   ├── projects/
│   └── applicationsets/
│
├── infrastructure/
│   ├── namespaces/
│   └── ingress/
│       └── nginx/
│
├── apps/
│   ├── auth-service/
│   ├── user-service/
│   ├── product-service/
│   └── order-service/
│
├── README.md
├── architecture.md
├── conventions.md
├── deployment.md
├── infrastructure.md
├── database.md
├── environments.md
└── operations.md
```

Each top-level directory has a clearly defined responsibility.

Do not place Kubernetes resources randomly at the repository root.

---

# Directory Responsibilities

## `bootstrap/`

Contains resources required to bootstrap the GitOps platform itself.

Example:

```text
bootstrap/
└── argocd/
    └── root-application.yaml
```

Bootstrap resources should be kept separate from normal application deployment resources.

---

## `argocd/`

Contains Argo CD configuration.

```text
argocd/
├── projects/
└── applicationsets/
```

This directory should contain resources that define how Argo CD manages ShopSphere applications.

It should not contain application Deployments or Services.

---

## `infrastructure/`

Contains infrastructure shared by multiple applications.

Examples:

```text
infrastructure/
├── namespaces/
└── ingress/
    └── nginx/
```

Examples of appropriate resources include:

- Namespaces
- NGINX configuration
- Shared infrastructure resources

Application-specific resources should remain under `apps/`.

---

## `apps/`

Contains deployment configuration for individual microservices.

Each service gets its own directory:

```text
apps/
├── auth-service/
├── user-service/
├── product-service/
└── order-service/
```

Do not combine multiple microservices into a single application directory.

---

# Application Directory Structure

Every microservice should follow the same structure.

```text
apps/
└── user-service/
    │
    ├── base/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── migration-job.yaml
    │   └── kustomization.yaml
    │
    └── overlays/
        └── production/
            ├── kustomization.yaml
            └── patch.yaml
```

The structure should remain consistent across all services.

For example:

```text
auth-service/
user-service/
product-service/
order-service/
```

should use the same general organization.

Consistency is more important than creating service-specific structures.

---

# Base and Overlay Rules

The repository uses the Kustomize base/overlay model.

```text
base/
    │
    ▼
Common configuration
    │
    ▼
production/
    │
    ▼
Production-specific configuration
```

The `base` should contain configuration that is common to the application.

The `production` overlay should contain values or configuration that are specific to production.

Do not place production-specific values in the base unless they genuinely apply to every future environment.

---

# Kustomization Files

Every Kustomize directory must contain a `kustomization.yaml`.

Example:

```text
base/
├── deployment.yaml
├── service.yaml
├── migration-job.yaml
└── kustomization.yaml
```

The `kustomization.yaml` should explicitly declare the resources and transformations used by that directory.

Avoid relying on implicit directory discovery.

---

# Kubernetes Resource Naming

Kubernetes resource names should use lowercase kebab-case.

Good:

```text
auth-service
user-service
product-service
order-service
```

Avoid:

```text
AuthService
user_service
USER-SERVICE
authService
```

Names should be descriptive and consistent across the repository.

---

# Resource Naming

Use the microservice name as the primary identifier.

For example:

```yaml
metadata:
  name: user-service
```

Related resources should use the same naming convention:

```text
user-service
user-service
user-service-migration
```

This makes resources easy to locate using Kubernetes commands.

---

# Labels

Kubernetes resources should use consistent labels.

At minimum, application resources should identify:

```text
app
app.kubernetes.io/name
app.kubernetes.io/part-of
```

For example:

```yaml
labels:
  app.kubernetes.io/name: user-service
  app.kubernetes.io/part-of: shopsphere
```

Labels should be used for identification and resource selection rather than embedding arbitrary information.

Where appropriate, standard Kubernetes recommended labels should be preferred.

---

# Namespaces

The current production environment uses:

```text
shopsphere-production
```

Application resources should explicitly belong to the intended namespace when the repository structure requires it.

Do not create a separate namespace for every microservice unless there is a concrete architectural requirement.

The initial architecture favors one namespace per environment.

---

# Deployments

Each microservice should have its own Kubernetes Deployment.

Example:

```text
auth-service
user-service
product-service
order-service
```

A Deployment should define:

- Container image
- Container port
- Replica configuration
- Resource requirements
- Environment configuration
- Secret references
- Health probes
- Appropriate security settings

Avoid combining multiple microservices into a single Deployment.

---

# Container Images

Production workloads must use immutable image versions.

Preferred:

```yaml
image: shopsphere/user-service:7f3a91c
```

Avoid:

```yaml
image: shopsphere/user-service:latest
```

Avoid mutable environment tags such as:

```text
production
stable
current
```

The image version should allow the running workload to be traced back to a specific source revision.

---

# Image Updates

Application image versions are normally updated by the CI pipeline.

The expected flow is:

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
GitOps image update
       │
       ▼
Argo CD
```

Developers should not manually change an image version unless there is a specific operational or deployment reason.

When manually changing an image version, the change must still be committed to Git.

---

# Never Use `latest`

The `latest` tag must not be used for production workloads.

This is prohibited:

```yaml
image: shopsphere/user-service:latest
```

A mutable tag makes it difficult to determine which version is actually running and makes rollback less predictable.

Use an immutable version instead.

---

# Kubernetes Services

Each microservice should expose an internal Kubernetes Service.

Example:

```text
user-service
```

The Service provides stable internal connectivity to the application's Pods.

Microservices should normally use internal Kubernetes networking rather than exposing their Pods directly.

---

# Public Exposure

Application Deployments and Services should not normally be directly exposed to the public internet.

Public traffic should enter through NGINX.

The intended flow is:

```text
Internet
    │
    ▼
NGINX
    │
    ▼
Kubernetes Service
    │
    ▼
Application Pods
```

Avoid creating a separate public LoadBalancer Service for every microservice.

---

# NGINX Conventions

NGINX is considered infrastructure.

Its configuration belongs under:

```text
infrastructure/
└── ingress/
    └── nginx/
```

Application directories should not contain NGINX controller configuration.

Routing should use the ShopSphere API structure.

For example:

```text
/api/v1/auth/*
/api/v1/users/*
/api/v1/products/*
/api/v1/orders/*
```

Each route should map to the appropriate Kubernetes Service.

---

# Database Ownership

Each microservice owns its own database.

The ownership model is:

```text
auth-service    → auth_db
user-service    → user_db
product-service → product_db
order-service   → order_db
```

A service must not directly connect to another service's database.

Do not introduce database credentials for another service into a service's configuration.

If information owned by another service is required, the service should communicate through an appropriate service interface.

---

# Database Connection Strings

Database connection strings must never be hardcoded in manifests.

Avoid:

```yaml
env:
  - name: DATABASE_URL
    value: postgresql://user:password@host/database
```

Sensitive values should be provided through Kubernetes Secrets or an external secret-management mechanism.

---

# ConfigMaps

Use ConfigMaps for non-sensitive configuration.

Examples:

```text
NODE_ENV
LOG_LEVEL
PORT
```

Do not store passwords, tokens, private keys, or database credentials in ConfigMaps.

---

# Secrets

Secrets must not be committed to Git in plaintext.

Avoid committing:

```yaml
stringData:
  DATABASE_URL: postgresql://...
  JWT_SECRET: ...
```

The GitOps repository should contain references or templates for secrets where appropriate, while the actual sensitive values should be supplied through the chosen secret-management mechanism.

---

# Database Migrations

Database migrations must be treated as deployment operations.

Do not normally execute migrations as part of application container startup.

Avoid:

```text
Container starts
    ↓
prisma migrate deploy
    ↓
Application starts
```

Prefer:

```text
Argo CD
    ↓
Migration Job
    ↓
prisma migrate deploy
    ↓
Application Deployment
```

This prevents multiple application replicas from unnecessarily attempting the same migration.

---

# Migration Jobs

Migration Jobs should clearly identify the service they belong to.

Example:

```text
user-service-migration
```

The migration Job must use the same application image or an image that contains the exact Prisma migration set required by that deployment.

Migration configuration should be maintained alongside the corresponding service.

---

# Argo CD Applications

Each microservice should have its own Argo CD Application.

Expected structure:

```text
Argo CD
│
├── shopsphere-auth
├── shopsphere-user
├── shopsphere-product
└── shopsphere-order
```

Do not combine all microservices into one Argo CD Application unless there is a specific architectural reason.

Independent Applications allow services to be synchronized independently.

---

# ApplicationSet

ApplicationSets may be used to generate the individual Argo CD Applications.

The ApplicationSet should remain focused on application discovery and generation.

Avoid putting complex deployment logic into ApplicationSet templates.

Deployment configuration should remain in the application's Kustomize resources.

---

# Argo CD Project

ShopSphere applications should belong to an appropriate Argo CD Project.

The Project should restrict:

- Allowed source repositories
- Allowed destination clusters
- Allowed namespaces
- Allowed resource types where practical

The purpose is to establish reasonable deployment boundaries without creating unnecessary Argo CD complexity.

---

# Argo CD Sync

Argo CD should be the system responsible for reconciling Git state with Kubernetes state.

The desired model is:

```text
Git change
    │
    ▼
Argo CD detects difference
    │
    ▼
Argo CD synchronization
    │
    ▼
Kubernetes desired state
```

Do not build a second deployment mechanism that independently modifies Kubernetes resources.

---

# Manual `kubectl` Changes

Production resources should not normally be modified manually using:

```bash
kubectl edit
kubectl patch
kubectl apply
```

for changes that should be persisted.

Instead:

```text
Change configuration
       │
       ▼
Commit to Git
       │
       ▼
Argo CD
       │
       ▼
Kubernetes
```

Manual changes may be necessary for emergency troubleshooting, but any permanent configuration change must eventually be represented in Git.

---

# Git Workflow

Infrastructure changes should normally follow:

```text
Create branch
     │
     ▼
Make GitOps change
     │
     ▼
Validate manifests
     │
     ▼
Commit
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
Argo CD reconciliation
```

Avoid directly pushing unreviewed production configuration changes to the default branch.

---

# Commit Messages

GitOps commit messages should clearly describe the change.

Good examples:

```text
feat: add user service deployment
feat: add production nginx ingress
chore: update user service image
fix: correct auth service readiness probe
chore: update production resource limits
```

Avoid vague messages:

```text
update
changes
fix stuff
deployment
```

A commit should make its purpose understandable from the Git history.

---

# Pull Requests

Pull requests should clearly explain:

- What changed
- Which service or infrastructure component changed
- Why the change was required
- Whether the change affects production
- Whether a database migration is involved
- Whether any manual operational step is required

For example:

```text
Service:
user-service

Change:
Update image from 7f3a91c to 81ab320.

Reason:
Deploy new user-service release.

Database migration:
Yes.

Manual action:
None.
```

---

# Environment Conventions

Only production exists initially.

Production configuration belongs under:

```text
overlays/
└── production/
```

Do not create empty environment directories simply for future use.

When a new environment becomes necessary, add it deliberately:

```text
overlays/
├── development/
├── staging/
└── production/
```

The base should remain shared whenever possible.

---

# Environment-Specific Configuration

Do not put environment-specific values into the base unless they are genuinely common.

For example:

```text
base
 └── application port

production
 └── production replica count
```

This keeps the base reusable.

Avoid copying the entire base configuration into every environment.

Use Kustomize overlays and patches to express differences.

---

# Resource Requests and Limits

Production Deployments should define appropriate CPU and memory requests.

Where practical, resource limits should also be defined.

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

The exact values should be based on application behavior rather than arbitrary large values.

Resource configuration should be documented or adjusted when actual workload characteristics become known.

---

# Health Probes

Production application Deployments should use Kubernetes health probes where the application provides suitable endpoints.

The application should distinguish between:

```text
Liveness
Readiness
```

A liveness probe determines whether the container should be restarted.

A readiness probe determines whether the application should receive traffic.

The probes should use the application's existing health endpoints rather than introducing duplicate health-check logic.

---

# Security Context

Application containers should follow reasonable Kubernetes security practices.

Where supported by the application image:

- Run as a non-root user.
- Use a read-only root filesystem where practical.
- Drop unnecessary Linux capabilities.
- Avoid privileged containers.
- Avoid host networking unless explicitly required.

Security settings should be introduced without making the deployment unnecessarily difficult to understand.

---

# Container Ports

Container ports should reflect the actual port exposed by the application.

Avoid arbitrary differences between:

```text
Container
Service
Ingress
```

unless there is a specific reason.

The normal flow should be easy to understand:

```text
NGINX
  ↓
Service Port
  ↓
Container Port
```

---

# Replicas

Replica counts should be defined through configuration rather than duplicated across multiple manifests.

The production overlay should be able to specify the desired number of replicas.

For example:

```yaml
spec:
  replicas: 2
```

The initial number should reflect actual project requirements and available cluster capacity.

Do not scale services arbitrarily simply to make the deployment appear more production-like.

---

# Resource Organization

Resources should be grouped by application ownership.

For example:

```text
apps/user-service/
```

should contain the resources required to deploy `user-service`.

Resources shared across applications belong under:

```text
infrastructure/
```

Argo CD resources belong under:

```text
argocd/
```

This makes ownership immediately visible from the filesystem.

---

# YAML Conventions

Kubernetes YAML should be:

- Valid YAML
- Consistently indented
- Explicit where clarity benefits the reader
- Free of unnecessary comments
- Organized logically
- Easy to review in pull requests

Avoid extremely compressed YAML or clever Kustomize constructs that make the deployment difficult to understand.

---

# Comments

Comments should explain **why**, not simply restate **what** the YAML does.

Good:

```yaml
# Run migrations before updating application Pods.
```

Avoid:

```yaml
# This is a Job.
kind: Job
```

The YAML itself already communicates the latter.

---

# File Naming

Kubernetes manifest files should use lowercase kebab-case.

Good:

```text
deployment.yaml
service.yaml
migration-job.yaml
config-map.yaml
network-policy.yaml
```

Avoid:

```text
Deployment.yaml
UserDeployment.yaml
user_service.yaml
```

Names should describe the resource's responsibility.

---

# One Resource Responsibility per File

Prefer one logical responsibility per file.

For example:

```text
deployment.yaml
service.yaml
migration-job.yaml
config-map.yaml
```

Do not create one enormous YAML file containing every resource in the entire application.

Small, focused files are easier to review and understand.

Multiple closely related resources may be combined when doing so genuinely improves readability.

---

# Public API of the Repository

Unlike application modules, the GitOps repository does not have a traditional programming API.

Its equivalent public interfaces are:

```text
Kustomize overlays
Argo CD Applications
Kubernetes resource definitions
```

These should remain predictable and stable.

Changing the directory structure should be treated as an architectural change because Argo CD and ApplicationSets may depend on it.

---

# Avoid Unnecessary Abstractions

Before introducing a new abstraction, ask:

```text
Does it solve a real problem?
        │
        ├── No → Do not introduce it.
        │
        └── Yes
             │
             ▼
Is there a simpler solution?
             │
             ├── Yes → Prefer the simpler solution.
             │
             └── No → Introduce it and document it.
```

Avoid adding infrastructure merely because it is common in large production platforms.

Examples of technologies that should not be introduced without a real requirement:

```text
Service Mesh
Complex Helm abstraction
Multiple GitOps controllers
Progressive delivery platform
Complex secret-management platform
Message broker
Additional ingress layers
Multiple Kubernetes clusters
```

The architecture should grow because the application needs it, not because the technology is available.

---

# Change Ownership

Use the following ownership model:

```text
Application Repository
    │
    ├── Application code
    ├── Prisma schema
    ├── Prisma migrations
    ├── Dockerfile
    └── CI workflow
```

```text
GitOps Repository
    │
    ├── Kubernetes resources
    ├── Deployment configuration
    ├── Kustomize configuration
    ├── Argo CD configuration
    ├── Ingress configuration
    └── Environment configuration
```

Neither repository should take responsibility for the other's primary concerns.

---

# Database Ownership Rules

The following rules are mandatory:

1. Every microservice owns its own database.

2. A service must never directly query another service's database.

3. Database credentials must be service-specific.

4. Prisma migrations remain owned by the corresponding application repository.

5. GitOps is responsible for running the migration as part of deployment.

6. Database migrations must be applied before the application version that requires them becomes active.

7. Database credentials must never be committed as plaintext.

---

# Deployment Safety Rules

Before changing a production deployment, verify:

- The Docker image exists.
- The image tag is immutable.
- The referenced Kubernetes resources are valid.
- The Kustomize overlay builds successfully.
- Any required database migration exists.
- Configuration and secrets are available.
- Health probes are appropriate.
- Resource requests and limits are reasonable.

A GitOps change should be treated as a production change even when the YAML modification is small.

---

# Validation Before Commit

Before committing Kubernetes changes, validate the configuration.

At minimum, verify:

```text
YAML syntax
      ↓
Kustomize build
      ↓
Kubernetes manifest validity
      ↓
Git diff review
```

The exact validation tooling may evolve as the repository grows, but invalid manifests should never intentionally be committed.

---

# Rollback Conventions

Rollback should normally be performed by reverting the GitOps state.

For an application image rollback:

```text
Current:
user-service:81ab320

Previous:
user-service:7f3a91c
```

The GitOps configuration should be changed back to the known-good version.

Then:

```text
Git
 ↓
Argo CD
 ↓
Kubernetes
```

This preserves the Git history and maintains Git as the source of truth.

---

# Emergency Changes

Emergency changes may occasionally require direct Kubernetes intervention.

If a manual production change is required:

1. Perform the minimum necessary intervention.
2. Record what was changed.
3. Determine the corresponding GitOps configuration.
4. Commit the permanent configuration to Git.
5. Allow Argo CD to reconcile the final desired state.

Manual intervention must not become the normal deployment mechanism.

---

# Documentation Rules

Architectural or operational changes should be reflected in the appropriate documentation.

Update documentation when a change affects:

- Repository structure
- Deployment architecture
- Database strategy
- Environment strategy
- Infrastructure components
- Argo CD behavior
- Operational procedures
- Security boundaries

Do not create a new document for every small change.

Update an existing document when the change belongs to an existing concern.

---

# Before Adding a New Resource

Before adding a Kubernetes resource, ask:

- Why is this resource required?
- Which application or infrastructure component owns it?
- Does it belong under `apps/`, `infrastructure/`, `argocd/`, or `bootstrap/`?
- Should it belong in the base or production overlay?
- Does it introduce a new dependency?
- Can an existing resource already solve the problem?
- Does the architecture documentation need to change?
- Does the operations documentation need to change?

If the resource introduces a significant architectural concept, document the decision before implementing it.

---

# Before Adding a New Technology

Before introducing a new technology, document:

```text
Problem
   ↓
Current limitation
   ↓
Proposed technology
   ↓
Why simpler alternatives are insufficient
   ↓
Operational impact
   ↓
Maintenance impact
```

The technology should only be introduced if the benefits justify the additional complexity.

---

# Convention Checklist

Before merging a GitOps change, verify:

### Repository

- [ ] Resource is in the correct directory.
- [ ] Naming follows repository conventions.
- [ ] File responsibility is clear.
- [ ] Documentation is updated if necessary.

### Kubernetes

- [ ] Resource names use lowercase kebab-case.
- [ ] Labels are consistent.
- [ ] Correct namespace is used.
- [ ] Resource ownership is clear.
- [ ] Health probes are configured where appropriate.
- [ ] Resource requests and limits are appropriate.

### Images

- [ ] Image uses an immutable version.
- [ ] `latest` is not used.
- [ ] The image exists in Docker Hub.
- [ ] The version can be traced to source code.

### Configuration

- [ ] Non-sensitive configuration uses ConfigMaps where appropriate.
- [ ] Sensitive configuration uses Secrets or the approved secret-management mechanism.
- [ ] No plaintext credentials are committed.

### Database

- [ ] The service accesses only its own database.
- [ ] Required Prisma migrations exist.
- [ ] Migration execution is handled separately from application startup.

### Argo CD

- [ ] The correct Argo CD Application owns the resource.
- [ ] The correct repository path is configured.
- [ ] The correct production overlay is referenced.

### Git

- [ ] The change is committed with a meaningful message.
- [ ] The Pull Request explains the change.
- [ ] The resulting Git diff has been reviewed.
- [ ] No unrelated changes are included.

---

# Summary

The purpose of these conventions is to keep the ShopSphere GitOps repository predictable.

The most important rules are:

```text
Git is the source of truth.

Applications and deployment configuration are separate.

Each microservice is independently deployable.

Each microservice owns its own database.

Production images use immutable versions.

Secrets are never committed as plaintext.

NGINX is the public entry point.

Kustomize manages environment configuration.

Argo CD manages Kubernetes reconciliation.

Permanent production changes are made through Git.

Infrastructure remains as simple as possible.
```

These conventions should be followed consistently across the repository.

When a new requirement conflicts with an existing convention, do not silently work around the convention. First determine whether the requirement represents a genuine architectural change. If it does, update the architecture and conventions documentation before introducing the new pattern.

The objective is not to create rigid rules for their own sake. The objective is to ensure that the repository remains understandable, reproducible, and maintainable as ShopSphere grows.
