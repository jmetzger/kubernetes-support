# ArgoCD Autopilot Installation mit Server-Side Apply Workaround

## Hintergrund

Ab ArgoCD v3.x überschreitet die `applicationsets.argoproj.io` CRD das Kubernetes-Annotations-Limit von 262.144 Bytes. `argocd-autopilot repo bootstrap` nutzt intern `kubectl apply` (Client-Side), was die gesamte CRD-Definition als JSON in die Annotation `kubectl.kubernetes.io/last-applied-configuration` schreibt. Das schlägt bei großen CRDs fehl.

Dieser Workaround installiert die CRDs vorab mit Server-Side Apply und konfiguriert ArgoCD anschließend so, dass das Problem bei zukünftigen Syncs nicht erneut auftritt.

---

## Voraussetzungen

- `kubectl` mit Zugriff auf den Ziel-Cluster
- `argocd-autopilot` CLI (v0.4.20 oder neuer)
- Git-Token und Repo-URL

```bash
export GIT_TOKEN=<DEIN_TOKEN>
export GIT_REPO=<DEINE_REPO_URL>
```

---

## Schritt 1: argocd-autopilot installieren

```bash
VERSION=v0.4.20
curl -L --output - \
  https://github.com/argoproj-labs/argocd-autopilot/releases/download/$VERSION/argocd-autopilot-linux-amd64.tar.gz | tar zx
sudo mv ./argocd-autopilot-* /usr/local/bin/argocd-autopilot
argocd-autopilot version
```

---

## Schritt 2: ArgoCD CRDs vorab mit Server-Side Apply installieren

Hier verwenden wir die ArgoCD-Version, die Autopilot v0.4.20 mitbringt (v3.1.5). Die CRDs werden mit `--server-side` applied, sodass **keine** `last-applied-configuration` Annotation erzeugt wird.

```bash
ARGOCD_VERSION=v3.1.5

kubectl apply --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/crds/application-crd.yaml \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/crds/appproject-crd.yaml \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/crds/applicationset-crd.yaml
```

Prüfen, dass keine `last-applied-configuration` Annotation existiert:

```bash
kubectl get crd applicationsets.argoproj.io -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | wc -c
```

Erwartete Ausgabe: `0` (keine Annotation vorhanden).

---

## Schritt 3: Bootstrap ausführen

```bash
argocd-autopilot repo bootstrap
```

> **Hinweis:** Autopilot wird versuchen, die CRDs erneut mit Client-Side Apply anzuwenden. Da die CRDs bereits existieren und sich nicht geändert haben, sollte der Apply durchgehen. Falls der Fehler dennoch auftritt, die Annotation manuell entfernen und erneut versuchen:
>
> ```bash
> kubectl annotate crd applicationsets.argoproj.io kubectl.kubernetes.io/last-applied-configuration-
> kubectl annotate crd applications.argoproj.io kubectl.kubernetes.io/last-applied-configuration-
> kubectl annotate crd appprojects.argoproj.io kubectl.kubernetes.io/last-applied-configuration-
> argocd-autopilot repo bootstrap
> ```

---

## Schritt 4: Warten bis ArgoCD läuft

```bash
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
```

Initiales Admin-Passwort auslesen:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

---

## Schritt 5: ServerSideApply für die argo-cd Application aktivieren

Nach dem Bootstrap managt ArgoCD sich selbst über die Application `argo-cd`. Damit zukünftige Syncs (z.B. ArgoCD-Upgrades) ebenfalls Server-Side Apply nutzen, muss die Sync-Option gesetzt werden.

Im GitOps-Repo die Datei `bootstrap/argo-cd.yaml` (oder das entsprechende Application-Manifest) bearbeiten:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-cd
  namespace: argocd
spec:
  # ... bestehende Konfiguration ...
  syncPolicy:
    syncOptions:
      - ServerSideApply=true
```

Änderung committen und pushen — ArgoCD synct sich selbst mit der neuen Option.

---

## Schritt 6: Alte Annotations aufräumen (optional)

Falls durch den Bootstrap doch Annotations erzeugt wurden, können diese nachträglich entfernt werden:

```bash
for crd in applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io; do
  kubectl annotate crd $crd kubectl.kubernetes.io/last-applied-configuration- 2>/dev/null
  echo "Annotation entfernt von: $crd"
