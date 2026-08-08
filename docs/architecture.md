# ShopSphere GitOps Architecture

This document describes the architecture of the **ShopSphere GitOps platform**, including the relationship between the application repository, GitOps repository, GitHub Actions, Docker Hub, Argo CD, Kubernetes, NGINX, and PostgreSQL.

The architecture is intentionally designed to be **simple, production-ready, and understandable to developers who are new to Kubernetes and GitOps**.

The primary objective is to establish clear boundaries between application development and application deployment while keeping the infrastructure easy to maintain.

---

# Architecture Goals

The GitOps architecture is designed around the following goals:

- Keep application development separate from deployment configuration.
- Use Git as the source of truth for Kubernetes desired state.
- Deploy microservices independently.
- Make deployments reproducible.
- Provide traceable application versions.
- Keep database ownership isolated between microservices.
- Provide a single public API entry point.
- Support a production environment initially.
- Allow additional environments to be introduced later.
- Keep the infrastructure understandable for junior developers.
- Avoid unnecessary infrastructure and platform abstractions.

The architecture should provide enough production discipline without turning a hobby project into an unnecessarily complex platform.

---

# High-Level Architecture

The complete ShopSphere deployment architecture can be represented as follows:

```text
                         ┌──────────────────────┐
                         │      Developer       │
                         └──────────┬───────────┘
                                    │
                                    │ Git Push
                                    ▼
                    ┌──────────────────────────────┐
                    │   ShopSphere Source Repo     │
                    │                              │
                    │ Microservice Source Code     │
                    │ Tests                         │
                    │ Dockerfiles                   │
                    │ GitHub Actions                │
                    └──────────────┬───────────────┘
                                   │
                                   │ CI
                                   ▼
                    ┌──────────────────────────────┐
                    │       GitHub Actions         │
                    │                              │
                    │ Lint → Test → Build         │
                    │ Docker Build → Docker Push   │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                         ┌──────────────────┐
                         │    Docker Hub    │
                         │                  │
                         │ Versioned Images │
                         └────────┬─────────┘
                                  │
                                  │ Image Version
                                  ▼
                    ┌──────────────────────────────┐
                    │   ShopSphere GitOps Repo     │
                    │                              │
                    │ Kubernetes Desired State     │
                    │ Kustomize Configuration      │
                    │ Argo CD Configuration        │
                    │ Infrastructure Configuration │
                    └──────────────┬───────────────┘
                                   │
                                   │ Reconciliation
                                   ▼
                         ┌──────────────────┐
                         │     Argo CD      │
                         └────────┬─────────┘
                                  │
                                  ▼
                    ┌──────────────────────────────┐
                    │       Kubernetes / AKS       │
                    │                              │
                    │  ┌────────────────────────┐  │
                    │  │ NGINX Ingress          │  │
                    │  └───────────┬────────────┘  │
                    │              │               │
                    │     ┌────────┼────────┐      │
                    │     ▼        ▼        ▼      │
                    │   Auth     User    Product    │
                    │  Service  Service  Service    │
                    │     │        │        │       │
                    │     └────────┼────────┘       │
                    │              ▼                │
                    │          Order Service        │
                    └──────────────────────────────┘
                                  │
                                  ▼
                       PostgreSQL Infrastructure
                                  │
                  ┌───────────────┼────────────────┐
                  │               │                │
                  ▼               ▼                ▼
               auth_db         user_db        product_db
                                                   │
                                                   ▼
                                                order_db
```

---

# Repository Architecture

ShopSphere intentionally uses two repositories.

```text
┌───────────────────────────────┐
│ Application Repository         │
│                               │
│ "How is the application built?"│
└───────────────┬───────────────┘
                │
                │ Docker Image
                ▼
┌───────────────────────────────┐
│ GitOps Repository              │
│                               │
│ "What should be running?"     │
└───────────────┬───────────────┘
                │
                │ Desired State
                ▼
┌───────────────────────────────┐
│ Argo CD                       │
│                               │
│ "Make the cluster match Git." │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│ Kubernetes                    │
└───────────────────────────────┘
```

