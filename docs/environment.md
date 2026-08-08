# ShopSphere Environment Strategy

This document defines how ShopSphere manages environment-specific configuration in the GitOps repository.

The current project has only one deployment environment:

```text
production
```

However, the GitOps repository is structured so that additional environments can be introduced later without redesigning the entire deployment architecture.

The environment strategy is based on **Kustomize bases and overlays**.

The core principle is:

```text
Base
  │
  ├── Common configuration
  │
  ▼
Environment Overlay
  │
  └── Environment-specific configuration
```

---

# Environment Goals

The environment architecture should:

- Support production today.
- Allow development and staging to be introduced later.
- Avoid duplicating Kubernetes manifests.
- Keep environment-specific configuration explicit.
- Prevent production configuration from leaking into other environments.
- Keep secrets isolated between environments.
- Make environment selection obvious.
- Keep the repository understandable to junior developers.
- Avoid creating infrastructure for environments that do not currently exist.

---

# Current Environment

ShopSphere currently has only:

```text
production
```

The initial repository therefore contains:

```text
overlays/
└── production/
```

There should not be empty directories for development or staging simply because those environments may exist in the future.

They should be introduced when they become actual deployment targets.

---

# Future Environment Model

When additional environments are required, the structure can become:

```text
overlays/
├── development/
├── staging/
└── production/
```

The common Kubernetes resources remain in the base.

Each overlay contains only the differences required for that environment.

Conceptually:

```text
                  Base
                   │
        ┌──────────┼──────────┐
        │          │          │
        ▼          ▼          ▼
 Development    Staging   Production
```

This avoids maintaining three independent copies of the same Kubernetes manifests.

---

# Environment Directory Structure

Each application follows the same structure.

Current:

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
            └── kustomization.yaml
```

Future:

```text
apps/
└── user-service/
    │
    ├── base/
    │
    └── overlays/
        ├── development/
        ├── staging/
        └── production/
```

The same structure applies to:

```text
auth-service
user-service
product-service
order-service
```

---

# What Belongs in the Base?

The base contains configuration that is common across environments.

Examples include:

```text
Deployment
Service
Container port
Health probes
Common labels
Common environment variable names
Migration Job
Common security configuration
```

For example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
```

The base should describe how the application is deployed, not where it is deployed.

---

# What Belongs in an Environment Overlay?

The environment overlay contains values that differ between environments.

Examples include:

```text
Replica count
Resource requirements
Image version
Environment name
Environment-specific configuration
Ingress hostname
Database configuration references
Environment-specific patches
```

For example:

```text
production
    replicas: 2

development
    replicas: 1
```

The Deployment structure remains shared while the environment-specific value is overridden by the overlay.

---

# Avoid Copying the Base

Do not create:

```text
production/deployment.yaml
staging/deployment.yaml
development/deployment.yaml
```

with almost identical contents.

Prefer:

```text
base/deployment.yaml

overlays/
├── production/
│   └── patch.yaml
├── staging/
│   └── patch.yaml
└── development/
    └── patch.yaml
```

This reduces configuration drift.

If a common configuration changes, it should normally be changed once in the base.

---

# Environment Ownership

Each environment represents an independent deployment target.

Conceptually:

```text
Development
    │
    └── Development resources

Staging
    │
    └── Staging resources

Production
    │
    └── Production resources
```

An environment must not accidentally depend on another environment's runtime resources.

For example:

```text
Development → Production Database
```

is not acceptable.

---

# Environment Isolation

Each environment should have independent:

- Application configuration
- Database credentials
- Database resources
- Secrets
- External service credentials
- Ingress configuration

The goal is:

```text
Development
     │
     ▼
Development resources

Staging
     │
     ▼
Staging resources

Production
     │
     ▼
Production resources
```

An environment should never use production credentials merely because they are convenient.

---

# Environment and Database Isolation

The environment boundary must also apply to PostgreSQL.

Current production:

```text
Production
    │
    ▼
PostgreSQL
    │
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db
```

