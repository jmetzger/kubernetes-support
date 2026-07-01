# ArgoCD Web Interface: Service auf LoadBalancer aendern

## Hintergrund

Nach dem Bootstrap ist der `argocd-server`-Service standardmaessig vom Typ `ClusterIP` —
er ist nur clusterweit erreichbar, nicht von aussen.

Damit wir das Web Interface im Browser oeffnen koennen, aendern wir den Service-Typ auf
`LoadBalancer`. Da ArgoCD sich selbst per GitOps verwaltet (`selfHeal: true`), muss die
Aenderung im gitops-Repo gepflegt werden — sonst wuerde ArgoCD sie sofort zuruecksetzen.

Wir nutzen dafuer ein **Kustomize-Patch** im `bootstrap/argo-cd`-Verzeichnis.

---

## Voraussetzungen

- Bootstrap-Uebung abgeschlossen, ArgoCD laeuft im Cluster
- `GIT_TOKEN` und `GIT_REPO` gesetzt (aus der Installations-Uebung)

Umgebungsvariablen neu setzen falls noetig:

```
export GIT_TOKEN=<dein-token>
export GIT_REPO=https://gitlab.com/training.tn1/<dein-gitops-repo>.git
```

---

## Schritt 1: gitops-Repo vorbereiten

```
cd
git clone $GIT_REPO gitops
# username
# und token eingeben 
cd ~/gitops
ls bootstrap/argo-cd/
```

Erwartete Ausgabe:

```
kustomization.yaml
```

---

## Schritt 2: Kustomize-Patch einfuegen

```
cd ~/gitops/bootstrap/argo-cd
cat kustomization.yaml 
```

```
cat > kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
- github.com/argoproj-labs/argocd-autopilot/manifests/base?ref=v0.4.20
patches:
- patch: |-
    apiVersion: v1
    kind: Service
    metadata:
      name: argocd-server
    spec:
      type: LoadBalancer
  target:
    kind: Service
    name: argocd-server
EOF
```

---

## Schritt 3: Aenderung pushen

```
cd ~/gitops
git add bootstrap/argo-cd/kustomization.yaml
git commit -m "patch argocd-server service to LoadBalancer"
git push
```

---

## Schritt 4: Auf ArgoCD-Sync warten

ArgoCD erkennt die Aenderung und patcht den Service automatisch.

```
kubectl get svc argocd-server -n argocd -w
```

Erwartete Ausgabe (nach ca. 10-30 Sekunden):

```
NAME            TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                      AGE
argocd-server   ClusterIP      10.109.4.242   <none>           80/TCP,443/TCP               1h
argocd-server   LoadBalancer   10.109.4.242   <pending>        80:31234/TCP,443:32345/TCP   1h
argocd-server   LoadBalancer   10.109.4.242   164.92.x.x       80:31234/TCP,443:32345/TCP   1h
```

Mit `Ctrl+C` abbrechen sobald eine External-IP erscheint (dauert ca. 60-90 Sekunden).

---

## Schritt 5: Zugangsdaten und URL auslesen

```
# Externe IP des ArgoCD Web Interface
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo
```

```
# Vollstaendige URL
echo "https://$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
```

```
# Benutzername
echo "admin"
```

```
# Passwort
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
echo
```

Damit koennt ihr euch im Browser einloggen:

| Feld | Wert |
|------|------|
| URL | `https://<external-ip>` (TLS-Warnung im Browser bestaetigen) |
| User | `admin` |
| Passwort | Ausgabe des Befehls oben |

---

## Schritt 6: Im Browser pruefen

Browser oeffnen, URL eingeben, TLS-Warnung akzeptieren, mit `admin` einloggen.

Ihr seht die ArgoCD-Uebersicht mit allen euren Applications.

---

## Aufraeumen (Optional)

Den Service wieder auf `ClusterIP` zuruecksetzen — einfach den Patch entfernen:

```
cd ~/gitops/bootstrap/argo-cd
```

```
cat > kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
- github.com/argoproj-labs/argocd-autopilot/manifests/base?ref=v0.4.20
EOF
```

```
cd ~/gitops
git add bootstrap/argo-cd/kustomization.yaml
git commit -m "revert argocd-server service to ClusterIP"
git push
```

ArgoCD synct und loescht den LoadBalancer automatisch.

```
kubectl get svc argocd-server -n argocd
```

Erwartete Ausgabe:

```
NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
argocd-server   ClusterIP   10.109.4.242   <none>        80/TCP,443/TCP   1h
```
