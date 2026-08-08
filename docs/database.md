# ShopSphere Database Architecture

This document defines the database architecture and operational strategy for the ShopSphere production environment.

ShopSphere follows the **database-per-service** principle. Each microservice owns its own logical PostgreSQL database and is responsible for the data belonging to that service.

The GitOps repository is responsible for deploying the Kubernetes resources required to connect applications to their databases and execute database migrations.

The application repositories remain responsible for the Prisma schemas and migration definitions.

The primary goals are:

- Keep database ownership clearly separated.
- Prevent microservices from directly accessing each other's databases.
- Keep PostgreSQL infrastructure simple.
- Keep application database access consistent.
- Make database migrations predictable.
- Avoid running PostgreSQL as a stateful workload inside Kubernetes.
- Keep credentials out of Git.
- Make the database architecture understandable to junior developers.
- Provide a clear path for future environments and scaling.

---

# Database Architecture Overview

The current production architecture uses PostgreSQL with one logical database per microservice.

```text
                         Managed PostgreSQL
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
           auth_db           user_db          product_db
                                                  │
                                                  ▼
                                               order_db
```

The ownership relationship is:

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

The important boundary is logical ownership.

A microservice may access its own database, but it must not directly query another microservice's database.

---

# Why Database per Service?

Each microservice has its own business responsibility and therefore owns its own data.

Without database isolation, services can become tightly coupled through shared tables.

For example:

```text
Order Service
     │
     ├── user tables
     ├── product tables
     └── order tables
```

This means the Order Service becomes dependent on the internal database structure of the User and Product services.

With database ownership:

```text
Order Service
     │
     ▼
  order_db
```

If Order Service needs information owned by User Service, it should communicate with User Service through an appropriate service interface.

For example:

```text
Order Service
      │
      │ HTTP / API
      ▼
 User Service
      │
      ▼
   user_db
```

The Order Service does not bypass User Service and connect directly to `user_db`.

This preserves the service boundary.

---

# Database Ownership

Every microservice must have one clearly defined database owner.

| Microservice    | Database     | Owner           |
| --------------- | ------------ | --------------- |
| Auth Service    | `auth_db`    | Auth Service    |
| User Service    | `user_db`    | User Service    |
| Product Service | `product_db` | Product Service |
| Order Service   | `order_db`   | Order Service   |

The service that owns the database is responsible for:

- Database schema
- Prisma schema
- Prisma migrations
- Data access
- Data integrity rules
- Database-specific business persistence

Other services must not modify or query the database directly.

---

# PostgreSQL Infrastructure

The initial production architecture uses a managed PostgreSQL platform rather than running PostgreSQL inside Kubernetes.

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

This separates persistent database infrastructure from the Kubernetes application platform.

Kubernetes is responsible for running:

```text
Auth Service
User Service
Product Service
Order Service
```

The managed PostgreSQL platform is responsible for:

```text
PostgreSQL
Storage
Database availability
Database backups
Database infrastructure
```

---

# Why Not Run PostgreSQL Inside Kubernetes?

PostgreSQL can be operated as a Kubernetes StatefulSet, but doing so introduces additional operational responsibilities.

These include:

- Persistent volume management
- Database backups
- Restore procedures
- PostgreSQL upgrades
- Failover
- Stateful workload management
- Storage failure handling
- Database recovery

For the current ShopSphere project, this complexity is unnecessary.

Using managed PostgreSQL allows the Kubernetes platform to remain focused on application workloads.

The architecture therefore becomes:

```text
Kubernetes / AKS
│
├── Argo CD
├── NGINX
├── Auth Service
├── User Service
├── Product Service
└── Order Service

Managed PostgreSQL
│
├── auth_db
├── user_db
├── product_db
└── order_db
```

---

# One PostgreSQL Server or Multiple Servers?

The database-per-service principle does not require a separate PostgreSQL server for every microservice.

The initial design uses one managed PostgreSQL server with separate logical databases:

