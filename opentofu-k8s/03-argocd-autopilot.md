# ArgoCD Autopilot — Übung

## Was ist ArgoCD Autopilot?

**ArgoCD** ist ein GitOps-Tool für Kubernetes: der gewünschte Cluster-Zustand liegt in Git,
ArgoCD sorgt dafür dass der tatsächliche Zustand immer damit übereinstimmt.

**Autopilot** löst das "Bootstrapping-Problem": Wer managed ArgoCD selbst?

```
Ohne Autopilot:
  ArgoCD manuell installieren
  → Apps manuell in ArgoCD anlegen
  → ArgoCD selbst nicht in Git → nicht reproduzierbar

Mit Autopilot:
  ArgoCD installieren + sofort via Git managen
  → ArgoCD managed sich selbst
  → Neuer Cluster? Git klonen + bootstrap = fertig
```

### Repo-Struktur die Autopilot anlegt

```
mein-gitops-repo/
  bootstrap/
    argo-cd.yaml          ← ArgoCD managed sich selbst
    cluster-resources/
  projects/
    mein-projekt.yaml     ← ArgoCD Project (RBAC-Grenze)
  apps/
    mein-projekt/
      nginx/
        base/
          kustomization.yaml
```

---

## Warum das für euren K8s-Cluster wichtig ist

Nach dem OpenTofu + Ansible Deploy habt ihr einen leeren K8s-Cluster.
ArgoCD Autopilot gibt euch:

| Ohne ArgoCD | Mit ArgoCD Autopilot |
|-------------|----------------------|
| `kubectl apply -f ...` manuell | Git Push → automatisch deployed |
| Wer hat was wann deployed? Unklar | Vollständiges Audit-Log in Git |
| Neuen Cluster aufsetzen = alles nochmal von Hand | `argocd-autopilot repo bootstrap` → alles da |
| Unterschiede zwischen Clustern schleichen sich ein | Git ist die einzige Wahrheit |

---

## Voraussetzungen

- Laufender K8s-Cluster (aus OpenTofu-Deploy)
- `kubectl` konfiguriert
- GitHub/GitLab Token mit Repo-Zugriff
- `argocd-autopilot` CLI

---

## Übung

### Schritt 1: CLI installieren

```bash
VERSION=v0.4.20
curl -L --output - \
  https://github.com/argoproj-labs/argocd-autopilot/releases/download/$VERSION/argocd-autopilot-linux-amd64.tar.gz \
  | tar zx

sudo mv ./argocd-autopilot-* /usr/local/bin/argocd-autopilot
argocd-autopilot version
```

---

### Schritt 2: Git-Token und Repo setzen

```bash
export GIT_TOKEN=<dein-token>
export GIT_REPO=https://github.com/<user>/mein-gitops-repo
```

> **Warum Env-Variable statt Flag?** Autopilot liest `GIT_TOKEN` automatisch aus der Umgebung —
> so landet der Token nicht in der Shell-History.

---

### Schritt 3: Bootstrap — mit Server-Side Apply Workaround

> **Hintergrund:** Ab ArgoCD v3.x überschreitet die `ApplicationSet`-CRD das Kubernetes-Annotations-Limit
> (262.144 Bytes). Autopilot nutzt intern Client-Side Apply, das die gesamte CRD als JSON in eine
> Annotation schreibt. Lösung: CRDs vorab mit Server-Side Apply installieren.
>
> Vollständige Erklärung: [Workaround-Dokument](../argocd/autopilot/zu-grosser-annotation-inhalt.md)

```bash
ARGOCD_VERSION=v3.1.5

# CRDs vorab mit Server-Side Apply installieren
kubectl apply --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/crds/application-crd.yaml \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/crds/appproject-crd.yaml \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/crds/applicationset-crd.yaml

# Bootstrap
argocd-autopilot repo bootstrap
```

Autopilot:
1. Erstellt die Repo-Struktur in Git
2. Installiert ArgoCD im Namespace `argocd`
3. Konfiguriert ArgoCD so dass es sich selbst aus Git synct

---

### Schritt 4: Warten + Zugriff

```bash
# Warten bis ArgoCD läuft
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

# Admin-Passwort holen
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

ArgoCD UI erreichbar machen:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# → https://localhost:8080
```

---

### Schritt 5: ServerSideApply aktivieren

