# Traefik und cert-manager via Helm in ArgoCD deployen

## Hintergrund

ArgoCD kann Helm Charts direkt aus einem Helm-Repository deployen — ohne lokales `helm install`.
Die Application-Definition kommt als YAML ins GitOps-Repo, ArgoCD synct automatisch.

Wir legen ein eigenes ArgoCD Project `infra` fuer Infrastruktur-Komponenten an
und deployen dort Traefik und cert-manager als Helm-Apps mit eigenen Values.

### Wie argocd-autopilot Apps organisiert

Das `infra`-Project enthaelt einen ApplicationSet, der nach Dateien sucht:

```
apps/**/infra/config.json
```

Der Pfad `infra` ist der Projektname — hardcoded vom `project create infra` Befehl.
Fuer jede App legen wir an:

```
apps/<app-name>/infra/config.json       <- ApplicationSet liest das, erstellt Zwischen-App
apps/<app-name>/base/kustomization.yml  <- listet die Application-Ressource
apps/<app-name>/base/application.yml    <- eigentliche ArgoCD Application (Helm-Source)
```

Das ist bewusst zweistufig (App-of-Apps):
1. ApplicationSet generiert `infra-<app>` → zeigt auf `apps/<app>/base/`
2. ArgoCD synct `base/` → findet `application.yml` → erstellt Helm-Application

## Schritt 1: Git-Repo klonen

```
cd
export GIT_TOKEN=<dein-token>
export GIT_REPO=<deine-repo-url>

git clone https://oauth2:${GIT_TOKEN}@$(echo $GIT_REPO | sed 's|https://||') gitops
cd gitops
```

Vorhandene Struktur anschauen:

```
ls
ls apps/
ls projects/
```

## Schritt 2: ArgoCD Project 'infra' anlegen

```
cd
./argocd-autopilot project create infra
```

Im GitLab-Repo erscheint jetzt `projects/infra.yaml` mit AppProject + ApplicationSet.

## Schritt 2.5 Achtung änderung abholen (empfohlen) 

```
cd ~/gitops
git pull
```


## Schritt 3: Traefik deployen

Verzeichnisstruktur anlegen:

```
cd ~/gitops
mkdir -p apps/traefik/infra
mkdir -p apps/traefik/base
```

### config.json anlegen

Die `srcRepoURL` zeigt auf dasselbe GitOps-Repo — ArgoCD liest die config.json
aus dem Repo und sucht dann den `srcPath` im selben Repo.

```
nano apps/traefik/infra/config.json
```

```
{
  "appName": "traefik",
  "userGivenName": "traefik",
  "destNamespace": "argocd",
  "destServer": "https://kubernetes.default.svc",
  "srcPath": "apps/traefik/base",
  "srcRepoURL": "$GIT_REPO",
  "srcTargetRevision": "HEAD"
}
```

```
# GIT_REPO-Variable eintragen
sed -i "s|\$GIT_REPO|${GIT_REPO}|g" apps/traefik/infra/config.json
```

### kustomization.yml anlegen

```
# vi apps/traefik/base/kustomization.yml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - application.yml
```

### application.yml anlegen

```
# vi apps/traefik/base/application.yml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: traefik-helm
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infra
  source:
    repoURL: https://helm.traefik.io/traefik
    chart: traefik
    targetRevision: v33.2.1
    helm:
      values: |
        service:
          type: LoadBalancer
  destination:
    server: https://kubernetes.default.svc
    namespace: traefik
  syncPolicy:
    automated:
      allowEmpty: true
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

`ServerSideApply=true` ist noetig, damit ArgoCD CRDs korrekt verwaltet
ohne OutOfSync-Status bei bereits vorhandenen Cluster-CRDs.

### Commit und Push

```
git add apps/traefik/
git commit -m "add traefik helm app"
git push
```

### Status pruefen

ArgoCD erstellt zuerst `infra-traefik` (Zwischen-App), dann `traefik-helm` (Helm-App):

```
kubectl get applications -n argocd
kubectl get pods -n traefik
kubectl get svc -n traefik
```

Erwartete Ausgabe:

```
NAME           SYNC STATUS   HEALTH STATUS
infra-traefik  Synced        Healthy
traefik-helm   Synced        Healthy