The separation is intentional.

The application repository should not contain production Kubernetes configuration.

The GitOps repository should not contain application source code.

This separation allows application developers and infrastructure configuration to evolve independently.

---

# Source Repository Responsibilities

The ShopSphere source repository contains the actual microservice implementations.

Its responsibilities include:

- Application source code
- TypeScript configuration
- Prisma schemas
- Prisma migrations
- Tests
- Dockerfiles
- GitHub Actions workflows
- Application-level configuration
- Building Docker images

When a microservice changes, GitHub Actions determines whether that service needs to be built and deployed.

The source repository produces an immutable application artifact:

```text
Source Code
     │
     ▼
Docker Image
     │
     ▼
Docker Hub
```

The source repository does not directly deploy the application to Kubernetes.

---

# GitHub Actions Responsibilities

GitHub Actions acts as the CI system.

Its responsibilities include:

```text
Code Change
     │
     ▼
Path Detection
     │
     ▼
Service-Specific Workflow
     │
     ├── Lint
     ├── Test
     ├── Build
     ├── Docker Build
     └── Docker Push
              │
              ▼
        Docker Hub
              │
              ▼
       Update GitOps
```

The workflow should only rebuild and publish a microservice when its relevant source code changes.

For example:

```text
auth-service changed
        │
        ▼
auth-service workflow
        │
        ▼
auth-service image
```

A change to `auth-service` should not unnecessarily rebuild the other three microservices.

---

# Docker Image Architecture

Every microservice produces its own Docker image.

```text
Docker Hub
│
├── shopsphere/auth-service
├── shopsphere/user-service
├── shopsphere/product-service
└── shopsphere/order-service
```

Images should use immutable identifiers.

For example:

```text
shopsphere/user-service:7f3a91c
```

The tag should identify the source revision that produced the image.

The GitOps repository then references the exact image version that Kubernetes should run.

Mutable tags such as `latest` should not be used for production deployments.

---

# GitOps Repository Responsibilities

The GitOps repository represents the desired state of the production Kubernetes environment.

It contains:

```text
Kubernetes manifests
Kustomize configuration
Argo CD configuration
Infrastructure configuration
Ingress configuration
Application image versions
Environment configuration
```

It does not contain:

```text
Application source code
Dockerfiles
Application tests
Application build logic
```

The repository should be declarative.

Instead of describing commands such as:

```text
Deploy user-service
```

the repository describes the desired state:

```text
A user-service Deployment should exist.
It should run image version X.
It should have N replicas.
It should expose port Y.
```

Argo CD is responsible for making the cluster match that declaration.

---

# Git as the Source of Truth

The GitOps repository is the authoritative source for the desired Kubernetes state.

The desired flow is:

```text
Git
 │
 ▼
Argo CD
 │
 ▼
Kubernetes
```

Changes should normally be made by modifying Git configuration rather than manually modifying production resources.

For example:

```text
GitOps Repository
       │
       ▼
kustomization.yaml
       │
       ▼
New image version
       │
       ▼
Argo CD detects change
       │
       ▼
Kubernetes reconciled
```

This provides:

- Auditability
- Reproducibility
- Version history
- Reviewable infrastructure changes
- Easier rollback

---

# Argo CD Architecture

Argo CD is the GitOps continuous delivery component.

Its responsibility is to continuously compare:

```text
Desired State
     │
     │ Git
     ▼
GitOps Repository

        versus

Actual State
     │
     ▼
Kubernetes Cluster
```

When the states differ, Argo CD can reconcile the cluster toward the desired state.

---

# Argo CD Application Model

Each ShopSphere microservice is represented as an independent Argo CD Application.

```text
Argo CD
│
├── shopsphere-auth
├── shopsphere-user
├── shopsphere-product
└── shopsphere-order
```

This provides independent deployment boundaries.

For example:

