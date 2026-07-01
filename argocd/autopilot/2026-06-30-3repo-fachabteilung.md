# GitOps: Repo fuer die Fachabteilung

## Hintergrund

Aufbauend auf dem 2-Repo-Setup fuegen wir ein drittes Repo hinzu.
Das Prinzip ist identisch: ein neues ArgoCD-Project (`team-dev`) mit einer
Root-Application, die auf `applications/` in Repo 3 zeigt.

Repo 3 enthaelt zwei Apps:
- **hello** — eigenes Helm Chart (nginx, im Repo)
- **mariadb** — externes Chart von ArtifactHub (cloudpirates/mariadb, OCI)

```
Repo 1 (argo-gitops-<deinname>)  <-- statisch, nicht anfassen
Repo 2 (helm-chart-templates-<deinname>)  <-- Infra (Traefik, cert-manager)
Repo 3 (app-team-dev-<deinname>)  <-- Fachabteilung
    ├── applications/
    │   ├── hello-app.yaml       <- eigenes Chart
    │   └── mariadb-app.yaml     <- cloudpirates/mariadb (ArtifactHub, OCI)
    ├── helm-values/
    │   └── hello-values.yaml
    └── custom-charts/
        └── hello/
            ├── Chart.yaml
            └── templates/
                ├── deployment.yaml
                └── service.yaml
```

---

## Voraussetzungen

- 2-Repo-Setup laeuft (Uebung `2026-06-30-2repo-gitops-setup.md` abgeschlossen)
- `GIT_TOKEN`, `GIT_REPO`, `MY_NAME` sind noch gesetzt

---

## Schritt 1: Neue Umgebungsvariablen setzen

```
export TEAM_NAME=team-dev
export REPO3=https://gitlab.com/training.tn1/app-${TEAM_NAME}-${MY_NAME}.git
```

---

## Schritt 2: Repo 3 in GitLab anlegen

Im GitLab-Browser:
`https://gitlab.com/training.tn1` → **New project** → **Create blank project**

- Name: `app-team-dev-${MY_NAME}` (z.B. `app-team-dev-jm`)
- Visibility: Private
- **kein** README / .gitignore

---

## Schritt 3: ArgoCD Project fuer die Fachabteilung anlegen

`argocd-autopilot` setzt `sourceRepos: ['*']` als Default — alle Repos und
OCI-Registries sind erlaubt. Fuer den Workshop reicht das.

```
cd
./argocd-autopilot project create ${TEAM_NAME}
```

---

## Schritt 4: Root-Application anlegen (zeigt auf Repo 3)

```
cd
./argocd-autopilot app create root-applications \
  --app $(echo $REPO3 | sed 's|\.git$||')/applications \
  --project ${TEAM_NAME} \
  --type dir
```

```
kubectl get applications -n argocd
```

---

## Schritt 5: Repo 3 klonen und Struktur anlegen

```
cd
git clone https://oauth2:${GIT_TOKEN}@$(echo $REPO3 | sed 's|https://||') app-${TEAM_NAME}-${MY_NAME}
cd ~/app-${TEAM_NAME}-${MY_NAME}
mkdir -p applications helm-values custom-charts/hello/templates
```

---

## Schritt 6: Eigenes Chart anlegen (hello-nginx)

```
cd ~/app-${TEAM_NAME}-${MY_NAME}
```

```
cat > custom-charts/hello/Chart.yaml << 'EOF'
apiVersion: v2
name: hello
description: Einfaches Nginx-Deployment
version: 0.1.0
EOF
```

```
cat > custom-charts/hello/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
spec:
  replicas: {{ .Values.replicas }}
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
        - name: hello
          image: nginx:alpine
          ports:
            - containerPort: 80
EOF
```

```
cat > custom-charts/hello/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: hello
spec:
  selector:
    app: hello
  ports:
    - port: 80
      targetPort: 80
EOF
```

```
cat > helm-values/hello-values.yaml << 'EOF'
replicas: 2
EOF
```

---

## Schritt 7: Application fuer hello-nginx anlegen

```
cd ~/app-${TEAM_NAME}-${MY_NAME}
```