```text
PostgreSQL Server
│
├── auth_db
├── user_db
├── product_db
└── order_db
```

This provides logical database isolation while avoiding the operational overhead of managing four PostgreSQL servers.

If future requirements introduce stronger isolation, independent scaling, compliance requirements, or database-specific infrastructure, individual PostgreSQL servers can be introduced later.

That should be an explicit architectural decision rather than the default.

---

# Database Credentials

Each microservice must have credentials that provide access only to its own database.

For example:

```text
Auth Service
    │
    └── Auth database credentials
             │
             ▼
          auth_db
```

and:

```text
User Service
    │
    └── User database credentials
             │
             ▼
          user_db
```

The same model applies to Product and Order services.

A service should not possess credentials that allow access to another service's database.

This creates a second layer of isolation in addition to the application architecture.

---

# Database Connection Configuration

Each application receives its database connection through configuration.

A typical application configuration contains:

```text
DATABASE_URL
```

The actual production value must not be committed to Git.

The intended flow is:

```text
Secret Management
       │
       ▼
Kubernetes Secret
       │
       ▼
Application Pod
       │
       ▼
Prisma
       │
       ▼
Service-Owned PostgreSQL Database
```

The exact production secret-management mechanism is defined by the infrastructure implementation.

---

# Secrets Must Not Be Stored in Git

The GitOps repository must not contain plaintext production database credentials.

Do not commit:

```yaml
stringData:
  DATABASE_URL: postgresql://username:password@host/database
```

Base64 encoding a password does not make it a secure secret.

The GitOps repository may contain:

- Secret references
- Secret templates
- External secret configuration
- Non-sensitive configuration

The actual production secret values must be provided through the approved secret-management mechanism.

---

# Prisma Architecture

Each application uses Prisma as its database access layer.

The application-level architecture is:

```text
Application
     │
     ▼
Service Layer
     │
     ▼
Shared Prisma Client
     │
     ▼
PostgreSQL
```

The existing ShopSphere Database module intentionally uses a single shared Prisma Client for the lifetime of the application. It also centralizes connection management, health checks, and configuration.

Feature code should use the shared Prisma Client rather than creating additional clients.

The application-level database lifecycle is:

```text
Application Starts
       │
       ▼
connectDatabase()
       │
       ▼
Prisma Connects
       │
       ▼
Health Check
       │
       ▼
Application Ready
```

During shutdown:

```text
Application Shutdown
       │
       ▼
disconnectDatabase()
       │
       ▼
Prisma Disconnects
       │
       ▼
Process Exits
```

This lifecycle is already established by the application Database module.

---

# Database Access Location

Database operations should remain inside the application's service layer.

The expected flow is:

```text
HTTP Controller
      │
      ▼
Business Service
      │
      ▼
Prisma Client
      │
      ▼
PostgreSQL
```

Controllers should not contain complex database queries.

The existing Database module documentation follows this same service-layer approach.

The GitOps repository does not change this application-level responsibility.

---

# Database Health

Each application provides a database health check through its Database module.

The health check is intentionally lightweight.

The existing implementation uses:

```sql
SELECT 1
```

The conceptual flow is:

```text
checkDatabaseHealth()
        │
        ▼
    SELECT 1
        │
        ▼
 PostgreSQL Response
        │
     ┌──┴──┐
     ▼     ▼
    UP     DOWN
```

This can be used by:

- Application health endpoints
- Kubernetes readiness checks
- Deployment verification
- Operational troubleshooting

The existing Database module defines this health-check behavior.

---

# Kubernetes Database Connectivity

Application Pods connect to the managed PostgreSQL service.

The intended flow is:

```text
Application Pod
      │
      ▼
Private / Controlled Network
      │
      ▼
Managed PostgreSQL
      │
      ▼
Service-Owned Database
```

PostgreSQL should not be publicly accessible from the internet.

Database access should be restricted to authorized application workloads.

