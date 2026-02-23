# HPE CSI Driver – Schritt-für-Schritt Installation
**Setup:** HPE Alletra | Debian 12 (Bookworm) | Helm | iSCSI + Multipath

---

## Voraussetzungen

- Kubernetes Cluster läuft (kubeadm, kubespray o.ä.)
- `kubectl` konfiguriert
- `helm` installiert
- HPE Alletra Array erreichbar vom Cluster
- iSCSI Netzwerk konfiguriert (mind. 2 NICs pro Node empfohlen)

---

## Schritt 1: iSCSI Netzwerk auf Nodes vorbereiten

Auf **jedem Worker Node** sicherstellen, dass die iSCSI-Interfaces konfiguriert sind:

```bash
# Netzwerk-Interfaces prüfen
ip a
```

Für Multipath: zwei separate iSCSI-Interfaces pro Node konfigurieren:
- `iscsi0` → Switch A
- `iscsi1` → Switch B

---

## Schritt 2: Node-Pakete manuell installieren und Multipath konfigurieren (Debian)

> **Hintergrund:** Node Conformance des HPE CSI Drivers würde `multipath-tools`, `open-iscsi`, `sg3_utils` und `nfs-common` automatisch installieren – modifiziert aber `/etc/multipath.conf` nachträglich: Es setzt `find_multipaths` auf `no` und fügt eigene device-Einträge ein. Um **vollständige Kontrolle** über die Multipath-Konfiguration zu behalten, installieren wir alle Pakete manuell und deaktivieren Node Conformance später beim Helm-Install (`disableNodeConformance=true`).

Auf **jedem Worker Node** alle benötigten Pakete installieren und Multipath konfigurieren:

```bash
apt install -y multipath-tools open-iscsi sg3-utils nfs-common

# iSCSI Initiator aktivieren
systemctl enable iscsid
systemctl start iscsid

cat > /etc/multipath.conf << 'EOF'
defaults {
    user_friendly_names yes
    find_multipaths     no
    polling_interval    5
}

blacklist {
    devnode "^(ram|raw|loop|fd|md|dm-|sr|scd|st)[0-9]*"
    devnode "^hd[a-z]"
    devnode "^sda"
}

devices {
    device {
        vendor                 "3PARdata"
        product                "VV"
        path_grouping_policy   group_by_prio
        path_checker           tur
        path_selector          "round-robin 0"
        hardware_handler       "1 alua"
        prio                   alua
        rr_weight              priorities
        rr_min_io              100
        failback               immediate
        no_path_retry          18
        fast_io_fail_tmo       10
    }
}
EOF

systemctl enable multipathd
systemctl restart multipathd

# Konfiguration prüfen
multipath -v2
```

> **Hinweis `find_multipaths no`:** HPE empfiehlt diesen Wert, da die `devices`-Sektion die korrekte Filterung bereits übernimmt. Mit `yes` würde Multipath bei nur einem verfügbaren Pfad (z.B. während Failover) kein dm-Device anlegen.

> **Wichtig:** Die `blacklist`-Regel für `sda` verhindert, dass die Boot-Platte in Multipath aufgenommen wird. Passen Sie diese ggf. an Ihre Umgebung an.

---

## Schritt 3: HPE Helm Repo hinzufügen

```bash
helm repo add hpe-storage https://hpe-storage.github.io/co-deployments/
helm repo update

# Verfügbare Versionen anzeigen
helm search repo hpe-storage/hpe-csi-driver
```

---

## Schritt 4: Namespace erstellen

```bash
kubectl create namespace hpe-storage
```

---

## Schritt 5: Secret für Array-Zugang erstellen

Das Secret enthält die Zugangsdaten zum HPE Alletra Array:

```yaml
# alletra-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alletra-secret
  namespace: hpe-storage
stringData:
  serviceName: alletra6000-csp-svc   # für Alletra 5000/6000
  servicePort: "8080"
  backend: 10.10.10.10               # IP des HPE Arrays
  username: admin
  password: YourPassword
```

```bash
kubectl apply -f alletra-secret.yaml
```

> **Hinweis:** Für **Alletra 9000 / Primera / 3PAR** anderen `serviceName` verwenden:
> `serviceName: primera3par-csp-svc`

---