```
cat > applications/hello-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hello
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: ${TEAM_NAME}
  sources:
    - repoURL: ${REPO3}
      targetRevision: main
      path: custom-charts/hello
      helm:
        valueFiles:
          - \$values/helm-values/hello-values.yaml
    - repoURL: ${REPO3}
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: ${TEAM_NAME}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

---

## Schritt 8: Application fuer MariaDB anlegen (ArtifactHub: cloudpirates/mariadb)

Chart-Quelle: https://artifacthub.io/packages/helm/cloudpirates-mariadb/mariadb

> **Hinweis zu OCI + StatefulSets**: Der cloudpirates/mariadb-Chart liegt als OCI-Image
> auf Docker Hub (`registry-1.docker.io/cloudpirates/mariadb`). ArgoCD benoetigt
> den vollen OCI-Pfad inklusive Chart-Name in `repoURL`.
>
> Zusaetzlich setzt Kubernetes nach dem Anlegen automatisch `storageClassName` und
> `volumeMode` in den `volumeClaimTemplates` des StatefulSets. Diese Felder sind
> im StatefulSet unveraenderbar (immutable). Damit ArgoCD diese Drift nicht versucht
> zu patchen, brauchen wir `ignoreDifferences` + `RespectIgnoreDifferences=true`.

```
cd ~/app-${TEAM_NAME}-${MY_NAME}
```

```
cat > applications/mariadb-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mariadb
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: ${TEAM_NAME}
  source:
    repoURL: oci://registry-1.docker.io/cloudpirates/mariadb
    chart: mariadb
    targetRevision: "0.16.5"
    helm:
      values: |
        auth:
          rootPassword: "workshop123"
          database: "workshopdb"
          username: "workshopuser"
          password: "workshop123"
        primary:
          persistence:
            size: 1Gi
  destination:
    server: https://kubernetes.default.svc
    namespace: ${TEAM_NAME}
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      jsonPointers:
        - /spec/volumeClaimTemplates
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
EOF
```

---

## Schritt 9: Repo 3 pushen

```
cd ~/app-${TEAM_NAME}-${MY_NAME}
git add .
git commit -m "add hello and mariadb applications"
git branch -m master main
git push --set-upstream origin main
```

---

## Schritt 10: Status pruefen

```
kubectl get applications -n argocd
```

Erwartete Ausgabe:

```
NAME                           SYNC STATUS   HEALTH STATUS
...
team-dev-root-applications     Synced        Healthy
hello                          Synced        Healthy
mariadb                        Synced        Healthy
```

```
kubectl get pods,statefulset,pvc -n team-dev
```

Erwartete Ausgabe:

```
NAME                        READY   STATUS    RESTARTS   AGE
pod/hello-xxxxxxxxxx-xxxxx  1/1     Running   0          1m
pod/hello-xxxxxxxxxx-xxxxx  1/1     Running   0          1m
pod/mariadb-0               1/1     Running   0          1m

NAME                       READY   AGE
statefulset.apps/mariadb   1/1     1m

NAME                                   STATUS   VOLUME   CAPACITY
persistentvolumeclaim/data-mariadb-0   Bound    ...      1Gi
```

MariaDB-Verbindung testen:

```
kubectl exec -it statefulset/mariadb -n team-dev -- \
  mariadb -u workshopuser -pworkshop123 workshopdb -e "SHOW DATABASES;"
```

---

## Neue App hinzufuegen (Workflow danach)

Nur Repo 3 wird bearbeitet — Repo 1 und Repo 2 bleiben unveraendert:

```
cd ~/app-${TEAM_NAME}-${MY_NAME}
```

```
cat > applications/neue-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: neue-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: ${TEAM_NAME}
  source:
    repoURL: ${REPO3}
    targetRevision: main
    path: custom-charts/neue-app
  destination:
    server: https://kubernetes.default.svc
    namespace: ${TEAM_NAME}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

```
git add .
git commit -m "add neue-app"
git push
```

---

## Aufraeumen

```
cd ~/app-${TEAM_NAME}-${MY_NAME}
rm applications/hello-app.yaml applications/mariadb-app.yaml
git add .
git commit -m "remove all applications"
git push
```

Warten bis ArgoCD die Apps loescht (ca. 60s):

```
kubectl get pods -n team-dev
```

Dann ArgoCD-Objekte aufraumen:

```
cd
./argocd-autopilot app delete root-applications --project ${TEAM_NAME}
./argocd-autopilot project delete ${TEAM_NAME}
```

```
kubectl get applications -n argocd
kubectl get ns ${TEAM_NAME}
```
