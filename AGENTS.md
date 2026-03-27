# AGENTS.md - AI Coding Agent Guidelines

## Repository Overview

This is a **Kubernetes GitOps homelab infrastructure** repository using [FluxCD](https://fluxcd.io/) to manage cluster state. It runs on [Talos Linux](https://www.talos.dev/) with applications deployed via Helm and Kustomize.

**Key Technologies:**
- FluxCD (GitOps continuous delivery)
- Kustomize (configuration management)
- SOPS + age (secrets encryption)
- Helm (application packaging)
- Talos Linux (immutable Kubernetes OS)

## Build / Lint / Test Commands

### Validate All Kustomizations
```bash
# Validate all kustomize builds across the cluster
find kubernetes/main/apps -name "kustomization.yaml" -exec dirname {} \; | \
  xargs -I {} sh -c 'echo "Building {}" && kustomize build {} > /dev/null || exit 1'
```

### Validate Single Application
```bash
# Test a specific application's kustomization
kustomize build kubernetes/main/apps/<app-name>/app

# Example: Test audiobookshelf
kustomize build kubernetes/main/apps/audiobookshelf/app
```

### YAML Validation (if yamllint installed)
```bash
# Lint all YAML files
yamllint kubernetes/

# Lint specific file
yamllint kubernetes/main/apps/<app-name>/app/<file>.yaml
```

### Kubernetes Schema Validation (if kubeconform installed)
```bash
# Validate Kubernetes manifests against schemas
kustomize build kubernetes/main/apps/<app-name>/app | kubeconform -strict
```

### Check SOPS Encryption
```bash
# Verify secrets are properly encrypted
sops -d kubernetes/main/apps/<app-name>/app/<secret>.sops.yaml > /dev/null && echo "Valid"
```

### Flux Validation
```bash
# Validate Flux Kustomization resources
flux get kustomizations

# Reconcile specific app manually
flux reconcile kustomization <app-name>
```

## Code Style Guidelines

### File Naming Conventions
- Use **kebab-case** for all filenames: `my-config.yaml`, `deployment.yaml`
- Secrets must use `.sops.yaml` extension: `secret.sops.yaml`
- Kustomization files must be named exactly: `kustomization.yaml`
- Application entry point: `ks.yaml` (Flux Kustomization resource)

### Directory Structure
```
apps/<app-name>/
├── ks.yaml                    # Flux Kustomization (root resource)
└── app/
    ├── kustomization.yaml     # Lists all resources
    ├── namespace.yaml         # App namespace
    ├── repository.yaml        # HelmRepository (if needed)
    ├── release.yaml           # HelmRelease
    ├── *.sops.yaml           # Encrypted secrets
    └── ...                   # Additional manifests
```

### YAML Formatting
- **Indentation:** 2 spaces (no tabs)
- **Document separators:** Use `---` at start of each file
- **Line endings:** Unix (LF)
- **Trailing whitespace:** Remove trailing whitespace
- **Empty lines:** Single blank line between resources
- **Quotes:** Use double quotes for strings with special characters

### Kubernetes Resource Standards

**Namespace Labels (Required):**
```yaml
metadata:
  labels:
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/warn: privileged
    goldilocks.fairwinds.com/enabled: "true"
```

**Common Metadata (Required in ks.yaml):**
```yaml
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app  # Anchor reference
```

**Flux Kustomization Template:**
```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app-name>
  namespace: flux-system
spec:
  targetNamespace: <app-name>
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/<app-name>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: false
  interval: 30m
  retryInterval: 1m
  timeout: 5m
```

### Secrets Management (SOPS)

**ALWAYS encrypt sensitive values:**
- All secrets must be stored in files ending with `.sops.yaml`
- Use `sops` CLI to edit: `sops <file>.sops.yaml`
- Never commit plaintext secrets
- Follow the encryption regex pattern: `^(data|stringData)$`

**Creating New Encrypted Secret:**
```bash
cat <<EOF > secret.sops.yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
  namespace: <namespace>
stringData:
  KEY: "value"  # Will be encrypted
EOF
sops -e -i secret.sops.yaml
```

### HelmRelease Conventions

**Standard HelmRelease Structure:**
```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app-name>
  namespace: <namespace>
spec:
  interval: 30m
  chart:
    spec:
      chart: <chart-name>
      version: "x.x.x"  # Pin version
      sourceRef:
        kind: HelmRepository
        name: <repo-name>
        namespace: flux-system
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  values:
    # App-specific values
```

### Variable References
- Use `${SECRET_EXTERNAL_DOMAIN}` for external domain references
- Use anchors (`&app`) and aliases (`*app`) for consistent naming
- Store cluster-wide vars in `kubernetes/main/flux-system/vars/`

## Error Handling

**No Automated Tests:** This repo has no traditional test suite. Validation is done via:
1. `kustomize build` success
2. Flux reconciliation status
3. Kubernetes manifest schema validation

**Debugging Tips:**
- Check Flux reconciliation: `flux get kustomizations --watch`
- Check pod status: `kubectl get pods -n <namespace>`
- View logs: `kubectl logs -n flux-system -l app=kustomize-controller`

## PR Workflow

Before submitting changes:
1. Run `kustomize build` on affected app(s)
2. Ensure secrets are encrypted with `.sops.yaml` extension
3. Verify YAML indentation (2 spaces)
4. Check that namespaces include required labels
5. Validate syntax with `yamllint` if available

## Resources

- [Flux Documentation](https://fluxcd.io/flux/)
- [Kustomize Reference](https://kubectl.docs.kubernetes.io/references/kustomize/)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [Talos Linux Docs](https://www.talos.dev/v1.9/)
- Based on [flux-cluster-template](https://github.com/onedr0p/flux-cluster-template)
