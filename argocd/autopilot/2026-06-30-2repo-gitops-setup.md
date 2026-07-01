# GitOps 2-Repo-Setup mit ArgoCD

## Hintergrund

Statt alles in einem Repo zu verwalten, trennen wir:

- **Repo 1** (`argo-gitops-<deinname>`) bleibt nach dem initialen Bootstrap unangeruehrt.
  Es enthaelt nur die Bootstrap-Infrastruktur und einen einzigen Einstiegspunkt,
  der auf Repo 2 zeigt.
- **Repo 2** (`helm-chart-templates-<deinname>`) enthaelt alle Application-Definitionen
  im `applications/`-Ordner sowie Helm-Values und eigene Charts.
  Den Suffix `<deinname>` ersetzt du durch deine Initialen, z.B. `jm`.

Wenn du eine neue App deployen willst, arbeitest du nur noch in Repo 2.

```
Repo 1 (argo-gitops-<deinname>)                 Repo 2 (helm-chart-templates-<deinname>)
├── bootstrap/            (autopilot, static)    ├── applications/
├── projects/                                    │   ├── traefik-app.yaml
│   └── infra.yaml        (AppProject)           │   ├── cert-manager-app.yaml
└── apps/                                        │   └── cluster-issuer-app.yaml
    └── root-applications/                       ├── helm-values/
        └── overlays/                            │   ├── traefik-values.yaml
            └── infra/    (zeigt auf Repo 2)     │   └── cert-manager-values.yaml
                                                 └── custom-charts/
                                                     └── cluster-issuer/
```

**Credentials:** argocd-autopilot legt beim Bootstrap automatisch eine Credential-Template
fuer `https://gitlab.com/` an. Repo 2 benoetigt daher keine separate Registrierung.

---

## Voraussetzungen

- ArgoCD laeuft im Cluster (bootstrap bereits durchgefuehrt)
- `argocd-autopilot` Binary vorhanden unter `~/argocd-autopilot`
- GitLab Repo 1 mit PAT vorhanden

---

## Schritt 1: Umgebungsvariablen setzen

```
export PATH=$PATH:~
```

```
cd
# GIT_REPO und GIT_TOKEN sollten bereits gesetzt sein 
```

Repo 1 klonen und Struktur anschauen:

```
cd
git clone https://oauth2:${GIT_TOKEN}@$(echo $GIT_REPO | sed 's|https://||') gitops
cd ~/gitops
ls
ls apps/
ls projects/
```

```
export MY_NAME=<dein-name>
export REPO2=https://gitlab.com/training.tn1/helm-chart-templates-${MY_NAME}.git
```

---

## Schritt 2: Repo 2 in GitLab anlegen

Im GitLab-Browser:
`https://gitlab.com/training.tn1` → **New project** → **Create blank project**

- Name: `helm-chart-templates-${MY_NAME}` (z.B. `helm-chart-templates-jm`)
- Visibility: Private
- **kein** README / .gitignore

---

## Schritt 3: AppProject 'infra' anlegen

`argocd-autopilot` setzt `sourceRepos: ['*']` als Default — alle Helm-Repos und
GitLab-Repos sind erlaubt. Fuer den Workshop reicht das.

```
cd
argocd-autopilot project create infra
```

---

## Schritt 4: Root-Application anlegen (zeigt auf Repo 2)

Dieser Befehl erstellt in Repo 1 den Einstiegspunkt auf `applications/` in Repo 2:

```
cd
argocd-autopilot app create root-applications \
  --app $(echo $REPO2 | sed 's|\.git$||')/applications \
  --project infra \
  --type dir
```

Danach wird Repo 1 nicht mehr bearbeitet.

```
kubectl get applications -n argocd
```

---

## Schritt 5: Repo 2 klonen und Struktur anlegen

```
cd
git clone https://oauth2:${GIT_TOKEN}@$(echo $REPO2 | sed 's|https://||') helm-chart-templates-${MY_NAME}
cd ~/helm-chart-templates-${MY_NAME}
mkdir -p applications helm-values custom-charts/cluster-issuer/templates
```

---

## Schritt 6: Traefik Application anlegen

```
cd ~/helm-chart-templates-${MY_NAME}
```

```
cat > applications/traefik-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: traefik
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infra
  sources:
    - repoURL: https://traefik.github.io/charts
      chart: traefik
      targetRevision: "41.0.0"
      helm:
        valueFiles:
          - \$values/helm-values/traefik-values.yaml
    - repoURL: ${REPO2}
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: traefik
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

```
cat > helm-values/traefik-values.yaml << 'EOF'
deployment:
  replicas: 1
