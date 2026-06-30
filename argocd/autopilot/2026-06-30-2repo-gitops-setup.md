# GitOps 2-Repo-Setup mit ArgoCD

## Hintergrund

Statt alles in einem Repo zu verwalten, trennen wir:

- **Repo 1** (`gitops-bootstrap`) bleibt nach dem initialen Setup unangeruehrt.
  Es enthaelt nur die Bootstrap-Infrastruktur und einen einzigen Einstiegspunkt,
  der auf Repo 2 zeigt.
- **Repo 2** (`helm-chart-templates-<deinname>`) enthaelt alle Application-Definitionen
  im `applications/`-Ordner sowie Helm-Values und eigene Charts.
  Den Suffix `<deinname>` ersetzt du durch deine Initialen, z.B. `helm-chart-templates-jm`.

Wenn du eine neue App deployen willst, arbeitest du nur noch in Repo 2.

```
Repo 1 (gitops-bootstrap)               Repo 2 (helm-chart-templates-<deinname>)
├── bootstrap/           (autopilot)     ├── applications/
├── projects/                            │   ├── traefik-app.yaml
│   └── infra.yaml       (AppProject)   │   ├── cert-manager-app.yaml
└── apps/                               │   └── cluster-issuer-app.yaml
    └── root-applications/              ├── helm-values/
        └── overlays/                   │   ├── traefik-values.yaml
            └── infra/  (zeigt auf →)  │   └── cert-manager-values.yaml
                                        └── custom-charts/
                                            └── cluster-issuer/
```

---

## Voraussetzungen

- ArgoCD laeuft im Cluster (bootstrap bereits durchgefuehrt)
- `argocd-autopilot` Binary vorhanden
- GitLab-Repo 1 und ein Personal Access Token (PAT)

---

## Schritt 1: Umgebungsvariablen setzen

```
cd
export GIT_TOKEN=<dein-token>
export GIT_REPO=https://gitlab.com/training.tn1/<dein-gitops-repo>.git
# Deine Initialen als Suffix fuer Repo 2, z.B. jm
export MY_NAME=<deine-initialen>
export REPO2=https://gitlab.com/training.tn1/helm-chart-templates-${MY_NAME}.git
```

Repo 1 klonen:

```
git clone https://oauth2:${GIT_TOKEN}@$(echo $GIT_REPO | sed 's|https://||') gitops-bootstrap
cd gitops-bootstrap
```

Aktuelle Struktur anschauen (vom Bootstrap):

```
ls
ls apps/
ls projects/
ls bootstrap/
```

---

## Schritt 2: ArgoCD Credentials fuer Helm-Repos hinterlegen

ArgoCD muss die Helm-Repositories kennen, bevor wir sie in Applications referenzieren.

```
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
sleep 2
argocd login localhost:8080 --insecure --username admin \
  --password $(kubectl get secret argocd-initial-admin-secret -n argocd \
    -o jsonpath="{.data.password}" | base64 -d)
```

Helm-Repos registrieren:

```
argocd repo add https://traefik.github.io/charts \
  --type helm --name traefik

argocd repo add https://charts.jetstack.io \
  --type helm --name jetstack
```

GitLab Repo 2 registrieren (gleicher Token wie Repo 1):

```
argocd repo add ${REPO2} \
  --username oauth2 \
  --password ${GIT_TOKEN}
```

Registrierung pruefen:

```
argocd repo list
```

Erwartete Ausgabe:

```
TYPE  NAME      REPO                                                     STATUS      MESSAGE
helm  traefik   https://traefik.github.io/charts                        Successful
helm  jetstack  https://charts.jetstack.io                              Successful
git   -         https://gitlab.com/training.tn1/helm-chart-templates-jm...        Successful
```

---

## Schritt 3: AppProject 'infra' anlegen

```
cd
./argocd-autopilot project create infra
```

Das legt `gitops-bootstrap/projects/infra.yaml` an. Jetzt `sourceRepos` ergaenzen,
damit ArgoCD die Helm-Repos und GitLab Repo 2 vertrauen darf:

```
cd ~/gitops-bootstrap
```

```
# vi projects/infra.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infra
  namespace: argocd
  labels:
    app.kubernetes.io/managed-by: argocd-autopilot
    app.kubernetes.io/name: infra
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  sourceRepos:
    - ${REPO2}
    - https://traefik.github.io/charts
    - https://charts.jetstack.io
  destinations:
    - server: https://kubernetes.default.svc
      namespace: '*'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
```

Commit und Push:

```
git add projects/infra.yaml
git commit -m "add infra project with sourceRepos"
git push
```

---