Future environments should use separate databases.

For example:

```text
Development
    │
    ▼
Development PostgreSQL
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db
```

```text
Staging
    │
    ▼
Staging PostgreSQL
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db
```

```text
Production
    │
    ▼
Production PostgreSQL
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db
```

The exact physical PostgreSQL topology may change later.

The important requirement is that environments remain logically isolated.

---

# Environment Variables

Environment variables are divided into two categories:

```text
Non-sensitive configuration
        │
        ▼
ConfigMap / deployment configuration
```

and:

```text
Sensitive configuration
        │
        ▼
Secret / external secret management
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

The GitOps repository must never contain plaintext production secret values.

---

# Environment Naming

Environment names should be lowercase and consistent.

Preferred:

```text
development
staging
production
```

Avoid variations such as:

```text
dev
prod
Production
PROD
stg
```

unless a specific external system requires a different identifier.

The canonical GitOps environment names should remain:

```text
development
staging
production
```

---

# Kubernetes Namespace Strategy

The initial production namespace is:

```text
shopsphere-production
```

When additional environments are introduced:

```text
shopsphere-development
shopsphere-staging
shopsphere-production
```

The namespace name should clearly identify the environment.

This allows Kubernetes resources to be understood without inspecting application configuration.

---

# Environment and Kubernetes Cluster

The initial architecture has one production Kubernetes environment.

Conceptually:

```text
Production
    │
    ▼
AKS
    │
    ▼
shopsphere-production
```

When additional environments are introduced, there are two possible strategies:

```text
Option A

One Kubernetes cluster
│
├── shopsphere-development
├── shopsphere-staging
└── shopsphere-production
```

or:

```text
Option B

Development AKS
Staging AKS
Production AKS
```

The project should not choose separate clusters simply because multiple environments exist.

Cluster separation should be introduced only when the isolation, security, availability, or operational requirements justify it.

---

# Recommended Initial Expansion

If development and staging are introduced while keeping the infrastructure simple, the first expansion should use environment-level namespaces.

```text
One AKS Cluster
│
├── shopsphere-development
├── shopsphere-staging
└── shopsphere-production
```

This keeps the infrastructure relatively small while providing clear workload separation.

A multi-cluster architecture can be introduced later if required.

---

# Argo CD Environment Structure

Each environment should be represented explicitly in Argo CD.

Current:

```text
Argo CD
   │
   └── Production Applications
```

Future:

```text
Argo CD
│
├── Development Applications
├── Staging Applications
└── Production Applications
```

Each environment should point to the appropriate Kustomize overlay.

For example:

```text
auth-service
    │
    ├── development overlay
    ├── staging overlay
    └── production overlay
```

Argo CD should never accidentally deploy the production overlay into a development namespace.

---

# Environment-Specific Argo CD Applications

When multiple environments exist, the application identity should include the environment.

For example:

```text
shopsphere-auth-development
shopsphere-auth-staging
shopsphere-auth-production
```

This makes Argo CD application status immediately understandable.

The same pattern applies to all services.

---

# Environment Application Matrix

With four microservices and three environments, the eventual structure would be:

| Environment | Auth | User | Product | Order |
| ----------- | ---- | ---- | ------- | ----- |
| Development | ✓    | ✓    | ✓       | ✓     |
| Staging     | ✓    | ✓    | ✓       | ✓     |
| Production  | ✓    | ✓    | ✓       | ✓     |

Each combination represents an independently managed Argo CD Application.

For example:

```text
shopsphere-user-development
shopsphere-user-staging
shopsphere-user-production
```

This provides independent deployment and health visibility.

---

# Image Versioning by Environment

The same Docker image may be promoted through multiple environments.

For example:

```text
shopsphere/user-service:81ab320
```

may first be deployed to development:

```text
Development
    │
    ▼
81ab320
```

and later promoted to staging:

```text
Staging
    │
    ▼
81ab320
```

and finally production:

```text
Production
    │
    ▼
