# OpenTofu K8s — Code-Analyse & Best Practices

## Agenda (Session ~1,5 Std.)

| # | Thema | Zeit |
|---|-------|------|
| 1 | Code-Analyse: Was ist gut, was kann besser | 30 min |
| 2 | Verbesserungen live umsetzen | 20 min |
| 3 | Multi-Cluster Self-Service via GitLab Formular | 20 min |
| 4 | ArgoCD Autopilot — Übung | 20 min |

---

## Überblick der Architektur

```
Packer → VM-Template (vSphere Content Library)
    │
    ▼
OpenTofu → VMs klonen (HAProxy, Control-Plane, Worker)
    │
    ▼
Ansible → K8s einrichten (kubeadm, Calico, HAProxy, Keepalived)
    │
    ▼
Kubernetes Cluster mit VIP (Keepalived)
```

Ausgeführt über **AWX** (Ansible Automation Platform) mit Credential Injector — Secrets kommen nie in den Code.

---

## ✅ Was gut gemacht ist

### 1. Secrets nie im Code — Credential Injector

**Warum wichtig:** Passwörter im Code landen in Git-History, Logs, Backups — für immer.

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

---

### 2. Provider-Version gepinnt

**Warum wichtig:** Ohne Version-Pinning kann morgen ein anderer Provider gezogen werden mit Breaking Changes.

```hcl
required_providers {
  vsphere = {
    source  = "hashicorp/vsphere"
    version = "~> 2.6"   # erlaubt 2.6.x, aber nicht 3.0
  }
}
```

---

### 3. IP-Berechnung mit `locals` statt hardcoded

**Warum wichtig:** Wartbarkeit — nur eine Variable ändern statt viele Stellen im Code.

```hcl
locals {
  cp_ip_prefix = join(".", slice(split(".", var.cp_base_ip), 0, 3))
  cp_ip_start  = tonumber(split(".", var.cp_base_ip)[3])
}

# Verwendung:
ipv4_address = "${local.cp_ip_prefix}.${local.cp_ip_start + count.index}"
```

---

### 4. Separater State pro Komponente

**Warum wichtig:** Wenn Control-Plane und Worker denselben State teilen, riskiert man beim Worker-Delete auch die Control-Planes zu löschen.

```
gitlab-state/k8s-prod-haproxy   ← nur HAProxy VMs
gitlab-state/k8s-prod-cp        ← nur Control-Plane VMs
gitlab-state/k8s-prod-wn        ← nur Worker VMs
```

---

### 5. Shell-Skripte mit `set -euo pipefail`

**Warum wichtig:** Ohne diese Flags laufen Shell-Skripte bei Fehlern einfach weiter — das Template könnte kaputt gebaut werden ohne dass man es merkt.

```bash
set -e        # exit bei Fehler
set -u        # exit bei undefined variable
set -o pipefail  # exit wenn Teil einer Pipe fehlschlägt
```

**Ergänzung für besseres Debugging:**

```bash
set -euo pipefail
trap 'echo "FEHLER in Zeile $LINENO — Exit Code: $?" >&2' ERR
```

Gibt beim Fehlschlag die genaue Zeile aus — wichtig weil Packer kein interaktives Terminal hat.

---

### 6. Idempotente Ansible-Tasks

**Warum wichtig:** Playbooks sollen mehrfach ausführbar sein ohne Schaden anzurichten.

```yaml
# Idempotent: creates: verhindert zweite Ausführung
- name: containerd Konfiguration erstellen
  shell: containerd config default > /etc/containerd/config.toml
  args:
    creates: /etc/containerd/config.toml

# Idempotent: stat + when verhindert doppelten kubeadm init
- name: Prüfen ob Cluster bereits existiert
  stat:
    path: /etc/kubernetes/admin.conf
  register: k8s_config

- name: kubeadm init
  command: kubeadm init ...
  when: not k8s_config.stat.exists
```

---

### 7. HA-Setup durchdacht

**Warum wichtig:** Single Point of Failure beim API-Server verhindert Control-Plane-Updates ohne Downtime.

```
                    ┌─────────────────┐
                    │   VIP (Keepalived) │
                    │   10.x.x.x:6443  │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │    HAProxy      │
                    │  (2x, VRRP)    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         Control-Plane-1  CP-2          CP-3
```

Zweistufiges HAProxy-Setup: Erst mit einem CP deployen, dann nach kubeadm-Init alle CPs eintragen.

---

## ⚠️ Was verbessert werden sollte