done
```

---

## Schritt 7: Global ServerSideApply als Default setzen (optional)

Damit alle ArgoCD Applications standardmäßig Server-Side Apply nutzen:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "application.sync.options": "ServerSideApply=true"
  }
}'
```

Auch diese Änderung sollte im GitOps-Repo persistiert werden (z.B. als Kustomize-Patch unter `bootstrap/argo-cd/`).

---

## Zusammenfassung

| Schritt | Aktion | Zweck |
|---------|--------|-------|
| 1 | autopilot CLI installieren | Tooling bereitstellen |
| 2 | CRDs mit `--server-side` vorab installieren | Annotations-Limit umgehen |
| 3 | `repo bootstrap` ausführen | ArgoCD + GitOps-Struktur aufsetzen |
| 4 | Warten + Passwort holen | Zugriff sicherstellen |
| 5 | `ServerSideApply=true` in argo-cd Application | Zukünftige Syncs absichern |
| 6 | Alte Annotations aufräumen | Sauberer Zustand |
| 7 | Global Default setzen | Alle Apps absichern |

---

## Wiederholbare Nutzung (neuer Cluster)

Für ein Skript, das den gesamten Prozess automatisiert:

```
cd
mkdir argocd-autopilot
cd argocd-autopilot
```

```
nano install.sh
```


```bash
#!/bin/bash
set -euo pipefail

export GIT_TOKEN="${GIT_TOKEN:?Fehler: GIT_TOKEN ist nicht gesetzt}"
export GIT_REPO="${GIT_REPO:?Fehler: GIT_REPO ist nicht gesetzt}"

ARGOCD_VERSION=v3.1.5

echo "==> CRDs mit Server-Side Apply installieren..."
kubectl apply --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/crds/application-crd.yaml \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/crds/appproject-crd.yaml \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/crds/applicationset-crd.yaml

echo "==> Bootstrap starten..."
argocd-autopilot repo bootstrap

echo "==> Annotations aufräumen..."
for crd in applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io; do
  kubectl annotate crd $crd kubectl.kubernetes.io/last-applied-configuration- 2>/dev/null || true
done

echo "==> Warten auf ArgoCD..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo "==> Fertig. Admin-Passwort:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
echo ""
echo "==> WICHTIG: Jetzt ServerSideApply im GitOps-Repo aktivieren!"
echo "    In bootstrap/argo-cd.yaml folgendes unter spec.syncPolicy ergänzen:"
echo ""
echo "    syncPolicy:"
echo "      syncOptions:"
echo "        - ServerSideApply=true"
echo ""
echo "    Dann committen und pushen, damit zukünftige Syncs Server-Side Apply nutzen."
```

```
chmod u+x install.sh
```

---

## Test: Funktioniert ServerSideApply?

Nach der Installation kannst du mit diesem Test prüfen, ob ArgoCD tatsächlich Server-Side Apply nutzt.

```bash
# 1. Künstlich eine dummy Annotation setzen
kubectl annotate crd applicationsets.argoproj.io \
  kubectl.kubernetes.io/last-applied-configuration="test" --overwrite

# 2. Prüfen, ob sie da ist
kubectl get crd applicationsets.argoproj.io \
  -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}'

# 3. Sync in ArgoCD auslösen
argocd app sync argo-cd

# 4. Erneut prüfen: Wurde die Annotation mit dem vollen CRD-Inhalt überschrieben?
kubectl get crd applicationsets.argoproj.io \
  -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | wc -c
```

**Erwartetes Ergebnis:**

- **ServerSideApply aktiv:** Die Annotation bleibt auf `test` (5 Bytes) oder wird entfernt. ArgoCD schreibt kein riesiges JSON rein.
- **ServerSideApply NICHT aktiv:** Die Annotation wird mit dem kompletten CRD-JSON überschrieben (>200.000 Bytes). Dann zurück zu Schritt 5.

> **Hinweis:** ArgoCD synct standardmäßig alle 3 Minuten automatisch. Ein manueller Sync per `argocd app sync` löst den Vorgang sofort aus.