**Warum:** Damit zukünftige ArgoCD-Updates (Syncs) ebenfalls Server-Side Apply nutzen
und das Annotations-Problem nicht wieder auftritt.

Im geklonten GitOps-Repo `bootstrap/argo-cd.yaml` bearbeiten:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-cd
  namespace: argocd
spec:
  syncPolicy:
    syncOptions:
      - ServerSideApply=true    # ← hinzufügen
```

```bash
git add bootstrap/argo-cd.yaml
git commit -m "fix: enable ServerSideApply for argo-cd"
git push
```

ArgoCD synct sich automatisch innerhalb von 3 Minuten selbst.

---

### Schritt 6: Erstes Projekt anlegen

**Warum Projekte?** ArgoCD Projects sind RBAC-Grenzen — sie definieren welche Git-Repos
und welche Cluster-Namespaces eine Gruppe von Apps nutzen darf.

```bash
argocd-autopilot project create mein-projekt
```

Das erstellt `projects/mein-projekt.yaml` im Git-Repo und pusht es automatisch.

---

### Schritt 7: Erste App deployen

Als Beispiel: nginx im Namespace `demo`

```bash
argocd-autopilot app create nginx \
  --app github.com/argoproj/argocd-autopilot/examples/nginx \
  --project mein-projekt
```

Autopilot:
1. Erstellt `apps/mein-projekt/nginx/` im Git-Repo
2. ArgoCD erkennt die neue App (via Git-Sync)
3. Nginx wird im Cluster deployed

Status prüfen:

```bash
kubectl get pods -n nginx
argocd app list
```

---

### Schritt 8: GitOps in Aktion — Änderung über Git

**Das ist der Kern von GitOps:** Nie direkt `kubectl apply`, immer über Git.

```bash
# Replicas erhöhen — im GitOps-Repo
cd mein-gitops-repo
vim apps/mein-projekt/nginx/base/deployment.yaml
# replicas: 1 → replicas: 3

git add .
git commit -m "scale: nginx auf 3 Replicas"
git push
```

ArgoCD erkennt die Änderung und synct automatisch:

```bash
# Status beobachten
watch argocd app get nginx
```

> **Manuell sofort synchen:**
> ```bash
> argocd app sync nginx
> ```

---

### Schritt 9: Was passiert bei `kubectl apply` direkt?

Das ist der "Drift"-Fall — jemand ändert den Cluster ohne Git:

```bash
kubectl scale deployment nginx -n nginx --replicas=1
```

ArgoCD erkennt den Unterschied zwischen Git (3 Replicas) und Cluster (1 Replica) und zeigt `OutOfSync`.

Mit Auto-Sync (empfohlen für nicht-Produktions-Cluster) korrigiert ArgoCD das automatisch zurück:

```yaml
# in der App-Definition
syncPolicy:
  automated:
    prune: true      # löscht Ressourcen die in Git nicht mehr existieren
    selfHeal: true   # korrigiert manuelle Änderungen automatisch
```

---

## Zusammenfassung der Übung

| Schritt | Was gelernt |
|---------|-------------|
| 1–2 | CLI + Token-Handling ohne Shell-History |
| 3 | Server-Side Apply Workaround für große CRDs |
| 4 | ArgoCD Bootstrap + erster Zugriff |
| 5 | ArgoCD managed sich selbst via GitOps |
| 6–7 | Projekt + App anlegen mit Autopilot |
| 8 | GitOps-Workflow: Änderung über Git, nicht kubectl |
| 9 | Drift-Erkennung und Auto-Heal |

---

## Verbindung zu OpenTofu

Der komplette Stack in GitOps:

```
OpenTofu (Terraform)          ArgoCD Autopilot
────────────────────          ────────────────
Infrastruktur (VMs,           Workloads (Deployments,
Netzwerk, K8s-Cluster)        Services, ConfigMaps)
         │                              │
         └──────────── Git ─────────────┘
                    (Single Source of Truth)
```

OpenTofu deployed die Infrastruktur, ArgoCD deployed die Applikationen — beide deklarativ, beide in Git, beide reproduzierbar.

---

## Nächste Schritte nach der Übung

- **App of Apps Pattern:** Eine Meta-App die alle anderen Apps managed
- **Sealed Secrets / External Secrets:** Secrets GitOps-fähig machen
- **ArgoCD Image Updater:** Automatisches Update bei neuen Container-Images
- **ApplicationSets:** Automatisch Apps für mehrere Cluster ausrollen
