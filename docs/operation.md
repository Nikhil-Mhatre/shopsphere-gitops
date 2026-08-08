# ShopSphere Operations Guide

This document is the operational runbook for the ShopSphere GitOps platform.

It explains how to operate, inspect, troubleshoot, deploy, and recover the ShopSphere production environment.

The goal is not to document every Kubernetes command that exists. The goal is to provide a small set of predictable procedures that developers can follow when something goes wrong.

The production platform consists of:

```text
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
              │
              ▼
       Managed PostgreSQL
```

---

# Operational Principles

ShopSphere follows these operational principles:

- Git is the source of truth.
- Argo CD is the deployment authority.
- Kubernetes is the runtime platform.
- GitHub Actions builds and publishes application images.
- Docker Hub stores immutable application images.
- Production configuration should normally be changed through Git.
- Manual Kubernetes changes are reserved for troubleshooting or emergencies.
- Each microservice is independently deployable.
- Each microservice owns its own database.
- Database migrations are treated as deployment operations.
- Application rollback does not automatically mean database rollback.
- Troubleshooting should begin by identifying which layer failed.
- Keep operational procedures simple enough for a junior developer to follow.

---

# Operational Layers

When troubleshooting ShopSphere, work from the outside toward the failing component.

```text
1. Git
   │
   ▼
2. Argo CD
   │
   ▼
3. Kubernetes
   │
   ▼
4. NGINX
   │
   ▼
5. Application
   │
   ▼
6. Database
```

This prevents jumping immediately into application code when the actual problem may be an image, deployment, secret, network, or database issue.

---

# Basic Operational Flow

A normal production deployment should look like:

```text
Application Change
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
Migration Job
       │
       ▼
Application Deployment
       │
       ▼
Health Verification
```

When something fails, identify the first stage that did not complete successfully.

---

# Accessing the Kubernetes Cluster

Before performing Kubernetes operations, authenticate against the correct production AKS cluster.

The exact Azure authentication procedure depends on the local development environment and Azure setup.

After authentication, verify that the expected cluster is selected.

Example:

```bash
kubectl config current-context
```

Do not assume that the currently selected Kubernetes context is production.

Always verify the context before executing commands that modify resources.

---

# Verify the Production Namespace

The current production namespace is:

```text
shopsphere-production
```

Verify that it exists:

```bash
kubectl get namespace shopsphere-production
```

List workloads in the namespace:

```bash
kubectl get all -n shopsphere-production
```

This provides a quick overview of:

- Deployments
- ReplicaSets
- Pods
- Services

---

# Basic Health Check

The first operational check should be:

```text
Is the application reachable?
        │
        ├── Yes → Check application behavior
        │
        └── No
             │
             ▼
        Check NGINX
             │
             ▼
        Check Service
             │
             ▼
        Check Pods
             │
             ▼
        Check Database
```

Do not immediately restart Pods without determining why the application is unhealthy.

---

# Argo CD Health

Argo CD is the primary deployment-status interface.

An application should normally be:

```text
Synced
+
Healthy
```

Conceptually:

```text
Git Desired State
       │
       ▼
     Argo CD
       │
       ├── Synced
       └── Healthy
```

Important states include:

```text
Synced
OutOfSync
Healthy
Progressing
Degraded
```

An application being `Synced` does not necessarily mean that it is healthy.

Both desired-state synchronization and runtime health must be considered.

---

# Argo CD Troubleshooting

When an application is unhealthy, inspect:

1. Application synchronization state.
2. Application health state.
3. Kubernetes resources owned by the Application.
4. Recent synchronization events.
5. Failed Jobs.
6. Pod status.
7. Pod logs.

The troubleshooting path should be:

```text
Argo CD Application
       │
       ▼
Sync Status
       │
       ▼
Health Status
       │
       ▼
Kubernetes Resource
       │
       ▼
Pod / Job
```

---

# OutOfSync

An `OutOfSync` application means the Kubernetes state does not match the desired state represented by Git.

Conceptually:

```text
Git
 │
 └── Desired State A

Kubernetes
 │
 └── Actual State B
```

Possible causes include:

- A GitOps change has not yet been synchronized.
- Someone manually changed a Kubernetes resource.
- Argo CD synchronization is disabled or failing.
- A resource was modified outside Git.
- A referenced resource cannot be applied.