81ab320
```

The image itself does not change.

Only the environment's desired state changes.

This is preferable to rebuilding the same source code separately for every environment.

---

# Immutable Image Rule

Environment configuration must not use mutable image tags.

Do not use:

```text
latest
development
staging
production
stable
```

Use immutable versions such as:

```text
81ab320
```

This allows the exact application version deployed to every environment to be identified.

---

# Environment Promotion

When multiple environments exist, promotion should move an already-built image between environments.

Conceptually:

```text
Source Commit
      │
      ▼
Docker Image
      │
      ▼
Development
      │
      ▼
Staging
      │
      ▼
Production
```

The image should not normally be rebuilt at every promotion stage.

The artifact that passed the earlier stage should be the artifact promoted forward.

---

# Current Production-Only Model

Because ShopSphere currently has only production, there is no environment promotion pipeline yet.

The current lifecycle is simply:

```text
Source
  │
  ▼
Build Image
  │
  ▼
Docker Hub
  │
  ▼
Production GitOps
  │
  ▼
Argo CD
  │
  ▼
Production Kubernetes
```

Do not introduce development-to-staging-to-production promotion logic until those environments actually exist.

---

# Environment Configuration and Secrets

Environment configuration should be separated from secret values.

For example:

```text
Production
│
├── Kustomize configuration
│
└── Secret references
```

The actual secret values should be supplied through the approved secret-management mechanism.

When environments are introduced:

```text
Development Secrets
Staging Secrets
Production Secrets
```

must remain separate.

A production secret must never be reused as a development or staging secret.

---

# ConfigMap Strategy

Environment-specific non-sensitive configuration may be represented through Kustomize and ConfigMaps.

For example:

```text
base
│
└── common configuration

production
│
└── production values
```

If a configuration value differs between environments, the overlay should override it rather than modifying the base.

Example:

```text
development
LOG_LEVEL=debug
```

```text
production
LOG_LEVEL=info
```

The exact configuration values should be determined by the application requirements.

---

# Secret Strategy

The GitOps repository should contain references to secrets rather than plaintext secret values.

The intended model is:

```text
Environment
     │
     ▼
Secret Management
     │
     ▼
Kubernetes Secret
     │
     ▼
Application
```

Each environment should have its own secret set.

For example:

```text
production
    └── production database credentials

staging
    └── staging database credentials

development
    └── development database credentials
```

---

# Environment-Specific Ingress

Ingress configuration may vary by environment.

For example:

```text
Development
api-dev.shopsphere.example.com

Staging
api-staging.shopsphere.example.com