### 1. Code-Duplikation — fehlendes Modul-Pattern

**Problem:** Jede Komponente (Control-Plane, HAProxy, Worker) hat denselben Provider-Block — 3x derselbe Code.

**Warum schlecht:** Änderung an einer Stelle muss 3x gemacht werden. Provider-Version-Update wird leicht vergessen.

**Lösung — Modul-Struktur:**

```
opentofu/
  modules/
    vsphere-vm/         ← einmal schreiben
      main.tf
      variables.tf
      outputs.tf
  k8s/
    control-plane/
      main.tf           ← nur noch Aufruf
      variables.tf
    workernode/
      main.tf
    haproxy/
      main.tf
```

```hcl
# k8s/control-plane/main.tf — statt 80 Zeilen nur noch:
module "controlplane" {
  source     = "../../modules/vsphere-vm"
  vm_prefix  = var.cp_prefix
  vm_count   = var.cp_count
  vm_cpu     = var.cp_cpu
  vm_ram     = var.cp_ram * 1024
  base_ip    = var.cp_base_ip
}
```

---

### 2. Backend nur als Env-Variablen — kein `backend.tf`

**Problem:** Das GitLab-State-Backend wird in jedem `deploy.yml` als ~6 Umgebungsvariablen gesetzt. Das sind ~50 Zeilen die sich wiederholen.

**Lösung — `backend.tf` mit leerem Block:**

```hcl
# modules/vsphere-vm/backend.tf
terraform {
  backend "http" {}   # Werte kommen per -backend-config
}
```

```yaml
# deploy.yml — nur noch eine Zeile statt sechs:
- name: tofu init
  command: >
    tofu init -reconfigure
    -backend-config="address={{ gitlab_state_url }}"
    -backend-config="lock_address={{ gitlab_state_url }}/lock"
    -backend-config="unlock_address={{ gitlab_state_url }}/lock"
```

---

### 3. `tofu apply -auto-approve` ohne vorheriges Plan

**Problem:** Ohne Plan wird direkt deployed — kein Review möglich, Fehler werden nicht frühzeitig erkannt.

**Warum wichtig:** Ein falscher Variable-Wert kann VMs löschen oder falsch konfigurieren.

**Lösung:**

```yaml
- name: tofu plan
  command: tofu plan -input=false -out=tfplan
  # In GitLab CI: tfplan als Artefakt speichern → manueller Review möglich

- name: tofu apply
  command: tofu apply -input=false tfplan
  # Nur den geprüften Plan anwenden
```

---

### 4. Kein `.terraform.lock.hcl`

**Problem:** Ohne Lockfile sind Provider-Versionen nicht reproduzierbar. `~> 2.6` erlaubt `2.6`, `2.7`, `2.8` ...

**Warum wichtig:** Heute funktioniert es, morgen nach einem Provider-Update nicht mehr.

**Lösung:**

```bash
tofu providers lock
git add .terraform.lock.hcl
git commit -m "chore: add terraform lock file"
```

---

### 5. Inkonsistente Variablen-Benennung

**Problem:** Verschiedene Module verwenden unterschiedliche Konventionen für dasselbe Konzept.

```hcl
# root/variables.tf
variable "dns_servers" { type = list(string) }  # Liste

# control-plane/variables.tf
variable "dns_server"  { type = string }         # einzelner String
```

```hcl
# control-plane/main.tf — hardcoded statt Variable
ipv4_netmask = 24    # ← sollte var.ip_netmask sein wie in root
```

**Lösung:** Einheitliche Variablen-Konventionen im Modul definieren.

---

### 6. `ansible_shell_allow_world_readable_temp: true`

**Problem:** Erlaubt anderen System-Usern die temporären Ansible-Dateien zu lesen. Entstand weil Ansible als root läuft.

**Warum problematisch:** Wenn Credentials in Ansible-Variablen stecken, könnten sie über `/tmp` lesbar sein.

**Lösung:**

```yaml
# statt ansible_shell_allow_world_readable_temp
vars:
  ansible_remote_tmp: /root/.ansible/tmp   # nur root lesbar
```

---

### 7. Doppelte Tasks

In `haproxy-setup.yml` ist der Task "Pakete installieren" zweimal identisch vorhanden.
In `k8s-setup.yml` ist "Prüfen ob Cluster bereits existiert" zweimal vorhanden.

**Warum wichtig:** Doppelte Tasks werden beide ausgeführt — unnötiger API-Call, verwirrend im Output.

---

### 8. Hardcoded Werte die Variablen sein sollten