The first step is to determine why the states differ.

Do not immediately force a synchronization without understanding the difference.

---

# Degraded Application

A `Degraded` application generally indicates that one or more managed resources are not healthy.

Begin with:

```text
Argo CD
   │
   ▼
Identify unhealthy resource
   │
   ├── Deployment
   ├── Pod
   ├── Job
   ├── Service
   └── Ingress
```

Then inspect the specific resource.

---

# Kubernetes Pod Status

List Pods:

```bash
kubectl get pods -n shopsphere-production
```

Example:

```text
NAME                              READY   STATUS
user-service-7c8d9f7b6c-abc12     1/1     Running
user-service-7c8d9f7b6c-def34     1/1     Running
```

Important statuses include:

```text
Running
Pending
CrashLoopBackOff
ImagePullBackOff
ErrImagePull
Completed
Error
```

The status should determine the next troubleshooting step.

---

# Pending Pod

A `Pending` Pod has not been successfully scheduled or started.

Inspect:

```bash
kubectl describe pod <pod-name> -n shopsphere-production
```

Look at the Events section.

Common causes include:

- Insufficient CPU
- Insufficient memory
- Scheduling constraints
- Missing volumes
- Missing secrets
- Missing configuration
- Node availability problems

Do not restart a Pending Pod blindly.

Determine why Kubernetes cannot schedule or initialize it.

---

# CrashLoopBackOff

`CrashLoopBackOff` means the container starts and repeatedly exits.

Start with:

```bash
kubectl logs <pod-name> -n shopsphere-production
```

Then inspect the previous container instance if necessary:

```bash
kubectl logs <pod-name> -n shopsphere-production --previous
```

Also inspect:

```bash
kubectl describe pod <pod-name> -n shopsphere-production
```

Common causes include:

- Application startup failure
- Missing environment variables
- Invalid configuration
- Database connection failure
- Migration-related problems
- Application runtime errors
- Incorrect container command

The correct response is to identify and fix the underlying failure rather than repeatedly restarting the Pod.

---

# ImagePullBackOff

If a Pod reports:

```text
ImagePullBackOff
```

verify:

```text
1. Image name
2. Image tag
3. Docker Hub availability
4. Registry credentials
5. Kubernetes image configuration
```

For example:

```text
shopsphere/user-service:81ab320
```

must actually exist in the configured registry.

This situation often indicates a deployment configuration or image publishing problem.

---

# Verify the Running Image

To determine which image a Deployment is configured to use:

```bash
kubectl get deployment user-service \
  -n shopsphere-production \
  -o jsonpath='{.spec.template.spec.containers[*].image}'
```

The image should match the version declared in the GitOps repository.

The expected relationship is:

```text
Source Commit
      │
      ▼
Docker Image
      │
      ▼
GitOps Image Tag
      │
      ▼
Kubernetes Image
```

If these values do not match, investigate the deployment pipeline.

---

# Inspect Deployment

Check Deployment status:

```bash
kubectl get deployment user-service \
  -n shopsphere-production
```

Describe the Deployment:

```bash
kubectl describe deployment user-service \
  -n shopsphere-production
```

Look for:

- Desired replicas
- Available replicas
- Updated replicas
- Failed events
- ReplicaSet changes
- Container image
- Rollout status

---

# Check Rollout Status

For a normal Deployment:

```bash
kubectl rollout status deployment/user-service \
  -n shopsphere-production
```

A successful rollout should eventually report that the rollout has completed.

If it hangs or fails, inspect:

```text
Deployment
   │
   ▼
ReplicaSet
   │
   ▼
Pods
```

---

# Deployment Rollout Failure

A rollout can fail because of:

- Container startup failure
- Readiness probe failure
- Image pull failure
- Insufficient resources
- Missing configuration
- Missing secrets
- Application runtime failure
- Database connectivity failure

Start with:

```bash
kubectl rollout status deployment/<service> \
  -n shopsphere-production
```

Then inspect the affected Pods.

---

# Readiness Probe Failure

A readiness failure means Kubernetes does not consider the Pod ready to receive traffic.