The exact Azure networking implementation may evolve independently from the application deployment manifests.

---

# Database Migrations

Database schema changes are managed through Prisma migrations.

The application repository owns the migration files.

For example:

```text
user-service/
│
├── prisma/
│   ├── schema.prisma
│   └── migrations/
│
└── Dockerfile
```

The GitOps repository owns the Kubernetes mechanism that executes those migrations.

This creates a clear responsibility boundary:

```text
Application Repository
        │
        └── Defines migration

GitOps Repository
        │
        └── Executes migration
```

---

# Migration Deployment Flow

A production deployment that contains database changes follows this pattern:

```text
New Application Image
        │
        ▼
GitOps Update
        │
        ▼
Argo CD Synchronization
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
        │   Deployment does not
        │   proceed normally
        │
        └── Success
               │
               ▼
       Application Deployment
```

The migration must complete successfully before the new application version is considered ready.

---

# Why Migrations Are Separate from Application Startup

Do not run:

```text
Container starts
      │
      ▼
prisma migrate deploy
      │
      ▼
Application starts
```

inside every application Pod.

Consider a Deployment with three replicas:

```text
Pod 1 → migrate
Pod 2 → migrate
Pod 3 → migrate
```

This unnecessarily introduces concurrent migration attempts.

Instead:

```text
Argo CD
   │
   ▼
Migration Job
   │
   ▼
Database Migration
   │
   ▼
Application Deployment
```

The migration is therefore treated as a deployment operation rather than an application startup operation.

---

# Migration Job Ownership

Each microservice should have its own migration Job.

For example:

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
```

The Job should clearly identify the service:

```text
user-service-migration
```

The same convention applies to the other services.

---

# Migration Image

The migration Job should use an image containing the migration files required for that application release.

Conceptually:

```text
shopsphere/user-service:81ab320
                │
                ├── Application
                │
                └── Prisma migrations
```

The migration Job runs:

```bash
prisma migrate deploy
```

using the appropriate database credentials.

This ensures that the migration being executed corresponds to the application version being deployed.

---

# Migration Compatibility

Database migrations must be designed carefully when an application is deployed using rolling updates.

The application should preferably remain compatible with the database schema during the transition.

A safe conceptual sequence is:

```text
Existing Application
        │
        ▼
Backward-Compatible Migration
        │
        ▼
New Application
```

Avoid destructive changes that immediately break the currently running application.

For example, removing a column that the existing application still requires should not be performed in the same deployment step without a migration strategy that accounts for the old version.

---

# Expand-and-Contract Strategy

When a database change could break the currently running application, use a staged approach.

For example:

```text
Step 1
Add new database structure
        │
        ▼
Step 2
Deploy application that supports both structures
        │
        ▼
Step 3
Migrate application usage
        │
        ▼
Step 4
Remove old structure later
```

This is preferable to combining incompatible schema and application changes into a single deployment.

The goal is to keep rolling deployments safe.

---

# Application Rollback Versus Database Rollback

A critical rule is:

**Rolling back an application does not automatically roll back its database migration.**

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

If the application is rolled back:

```text
Version B
    │
    ▼
Version A
```

the database may still contain the changes introduced by Migration B.

Therefore:

```text
Application Rollback
        ≠
Database Rollback
```

Before rolling an application back, determine whether the previous application version remains compatible with the current database schema.

Destructive database rollback procedures must be explicitly designed and should not be assumed to be automatically available.

---

# Database Transactions

Transactions belong to the application layer.

When multiple related operations must succeed or fail together, the application should use Prisma transactions.

Conceptually:

```text
Service
   │
   ▼
Prisma Transaction
   │
   ├── Operation A
   ├── Operation B
   └── Operation C
        │
        ▼
     Commit
```

The existing Database module documentation recommends Prisma transactions when multiple database operations must succeed together.

The GitOps repository does not implement transaction logic.

---

# Database Connection Lifecycle

The application owns its database connection lifecycle.

Startup:

```text
Application Starts
       │
       ▼