| Datei | Wert | Besser |
|-------|------|--------|
| `haproxy-setup.yml` | `interface: "ens192"` | `{{ ansible_default_ipv4.interface }}` |
| `haproxy-setup.yml` | `auth_pass k8shaproxy` | Variable aus Vault |
| `k8s-setup.yml` | `calico_version: "v3.31.2"` | Variable wie `k8s_version` |
| `k8s-setup.yml` | `vip: "10.x.x.x"` | Zentrale group_vars statt 3x separat |
| `HAProxy/main.tf` | `count = 2` | `var.lb_count` |

---

## ❌ Was behoben werden muss

### 1. `PasswordAuthentication yes` im VM-Template

**Problem:** Alle geklonten VMs erlauben SSH-Login mit Passwort.

**Warum kritisch:** Brute-Force-Angriffe möglich. In einem K8s-Cluster reicht ein kompromittierter Node für Lateral Movement.

**Lösung in `user-data`:**

```yaml
ssh:
  install-server: true
  allow-pw: false        # ← nur Key-Auth
  authorized-keys:
    - "{{ ssh_public_key }}"  # ← aus Variable, nicht hardcoded
```

---

### 2. `NOPASSWD:ALL` sudo für ubuntu-User

**Problem:** Jeder mit SSH-Zugang hat implizit vollen Root-Zugriff ohne Passwort.

**Warum kritisch:** Kompromittierter SSH-Key = voller Cluster-Zugriff.

**Lösung:** Nur die tatsächlich benötigten Befehle freigeben:

```bash
# statt NOPASSWD:ALL
ubuntu ALL=(ALL) NOPASSWD: /usr/bin/kubeadm, /usr/bin/kubectl, /bin/systemctl
```

---

### 3. Zwei verschiedene containerd-Quellen

**Problem:**
- Packer-Script (`03-containerd.sh`): installiert `containerd.io` aus **Docker-Repo**
- Ansible (`k8s-setup.yml`): installiert `containerd` aus **Ubuntu-Default-Repo**

**Warum kritisch:** Zwei verschiedene Pakete mit unterschiedlichen Versionen, Konfigurationspfaden und Update-Zyklen. Kann zu schwer debuggbaren Konflikten führen wenn z.B. das Ansible-Playbook auf einem Template läuft das bereits Docker-containerd hat.

**Lösung:** Einheitlich `containerd.io` aus Docker-Repo — aktueller, besser getestet mit K8s.

---

### 4. `StrictHostKeyChecking=no`

```yaml
ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
```

**Problem:** MITM-Angriffe werden nicht erkannt — jemand könnte sich als K8s-Node ausgeben.

**Lösung:** `known_hosts` beim Deploy automatisch befüllen:

```yaml
- name: SSH Fingerprint holen und speichern
  known_hosts:
    name: "{{ ansible_host }}"
    key: "{{ lookup('pipe', 'ssh-keyscan ' + ansible_host) }}"
    state: present
```

---

### 5. `validate_certs: false` in AWX-Inventory-Sync

**Problem:** TLS-Zertifikat von AWX wird nicht geprüft — MITM möglich.

**Lösung:** Entweder gültiges Zertifikat für AWX, oder CA-Zertifikat explizit angeben:

```yaml
uri:
  validate_certs: true
  ca_path: /etc/ssl/certs/intern-ca.pem
```

---

## Zusammenfassung

| Kategorie | Status | Priorität |
|-----------|--------|-----------|
| Secrets-Handling (AWX Credential Injector) | ✅ Gut | — |
| Provider-Version gepinnt | ✅ Gut | — |
| HA-Architektur (HAProxy + Keepalived) | ✅ Gut | — |
| Idempotenz Ansible | ✅ Größtenteils gut | — |
| Code-Duplikation (kein Modul-Pattern) | ⚠️ Verbessern | Mittel |
| Backend-Konfiguration | ⚠️ Verbessern | Mittel |
| `tofu plan` vor apply | ⚠️ Verbessern | Hoch |
| Lockfile fehlt | ⚠️ Verbessern | Mittel |
| Doppelte Tasks | ⚠️ Verbessern | Niedrig |
| PasswordAuthentication yes | ❌ Beheben | Hoch |
| NOPASSWD:ALL sudo | ❌ Beheben | Hoch |
| Zwei containerd-Quellen | ❌ Beheben | Hoch |
| StrictHostKeyChecking=no | ❌ Beheben | Mittel |
| validate_certs: false (AWX) | ❌ Beheben | Mittel |
