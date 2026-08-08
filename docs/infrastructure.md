# ShopSphere Infrastructure

This document describes the infrastructure required to run ShopSphere in the production Kubernetes environment.

The infrastructure is intentionally kept simple. The goal is to provide the components required to run, expose, and manage the ShopSphere microservices without introducing unnecessary platform complexity.

The current infrastructure consists primarily of:

```text
Azure
│
├── AKS
│   │
│   ├── Argo CD
│   ├── NGINX Ingress Controller
│   └── ShopSphere workloads
│
└── Managed PostgreSQL
    │
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db
```

---

# Infrastructure Goals

The infrastructure should provide:

- A Kubernetes platform for running ShopSphere.
- GitOps-based application deployment.
- A single public API entry point.
- Internal networking between microservices.
- Independent application deployments.
- Independent database ownership.
- Secure configuration and secret handling.
- Health-based application routing.
- A clear path toward additional environments.
- Minimal operational complexity.

The infrastructure should remain understandable to developers who are new to Kubernetes and GitOps.

---

# Infrastructure Architecture

The production infrastructure can be represented as:

```text
                         Internet
                            │
                            ▼
                  Azure Load Balancer
                            │
                            ▼
                 NGINX Ingress Controller
                            │
                            ▼
                 shopsphere-production
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

Argo CD operates alongside the workloads and manages their desired state:

```text
GitOps Repository
       │
       ▼
     Argo CD
       │
       ▼
Kubernetes / AKS
```

PostgreSQL is treated as external managed infrastructure rather than as a Kubernetes workload.

---

# Infrastructure Components

The production platform consists of the following major components:

| Component                | Responsibility                                |
| ------------------------ | --------------------------------------------- |
| AKS                      | Kubernetes runtime platform                   |
| Argo CD                  | GitOps continuous delivery and reconciliation |
| NGINX Ingress Controller | Public HTTP routing                           |
| Kubernetes Namespace     | Logical isolation for ShopSphere workloads    |
| Kubernetes Deployments   | Run microservice Pods                         |
| Kubernetes Services      | Internal service discovery and networking     |
| ConfigMaps               | Non-sensitive application configuration       |
| Secrets                  | Sensitive application configuration           |
| Managed PostgreSQL       | Persistent application databases              |
| Database Migration Jobs  | Execute Prisma migrations during deployment   |

Each component has a defined responsibility.

---

# Azure Kubernetes Service

ShopSphere uses **Azure Kubernetes Service (AKS)** as the production Kubernetes platform.

AKS provides the Kubernetes control plane and worker infrastructure required to run the application workloads.

Conceptually:

```text
AKS
│
├── Kubernetes Control Plane
│
└── Worker Nodes
    │
    ├── Argo CD
    ├── NGINX
    └── ShopSphere Applications
```

The GitOps repository does not manage application source code or build Docker images.

Its responsibility begins at the Kubernetes deployment layer.

---

# Kubernetes Cluster Responsibility

The Kubernetes cluster is responsible for running ShopSphere workloads.

Kubernetes handles:

- Pod scheduling
- Container execution
- Service discovery
- Rolling updates
- Replica management
- Health-based workload management
- Resource management

Kubernetes should not be treated as the source of truth for deployment configuration.

The desired state remains in Git.

```text
GitOps Repository
       │
       ▼
     Argo CD
       │
       ▼
 Kubernetes
```

---

# Kubernetes Namespace

The current project uses a single production namespace:

```text
shopsphere-production
```

The namespace contains ShopSphere application workloads and their application-specific Kubernetes resources.

Conceptually:

```text
shopsphere-production
│
├── auth-service
├── user-service
├── product-service
└── order-service
```

A separate namespace is not created for every microservice.

This keeps the initial platform simple.

---

# Future Namespace Strategy

When additional environments are introduced, environment-level namespace isolation can be used.

For example:

```text
shopsphere-development
shopsphere-staging
shopsphere-production
```

This provides a straightforward environment boundary without requiring a redesign of the application architecture.

The current implementation only creates the production namespace.

---

# Argo CD

Argo CD is the GitOps continuous delivery component.

Its responsibility is to synchronize Kubernetes resources with the desired state stored in the GitOps repository.

```text
GitOps Repository
       │
       ▼
     Argo CD
       │
       ▼
