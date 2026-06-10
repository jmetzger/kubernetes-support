# Was gut gemacht ist — OpenTofu K8s

Best Practices die im bestehenden Setup bereits korrekt umgesetzt sind.

---

## 1. Secrets nie im Code — Credential Injector

**Warum wichtig:** Passwörter im Code landen in Git-History, Logs, Backups — für immer.
Selbst nach einem `git rm` sind sie in der History noch vorhanden.

**Wie umgesetzt:** Credentials kommen per AWX Credential Injector als Umgebungsvariablen zur Laufzeit:

```yaml
environment:
  TF_VAR_vcenter_password: "{{ lookup('env', 'VSPHERE_PASSWORD') }}"
```

OpenTofu-Variable als `sensitive` markiert — kein Output in Logs:

```hcl
variable "vcenter_password" {
  type      = string
  sensitive = true
}
```

**Praktisch:** AWX injiziert den Wert beim Job-Start in die Umgebung des Prozesses.
Der Wert existiert nur im RAM des laufenden Prozesses — nie auf Disk, nie in Git.

---

## 2. Provider-Version gepinnt

**Warum wichtig:** Ohne Version-Pinning zieht OpenTofu beim nächsten `tofu init` automatisch
die neueste Version — das kann Breaking Changes mitbringen die heute noch nicht bekannt sind.

```hcl
required_providers {
  vsphere = {
    source  = "hashicorp/vsphere"
    version = "~> 2.6"   # erlaubt 2.6.x, aber nicht 3.0
  }
}
```

**`~>` (Pessimistic Constraint Operator):**
- `~> 2.6` → erlaubt `2.6`, `2.7`, `2.8` — aber nicht `3.0`
- `~> 2.6.0` → erlaubt nur `2.6.x` — kein Minor-Update

**Nächster Schritt:** Zusätzlich `.terraform.lock.hcl` committen — dann ist die exakte Version
(z.B. `2.6.1`) eingefroren, nicht nur der erlaubte Bereich.

---

## 3. IP-Berechnung mit `locals` statt hardcoded

**Warum wichtig:** Wartbarkeit — nur eine Variable ändern statt viele Stellen im Code.
Hardcoded IPs an mehreren Stellen führen bei Änderungen zu Inkonsistenzen.

```hcl
locals {
  cp_ip_prefix = join(".", slice(split(".", var.cp_base_ip), 0, 3))
  cp_ip_start  = tonumber(split(".", var.cp_base_ip)[3])
}

# Verwendung — IPs werden automatisch hochgezählt:
ipv4_address = "${local.cp_ip_prefix}.${local.cp_ip_start + count.index}"
```

**Praktisch:** `var.cp_base_ip = "10.0.0.220"` → VMs bekommen `10.0.0.220`, `10.0.0.221`, `10.0.0.222`
Nur `cp_base_ip` ändern — alle IPs passen sich an.

---

## 4. Separater State pro Komponente

**Warum wichtig:** Ein gemeinsamer State für alle Komponenten bedeutet:
`tofu destroy` auf Worker löscht im Zweifel auch Control-Planes.

**Wie umgesetzt:** Jede Komponente hat einen eigenen State im GitLab-Backend:

```
gitlab-state/k8s-prod-haproxy   ← nur HAProxy VMs
gitlab-state/k8s-prod-cp        ← nur Control-Plane VMs
gitlab-state/k8s-prod-wn        ← nur Worker VMs
```

**Praktisch:** Worker können unabhängig skaliert oder neu gebaut werden,
ohne dass die Control-Plane angefasst wird. Jede Komponente hat ihren eigenen Lifecycle.

---

## 5. Shell-Skripte mit `set -euo pipefail`

**Warum wichtig:** Ohne diese Flags laufen Shell-Skripte bei Fehlern einfach weiter —
das Packer-Template könnte kaputt gebaut werden ohne dass man es merkt.

```bash
set -e        # exit bei jedem Befehl mit Exit-Code != 0
set -u        # exit bei undefined Variable (verhindert stille Tippfehler)
set -o pipefail  # exit wenn irgendein Teil einer Pipe fehlschlägt
```

**Ergänzung für besseres Debugging:**

```bash
set -euo pipefail
trap 'echo "FEHLER in Zeile $LINENO — Exit Code: $?" >&2' ERR
```

Gibt beim Fehlschlag die genaue Zeile aus — wichtig weil Packer kein interaktives
Terminal hat und der Output oft in einer langen Log-Datei verschwindet.

**Achtung:** `set -e` kann zu aggressiv sein:

```bash
grep "pattern" datei.txt   # exit code 1 wenn kein Match → Script bricht ab!
grep "pattern" datei.txt || true   # explizit tolerieren
```

---

## 6. Idempotente Ansible-Tasks

**Warum wichtig:** Playbooks sollen mehrfach ausführbar sein ohne Schaden anzurichten —
z.B. bei erneutem Run nach einem Fehler, oder bei Idempotenz-Tests in CI.

**Muster 1 — `creates:` verhindert zweite Ausführung:**

```yaml
- name: containerd Konfiguration erstellen
  shell: containerd config default > /etc/containerd/config.toml
  args:
    creates: /etc/containerd/config.toml   # überspringen wenn Datei existiert
```

**Muster 2 — `stat` + `when` verhindert doppelten kubeadm init:**

```yaml
- name: Prüfen ob Cluster bereits existiert
  stat:
    path: /etc/kubernetes/admin.conf
  register: k8s_config

- name: kubeadm init
  command: kubeadm init ...
  when: not k8s_config.stat.exists   # nur wenn noch kein Cluster da
```

**Praktisch:** Das zweite Muster ist entscheidend — `kubeadm init` auf einem
bereits initialisierten Cluster würde fehlschlagen oder den Cluster beschädigen.

---

## 7. HA-Setup mit HAProxy + Keepalived

**Warum wichtig:** Ohne HA hat der K8s-API-Server einen Single Point of Failure.
Fällt der einzige Control-Plane aus, ist der Cluster nicht mehr steuerbar —
laufende Workloads laufen weiter, aber kein Deploy, kein Scale, kein Rollout.

```
                    ┌──────────────────┐
                    │  VIP (Keepalived) │
                    │  10.x.x.x:6443   │
                    └────────┬─────────┘
                             │
                    ┌────────┴────────┐
                    │    HAProxy      │
                    │  (2x, VRRP)     │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         Control-Plane-1  CP-2          CP-3
           (etcd)        (etcd)        (etcd)
```

**Zweistufiges HAProxy-Setup — warum:**

1. **haproxy-setup.yml:** HAProxy mit nur CP-1 — weil CP-2 und CP-3 noch nicht existieren
2. **kubeadm init** auf CP-1, dann CP-2 und CP-3 joinen
3. **haproxy-finalize.yml:** HAProxy-Config mit allen drei CPs aktualisieren

Dieser Ablauf ist notwendig weil HAProxy die IPs seiner Backend-Server beim Start
auflösen muss — nicht existierende Hosts würden den HAProxy-Start blockieren.