## Schritt 4: Root-Application anlegen (zeigt auf Repo 2)

Dieser Befehl erstellt die einzige Application in Repo 1 —
sie zeigt auf den `applications/`-Ordner in Repo 2:

```
cd
./argocd-autopilot app create root-applications \
  --app $(echo $REPO2 | sed 's|\.git$||')/applications \
  --project infra \
  --type dir
```

Das erzeugt in Repo 1:

```
apps/root-applications/overlays/infra/   <- ApplicationSet liest das
```

Danach wird Repo 1 nicht mehr bearbeitet.

Status pruefen:

```
kubectl get applications -n argocd
```

Erwartete Ausgabe (root-applications ist noch Healthy/Unknown, weil Repo 2 leer ist):

```
NAME                  SYNC STATUS   HEALTH STATUS
argo-cd               Synced        Healthy
root                  Synced        Healthy
infra-root-applications  Unknown    Healthy
```

---

## Schritt 5: Repo 2 aufsetzen

GitLab Repo 2 anlegen: `https://gitlab.com/training.tn1/helm-chart-templates-${MY_NAME}`
(leer, ohne README.md)

Dann klonen:

```
cd
git clone https://oauth2:${GIT_TOKEN}@$(echo $REPO2 | sed 's|https://||') helm-chart-templates-${MY_NAME}
cd helm-chart-templates-${MY_NAME}
```

Verzeichnisstruktur anlegen:

```
mkdir -p applications
mkdir -p helm-values
mkdir -p custom-charts/cluster-issuer/templates
```

---

## Schritt 6: Traefik Application anlegen

Multi-Source: Helm-Chart von ArtifactHub + Values-File aus Repo 2.

```
# vi applications/traefik-app.yaml
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
          - $values/helm-values/traefik-values.yaml
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
```

```
# vi helm-values/traefik-values.yaml
deployment:
  replicas: 1
```

---

## Schritt 7: cert-manager Application anlegen

```
# vi applications/cert-manager-app.yaml
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
          - $values/helm-values/cert-manager-values.yaml
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
```

```
# vi helm-values/cert-manager-values.yaml
crds:
  enabled: true
```

---

## Schritt 8: ClusterIssuer Application anlegen

Das ist ein eigenes lokales Chart in Repo 2 — kein Helm-Repo noetig.

### Chart.yaml

```
# vi custom-charts/cluster-issuer/Chart.yaml
apiVersion: v2
name: cluster-issuer
description: Lokales Chart fuer den ClusterIssuer (Let's Encrypt)
version: 0.1.0
```

### Template

```
# vi custom-charts/cluster-issuer/templates/cluster-issuer.yaml
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
```

### Application

```
# vi applications/cluster-issuer-app.yaml
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
```

---

## Schritt 9: Alles in Repo 2 pushen

```
git add .
git commit -m "add traefik, cert-manager, cluster-issuer applications"
git push
```

ArgoCD picked das automatisch auf (root-applications zeigt auf applications/).

---

## Schritt 10: Status pruefen

```
kubectl get applications -n argocd
```

Erwartete Ausgabe:

```
NAME                     SYNC STATUS   HEALTH STATUS
argo-cd                  Synced        Healthy
autopilot-bootstrap      Synced        Healthy
root                     Synced        Healthy
infra-root-applications  Synced        Healthy
traefik                  Synced        Healthy
cert-manager             Synced        Healthy
cluster-issuer           Synced        Healthy
```

```
kubectl get pods -n traefik
kubectl get pods -n cert-manager
kubectl get clusterissuer letsencrypt-prod
```

Erwartete Ausgabe:

```
NAME                   READY   AGE
letsencrypt-prod       True    1m
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

### Applications loeschen (in Repo 2)

```
rm applications/cluster-issuer-app.yaml
rm applications/cert-manager-app.yaml
rm applications/traefik-app.yaml
git add .
git commit -m "remove all applications"
git push
```

ArgoCD synct automatisch und loescht Traefik, cert-manager und den ClusterIssuer im Cluster.

### Project loeschen (in Repo 1)

```
cd ~/gitops-bootstrap
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
root                  Synced        Healthy

Error from server (NotFound): namespaces "traefik" not found
Error from server (NotFound): namespaces "cert-manager" not found
```

---

## Zusammenfassung

| Komponente | Typ | Helm-Repo / Chart-Pfad |
|------------|-----|------------------------|
| Traefik | Helm (ArtifactHub) | `https://traefik.github.io/charts` |
| cert-manager | Helm (ArtifactHub) | `https://charts.jetstack.io` |
| ClusterIssuer | Lokales Chart | `custom-charts/cluster-issuer/` |
