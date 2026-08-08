# ShopSphere GitOps

The **ShopSphere GitOps repository** contains the Kubernetes configuration and deployment definitions required to run ShopSphere in production.

This repository is the **source of truth for the desired state of the ShopSphere production environment**.

Application source code, tests, Dockerfiles, and CI pipelines remain in the ShopSphere source repository. This repository is responsible for describing **which application versions should run, how they should run, and what infrastructure is required to run them**.

Argo CD continuously watches this repository and reconciles the desired state defined here with the Kubernetes cluster.

---

## Purpose

The purpose of this repository is to provide a simple, predictable, and production-ready GitOps workflow for ShopSphere.

The repository manages:

- Kubernetes workloads
- Microservice deployments
- Kubernetes Services
- Production configuration
- NGINX ingress routing
- Argo CD applications
- Database migration Jobs
- Environment-specific configuration
- Application image versions
- Infrastructure configuration required by ShopSphere

The repository does **not** contain application source code.

---

## GitOps Model

ShopSphere follows a pull-based GitOps model.

The application repository builds and publishes Docker images. GitHub Actions then updates the desired image version in this repository.

Argo CD watches this repository and applies the declared state to Kubernetes.

```text
ShopSphere Source Repository
            │
            │ GitHub Actions
            ▼
       Build & Test
            │
            ▼
       Docker Image
            │
            ▼
         Docker Hub
            │
            │ Update image tag
            ▼
   ShopSphere GitOps Repository
            │
            │ Argo CD
            ▼
      Kubernetes / AKS
            │
            ▼
    Running Applications
```

Git therefore becomes the source of truth for the Kubernetes deployment state.

---

## Repository Responsibilities

The ShopSphere system uses two separate repositories with different responsibilities.

### Application Repository

The application repository is responsible for:

- Microservice source code
- TypeScript code
- Prisma schema and migrations
- Unit and integration tests
- Dockerfiles
- GitHub Actions CI workflows
- Building Docker images
- Publishing Docker images to Docker Hub

Its responsibility ends when a versioned Docker image has been published and the GitOps repository has been updated.

### GitOps Repository

This repository is responsible for:

- Kubernetes manifests
- Kustomize configuration
- Argo CD configuration
- Application deployment configuration
- Production configuration
- Application image versions
- NGINX routing
- Database migration Jobs
- Infrastructure configuration

It does not build application artifacts.

---

## Deployment Flow

A normal ShopSphere deployment follows this process:

```text
Developer
    │
    ▼
Changes Microservice Code
    │
    ▼
Pushes to Source Repository
    │
    ▼
GitHub Actions
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
GitHub Actions updates
GitOps image version
            │
            ▼
   GitOps Repository
            │
            ▼
         Argo CD
            │
            ▼
   Kubernetes Cluster
            │
            ▼
Database Migration Job
            │
            ▼
 Kubernetes Deployment
            │
            ▼
      Rolling Update
```

Only the microservice affected by the source-code change should normally be updated.

For example, a change to `user-service` should result in a new `user-service` image and an update to the corresponding GitOps configuration.

---

## Current Production Architecture

ShopSphere currently targets a single **production environment**.

The Kubernetes architecture is intentionally simple.

```text
                         Internet
                            │
                            ▼
                  Azure Load Balancer
                            │
                            ▼
                  NGINX Ingress Controller
                            │
             ┌──────────────┼──────────────┐
             │              │              │
             ▼              ▼              ▼
        Auth Service    User Service   Product Service
             │              │              │
             ▼              ▼              ▼
          auth_db         user_db       product_db

                            │
                            ▼
                       Order Service
                            │
                            ▼
                         order_db
```

The services run inside Kubernetes and communicate through internal Kubernetes Services.

Only the ingress layer is publicly exposed.

---

## Microservices

The current ShopSphere architecture contains four independently deployable microservices.

```text
apps/
├── auth-service/
├── user-service/
├── product-service/
└── order-service/
```