Kubernetes Cluster
```

Argo CD should manage the ShopSphere application resources rather than relying on GitHub Actions to directly deploy into Kubernetes.

---

# Argo CD Applications

Each microservice has its own Argo CD Application.

```text
Argo CD
│
├── shopsphere-auth
├── shopsphere-user
├── shopsphere-product
└── shopsphere-order
```

This allows each service to be independently synchronized and monitored.

For example:

```text
user-service image changed
        │
        ▼
shopsphere-user
        │
        ▼
Argo CD synchronization
        │
        ▼
user-service Deployment
```

The other applications remain unchanged.

---

# Argo CD Project

ShopSphere applications should belong to an Argo CD Project that defines reasonable boundaries around:

- Source repositories
- Kubernetes clusters
- Namespaces
- Permitted resource types

The project should remain simple.

Its purpose is to provide a security and organizational boundary rather than to reproduce the entire Kubernetes authorization model.

---

# ApplicationSet

An Argo CD ApplicationSet can be used to generate the individual ShopSphere Applications.

Conceptually:

```text
ApplicationSet
      │
      ├── shopsphere-auth
      ├── shopsphere-user
      ├── shopsphere-product
      └── shopsphere-order
```

The ApplicationSet should remain responsible primarily for application discovery and Application generation.

Application-specific Kubernetes configuration belongs under `apps/`.

---

# NGINX Ingress Controller

NGINX provides the public HTTP entry point for ShopSphere.

The intended traffic path is:

```text
Internet
   │
   ▼
Azure Load Balancer
   │
   ▼
NGINX Ingress Controller
   │
   ▼
Kubernetes Service
   │
   ▼
Application Pod
```

NGINX handles HTTP routing before requests reach the individual microservices.

The project should use an actively maintained NGINX Kubernetes ingress implementation rather than the archived Kubernetes `ingress-nginx` project.

NGINX configuration is considered infrastructure and belongs under:

```text
infrastructure/
└── ingress/
    └── nginx/