The flow is:

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
Application Dependencies
```

If readiness fails, inspect the application health endpoint and logs.

The application health system already includes database health information, and the database module exposes a lightweight `SELECT 1` check for this purpose.

Do not disable readiness probes merely to make the Pod appear healthy.

---

# Liveness Probe Failure

A liveness failure can cause Kubernetes to restart the container.

Before changing the probe, determine whether:

- The application is genuinely unhealthy.
- The probe endpoint is incorrect.
- The probe timeout is too aggressive.
- The application requires more startup time.
- A dependency is incorrectly included in the liveness check.

Liveness and readiness have different purposes.

Do not use them interchangeably.

---

# Application Logs

Inspect application logs with:

```bash
kubectl logs <pod-name> \
  -n shopsphere-production
```

Follow logs:

```bash
kubectl logs -f <pod-name> \
  -n shopsphere-production
```

For a previous crashed container:

```bash
kubectl logs <pod-name> \
  -n shopsphere-production \
  --previous
```

The ShopSphere applications use structured logging.

When troubleshooting, look for information such as:

```text
requestId
correlationId
service
event
error
database status
```

Do not expose secrets while copying logs into issues or pull requests.

---

# Database Troubleshooting

If an application cannot communicate with PostgreSQL, separate the problem into:

```text
Configuration
      │
      ▼
Credentials
      │
      ▼
Network
      │
      ▼
PostgreSQL
      │
      ▼
Prisma
```

The application Database module establishes the connection during startup and performs a health check before the application is considered ready.

---

# Database Connection Failure

Typical symptoms include:

```text
Application fails during startup
Readiness probe fails
Database health reports DOWN
Prisma connection errors
```

Check:

1. `DATABASE_URL` reference.
2. Kubernetes Secret.
3. Database hostname.
4. Database name.
5. Database username.
6. Database password.
7. Network connectivity.
8. PostgreSQL availability.
9. Database permissions.

Do not immediately change application code.

Database connectivity failures are often configuration or infrastructure problems.

---

# Database Health

The application database health check performs a lightweight query:

```sql
SELECT 1
```

A successful result means the application can communicate with PostgreSQL.

The health result is conceptually:

```text
Database
   │
   ▼
SELECT 1
   │
   ├── Success → UP
   │
   └── Failure → DOWN
```

The existing application database module reports database health and latency for this purpose.

---

# Database Migration Operations

Database migrations are executed separately from application startup.

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
PostgreSQL
```

The application container itself should not execute migrations every time a Pod starts.

---

# Check Migration Job

List Jobs:

```bash
kubectl get jobs \
  -n shopsphere-production
```

Find the service migration Job:

```text
user-service-migration
```

Inspect it:

```bash
kubectl describe job user-service-migration \
  -n shopsphere-production
```

Then inspect the migration Pod logs.

```bash
kubectl logs <migration-pod> \
  -n shopsphere-production
```

---

# Successful Migration

A successful migration should follow:

```text
Migration Job
     │
     ▼
prisma migrate deploy
     │
     ▼
PostgreSQL
     │
     ▼
Completed
     │
     ▼
Application rollout
```

Verify the Job completed successfully before considering the deployment healthy.

---

# Failed Migration

If the migration fails:

```text
Migration Job
      │
      X
Migration Failed
```

Do not manually start the new application version simply to bypass the failure.

Investigate:

- Migration error
- Database connectivity
- Database permissions
- Existing schema state
- Migration ordering
- Constraint violations
- Application/database compatibility

The application rollout should not be considered successful until the migration problem is resolved.

---

# Migration Failure Recovery

A failed migration should generally follow:

```text
1. Stop and inspect
        │
        ▼
2. Read migration logs
        │
        ▼
3. Determine whether database state changed
        │
        ▼
4. Determine whether migration is safe to retry
        │
        ▼
5. Correct the underlying problem
        │
        ▼
6. Retry using the controlled deployment process
```

Do not manually modify production database schema unless there is a documented emergency procedure.

---

# Database Rollback Warning

Never assume that reverting the application image also reverts the database.

For example:

```text
Version A
    │
    ▼
Migration B
    │
    ▼
Version B
```

If Version B is rolled back:

```text
Version B
    │
    ▼
Version A
```

Migration B may still exist in the database.

Therefore:

```text
Application Rollback
        ≠
Database Rollback
```

Before rolling back an application, verify database compatibility.

---

# NGINX Troubleshooting

If the application Pods are healthy but API requests fail, inspect the ingress layer.

The expected traffic flow is:

```text
Client
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

Check ingress resources:

```bash
kubectl get ingress \
  -n shopsphere-production
```

Describe the ingress:

```bash
kubectl describe ingress <ingress-name> \
  -n shopsphere-production
```

Verify:

- Hostname
- Path
- Backend Service
- Backend Port
- TLS configuration
- Ingress events

---

# API Routing Troubleshooting

For a route such as:

```text
/api/v1/users/*
```

verify:

```text
NGINX
  │
  ▼
user-service
  │
  ▼
User Pods
```

If the request reaches NGINX but not the application:

```text
NGINX
   │
   X
Service / routing
```

If the request reaches the Service but not the Pods:

```text
Service
   │
   X
Pod selector / readiness
```

If the request reaches the Pod but fails:

```text
Pod
   │
   X
Application
```

This layered approach makes routing problems easier to isolate.

---

# Kubernetes Service Troubleshooting

List Services:

```bash
kubectl get services \
  -n shopsphere-production
```

Inspect a Service:

```bash
kubectl describe service user-service \
  -n shopsphere-production
```

Verify that the Service has endpoints.

A Service without healthy endpoints cannot route traffic successfully.

Conceptually:

```text
Service
   │
   ├── Pod A Ready
   ├── Pod B Ready
   └── Pod C Ready
```

If no Pods are ready:

```text
Service
   │
   └── No usable endpoints
```

Investigate Pod readiness and labels.

---

# Label and Selector Problems

A common Kubernetes failure occurs when a Service selector does not match the labels on Pods.

Expected:

```text
Service selector
       │
       ▼
Pod labels
       │
       ▼
Match
```

If they do not match:

```text
Service selector
       │
       X
Pod labels
```

The Service will not route traffic to those Pods.

Inspect:

```bash
kubectl get pods \
  -n shopsphere-production \
  --show-labels
```

and:

```bash
kubectl describe service <service-name> \
  -n shopsphere-production
```

---

# Resource Problems

If Pods cannot start because of resource constraints, inspect:

```bash
kubectl describe pod <pod-name> \
  -n shopsphere-production
```

Look for scheduling events.

Possible causes include:

- CPU exhaustion
- Memory exhaustion
- Insufficient node capacity
- Incorrect resource requests
- Cluster autoscaling limitations

Do not immediately increase resource requests.

First determine whether the workload actually requires more resources or whether the current configuration is incorrect.

---

# Restarting a Pod

A Pod can be restarted for troubleshooting when appropriate.

However, restarting a Pod should not be considered a fix.

If the application repeatedly crashes:

```text
Restart
   │
   ▼
Crash
   │
   ▼
Restart
   │
   ▼
Crash
```

the underlying issue remains.

Use logs and events to identify the cause.

---

# Restarting a Deployment

A Deployment can be restarted when an operational situation requires it.

However, this should not be the first response to an unhealthy deployment.

Before restarting, determine:

- Why is the application unhealthy?
- Is the image correct?
- Are configuration and secrets correct?
- Is PostgreSQL available?
- Are probes correct?
- Is there an active rollout?

If the root cause is a bad image or configuration, restarting the Deployment does not solve the problem.

---

# Manual Kubernetes Changes

Manual changes should be treated as temporary operational actions.

Avoid using:

```bash
kubectl edit
kubectl patch
kubectl apply
```

as the normal production deployment mechanism.

The permanent solution should be:

```text
Change
  │
  ▼
GitOps Repository
  │
  ▼
Argo CD
  │
  ▼
Kubernetes
```

This preserves Git as the source of truth.

---

# Configuration Drift

Configuration drift occurs when Kubernetes differs from Git.

For example:

```text
Git
 │
 └── replicas: 2

Kubernetes
 │
 └── replicas: 3
```

If the difference was not intentionally represented in Git, it is drift.

The correct long-term response is to determine which state is correct and then update Git accordingly.

Do not leave production in an undocumented state.

---

# Deployment Rollback

The preferred rollback mechanism is a GitOps rollback.

Suppose:

```text
Current:
user-service:81ab320
```

and the known-good version is:

```text
Previous:
user-service:7f3a91c
```

Update the GitOps configuration:

```text
81ab320
   │
   ▼
7f3a91c
```

Then commit the change:

```text
fix: rollback user-service to 7f3a91c
```

Argo CD then reconciles the cluster.

---

# Rollback Procedure

Use the following procedure:

```text
1. Identify the failing version.
        │
        ▼
2. Identify the last known-good version.
        │
        ▼
3. Confirm the image exists.
        │
        ▼
4. Check database compatibility.
        │
        ▼
5. Update GitOps image version.
        │
        ▼
6. Commit the rollback.
        │
        ▼
7. Allow Argo CD to synchronize.
        │
        ▼
8. Verify Pods.
        │
        ▼
9. Verify health endpoint.
        │
        ▼
10. Verify API functionality.
```

---

# Kubernetes Rollback

Kubernetes provides native Deployment rollback functionality.

However, for normal ShopSphere deployments, Git should remain the source of truth.

A direct Kubernetes rollback may temporarily change the cluster without changing Git.

That creates:

```text
Git
 │
 └── Version B

Kubernetes
 │
 └── Version A
```

Therefore, if a Kubernetes-native rollback is used during an emergency, the corresponding GitOps state must be reconciled afterward.

---

# Application Rollback Checklist

Before rollback:

- [ ] Identify the failing image.
- [ ] Identify the last known-good image.
- [ ] Confirm the previous image exists.
- [ ] Check database schema compatibility.
- [ ] Check whether migrations were applied.
- [ ] Update the GitOps image tag.
- [ ] Commit the rollback.
- [ ] Verify Argo CD synchronization.
- [ ] Verify Pod health.
- [ ] Verify readiness.
- [ ] Verify API behavior.

---

# Emergency Operations

Emergency changes may sometimes require direct Kubernetes intervention.

Examples include:

```text
Production outage
Argo CD unavailable
Broken deployment
Severe configuration problem
```

In such cases:

```text
1. Restore service.
2. Record what was changed.
3. Determine the permanent Git configuration.
4. Update the GitOps repository.
5. Reconcile Kubernetes with Git.
```

Emergency access must not become an alternative deployment process.

---

# Argo CD Unavailable

If Argo CD itself is unavailable, existing Kubernetes workloads may continue running.

The immediate question is:

```text
Are existing applications healthy?
```

If yes:

```text
Existing workloads
        │
        ▼
Continue operating
```

while Argo CD is investigated.

If an urgent deployment is required while Argo CD is unavailable, the operational decision should be documented and the resulting Kubernetes state must later be reconciled with Git.

---

# Kubernetes API Problems

If Kubernetes itself is unavailable or inaccessible:

```text
Developer
   │
   X
Kubernetes API
```

First determine whether the problem is:

- Local authentication
- Incorrect Kubernetes context
- Azure authentication
- AKS availability
- Network connectivity
- Kubernetes API availability

Do not modify application configuration until the cluster access problem is understood.

---

# Docker Hub Problems

If a new image cannot be pulled:

```text
Kubernetes
    │
    ▼
Docker Hub
    │
    X
Image unavailable
```

Check:

- Image name
- Image tag
- Registry availability
- Registry credentials
- Image architecture
- Whether GitOps references the correct image

The GitOps repository should not reference an image that has not been successfully published.

---

# GitOps Repository Problems

If the GitOps repository contains an invalid configuration:

```text
GitOps
   │
   ▼
Argo CD
   │
   X
Synchronization failure
```

Inspect:

- Git commit
- Kustomize output
- YAML syntax
- Resource references
- Namespace
- Image version
- Secret references

Fix the GitOps configuration and commit the correction.

---

# Kustomize Validation

Before merging a GitOps change, build the target overlay locally.

For example:

```bash
kubectl kustomize apps/user-service/overlays/production
```

or:

```bash
kustomize build apps/user-service/overlays/production
```

The generated configuration should be reviewed before deployment.

The exact validation tooling can evolve as the repository grows.

---

# Git Diff Review

Before committing a production change:

```bash
git diff
```

Verify:

- Only intended resources changed.
- Correct environment is modified.
- Correct service is modified.
- Image tag is correct.
- No secrets were added.
- No unrelated resources changed.

A small Git diff is easier to review and safer to deploy.

---

# Production Deployment Verification

After a successful Argo CD synchronization:

```text
1. Argo CD
        │
        ▼
2. Deployment
        │
        ▼
3. Pods
        │
        ▼
4. Readiness
        │
        ▼
5. Database health
        │
        ▼
6. API
```

Verify the affected service rather than assuming that a successful Argo CD synchronization means the application itself is functioning correctly.

---

# API Verification

After deployment, verify the service's health endpoint.

The expected flow is:

```text
Client
   │
   ▼
NGINX
   │
   ▼
Service
   │
   ▼
Application
   │
   ▼
Health Endpoint
```

If the health endpoint succeeds, perform a small functional API check appropriate to the service.

Do not use production data-destructive operations merely to verify deployment.

---

# Database Verification After Deployment

If a deployment contains a database migration:

```text
Migration Job
      │
      ▼
Completed
      │
      ▼
Application Ready
```

Verify:

- Migration Job completed.
- Application became ready.
- Database health is `UP`.
- Relevant API operations work.

The existing application database module performs its connection verification during startup and provides health status for operational checks.

---

# NGINX Verification After Deployment

If application Pods are healthy but the public API is unavailable:

```text
Application
   │
   ✓
Pods healthy

NGINX
   │
   X
Public API failure
```

Inspect:

```text
Ingress
Service
Endpoints
TLS
Host
Path
```

The application should not be modified until the ingress layer has been ruled out.

---

# Service Dependency Troubleshooting

If Service A depends on Service B:

```text
Service A
   │
   ▼
Service B
```

and Service A is failing, check Service B before changing Service A.

Use:

```text
A
│
├── DNS
├── Network
├── HTTP request
└── B health
```

Do not solve service-to-service problems by giving Service A direct access to Service B's database.

The database ownership boundary must remain intact.

---

# Logging During Incidents

During troubleshooting, use structured logs to correlate events.

Useful fields may include:

```text
requestId
correlationId
service
event
error
timestamp
```

Database lifecycle logs are generated by the Database module itself, including connection start, successful connection, failure, and disconnection.

Do not log:

```text
Passwords
JWT secrets
Database passwords
Access tokens
Private keys
```

---

# Incident Investigation Order

When an application is completely unavailable, use this order:

```text
1. Public endpoint
        │
        ▼
2. NGINX
        │
        ▼
3. Kubernetes Service
        │
        ▼
4. Pods
        │
        ▼
5. Application logs
        │
        ▼
6. Database
```

When only a new deployment is failing:

```text
1. GitOps change
        │
        ▼
2. Image
        │
        ▼
3. Argo CD
        │
        ▼
4. Migration Job
        │
        ▼
5. Deployment
        │
        ▼
6. Pod
```

This avoids troubleshooting unrelated components.

---

# Common Failure Scenarios

## Application Does Not Start

Check:

```text
Pod status
   ↓
Pod logs
   ↓
Environment configuration
   ↓
Secrets
   ↓
Database connection
```

---

## Application Starts but Is Not Ready

Check:

```text
Readiness probe
   ↓
Health endpoint
   ↓
Database health
   ↓
Required dependencies
```

---

## API Returns 404

Check:

```text
Ingress path
   ↓
Service
   ↓
Application route
```

Do not assume the application route is wrong before verifying NGINX routing.

---

## API Returns 502 / 503

Check:

```text
NGINX
   ↓
Service
   ↓
Endpoints
   ↓
Pod readiness
```

A 502/503 often indicates that NGINX cannot successfully reach a healthy backend.

---

## New Image Is Not Running

Check:

```text
GitOps image tag
   ↓
Argo CD sync
   ↓
Deployment image
   ↓
Pod image
```

Verify every layer rather than assuming Argo CD has deployed the image.

---

## Migration Fails

Check:

```text
Migration logs
   ↓
Database connectivity
   ↓
Database permissions
   ↓
Existing schema
   ↓
Migration compatibility
```

Do not bypass the migration failure by manually starting the application unless an emergency procedure explicitly requires it.

---

# Operational Change Rules

When performing an operational change:

1. Understand the failure first.
2. Make the smallest necessary change.
3. Avoid changing multiple unrelated resources.
4. Record emergency changes.
5. Restore Git as the source of truth.
6. Verify the application afterward.
7. Document recurring problems if they reveal a missing operational procedure.

---

# Operational Commands Reference

The following commands are useful for routine investigation.

Check Kubernetes context:

```bash
kubectl config current-context
```

List resources:

```bash
kubectl get all -n shopsphere-production
```

List Pods:

```bash
kubectl get pods -n shopsphere-production
```

Describe a Pod:

```bash
kubectl describe pod <pod-name> \
  -n shopsphere-production
```

View logs:

```bash
kubectl logs <pod-name> \
  -n shopsphere-production
```

Follow logs:

```bash
kubectl logs -f <pod-name> \
  -n shopsphere-production
```

View previous container logs:

```bash
kubectl logs <pod-name> \
  -n shopsphere-production \
  --previous
```

List Deployments:

```bash
kubectl get deployments \
  -n shopsphere-production
```

Check rollout:

```bash
kubectl rollout status deployment/<service> \
  -n shopsphere-production
```

List Services:

```bash
kubectl get services \
  -n shopsphere-production
```

List Ingress resources:

```bash
kubectl get ingress \
  -n shopsphere-production
```

List Jobs:

```bash
kubectl get jobs \
  -n shopsphere-production
```

Describe a Job:

```bash
kubectl describe job <job-name> \
  -n shopsphere-production
```

---

# What Not to Do

Avoid the following operational habits:

```text
Restart everything because one service is unhealthy.

Delete Pods without checking their logs.

Change production configuration directly with kubectl.

Disable health probes to make deployments pass.

Use latest images.

Run migrations manually without understanding the migration state.

Roll back an application without checking database compatibility.

Expose PostgreSQL publicly for troubleshooting.

Copy production secrets into local configuration.

Give one service access to another service's database.

Make several unrelated infrastructure changes during an incident.
```

These practices make the system harder to reason about and can turn a small failure into a larger incident.

---

# Production Incident Checklist

When a production issue occurs:

```text
1. Identify the affected service.
        │
        ▼
2. Check public API availability.
        │
        ▼
3. Check Argo CD.
        │
        ▼
4. Check Kubernetes Deployment.
        │
        ▼
5. Check Pods.
        │
        ▼
6. Check logs.
        │
        ▼
7. Check NGINX.
        │
        ▼
8. Check database.
        │
        ▼
9. Determine root cause.
        │
        ▼
10. Apply smallest safe correction.
        │
        ▼
11. Verify recovery.
        │
        ▼
12. Reconcile any manual changes back into Git.
```

---

# Post-Incident Review

After a significant production issue, record:

```text
What happened?
Why did it happen?
Which service was affected?
When did it begin?
How was it detected?
What was the immediate fix?
What was the root cause?
Was GitOps state affected?
Was database state affected?
Was a rollback required?
What should be changed to prevent recurrence?
```

The goal is not to produce lengthy incident reports for every minor issue.

Document incidents when they reveal an architectural, deployment, security, or operational weakness.

---

# Operational Ownership

The operational responsibility is divided as follows:

```text
GitHub Actions
│
└── Build and publish application images
```

```text
Docker Hub
│
└── Store application images
```

```text
GitOps Repository
│
└── Define desired deployment state
```

```text
Argo CD
│
└── Reconcile desired state
```

```text
Kubernetes
│
└── Run workloads
```

```text
NGINX
│
└── Route public HTTP traffic
```

```text
Managed PostgreSQL
│
└── Store persistent application data
```

This separation should be preserved during troubleshooting.

---

# Operational Principles Summary

The most important operational rules are:

```text
Check before changing.

Git before kubectl.

Argo CD before manual deployment.

Logs before restarting.

Database compatibility before rollback.

Service boundaries before database access.

Small changes before broad changes.

Record emergency changes.

Restore Git as the source of truth.
```

---

# Final Operational Model

The normal operational lifecycle is:

```text
                    Git
                     │
                     ▼
                  Argo CD
                     │
                     ▼
                 Kubernetes
                     │
          ┌──────────┼──────────┐
          │          │          │
          ▼          ▼          ▼
        NGINX     Services    Jobs
          │          │          │
          │          ▼          ▼
          │        Pods      Migrations
          │          │          │
          └──────────┼──────────┘
                     ▼
              Managed PostgreSQL
```

The preferred operational model is therefore:

```text
Git defines what should exist.

Argo CD reconciles it.

Kubernetes runs it.

NGINX exposes it.

PostgreSQL stores its data.

Logs and health checks tell us whether it is working.
```

ShopSphere should remain operationally simple until real requirements justify additional infrastructure, automation, or observability systems.