Each microservice has:

- Its own Docker image
- Its own Kubernetes Deployment
- Its own Kubernetes Service
- Its own database
- Its own Prisma migrations
- Its own Argo CD Application

A microservice must not directly access another microservice's database.

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

Communication between microservices should happen through their APIs or other explicitly designed service-to-service mechanisms.

---

## Database Strategy

ShopSphere follows the **database-per-service** principle.

The project uses PostgreSQL, with each microservice owning its own logical database.

The initial production model is:

```text
PostgreSQL
│
├── auth_db
├── user_db
├── product_db
└── order_db
```

The PostgreSQL infrastructure is separate from the Kubernetes application workloads.

Each microservice receives credentials for its own database only.

The GitOps repository is responsible for deploying database migration Jobs, while the application repository owns the Prisma schema and migration files.

Database migrations are executed separately from application container startup so that multiple application replicas do not attempt to perform the same migration.

---

## NGINX Routing

NGINX provides the public HTTP entry point for ShopSphere.

External requests are routed to the appropriate internal Kubernetes Service.

The intended routing model is:

```text
/api/v1/auth/*       → auth-service
/api/v1/users/*      → user-service
/api/v1/products/*   → product-service
/api/v1/orders/*     → order-service
```

The microservices themselves should not be exposed directly to the public internet.

NGINX is treated as infrastructure and is therefore maintained under:

```text
infrastructure/
└── ingress/
    └── nginx/
```

---

## Argo CD

Argo CD is responsible for continuously reconciling the Kubernetes cluster with the desired state stored in this repository.

Conceptually:

```text
GitOps Repository
       │
       ▼
     Argo CD
       │
       ▼
Desired Kubernetes State
       │
       ▼
 Kubernetes Cluster
```

Each ShopSphere microservice is represented as an independent Argo CD Application.

```text
Argo CD
│
├── shopsphere-auth
├── shopsphere-user
├── shopsphere-product
└── shopsphere-order
```

This allows each microservice to be deployed and synchronized independently.

---

## Kubernetes Namespace

The current project uses a single production namespace for ShopSphere workloads.

```text
shopsphere-production
```

The namespace contains the ShopSphere application workloads and their supporting Kubernetes resources.

A separate namespace can be introduced for additional environments later.

For example:

```text
shopsphere-development
shopsphere-staging
shopsphere-production
```

The current repository intentionally implements only production.

---

## Repository Structure

The repository is organized around three major responsibilities:

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

### `bootstrap/`

Contains the initial resources required to bootstrap Argo CD and connect it to the GitOps repository.

### `argocd/`

Contains Argo CD-specific resources such as:

- Argo CD Projects
- ApplicationSets
- Application configuration

### `infrastructure/`

Contains infrastructure shared by ShopSphere applications.

Examples include:

- Kubernetes namespaces
- NGINX ingress configuration
- Other shared infrastructure introduced later

### `apps/`

Contains deployment configuration for individual ShopSphere microservices.

Each application follows the same general structure:

```text
apps/
└── user-service/
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

The `base` directory contains reusable application configuration.

The `production` overlay contains production-specific configuration.

This structure allows additional environments to be introduced later without redesigning the application manifests.

---

## Kustomize

The repository uses **Kustomize** to organize Kubernetes configuration.

The basic model is:

```text
Base
 │
 ├── Deployment
 ├── Service
 ├── Migration Job
 └── Other common resources
        │
        ▼
Production Overlay
        │
        ▼
Production Kubernetes Resources
```

The base should contain configuration that is common to an application.

Environment-specific values belong in the corresponding overlay.

This keeps the current production-only implementation simple while leaving a clear path toward additional environments.

---

## Container Images

Application images are built by GitHub Actions and published to Docker Hub.

Images should use immutable version identifiers rather than `latest`.

For example:

```text
shopsphere/user-service:7f3a91c
```

where the tag identifies the source revision that produced the image.

The GitOps repository records the image version that should be deployed.

This makes deployments traceable and allows a previous image version to be restored when necessary.

---

## Secrets

Secrets such as database credentials must not be committed directly to the Git repository.

The GitOps configuration should reference the appropriate secret-management mechanism.

The exact production secret-management implementation is documented separately in the infrastructure and deployment documentation.

The general principle is:

```text
Secret Source
     │
     ▼