connectDatabase()
       │
       ▼
Health Check
       │
       ▼
Application Ready
```

Shutdown:

```text
Application Shutdown
       │
       ▼
disconnectDatabase()
       │
       ▼
Process Exits
```

Kubernetes controls the lifecycle of the application Pod, while the application controls the lifecycle of its Prisma connection.

These are separate responsibilities.

---

# Kubernetes Readiness

The database health check can be incorporated into application readiness.

Conceptually:

```text
Kubernetes
    │
    ▼
Readiness Probe
    │
    ▼
Application Health Endpoint
    │
    ▼
Database Health
    │
    ├── UP   → Pod Ready
    │
    └── DOWN → Pod Not Ready
```

This prevents a Pod from receiving normal traffic when the application cannot communicate with its required database.

The exact health endpoint behavior is owned by the application.

---

# Database Configuration by Environment

The database configuration should vary by environment.

Currently there is only:

```text
production
```

Therefore, the production deployment references production database credentials and endpoints.

When additional environments are introduced:

```text
development → development databases
staging     → staging databases
production  → production databases
```

Each environment should have separate database credentials.

An environment must never accidentally point to another environment's production database.

---

# Future Environment Database Model

The current architecture is:

```text
Production
│
└── PostgreSQL
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db
```

A future multi-environment architecture could become:

```text
Development
└── PostgreSQL
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db

Staging
└── PostgreSQL
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db

Production
└── PostgreSQL
    ├── auth_db
    ├── user_db
    ├── product_db
    └── order_db
```

The exact physical PostgreSQL topology can be decided later.

The important requirement is environment isolation.

---

# Database Naming

Database names should clearly identify the owning service.

Preferred:

```text
auth_db
user_db
product_db
order_db
```

Avoid generic names such as:

```text
database1
shopsphere_db
main_db
application_db
```

A database name should make ownership immediately obvious.

---

# Database User Naming

Database users should also identify their owning service.

For example:

```text
auth_user
user_service_user
product_service_user
order_service_user
```

The exact naming convention can be finalized when the managed PostgreSQL infrastructure is provisioned.

The important rule is that credentials should be service-specific rather than shared across all applications.

---

# Database Access Rules

The following rules apply to all ShopSphere services:

1. A service may access only its own database.

2. A service must not query another service's database.

3. A service must not use another service's database credentials.

4. Database credentials must be stored as secrets.

5. Prisma schema and migrations belong to the owning application repository.

6. Migration execution belongs to the deployment process.

7. Database migrations must be compatible with the application's deployment strategy.

8. Application rollback must account for database schema compatibility.

9. PostgreSQL must not be publicly exposed.

10. Persistent application data must not be stored inside application containers.

---

# Backup Strategy

Database backups are handled by the managed PostgreSQL platform rather than the Kubernetes application workloads.

The database infrastructure should provide appropriate backup capabilities for production.

The project should eventually define:

- Backup retention
- Recovery expectations
- Restore procedure
- Recovery testing

The Kubernetes application should not implement its own PostgreSQL backup mechanism.

---

# Disaster Recovery

The database recovery model is based on two independent pieces:

```text
GitOps Repository
        │
        └── Reproducible deployment configuration

Managed PostgreSQL
        │
        └── Persistent data and backups
```

The application platform can therefore be reconstructed from Git and versioned container images, while persistent database data is recovered through the managed PostgreSQL backup and recovery mechanisms.

A complete disaster-recovery procedure should be documented separately if the project later requires one.

---

# Database Security

The database architecture should follow these security principles:

- PostgreSQL should not be publicly accessible.
- Each service should use service-specific credentials.
- Credentials must not be committed to Git.
- Applications should receive only the credentials they require.
- Database traffic should use secure connections.
- Production databases should not be reused by development environments.
- Database access should be restricted through appropriate network controls.
- Database users should have only the permissions required by their service.

The exact Azure networking and identity configuration can evolve independently of this database ownership model.

---

# Database Logging

Database lifecycle events are logged by the application's Database module.

Examples include:

```text
Connection started
Connection established
Connection failed
Database disconnected
```

The existing Database module intentionally keeps infrastructure logging inside the database module rather than requiring feature modules to duplicate it.

Feature modules should focus on business-level events.

Sensitive database credentials and connection strings must never be written to application logs.

---

# Database Health and Operations

Database health can be observed through:

```text
Application Health Endpoint
          │
          ▼
