# User Service Helm Chart

## Overview

This Helm chart deploys the ShopSphere User Service.

Features:

- Deployment
- Service
- ServiceAccount
- ConfigMap
- Secret
- Health Probes
- Resource Limits
- Rolling Updates
- Security Contexts

---

## Prerequisites

- Kubernetes 1.30+
- Helm 3.17+
- PostgreSQL
- Existing PostgreSQL Secret

---

## Installation

```bash
helm install user-service charts/user-service
```

---

## Upgrade

```bash
helm upgrade user-service charts/user-service
```

---

## Uninstall

```bash
helm uninstall user-service
```

---

## Configuration

| Parameter        | Description             | Default     |
| ---------------- | ----------------------- | ----------- |
| replicaCount     | Number of replicas      | 1           |
| image.repository | Container image         | ghcr.io/... |
| image.tag        | Image version           | latest      |
| service.type     | Kubernetes Service type | ClusterIP   |
| service.port     | Service port            | 80          |

(Continue for all important values.)

---

## Secrets

Development:

Helm creates JWT Secret.

Production:

Use:

```yaml
secret:
  existingSecret: user-service-secret
```

---

## Database

The application expects a PostgreSQL Secret containing:

- username
- password

---

## Health Checks

- Startup Probe
- Readiness Probe
- Liveness Probe

---

## Security

- Non-root container
- Dropped Linux capabilities
- Read-only root filesystem
- No privilege escalation
- Service Account Token disabled

---

## Production Recommendations

- Use existing Secrets.
- Use private container registry.
- Configure resource requests/limits.
- Use HorizontalPodAutoscaler if needed.
- Enable monitoring and centralized logging.

---

## Directory Structure

```text
charts/user-service/
├── Chart.yaml
├── values.yaml
├── values.schema.json
├── README.md
└── templates/
```

---

## License

Internal ShopSphere Project.