```

---

# Public API Routing

The public API should use a single entry point.

For example:

```text
https://api.shopsphere.example.com
```

Path-based routing determines which microservice receives the request.

```text
/api/v1/auth/*
        │
        ▼
auth-service

/api/v1/users/*
        │
        ▼
user-service

/api/v1/products/*
        │
        ▼
product-service

/api/v1/orders/*
        │
        ▼
order-service
```

The individual microservices should not require separate public endpoints.

---

# Internal Kubernetes Services

Each microservice receives an internal Kubernetes Service.

```text
auth-service
user-service
product-service
order-service
```

The Service provides:

- Stable DNS
- Stable networking
- Load balancing across Pods
- Decoupling from individual Pod IP addresses

The normal traffic flow is:

```text
NGINX
  │
  ▼
Kubernetes Service
  │
  ▼
Application Pods
```

Microservices should use Kubernetes Services for internal service-to-service communication.

---

# Public and Private Boundaries

The infrastructure separates public and private components.

```text
                    Internet
                       │
                       ▼
                NGINX Ingress
                       │
                       ▼
              Internal Services
                       │
                       ▼
                Application Pods
                       │
                       ▼
             Service-Owned Database
```

The following should not normally be publicly exposed:

- Application Pods
- Internal Kubernetes Services
- PostgreSQL
- Argo CD internal components

Only the required public ingress endpoint should be exposed externally.

---

# Microservice Deployments

Each microservice has its own Kubernetes Deployment.

```text
shopsphere-production
│
├── auth-service Deployment
├── user-service Deployment
├── product-service Deployment
└── order-service Deployment
```

Each Deployment is responsible for running the appropriate application container.

A Deployment should define the required:

- Image
- Replicas
- Container port
- Resource requirements
- Environment configuration
- Secret references
- Health probes
- Security configuration

---

# Pod Health

Application Pods should provide health information suitable for Kubernetes.

The application should expose appropriate health endpoints.

Kubernetes should use:

```text
Readiness Probe
Liveness Probe
```

The readiness probe determines whether the Pod should receive traffic.

The liveness probe determines whether the container is still functioning sufficiently to remain running.

The application should not receive normal traffic until its readiness requirements are satisfied.

---

# Resource Management

Production Deployments should define resource requests.

Where appropriate, resource limits should also be defined.

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

The actual values should be based on observed application behavior and available cluster resources.

The repository should avoid excessively large resource allocations simply to appear production-ready.

---

# Configuration

Application configuration is separated into:

```text
Non-sensitive configuration
        │
        ▼
    ConfigMap
```

and:

```text
Sensitive configuration
        │
        ▼
Secret / External Secret Management
```

Examples of non-sensitive configuration:

```text
NODE_ENV
PORT
LOG_LEVEL
```

Examples of sensitive configuration:

```text
DATABASE_URL
JWT_SECRET
API credentials
private keys
```

Sensitive values must not be committed to Git as plaintext.

---

# ConfigMaps

ConfigMaps are used for non-sensitive configuration.

For example:

```yaml
data:
  NODE_ENV: production
  LOG_LEVEL: info
```

ConfigMaps should not contain:

- Passwords
- Database credentials
- JWT secrets
- Private keys
- Access tokens

Configuration should be placed in the application-specific directory when it belongs only to one microservice.

Shared configuration belongs under infrastructure only when it is genuinely shared.

---

# Kubernetes Secrets

Kubernetes Secrets provide a mechanism for supplying sensitive configuration to workloads.

However, a Kubernetes Secret manifest containing base64-encoded values is not automatically equivalent to secure secret storage.

Therefore, production secrets should eventually be integrated with an appropriate external secret-management solution.

The architecture should support a flow such as:

```text
External Secret Store
        │
        ▼
Kubernetes Secret
        │
        ▼
Application Pod
```

The exact secret-management implementation should be introduced separately and should not be mixed with ordinary ConfigMap configuration.

---

# Managed PostgreSQL

ShopSphere uses PostgreSQL for persistent application data.

PostgreSQL is treated as managed infrastructure outside the Kubernetes application workloads.

Conceptually:

```text
Azure
│
└── Managed PostgreSQL
    │
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db
```

The Kubernetes cluster therefore does not need to manage PostgreSQL StatefulSets, persistent volumes, or PostgreSQL-specific failover logic.

---

# Database-per-Service

Each microservice owns a separate logical database.

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

A service must not directly connect to another service's database.

This boundary is fundamental to the ShopSphere microservice architecture.

---

# PostgreSQL Server Versus Database

Database ownership does not require four independent PostgreSQL servers.

The initial architecture can use:

```text
One Managed PostgreSQL Server
             │
     ┌───────┼────────┐
     │       │        │
     ▼       ▼        ▼
  auth_db user_db product_db
                       │
                       ▼
                    order_db
```

This provides logical database isolation while avoiding the operational overhead of managing four separate PostgreSQL servers.

If future scale or security requirements justify independent PostgreSQL servers, that decision can be revisited.

---

# Database Connectivity

Each application receives only the connection information required for its own database.

For example:

```text
auth-service
    │
    └── DATABASE_URL → auth_db
```

and:

```text
user-service
    │
    └── DATABASE_URL → user_db
```

The same pattern applies to Product and Order services.

Credentials should be unique to each service.

---

# Database Network Boundary

PostgreSQL should not be publicly accessible to the internet.

The intended connectivity is:

```text
Kubernetes Application
        │
        ▼
Private / Controlled Network
        │
        ▼
Managed PostgreSQL
```

The exact network implementation depends on the Azure environment and networking configuration.

The important architectural requirement is that database access is restricted to authorized application workloads.

---

# Database Migrations

Each application owns its Prisma migration files.

The GitOps repository provides the Kubernetes mechanism required to execute those migrations.

The deployment flow is:

```text
Argo CD
   │
   ▼
Migration Job
   │
   ▼
prisma migrate deploy
   │
   ▼
Application Deployment
```

Migration Jobs should be associated with the microservice they belong to.

For example:

```text
user-service-migration
```

The migration Job should use the application image containing the appropriate Prisma migration set.

---

# Why PostgreSQL Is Not a Kubernetes Workload

Running PostgreSQL inside Kubernetes would require additional infrastructure for:

- Persistent storage
- Backup
- Restore
- Database upgrades
- Failover
- Stateful workload management

For the current project, this would add operational complexity without providing meaningful benefits.

A managed PostgreSQL service allows Kubernetes to remain focused on application workloads.

---

# Storage

The ShopSphere application containers should be treated as stateless workloads.

Application state should not depend on the local filesystem of a Pod.

Persistent data belongs in the appropriate external systems, primarily PostgreSQL.

Conceptually:

```text
Application Pod
     │
     ├── Temporary filesystem
     │
     └── Persistent application data
              │
              ▼
          PostgreSQL
```

If another persistent storage requirement appears later, it should be introduced explicitly rather than storing important data inside container filesystems.

---

# Networking

The initial networking model is intentionally simple.

```text
Internet
   │
   ▼
NGINX
   │
   ▼
Kubernetes Services
   │
   ▼
Application Pods
   │
   ▼
Managed PostgreSQL
```

Internal Kubernetes networking provides service discovery between workloads.

Applications should communicate using stable Service names rather than Pod IP addresses.

---

# Service-to-Service Communication

When one microservice needs another microservice, communication should occur through a defined service interface.

For example:

```text
Order Service
     │
     │ HTTP/API
     ▼
User Service
```

The Order Service should not bypass the User Service and connect directly to `user_db`.

The database boundary and service communication boundary should remain separate.

---

# DNS and Service Discovery

Within Kubernetes, applications should communicate through Kubernetes Service DNS names.

For example:

```text
http://user-service
```

rather than:

```text
http://10.x.x.x
```

Pod IP addresses are ephemeral and should never be treated as stable application endpoints.

The Kubernetes Service provides the stable endpoint.

---

# Ingress and Service Separation

NGINX and Kubernetes Services have different responsibilities.

```text
NGINX
│
└── Determines where an HTTP request should go.

Kubernetes Service
│
└── Provides stable internal connectivity to application Pods.
```

NGINX should not contain application logic.

Kubernetes Services should not contain external routing logic.

Keeping these responsibilities separate makes the architecture easier to reason about.

---

# Argo CD and Infrastructure Separation

Argo CD manages desired Kubernetes resources.

It does not become the owner of external application data.

For example:

```text
Argo CD
   │
   ├── Kubernetes Deployment
   ├── Kubernetes Service
   ├── NGINX configuration
   └── Migration Job
```

while:

```text
Managed PostgreSQL
   │
   ├── Database infrastructure
   └── Persistent application data
```

The GitOps repository may contain the configuration required for applications to connect to PostgreSQL, but the database's persistent operational lifecycle remains outside the application Pods.

---

# Infrastructure Directory Structure

Infrastructure resources should be organized as follows:

```text
infrastructure/
│
├── namespaces/
│   └── production.yaml
│
└── ingress/
    └── nginx/
        ├── ...
        └── ...
```

As infrastructure grows, additional components can be introduced under `infrastructure/`.

For example:

```text
infrastructure/
├── namespaces/
├── ingress/
├── networking/
└── ...
```

A new directory should only be introduced when a distinct infrastructure responsibility exists.

---

# Application Directory Boundary

Application-specific infrastructure remains under the application's directory.

For example:

```text
apps/
└── user-service/
    ├── base/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── migration-job.yaml
    │
    └── overlays/
        └── production/
```

Do not move an application-specific Deployment into `infrastructure/`.

Conversely, do not put shared infrastructure such as NGINX inside an application directory.

---

# Infrastructure Lifecycle

Infrastructure follows the same GitOps lifecycle as applications.

```text
Infrastructure Change
        │
        ▼
GitOps Repository
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

The infrastructure should not normally be modified manually in production.

---

# Infrastructure Change Categories

Infrastructure changes can generally be divided into:

```text
Cluster-level
     │
     ├── AKS configuration
     └── Cluster infrastructure

Platform-level
     │
     ├── Argo CD
     ├── NGINX
     └── Namespaces

Application-level
     │
     ├── Deployment
     ├── Service
     ├── ConfigMap
     ├── Secret reference
     └── Migration Job
```

The GitOps repository primarily manages the platform and application Kubernetes layers.

The underlying AKS infrastructure may be managed separately depending on how the Azure infrastructure is provisioned.

---

# Infrastructure Versus Application Repository

The responsibility boundary is:

```text
Application Repository
│
├── Source code
├── Dockerfile
├── Tests
├── Prisma schema
├── Prisma migrations
└── CI
```

```text
GitOps Repository
│
├── Kubernetes
├── Argo CD
├── NGINX
├── Application configuration
├── Image versions
└── Deployment configuration
```

The application repository should not need to know the internal Kubernetes structure beyond the interfaces required to build and package the application.

---

# Security Boundaries

The infrastructure should follow these boundaries:

```text
                    Internet
                       │
                       ▼
                 NGINX Ingress
                       │
                       ▼
             Internal Kubernetes
                       │
                       ▼
              Application Pods
                       │
                       ▼
              Service-Owned DB
```

Security requirements include:

- Do not expose application Pods directly.
- Do not expose PostgreSQL publicly.
- Do not commit production secrets to Git.
- Give each service access only to its own database.
- Avoid privileged containers.
- Prefer non-root application containers.
- Use TLS for external API traffic.
- Restrict administrative interfaces such as Argo CD appropriately.

---

# TLS

External API traffic should use HTTPS.

The intended model is:

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
Internal Kubernetes Service
```

TLS certificate management should be introduced through an explicit mechanism when the production cluster is configured.

The application Pods do not need to individually terminate public TLS when NGINX is responsible for ingress termination.

---

# Observability Boundary

Observability is not a primary infrastructure component in the initial GitOps implementation.

The applications already provide structured logging.

The initial infrastructure should therefore avoid introducing a complete observability platform solely for the purpose of making the architecture appear production-ready.

When observability requirements become concrete, components such as:

```text
Metrics
Centralized Logs
Tracing
Dashboards
Alerting
```

can be introduced deliberately.

The infrastructure should remain compatible with those additions without requiring a fundamental redesign.

---

# Backup Responsibility

Database backups are the responsibility of the managed PostgreSQL platform rather than the Kubernetes application Pods.

Application containers should never implement their own PostgreSQL backup mechanism.

The production database strategy should eventually define:

- Backup retention
- Recovery expectations
- Restore procedure
- Disaster recovery requirements

These concerns belong to the database infrastructure rather than application deployment.

---

# Disaster Recovery

The initial project does not require a complex multi-cluster disaster recovery architecture.

The primary recovery principles are:

```text
GitOps Repository
       │
       └── Reproducible Kubernetes state

Docker Hub
       │
       └── Versioned application images

Managed PostgreSQL
       │
       └── Persistent application data and backups
```

The combination of versioned deployment configuration, immutable images, and managed database backups provides a foundation for recovery.

More advanced disaster recovery mechanisms should only be introduced when required.

---

# Scaling Strategy

The initial architecture supports horizontal application scaling through Kubernetes Deployments.

For example:

```text
user-service
     │
     ├── Pod 1
     ├── Pod 2
     └── Pod 3
```

The Kubernetes Service distributes traffic across ready Pods.

The application should remain stateless so that additional replicas can be created without requiring local persistent state.

Database scaling is handled separately by the PostgreSQL infrastructure.

---

# Infrastructure Growth Path

The initial infrastructure is:

```text
AKS
│
├── Argo CD
├── NGINX
└── ShopSphere applications

Managed PostgreSQL
├── auth_db
├── user_db
├── product_db
└── order_db
```

Future infrastructure may introduce:

```text
Additional environments
External secret management
Centralized observability
Network policies
Autoscaling
Message infrastructure
Additional clusters
```

These components are deliberately excluded until actual requirements justify them.

---

# What This Infrastructure Does Not Include

The initial platform intentionally does not include:

```text
Service Mesh
Kafka
RabbitMQ
Complex API Gateway
Multiple Ingress Controllers
Multiple Kubernetes Clusters
Database StatefulSets
Complex Progressive Delivery
Centralized Observability Stack
Complex Secret Platform
```

These technologies may become appropriate in the future, but they are not required for the current ShopSphere architecture.

Avoid adding infrastructure merely because it is common in larger production environments.

---

# Infrastructure Change Rules

Before introducing a new infrastructure component, answer:

1. What problem does it solve?

2. Why does the current infrastructure not solve the problem?

3. Is there a simpler solution?

4. What operational responsibility does it introduce?

5. Does it require new credentials or secrets?

6. Does it affect the deployment architecture?

7. Does it affect existing microservices?

8. Does the architecture documentation need to change?

9. Does the operations documentation need to change?

A significant infrastructure change should be documented before implementation.

---

# Infrastructure Validation

Before merging an infrastructure change, validate:

```text
YAML syntax
    │
    ▼
Kustomize build
    │
    ▼
Kubernetes manifest validation
    │
    ▼
Git diff review
    │
    ▼
Pull Request
```

Infrastructure changes should not be considered complete simply because the YAML is syntactically valid.

The resulting Kubernetes resources must also be logically correct and consistent with the architecture.

---

# Infrastructure Ownership Summary

The infrastructure responsibilities can be summarized as:

| Component             | Primary Responsibility        |
| --------------------- | ----------------------------- |
| AKS                   | Kubernetes runtime            |
| Argo CD               | GitOps reconciliation         |
| ApplicationSet        | Generate Argo CD Applications |
| NGINX                 | Public HTTP routing           |
| Kubernetes Deployment | Run application Pods          |
| Kubernetes Service    | Internal service discovery    |
| ConfigMap             | Non-sensitive configuration   |
| Secret                | Sensitive configuration       |
| Migration Job         | Database migration execution  |
| Managed PostgreSQL    | Persistent application data   |
| GitOps Repository     | Desired infrastructure state  |

---

# Final Infrastructure Model

The intended production architecture is:

```text
                              Internet
                                 │
                                 ▼
                       Azure Load Balancer
                                 │
                                 ▼
                      NGINX Ingress Controller
                                 │
                                 ▼
                     shopsphere-production
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
              ▼                  ▼                  ▼
         Auth Service       User Service       Product Service
              │                  │                  │
              ▼                  ▼                  ▼
           auth_db             user_db          product_db

                                 │
                                 ▼
                            Order Service
                                 │
                                 ▼
                              order_db
```

Deployment management operates alongside the workloads:

```text
GitOps Repository
        │
        ▼
      Argo CD
        │
        ▼
        AKS
```

The database infrastructure remains external:

```text
                    Managed PostgreSQL
                           │
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
         auth_db        user_db       product_db
                                          │
                                          ▼
                                       order_db
```

---

# Summary

ShopSphere infrastructure is intentionally divided into clear responsibilities.

```text
AKS
 │
 ├── Argo CD
 │
 ├── NGINX
 │
 └── ShopSphere workloads
       │
       ├── Auth Service
       ├── User Service
       ├── Product Service
       └── Order Service
```

Each service communicates through Kubernetes Services and owns its own logical PostgreSQL database.

NGINX provides the single public HTTP entry point.

Argo CD manages the desired Kubernetes state from Git.

Managed PostgreSQL provides persistent application storage outside the Kubernetes application workloads.

The infrastructure is designed to support future environments and additional platform capabilities without requiring the current system to be over-engineered.

The guiding principle is:

```text
Use Kubernetes for application workloads.
Use Argo CD for GitOps reconciliation.
Use NGINX for public routing.
Use managed PostgreSQL for persistent data.
Use Git as the source of truth.
Keep everything else as simple as possible.
```