Database Health Check
          │
          ▼
PostgreSQL
```

The existing Database module returns a simple health status and latency measurement, allowing the health result to be used by application health endpoints and Kubernetes readiness checks.

Operational database troubleshooting should begin by determining whether the problem is:

```text
Application
    │
    ├── Configuration
    ├── Credentials
    ├── Network
    └── Prisma

or

PostgreSQL
    │
    ├── Availability
    ├── Capacity
    ├── Connections
    └── Database health
```

---

# Database Deployment Flow

A database-aware application deployment can be represented as:

```text
Developer
    │
    ▼
Application Change
    │
    ▼
GitHub Actions
    │
    ▼
Docker Image
    │
    ▼
Docker Hub
    │
    ▼
GitOps Image Update
    │
    ▼
Argo CD
    │
    ▼
Migration Job
    │
    ▼
PostgreSQL
    │
    ▼
Migration Successful
    │
    ▼
Application Deployment
    │
    ▼
Health Verification
```

This keeps database migration execution inside the deployment lifecycle while keeping migration definitions inside the application repository.

---

# Database Failure During Deployment

If a migration fails:

```text
Argo CD
   │
   ▼
Migration Job
   │
   X
Migration Failed
```

The application rollout should not be treated as successful.

The failure should be investigated before attempting to continue the deployment.

Potential causes include:

- Invalid migration
- Database connectivity failure
- Authentication failure
- Constraint violation
- Incompatible schema state
- Insufficient database permissions
- Database availability issue

---

# Database Failure During Runtime

If PostgreSQL becomes unavailable after the application has already started:

```text
Application
    │
    ▼
Database Request
    │
    X
PostgreSQL unavailable
```

The application should use its existing error-handling and health-check mechanisms.

Kubernetes readiness should prevent an unhealthy application from receiving traffic when its readiness requirements are no longer satisfied.

The application should not attempt to create uncontrolled database clients or implement ad-hoc database recovery logic in individual feature modules.

---

# Connection Pooling

Prisma manages database connections through its database engine and connection pooling behavior.

The application should continue using the shared Prisma Client rather than creating a new client for each request.

The existing Database module explicitly follows the one-shared-client model to avoid unnecessary connections and memory usage.

If connection limits become a real production concern, connection-pool configuration should be adjusted deliberately rather than introducing additional database abstractions.

---

# Database Scaling

Database scaling is separate from application scaling.

Application scaling:

```text
user-service
   │
   ├── Pod 1
   ├── Pod 2
   └── Pod 3
```

Database scaling:

```text
user_db
   │
   └── PostgreSQL Infrastructure