NAME           TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)
traefik-helm   LoadBalancer   10.x.x.x      <externe-ip>   80:xxx/TCP,443:xxx/TCP
```

## Schritt 4: cert-manager deployen

```
cd ~/gitops
mkdir -p apps/cert-manager/infra
mkdir -p apps/cert-manager/base
```

### config.json anlegen

```
nano apps/cert-manager/infra/config.json
```

```
{
  "appName": "cert-manager",
  "userGivenName": "cert-manager",
  "destNamespace": "argocd",
  "destServer": "https://kubernetes.default.svc",
  "srcPath": "apps/cert-manager/base",
  "srcRepoURL": "$GIT_REPO",
  "srcTargetRevision": "HEAD"
}
```

```
sed -i "s|\$GIT_REPO|${GIT_REPO}|g" apps/cert-manager/infra/config.json
```

### kustomization.yml anlegen

```
nano apps/cert-manager/base/kustomization.yml
```

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - application.yml
```

### application.yml anlegen

```
# vi apps/cert-manager/base/application.yml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager-helm
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infra
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.16.3
    helm:
      values: |
        crds:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      allowEmpty: true
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### Commit und Push

```
git add apps/cert-manager/
git commit -m "add cert-manager helm app"
git push
```

### Status pruefen

```
kubectl get applications -n argocd
kubectl get pods -n cert-manager
kubectl get crds | grep cert-manager.io | head -5
```

Erwartete Ausgabe:

```
NAME                    SYNC STATUS   HEALTH STATUS
cert-manager-helm       Synced        Healthy
infra-cert-manager      Synced        Healthy

NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-xxxxxx                        1/1     Running   0          2m
cert-manager-cainjector-xxxxxx             1/1     Running   0          2m
cert-manager-webhook-xxxxxx                1/1     Running   0          2m
```

## Schritt 5: ClusterIssuer fuer Let's Encrypt Staging anlegen

Der ClusterIssuer ist kein Helm Chart — das Manifest liegt im GitOps-Repo,
ArgoCD deployt es als normale Kubernetes-Ressource.

```
cd ~/gitops
mkdir -p apps/cluster-issuers/infra
mkdir -p apps/cluster-issuers/base/manifests
```

### config.json anlegen

```
# vi apps/cluster-issuers/infra/config.json
{
  "appName": "cluster-issuers",
  "userGivenName": "cluster-issuers",
  "destNamespace": "cert-manager",
  "destServer": "https://kubernetes.default.svc",
  "srcPath": "apps/cluster-issuers/base",
  "srcRepoURL": "$GIT_REPO",
  "srcTargetRevision": "HEAD"
}
```

```
sed -i "s|\$GIT_REPO|${GIT_REPO}|g" apps/cluster-issuers/infra/config.json
```

### kustomization.yml anlegen

```
# vi apps/cluster-issuers/base/kustomization.yml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - manifests/01-clusterissuer-staging.yml
```

### ClusterIssuer Manifest anlegen

```
# vi apps/cluster-issuers/base/manifests/01-clusterissuer-staging.yml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: training@t3company.de
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
```

### Commit und Push

```
git add apps/cluster-issuers/
git commit -m "add cluster-issuers with letsencrypt staging"
git push
```

### Status pruefen

Zuerst warten bis cert-manager vollstaendig deployed ist, dann:

```
kubectl get applications -n argocd
kubectl get clusterissuer letsencrypt-staging
kubectl describe clusterissuer letsencrypt-staging
```

Erwartete Ausgabe:

```
NAME                   READY   AGE
letsencrypt-staging    True    1m
```

## ArgoCD UI pruefen

Im ArgoCD Web Interface sind jetzt folgende Applications sichtbar:

| Application | Typ | Status |
|-------------|-----|--------|
| infra-traefik | Zwischen-App (kustomize) | Synced, Healthy |
| traefik-helm | Helm Chart | Synced, Healthy |
| infra-cert-manager | Zwischen-App (kustomize) | Synced, Healthy |
| cert-manager-helm | Helm Chart | Synced, Healthy |
| infra-cluster-issuers | Zwischen-App (kustomize) | Synced, Healthy |

## Zusammenfassung

| Komponente | Helm Repo | Namespace | Extra Values |
|------------|-----------|-----------|--------------|
| Traefik | helm.traefik.io/traefik | traefik | LoadBalancer, ServerSideApply |
| cert-manager | charts.jetstack.io | cert-manager | CRDs automatisch, ServerSideApply |
| ClusterIssuer | Git-Repo (Manifest) | - | Let's Encrypt Staging |

### Repo-Struktur nach der Uebung

```
apps/
├── traefik/
│   ├── infra/config.json
│   └── base/
│       ├── kustomization.yml
│       └── application.yml
├── cert-manager/
│   ├── infra/config.json
│   └── base/
│       ├── kustomization.yml
│       └── application.yml
└── cluster-issuers/
    ├── infra/config.json
    └── base/
        ├── kustomization.yml
        └── manifests/
            └── 01-clusterissuer-staging.yml
```