Kubernetes Secret
     │
     ▼
Application Pod
```

Sensitive values should never be embedded in ordinary ConfigMaps or committed as plaintext configuration.

---

## Environments

Only production is currently implemented.

The repository is intentionally structured to support additional environments later.

Current:

```text
overlays/
└── production/
```

Future:

```text
overlays/
├── development/
├── staging/
└── production/
```

The base configuration should remain environment-independent wherever practical.

Environment-specific configuration belongs inside the appropriate overlay.

No additional environment should be introduced until there is a real requirement for it.

---

## GitOps Principles

The repository follows several fundamental principles.

### Git is the Source of Truth

The desired Kubernetes state must be represented in Git.

### Changes Are Made Through Pull Requests

Production configuration should normally be changed through Git rather than manually modifying resources inside the cluster.

### Argo CD Reconciles the Cluster

Argo CD is responsible for applying the desired state to Kubernetes.

### Application and Deployment Are Separate

The application repository builds artifacts.

The GitOps repository defines how those artifacts are deployed.

### Images Are Immutable

Deployments should reference specific image versions rather than mutable tags such as `latest`.

### Services Own Their Databases

Each microservice owns its own database and must not directly access another service's database.

### Keep the Platform Simple

Infrastructure should only be introduced when it solves a real problem.

The repository intentionally avoids unnecessary platform components and abstractions.

---

## Documentation

The repository contains additional documentation for specific concerns.

| Document            | Purpose                                                                      |
| ------------------- | ---------------------------------------------------------------------------- |
| `architecture.md`   | Explains the architecture and the reasoning behind major design decisions.   |
| `conventions.md`    | Defines GitOps, Kubernetes, naming, and repository conventions.              |
| `deployment.md`     | Explains how application changes move from source code to production.        |
| `infrastructure.md` | Documents Kubernetes and supporting infrastructure.                          |
| `database.md`       | Documents the database-per-service strategy and database migrations.         |
| `environments.md`   | Explains the current production environment and future environment strategy. |
| `operations.md`     | Provides troubleshooting and operational procedures.                         |

The README should remain an entry point rather than becoming a detailed Kubernetes manual.

---

## Design Philosophy

ShopSphere is a hobby project, so the GitOps architecture intentionally favors **clarity over unnecessary complexity**.

The infrastructure should be production-ready enough to demonstrate sound engineering practices while remaining understandable to developers who are new to Kubernetes and GitOps.

Before introducing a new technology or abstraction, ask:

```text
Does the project currently need it?
            │
            ├── No ──→ Do not introduce it.
            │
            └── Yes
                 │
                 ▼
        Is there a simpler solution?
                 │
                 ├── Yes ──→ Prefer the simpler solution.
                 │
                 └── No ──→ Introduce it with documentation.
```

The goal is not to demonstrate how many DevOps technologies can be used.

The goal is to create a deployment platform that is understandable, reproducible, maintainable, and capable of growing with ShopSphere.

---

## Summary

The ShopSphere GitOps repository is the source of truth for the production Kubernetes environment.

The overall deployment model is:

```text
Application Repository
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
        ├── NGINX
        ├── Auth Service
        ├── User Service
        ├── Product Service
        └── Order Service
```

The architecture intentionally separates application development from deployment configuration while keeping the deployment process transparent.

The GitOps repository defines **what should be running**.

Argo CD ensures **that desired state is running in Kubernetes**.

The application repository defines **how the application is built**.

Together, these repositories provide the foundation for a simple and production-ready ShopSphere deployment platform.