```text
user-service image changed
        │
        ▼
GitOps change
        │
        ▼
shopsphere-user
        │
        ▼
Argo CD sync
        │
        ▼
User Service updated
```

The other applications do not need to be redeployed.

---

# ApplicationSet

The repository may use an Argo CD ApplicationSet to generate the individual microservice Applications.

Conceptually:

```text
ApplicationSet
      │
      ├── auth-service
      ├── user-service
      ├── product-service
      └── order-service
```

This avoids manually maintaining four nearly identical Argo CD Application definitions.

The ApplicationSet should remain simple and should primarily provide application discovery and generation.

It should not become a second deployment system.

---

# Kubernetes Architecture

ShopSphere applications run inside a Kubernetes cluster.

The initial deployment contains:

```text
Kubernetes Cluster
│
├── Argo CD
│
├── NGINX Ingress Controller
│
└── shopsphere-production
    │
    ├── auth-service
    ├── user-service
    ├── product-service
    └── order-service
```

Each microservice consists primarily of:

```text
Deployment
Service
Configuration
Secret References
Migration Job
```

Additional resources should only be introduced when the application actually requires them.

---

# Namespace Architecture

The initial system uses one production namespace:

```text
shopsphere-production
```

The namespace contains the ShopSphere application workloads.

The architecture intentionally avoids creating a separate namespace for every microservice.

For four services, separate namespaces would introduce additional operational complexity without providing enough benefit.

When multiple environments are introduced later, environment-level namespaces can be used:

```text
shopsphere-development
shopsphere-staging
shopsphere-production
```

---

# Microservice Deployment Architecture

Each microservice is independently deployable.

For example:

```text
apps/user-service/
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

The same pattern is used for the other services.

The `base` contains reusable deployment configuration.

The environment overlay contains environment-specific configuration.

---

# Kubernetes Service Architecture

Each microservice receives an internal Kubernetes Service.

```text
auth-service
user-service
product-service
order-service
```

These Services provide stable internal DNS names and decouple clients from individual Pod addresses.

The microservice Pods should not normally be directly exposed to the public internet.

Public traffic enters through the ingress layer.

---

# NGINX Architecture

NGINX acts as the public HTTP routing layer.

The traffic flow is:

```text
Internet
   │
   ▼
External Load Balancer
   │
   ▼