## Schritt 6: HPE CSI Driver via Helm installieren

Da alle Node-Pakete bereits manuell installiert wurden, wird Node Conformance deaktiviert. So bleibt die `/etc/multipath.conf` unangetastet.

```bash
helm install hpe-csi-driver hpe-storage/hpe-csi-driver \
  --namespace hpe-storage \
  --set disableNodeConformance=true \
  --wait
```

> **Warum `disableNodeConformance=true`?** Node Conformance würde `/etc/multipath.conf` nachträglich modifizieren (u.a. `find_multipaths` überschreiben, eigene device-Einträge einfügen). Da wir Schritt 2 vollständig manuell durchgeführt haben, ist Node Conformance nicht nötig und würde unsere Konfiguration verändern.

---

## Schritt 7: Installation verifizieren

```bash
# Alle CSI Pods prüfen
kubectl get pods -n hpe-storage

# Erwartete Pods:
# hpe-csi-controller-xxx   Running
# hpe-csi-node-xxx         Running (auf jedem Worker Node)
# alletra6000-csp-xxx      Running

# Node Logs prüfen (Node Conformance ist deaktiviert, trotzdem auf Fehler prüfen)
kubectl logs -n hpe-storage -l app=hpe-csi-node | grep -i "error\|iscsi\|multipath"
```

---

## Schritt 8: StorageClass erstellen

```yaml
# storageclass-iscsi.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hpe-alletra-iscsi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.hpe.com
parameters:
  csi.storage.k8s.io/fstype: xfs
  csi.storage.k8s.io/provisioner-secret-name: alletra-secret
  csi.storage.k8s.io/provisioner-secret-namespace: hpe-storage
  csi.storage.k8s.io/controller-publish-secret-name: alletra-secret
  csi.storage.k8s.io/controller-publish-secret-namespace: hpe-storage
  csi.storage.k8s.io/node-stage-secret-name: alletra-secret
  csi.storage.k8s.io/node-stage-secret-namespace: hpe-storage
  csi.storage.k8s.io/node-publish-secret-name: alletra-secret
  csi.storage.k8s.io/node-publish-secret-namespace: hpe-storage
  csi.storage.k8s.io/controller-expand-secret-name: alletra-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: hpe-storage
  accessProtocol: iscsi
  description: "Volume created by HPE CSI Driver"
reclaimPolicy: Delete
allowVolumeExpansion: true
```

```bash
kubectl apply -f storageclass-iscsi.yaml
kubectl get storageclass
```

---

## Schritt 9: Test – PVC erstellen und prüfen

```yaml
# test-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: hpe-alletra-iscsi
  resources:
    requests:
      storage: 10Gi
```

```bash
kubectl apply -f test-pvc.yaml

# Status prüfen – sollte nach kurzer Zeit "Bound" sein
kubectl get pvc test-pvc
```

---

## Schritt 10: Multipath verifizieren (auf Worker Node)

Wenn ein Volume gemountet ist, auf dem Node prüfen:

```bash
# Multipath Devices anzeigen
multipath -ll

# iSCSI Sessions prüfen
iscsiadm -m session

# Erwartete Ausgabe bei korrekt konfiguriertem Multipath:
# 2 Sessions → 2 Pfade → 1 dm-Device (/dev/dm-X)

# Pfad-Status detailliert anzeigen
multipath -v3 2>&1 | grep -E "dm-|status|action"
```

---

## Zusammenfassung der Komponenten

| Komponente | Beschreibung |
|---|---|
| `hpe-csi-controller` | Zentrale CSI Steuerung (1x im Cluster) |
| `hpe-csi-node` | Läuft auf jedem Worker Node, mountet Volumes |
| `alletra6000-csp` | Container Storage Provider, spricht mit dem Array |
| `multipathd` | Auf dem Node-OS, aggregiert iSCSI-Pfade |
| `iscsid` | iSCSI Initiator Service auf dem Node |

---

## Nützliche Links

- SCOD Dokumentation: https://scod.hpedev.io
- Alletra 5000/6000 CSP: https://scod.hpedev.io/csi_driver/container_storage_provider/hpe_alletra_6000/
- Helm Chart Parameter: https://github.com/hpe-storage/co-deployments/tree/master/helm/charts/hpe-csi-driver