EOF
```

---

## Schritt 7: cert-manager Application anlegen

```
cd ~/helm-chart-templates-${MY_NAME}
```

```
cat > applications/cert-manager-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infra
  sources:
    - repoURL: https://charts.jetstack.io
      chart: cert-manager
      targetRevision: "v1.20.3"
      helm:
        valueFiles:
          - \$values/helm-values/cert-manager-values.yaml
    - repoURL: ${REPO2}
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

```
cat > helm-values/cert-manager-values.yaml << 'EOF'
crds:
  enabled: true
EOF
```

---

## Schritt 8: ClusterIssuer Application anlegen

```
cd ~/helm-chart-templates-${MY_NAME}
```

Chart-Definition:

```
cat > custom-charts/cluster-issuer/Chart.yaml << 'EOF'
apiVersion: v2
name: cluster-issuer
description: Lokales Chart fuer den ClusterIssuer
version: 0.1.0
EOF
```

Template:

```
cat > custom-charts/cluster-issuer/templates/cluster-issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: training@t3company.de
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: traefik
EOF
```

Application:

```
cat > applications/cluster-issuer-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-issuer
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infra
  source:
    repoURL: ${REPO2}
    targetRevision: main
    path: custom-charts/cluster-issuer
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

---

## Schritt 9: Repo 2 pushen

```
cd ~/helm-chart-templates-${MY_NAME}
git add .
git commit -m "add traefik, cert-manager, cluster-issuer applications"
git branch -m master main
git push --set-upstream origin main
```

ArgoCD synct automatisch (root-applications zeigt auf `applications/`).

---

## Schritt 10: Status pruefen

```
kubectl get applications -n argocd
```

Erwartete Ausgabe:

```
NAME                           SYNC STATUS   HEALTH STATUS
argo-cd                        Synced        Healthy
autopilot-bootstrap            Synced        Healthy
cert-manager                   Synced        Healthy
cluster-issuer                 Synced        Healthy
cluster-resources-in-cluster   Synced        Healthy
infra-root-applications        Synced        Healthy
root                           Synced        Healthy
traefik                        Synced        Healthy
```

```
kubectl get pods -n traefik
kubectl get pods -n cert-manager
kubectl get clusterissuer letsencrypt-prod
```

Erwartete Ausgabe:

```
NAME               READY   AGE
letsencrypt-prod   True    1m
```

---

## Workflow danach

| Was | Wo aendern |
|-----|------------|
| Neuer Artifactory-Chart | `applications/<chart>-app.yaml` + `helm-values/<chart>-values.yaml` in Repo 2 |
| Neues lokales Chart | `custom-charts/<name>/` + `applications/<name>-app.yaml` in Repo 2 |
| Repo 1 | wird nicht mehr angefasst |

---

## Aufraeumen

### Applications in Repo 2 loeschen

```
cd ~/helm-chart-templates-${MY_NAME}
rm applications/cluster-issuer-app.yaml
rm applications/cert-manager-app.yaml
rm applications/traefik-app.yaml
git add .
git commit -m "remove all applications"
git push
```

ArgoCD synct automatisch und loescht Traefik, cert-manager und ClusterIssuer.

### Project loeschen (in Repo 1)

```
cd
./argocd-autopilot app delete root-applications --project infra
./argocd-autopilot project delete infra
```

### Status pruefen

```
kubectl get applications -n argocd
kubectl get ns traefik cert-manager
```

Erwartete Ausgabe:

```
NAME                  SYNC STATUS   HEALTH STATUS
argo-cd               Synced        Healthy
autopilot-bootstrap   Synced        Healthy
root                  Synced        Healthy

Error from server (NotFound): namespaces "traefik" not found
Error from server (NotFound): namespaces "cert-manager" not found
```

---

## Repo-Struktur nach der Uebung

```
Repo 1 (argo-gitops-<deinname>)
├── bootstrap/
├── projects/
│   └── infra.yaml
└── apps/
    └── root-applications/
        └── overlays/
            └── infra/

Repo 2 (helm-chart-templates-<deinname>)
├── applications/
│   ├── traefik-app.yaml
│   ├── cert-manager-app.yaml
│   └── cluster-issuer-app.yaml
├── helm-values/
│   ├── traefik-values.yaml
│   └── cert-manager-values.yaml
└── custom-charts/
    └── cluster-issuer/
        ├── Chart.yaml
        └── templates/
            └── cluster-issuer.yaml
```