```

Adding more application replicas does not automatically require additional PostgreSQL servers.

If database capacity becomes a bottleneck, PostgreSQL-specific scaling strategies should be evaluated independently.

---

# Future Database Enhancements

The current architecture intentionally does not introduce advanced database infrastructure.

Potential future enhancements include:

```text
Read replicas
Connection pooling infrastructure
Database metrics
Query performance monitoring
Automated restore testing
Independent PostgreSQL servers
Database partitioning
Database sharding
```

These should only be introduced when actual application requirements justify them.

---

# What This Architecture Does Not Do

The initial database architecture intentionally does not include:

```text
PostgreSQL StatefulSets inside Kubernetes
Shared database across all services
Cross-service direct database access
Public PostgreSQL access
Shared database credentials
Automatic database rollback
Multiple database servers without a requirement
Complex database abstraction layers
```

The goal is to establish clear database ownership without unnecessary infrastructure.

---

# Database Responsibility Boundary

The final responsibility boundary is:

```text
Application Repository
│
├── Prisma schema
├── Prisma migrations
├── Database queries
├── Transactions
└── Database module
```

```text
GitOps Repository
│
├── Database Migration Job
├── Database Secret references
├── Environment configuration
└── Deployment configuration
```

```text
Managed PostgreSQL
│
├── PostgreSQL server
├── Logical databases
├── Persistent data
├── Backups
└── Database infrastructure
```

Each layer has a clear responsibility.

---

# Database Architecture Principles

The ShopSphere database architecture follows these principles:

1. **Every microservice owns its own database.**

2. **A service must never directly access another service's database.**

3. **One managed PostgreSQL platform can host multiple service-owned databases.**

4. **Database credentials are service-specific.**

5. **Credentials are never committed to Git.**

6. **Prisma schemas and migrations belong to the owning application.**

7. **Migration execution belongs to the deployment process.**

8. **Migrations should be compatible with rolling deployments.**

9. **Application rollback does not automatically imply database rollback.**

10. **PostgreSQL should not be publicly accessible.**

11. **Application Pods remain stateless.**

12. **The shared Prisma Client is used within each application.**

13. **Database health is exposed through the application's health system.**

14. **Managed PostgreSQL is preferred over running PostgreSQL inside Kubernetes for the current project.**

15. **Database infrastructure should remain as simple as the project's requirements allow.**

---

# Database Checklist

Before introducing or modifying database infrastructure, verify:

### Ownership

- [ ] The owning microservice is clearly identified.
- [ ] The database is not shared with another service.
- [ ] No service requires another service's database credentials.

### Configuration

- [ ] `DATABASE_URL` is provided through secure configuration.
- [ ] No credentials are committed to Git.
- [ ] Production credentials are separate from future non-production environments.

### Prisma

- [ ] The Prisma schema belongs to the correct service.
- [ ] Required migrations exist.
- [ ] The application uses the shared Prisma Client.
- [ ] Database access remains in the appropriate service layer.

### Deployment

- [ ] Migration Job exists when a schema change is required.
- [ ] Migration uses the appropriate application image.
- [ ] Migration runs before the application version requiring it.
- [ ] Migration failure prevents a successful rollout.

### Kubernetes

- [ ] Application Pods can reach PostgreSQL.
- [ ] PostgreSQL is not publicly exposed.
- [ ] Readiness checks reflect database availability where appropriate.
- [ ] Secrets are available to the correct workload only.

### Operations

- [ ] Database backups are configured through the managed PostgreSQL platform.
- [ ] Recovery expectations are understood.
- [ ] Application rollback compatibility has been considered.
- [ ] Destructive migrations have been reviewed carefully.

---

# Summary

ShopSphere uses a simple database-per-service architecture built around PostgreSQL and Prisma.

The production model is:

```text
                    Managed PostgreSQL
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
       auth_db          user_db         product_db
                                             │
                                             ▼
                                          order_db
```

Each microservice owns its database:

```text
Auth Service    → auth_db
User Service    → user_db
Product Service → product_db
Order Service   → order_db
```

The application repository defines the database schema and Prisma migrations.

The GitOps repository defines how migrations are executed in Kubernetes.

The managed PostgreSQL platform owns persistent database infrastructure and backups.

The deployment flow is:

```text
Application Image
       │
       ▼
GitOps
       │
       ▼
Argo CD
       │
       ▼
Migration Job
       │
       ▼
PostgreSQL
       │
       ▼
Application Deployment
```

The most important rule is:

```text
A service owns its data.

A service accesses only its own database.

Other services access that data through the owning service's interface.
```

This architecture provides strong service boundaries while keeping the infrastructure small enough for the ShopSphere project to remain understandable and maintainable.