Production
api.shopsphere.example.com
```

The common routing structure can remain in the base while hostnames and environment-specific TLS configuration are provided by overlays.

The application path structure should remain consistent:

```text
/api/v1/auth/*
/api/v1/users/*
/api/v1/products/*
/api/v1/orders/*
```

---

# Environment-Specific Resource Sizing

Resource requirements may differ by environment.

For example:

```text
Development
    replicas: 1

Staging
    replicas: 1 or 2

Production
    replicas: 2+
```

The exact values should be determined by actual workload requirements.

Do not artificially make production configuration large simply because it is production.

Similarly, development should not consume production-level resources without a reason.

---

# Environment-Specific Autoscaling

Autoscaling is not required for the initial production-only implementation.

If Horizontal Pod Autoscaling is introduced later, its configuration can be environment-specific.

For example:

```text
development
    HPA disabled

staging
    HPA optional

production
    HPA enabled
```

This should only be introduced when actual workload characteristics justify autoscaling.

---

# Environment-Specific Database Configuration

The database endpoint must be environment-specific.

For example:

```text
Development
    DATABASE_URL → development database

Staging
    DATABASE_URL → staging database

Production
    DATABASE_URL → production database
```

The application code itself should not contain environment-specific database hostnames.

Database configuration should be injected at deployment time.

---

# Environment-Specific Database Migrations

Each environment maintains its own database schema state.

For example:

```text
Development
    │
    ▼
development database migrations

Staging
    │
    ▼
staging database migrations

Production
    │
    ▼
production database migrations
```

The same migration sequence should be applied to each environment as the application version is promoted.

A migration should not be considered complete simply because it succeeded in development.

It must also successfully execute against the target environment's database.

---

# Environment Drift

Environment drift occurs when environments no longer represent the same application configuration model.

For example:

```text
Development
    │
    └── base + development overlay

Production
    │
    └── completely different manifests
```

This makes deployments difficult to predict.

Kustomize should therefore be used to keep common configuration shared.

The goal is:

```text
Common Base
    +
Small Environment Differences
```

rather than:

```text
Independent Configuration Copies
```

---

# Avoid Environment-Specific Application Code

The application repository should not contain logic such as:

```text
if production
    do X

if staging
    do Y

if development
    do Z
```

unless the application genuinely requires different behavior.

Environment differences should primarily be expressed through configuration.

This keeps the application artifact consistent across environments.

---

# Environment Promotion and Git

When multiple environments exist, environment changes should remain Git-managed.

For example:

```text
GitOps Repository
│
├── development overlay
├── staging overlay
└── production overlay
```

Promotion can therefore be represented as a Git change:

```text
Development
    │
    ▼
Staging image update
    │
    ▼
Production image update
```

This keeps the entire promotion history auditable.

---

# Production Protection

Production should have stricter change controls than development.

At minimum:

```text
Development
    │
    └── Fast iteration

Staging
    │
    └── Pre-production validation

Production
    │
    └── Reviewed and controlled changes
```

The exact branch protection and approval rules belong to the repository and organizational workflow rather than Kubernetes itself.

---

# Environment Branches

The GitOps repository should not initially create long-lived branches such as:

```text
development
staging
production
```

for environment state.

Environment differences should be represented through directories and Kustomize overlays.

Preferred:

```text
main
│
└── overlays/
    ├── development/
    ├── staging/
    └── production/
```

This keeps the desired state in one version-controlled history.

---

# Why Not Use Environment Branches?

Environment branches can create configuration drift.

For example:

```text
production branch
    ≠
staging branch
    ≠
development branch
```

It becomes difficult to determine which configuration is shared and which is environment-specific.

Kustomize overlays provide a more explicit model:

```text
One base
    +
Environment overlays
```

---

# Environment Naming in GitOps

The environment name should be visible in paths.

Preferred:

```text
apps/user-service/overlays/production/
```

rather than:

```text
apps/user-service/overlays/current/
```

or:

```text
apps/user-service/config/
```

The path should communicate exactly which environment it represents.

---

# Environment Ownership Model

The repository can be understood as three layers:

```text
Base
 │
 └── Defines application deployment structure

Overlay
 │
 └── Defines environment-specific differences

Argo CD
 │
 └── Deploys the selected environment
```

For example:

```text
user-service
│
├── base
│
└── overlays
    └── production
```

Argo CD points to:

```text
apps/user-service/overlays/production
```

The selected path determines the environment being deployed.

---

# Environment Validation

Before introducing or modifying an environment, validate:

```text
Kustomize build
        │
        ▼
Kubernetes manifest validation
        │
        ▼
Environment configuration review
        │
        ▼
Secret reference validation
        │
        ▼
Argo CD configuration review
```

Each environment overlay should produce a valid Kubernetes configuration independently.

---

# Environment Checklist

Before adding or changing an environment:

### Repository

- [ ] Environment name follows the naming convention.
- [ ] Environment has its own Kustomize overlay.
- [ ] Common configuration remains in the base.
- [ ] No unnecessary manifest duplication exists.

### Kubernetes

- [ ] Correct namespace is used.
- [ ] Correct resource configuration is applied.
- [ ] Environment-specific replica settings are intentional.
- [ ] Environment-specific ingress configuration is correct.

### Database

- [ ] Environment uses the correct PostgreSQL infrastructure.
- [ ] Database credentials are environment-specific.
- [ ] Database is not shared with another environment.
- [ ] Required migrations can execute against the target database.

### Secrets

- [ ] No plaintext secrets are committed.
- [ ] Secret references point to the correct environment.
- [ ] Production credentials are isolated.

### Argo CD

- [ ] Argo CD points to the correct overlay.
- [ ] Correct namespace is targeted.
- [ ] Application name identifies the environment.
- [ ] No application accidentally points to another environment.

---

# Future Multi-Environment Architecture

When all three environments are eventually required, the target structure is:

```text
apps/
│
├── auth-service/
│   ├── base/
│   └── overlays/
│       ├── development/
│       ├── staging/
│       └── production/
│
├── user-service/
│   ├── base/
│   └── overlays/
│       ├── development/
│       ├── staging/
│       └── production/
│
├── product-service/
│   ├── base/
│   └── overlays/
│       ├── development/
│       ├── staging/
│       └── production/
│
└── order-service/
    ├── base/
    └── overlays/
        ├── development/
        ├── staging/
        └── production/
```

The Argo CD structure would then conceptually become:

```text
Argo CD
│
├── Development
│   ├── Auth
│   ├── User
│   ├── Product
│   └── Order
│
├── Staging
│   ├── Auth
│   ├── User
│   ├── Product
│   └── Order
│
└── Production
    ├── Auth
    ├── User
    ├── Product
    └── Order
```

---

# Environment Strategy Summary

The ShopSphere environment strategy can be summarized as:

```text
Current:

Production
    │
    ▼
production overlay
    │
    ▼
Argo CD
    │
    ▼
AKS
```

Future:

```text
                    Base
                     │
          ┌──────────┼──────────┐
          │          │          │
          ▼          ▼          ▼
     Development   Staging   Production
          │          │          │
          ▼          ▼          ▼
       Argo CD     Argo CD    Argo CD
          │          │          │
          └──────────┼──────────┘
                     ▼
                  Kubernetes
```

The environment model deliberately keeps the current implementation simple while preserving a straightforward path to additional environments.

---

# Environment Principles

The ShopSphere environment strategy follows these principles:

1. **Production is the only environment currently deployed.**

2. **Environment configuration is managed through Kustomize overlays.**

3. **Common configuration belongs in the base.**

4. **Environment-specific differences belong in overlays.**

5. **Do not duplicate entire Kubernetes manifests for each environment.**

6. **Each environment has its own database configuration.**

7. **Environment credentials are isolated.**

8. **Production secrets must never be reused by other environments.**

9. **Images remain immutable across environments.**

10. **The same application artifact can be promoted between environments.**

11. **Environment state is stored in Git rather than environment branches.**

12. **Argo CD deploys the overlay corresponding to the environment.**

13. **Environment names should be explicit and consistent.**

14. **Additional environments should be introduced only when they are actually required.**

15. **The environment architecture should remain as simple as the project's needs allow.**

---

# Final Environment Model

The current ShopSphere deployment is intentionally simple:

```text
                    GitOps Repository
                           │
                           ▼
                  production overlay
                           │
                           ▼
                        Argo CD
                           │
                           ▼
                         AKS
                           │
                           ▼
                shopsphere-production
```

The architecture is already prepared for future expansion:

```text
                    GitOps Repository
                           │
                           ▼
                         Base
                           │
             ┌─────────────┼─────────────┐
             │             │             │
             ▼             ▼             ▼
        Development      Staging     Production
             │             │             │
             ▼             ▼             ▼
          Argo CD       Argo CD      Argo CD
             │             │             │
             ▼             ▼             ▼
       Kubernetes     Kubernetes    Kubernetes
```

The key rule is:

```text
One application artifact.
One shared deployment base.
Environment-specific overlays.
Environment-specific secrets and databases.
Git-managed desired state.
```

This approach keeps the current production-only implementation straightforward while providing a clean path toward development and staging when ShopSphere actually needs them.