NGINX Ingress
   │
   ├── /api/v1/auth/* ────────► auth-service
   │
   ├── /api/v1/users/* ───────► user-service
   │
   ├── /api/v1/products/* ───► product-service
   │
   └── /api/v1/orders/* ─────► order-service
```

This creates one public API entry point while keeping the individual microservices internal to the cluster.

NGINX is infrastructure rather than an application.

Therefore its configuration belongs under:

```text
infrastructure/
└── ingress/
    └── nginx/
```

---

# Why a Single Public Entry Point?

Without an ingress layer, each microservice could require its own externally accessible endpoint.

That would create:

```text
auth.example.com
user.example.com
product.example.com
order.example.com
```

Instead, ShopSphere uses a single API endpoint:

```text
api.shopsphere.example.com
```

with path-based routing:

```text
/api/v1/auth
/api/v1/users
/api/v1/products
/api/v1/orders
```

This provides a simpler external API surface and allows routing concerns to remain centralized.

---

# Database Architecture

ShopSphere follows the database-per-service principle.

The logical architecture is:

```text
                 PostgreSQL
                     │
       ┌─────────────┼─────────────┐
       │             │             │
       ▼             ▼             ▼
    auth_db       user_db      product_db
                                   │
                                   ▼
                                order_db
```

Each microservice owns its database.

```text
Auth Service
     │
     ▼
  auth_db

User Service
     │
     ▼
  user_db

Product Service
     │
     ▼
  product_db

Order Service
     │
     ▼
  order_db
```

The important architectural boundary is ownership.

A service must not directly query another service's database.

---

# Why Separate Databases?

Database isolation prevents services from becoming tightly coupled through shared database tables.

Without database ownership:

```text
Order Service
      │
      ├── user tables
      ├── product tables
      └── order tables
```

The Order Service would become dependent on the internal database structure of other services.

With database-per-service:

```text
Order Service
      │
      ▼
    order_db
```

If the Order Service requires information owned by another service, it should communicate with that service through an explicitly defined API or other service-to-service mechanism.

This preserves service boundaries.

---

# PostgreSQL Infrastructure

For the initial production architecture, PostgreSQL infrastructure is treated separately from the Kubernetes application workloads.

Conceptually:

```text
Managed PostgreSQL
│
├── auth_db
├── user_db
├── product_db
└── order_db
```

This avoids operating PostgreSQL as a StatefulSet inside the Kubernetes cluster.

The application platform therefore remains responsible primarily for:

```text
Kubernetes workloads
```

while the managed database platform is responsible for:

```text
PostgreSQL availability
Storage
Backups
Database infrastructure
```

This separation reduces operational complexity for the project.

---

# Database Migration Architecture

Each microservice owns its Prisma migrations.

The migration lifecycle is separate from application startup.

The preferred deployment flow is:

```text
Argo CD Sync
      │
      ▼
Migration Job
      │
      ▼
prisma migrate deploy
      │
      ├── Failure ──────► Deployment stops
      │
      └── Success
             │
             ▼
       Application Update
```

Migrations should not normally execute every time an application Pod starts.

This prevents multiple application replicas from attempting to perform the same migration concurrently.

---

# Configuration Architecture

Configuration is divided into non-sensitive and sensitive configuration.

Non-sensitive configuration can be represented using Kubernetes ConfigMaps.

Examples include:

```text
NODE_ENV
LOG_LEVEL
PORT
API configuration
```

Sensitive configuration should be supplied through Kubernetes Secrets or an external secret-management system.

Examples include:

```text
DATABASE_URL
JWT secrets
API credentials
private keys
```

The GitOps repository should not contain plaintext production secrets.

---

# Environment Architecture

Only production is implemented initially.

The repository uses the Kustomize model:

```text
base/
└── common resources

overlays/
└── production/
    └── production-specific configuration
```

The architecture is intentionally designed so that additional environments can later be introduced as overlays:

```text
base/
│
└── ...

overlays/
├── development/
├── staging/
└── production/
```

The base should remain environment-independent wherever practical.

---

# Deployment Architecture

A normal deployment follows this sequence:

```text
1. Developer changes service
           │
           ▼
2. Source repository
           │
           ▼
3. GitHub Actions
           │
           ├── Validate
           ├── Test
           ├── Build
           └── Publish image
                    │
                    ▼
4. Docker Hub
           │
           ▼
5. GitOps image version updated
           │
           ▼
6. Git commit
           │
           ▼
7. Argo CD detects desired-state change
           │
           ▼
8. Migration Job
           │
           ▼
9. Kubernetes Deployment update
           │
           ▼
10. Rolling update
```

This creates a clear separation between CI and CD.

---

# CI and CD Separation

The architecture deliberately separates Continuous Integration from Continuous Delivery.

```text
CI
│
├── Source code
├── Test
├── Build
├── Docker image
└── Docker Hub
```

versus:

```text
CD
│
├── GitOps repository
├── Argo CD
├── Kubernetes
└── Running application
```

GitHub Actions is responsible for producing and publishing the artifact.

Argo CD is responsible for deploying the declared artifact.

Neither system should take over the primary responsibility of the other.

---

# Deployment Traceability

A production deployment should be traceable from:

```text
Running Pod
     │
     ▼
Docker Image
     │
     ▼
Image Tag
     │
     ▼
Git Commit
     │
     ▼
Source Code Commit
```

For example:

```text
Source Commit
    7f3a91c
       │
       ▼
Docker Image
shopsphere/user-service:7f3a91c
       │
       ▼
GitOps Repository
image tag = 7f3a91c
       │
       ▼
Kubernetes
running image = 7f3a91c
```

This makes it possible to determine exactly which source revision is running in production.

---

# Rollback Architecture

Because image versions are immutable and deployment state is stored in Git, rollback can be performed by reverting the GitOps configuration to a known working image version.

For example:

```text
Current
user-service:7f3a91c
```

can be changed back to:

```text
Previous
user-service:42ab821
```

The desired state is then committed to Git.

Argo CD detects the change and reconciles Kubernetes back to the previous version.

The exact operational rollback procedure is documented in `operations.md`.

---

# Failure Boundaries

The architecture intentionally creates clear failure boundaries.

## CI Failure

```text
Source Code
    │
    ▼
GitHub Actions
    │
    X
```

If CI fails, no new production image should be published or deployed.

---

## Image Publishing Failure

```text
GitHub Actions
      │
      ▼
Docker Hub
      │
      X
```

If the image cannot be published, the GitOps desired state should not be advanced to an unavailable image.

---

## Migration Failure

```text
Argo CD
   │
   ▼
Migration Job
   │
   X
```

If a database migration fails, the application deployment should not proceed as though the migration succeeded.

---

## Application Deployment Failure

```text
Kubernetes
     │
     ▼
Application Deployment
     │
     X
```

Argo CD exposes the synchronization and health state so that the failure can be investigated.

---

# Security Boundaries

The architecture separates public, internal, and sensitive resources.

```text
Internet
   │
   ▼
NGINX
   │
   ▼
Internal Kubernetes Services
   │
   ▼
Application Pods
   │
   ▼
Service-Owned Database
```

The intended boundaries are:

- NGINX is the public entry point.
- Application Services are internal.
- Pods are not directly exposed publicly.
- Each service accesses only its own database.
- Database credentials are treated as secrets.
- Git contains configuration, not plaintext credentials.

---

# Why Kustomize?

Kustomize is used to manage Kubernetes configuration because the current project has a relatively small number of services and environments.

The basic model is straightforward:

```text
Base
 │
 ├── Deployment
 ├── Service
 ├── Migration Job
 └── Common configuration
        │
        ▼
Production Overlay
        │
        ▼
Production Resources
```

This avoids introducing a large templating system when the current requirements do not justify one.

If the project's deployment requirements become significantly more complex, the architecture can be reconsidered.

The current design intentionally favors readability.

---

# Why Not Deploy Everything as One Argo CD Application?

The four microservices are independently deployable.

Therefore:

```text
One Application
     │
     ├── Auth
     ├── User
     ├── Product
     └── Order
```

would unnecessarily couple their deployment lifecycles.

Instead:

```text
Argo CD
│
├── Auth Application
├── User Application
├── Product Application
└── Order Application
```

Each service can then be synchronized independently.

This also makes deployment status easier to understand.

---

# Why Not Create One Namespace Per Microservice?

The project currently has only four services.

Using:

```text
auth-namespace
user-namespace
product-namespace
order-namespace
```

would add additional Kubernetes management overhead.

A single production namespace:

```text
shopsphere-production
```

is sufficient for the current project.

Environment isolation provides more value than service-level namespace isolation at this stage.

---

# Why Not Run PostgreSQL Inside Kubernetes?

Running PostgreSQL inside Kubernetes is possible, but it would introduce responsibilities such as:

- Persistent storage management
- Backup management
- Recovery procedures
- PostgreSQL upgrades
- Failover
- Stateful workload management

For this project, those responsibilities do not provide enough value to justify the additional complexity.

A managed PostgreSQL platform keeps the Kubernetes architecture focused on application workloads.

---

# Why Not Run Database Migrations During Container Startup?

Consider a Deployment with three replicas:

```text
Pod 1 → prisma migrate deploy
Pod 2 → prisma migrate deploy
Pod 3 → prisma migrate deploy
```

This creates unnecessary migration concurrency.

Instead:

```text
Migration Job
      │
      ▼
Database
      │
      ▼
Application Deployment
```

The migration is a deployment concern rather than an application-container startup concern.

---

# Scalability Path

The initial architecture is intentionally small, but it has a clear growth path.

## Current

```text
Production
    │
    ▼
One Kubernetes Cluster
    │
    ├── Auth
    ├── User
    ├── Product
    └── Order
```

## Future Environments

```text
Development
Staging
Production
```

Each environment can use its own Kustomize overlay and Kubernetes namespace.

---

# Future Infrastructure Growth

The architecture can evolve when actual requirements justify additional components.

Potential future additions include:

```text
External secret management
Observability platform
Centralized metrics
Distributed tracing
Message broker
Additional Kubernetes clusters
Automated progressive delivery
Read replicas
Database scaling
```

These technologies are intentionally not part of the initial architecture.

A new component should be introduced only when it solves a demonstrated problem.

---

# Architectural Principles

The ShopSphere GitOps architecture follows these principles:

1. **Git is the source of truth.**

2. **Application source and deployment configuration are separated.**

3. **Each microservice is independently deployable.**

4. **Each microservice owns its own database.**

5. **Services do not directly access another service's database.**

6. **Production traffic enters through a single ingress layer.**

7. **Internal services are not directly exposed to the internet.**

8. **Application images use immutable versions.**

9. **Database migrations are separated from application startup.**

10. **Environment-specific configuration belongs in overlays.**

11. **Argo CD is responsible for Kubernetes reconciliation.**

12. **Infrastructure should remain as simple as the requirements allow.**

13. **New technologies should be introduced only when they provide meaningful value.**

14. **The architecture should remain understandable to junior developers.**

---

# Architectural Decision Summary

The major architectural decisions are summarized below.

| Decision                 | Choice                              | Reason                                            |
| ------------------------ | ----------------------------------- | ------------------------------------------------- |
| Source control           | GitHub                              | Existing source-control platform                  |
| CI                       | GitHub Actions                      | Already integrated with source repository         |
| Container registry       | Docker Hub                          | Stores versioned application images               |
| CD / GitOps              | Argo CD                             | Reconciles Git desired state with Kubernetes      |
| Kubernetes               | AKS                                 | Target production Kubernetes platform             |
| Kubernetes configuration | Kustomize                           | Simple base/overlay model                         |
| Ingress                  | NGINX                               | Centralized HTTP routing                          |
| Application deployment   | One Argo CD Application per service | Independent deployments                           |
| Namespace                | One production namespace            | Simple for four services                          |
| Database                 | PostgreSQL                          | Application database                              |
| Database ownership       | One database per service            | Service isolation                                 |
| ORM / migrations         | Prisma                              | Application repository responsibility             |
| Database deployment      | Managed PostgreSQL                  | Avoid operating Stateful PostgreSQL in Kubernetes |
| Image versioning         | Immutable tags                      | Traceability and rollback                         |
| Environment              | Production initially                | Avoid unnecessary complexity                      |
| Future environments      | Kustomize overlays                  | Clear expansion path                              |

---

# Summary

The ShopSphere GitOps architecture separates application development, artifact creation, deployment configuration, and Kubernetes reconciliation into clear responsibilities.

The complete flow is:

```text
Application Repository
        │
        │ GitHub Actions
        ▼
    Docker Image
        │
        ▼
     Docker Hub
        │
        ▼
   GitOps Repository
        │
        │ Desired State
        ▼
      Argo CD
        │
        ▼
 Kubernetes / AKS
        │
        ├── NGINX
        │
        ├── Auth Service ─────► auth_db
        │
        ├── User Service ─────► user_db
        │
        ├── Product Service ──► product_db
        │
        └── Order Service ────► order_db
```

The architecture intentionally avoids unnecessary layers and technologies.

The primary objective is not to build the most sophisticated Kubernetes platform possible. It is to establish a deployment architecture that is:

- Declarative
- Reproducible
- Traceable
- Independently deployable
- Secure by default
- Easy to operate
- Easy to extend
- Easy for beginners to understand

The architecture should evolve only when ShopSphere's actual requirements require it.
