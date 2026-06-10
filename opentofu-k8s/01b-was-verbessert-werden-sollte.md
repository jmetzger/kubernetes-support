# Was verbessert werden sollte — OpenTofu K8s

Punkte die funktionieren, aber mittel- bis langfristig Probleme verursachen.

---

## 1. Code-Duplikation — fehlendes Modul-Pattern

**Problem:** Jede Komponente (Control-Plane, HAProxy, Worker) hat denselben Provider-Block — 3x derselbe Code.

**Warum schlecht:** Eine Änderung (z.B. Provider-Version-Update) muss an 3 Stellen gemacht werden. Wird eine vergessen, verhält sich der Code inkonsistent.

**Aktuell:**
```
opentofu/k8s/control-plane/main.tf  ← Provider-Block + VM-Resource
opentofu/k8s/haproxy/main.tf        ← identischer Provider-Block + VM-Resource
opentofu/k8s/workernode/main.tf     ← identischer Provider-Block + VM-Resource
```

**Lösung — Modul-Struktur:**

```
opentofu/
  main.tf           ← GEAENDERT: nur noch provider-Block
  control-plane.tf  ← NEU: module "control_plane"
  haproxy.tf        ← NEU: module "haproxy"
  workernode.tf     ← NEU: module "workernode"
  variables.tf      ← GEAENDERT: alle Variablen konsolidiert
  modules/
    vsphere-vm/     ← NEU: data sources + VM resource (kein Provider)
      main.tf
      variables.tf
      outputs.tf
```

Ein einziges `tofu apply` in `opentofu/` deployed alles.

```hcl
# control-plane.tf — statt 80 Zeilen nur noch:
module "control_plane" {
  source = "./modules/vsphere-vm"

  datacenter      = var.datacenter
  cluster         = var.cluster
  datastore       = var.datastore
  network         = var.network
  content_library = var.content_library
  template_name   = var.template_name
  domain          = var.domain
  gateway         = var.gateway
  dns_server      = var.dns_server

  vm_prefix = var.cp_prefix
  vm_count  = var.cp_count
  base_ip   = var.cp_base_ip
  cpu       = var.cp_cpu
  ram       = var.cp_ram
  disk      = var.cp_disk
}
```

Der Provider steht einmal in `main.tf` — alle drei Module erben ihn automatisch.
Detailliertes Beispiel: [04-modul-struktur-vsphere-vm.md](04-modul-struktur-vsphere-vm.md)

---

## 2. Backend nur als Env-Variablen — kein `backend.tf`

**Problem:** Das GitLab-State-Backend wird in jedem `deploy.yml` als 6 Umgebungsvariablen gesetzt — das sind ~50 Zeilen die sich in jedem Playbook wiederholen.

```yaml
# aktuell: in jedem deploy.yml ~6x
environment:
  TF_HTTP_ADDRESS: "https://gitlab.intern/.../state/{{ vm_prefix }}-cp"
  TF_HTTP_LOCK_ADDRESS: "https://gitlab.intern/.../state/{{ vm_prefix }}-cp/lock"
  TF_HTTP_UNLOCK_ADDRESS: "https://gitlab.intern/.../state/{{ vm_prefix }}-cp/lock"
  TF_HTTP_LOCK_METHOD: "POST"
  TF_HTTP_UNLOCK_METHOD: "DELETE"
```

**Lösung — leerer `backend`-Block in `main.tf`:**

```hcl
terraform {
  backend "http" {}   # Werte kommen per -backend-config zur Laufzeit
}
```

```yaml
# deploy.yml — übersichtlicher:
- name: tofu init
  command: >
    tofu init -reconfigure
    -backend-config="address={{ gitlab_state_url }}"
    -backend-config="lock_address={{ gitlab_state_url }}/lock"
    -backend-config="unlock_address={{ gitlab_state_url }}/lock"
    -backend-config="lock_method=POST"
    -backend-config="unlock_method=DELETE"
```

**Praktisch:** URL-Änderung (z.B. neues GitLab-Projekt) nur noch an einer Stelle im Playbook.

---

## 3. `tofu apply -auto-approve` ohne vorheriges Plan

**Problem:** Es wird direkt deployed ohne vorher zu zeigen was sich ändert.

**Warum wichtig:** Ein falscher Variablenwert (z.B. `vm_count = 0` statt `3`) kann alle VMs löschen — ohne Warnung.

```yaml
# aktuell — kein Review möglich:
- name: tofu apply
  command: tofu apply -input=false -auto-approve
```

**Lösung — Plan vor Apply:**

```yaml
- name: tofu plan
  command: tofu plan -input=false -out=tfplan

- name: tofu apply
  command: tofu apply -input=false tfplan
```

**In GitLab CI/CD:** `tfplan` als Job-Artefakt speichern → manueller Review-Schritt möglich bevor Apply läuft:

```yaml
plan:
  script: tofu plan -out=tfplan
  artifacts:
    paths: [tfplan]

apply:
  script: tofu apply tfplan
  when: manual        # ← Mensch bestätigt nach Plan-Review
  needs: [plan]
```

---

## 4. Kein `.terraform.lock.hcl`

**Problem:** Ohne Lockfile zieht `tofu init` beim nächsten Aufruf die aktuell neueste Provider-Version innerhalb des erlaubten Bereichs.

**Warum wichtig:** `version = "~> 2.6"` erlaubt heute `2.6.1`, morgen `2.7.0` — mit potenziellen Breaking Changes.

```bash
# Lockfile erzeugen — einmalig ausführen:
tofu providers lock \
  -platform=linux_amd64 \
  -platform=darwin_amd64

git add .terraform.lock.hcl
git commit -m "chore: add provider lock file"
```

**Danach:** `tofu init` nutzt immer exakt dieselbe Provider-Version auf jedem System.

---

## 5. Inkonsistente Variablen-Benennung

**Problem:** Verschiedene Module verwenden unterschiedliche Konventionen für dasselbe Konzept.

```hcl
# root/variables.tf
variable "dns_servers" { type = list(string) }   # Plural, Liste

# control-plane/variables.tf
variable "dns_server"  { type = string }          # Singular, einzelner String
```

```hcl
# control-plane/main.tf — hardcoded statt Variable
ipv4_netmask = 24    # ← in root ist es var.ip_netmask
```

**Warum schlecht:** Wer ein neues Modul hinzufügt, weiß nicht welche Konvention gilt.
Beim Zusammenführen zu einem Modul (siehe Punkt 1) würden diese Inkonsistenzen Fehler verursachen.

**Lösung:** Variablen-Konventionen in einer `CONVENTIONS.md` oder direkt im Modul dokumentieren,
dann alle Module vereinheitlichen.

---

## 6. `ansible_shell_allow_world_readable_temp: true`

**Problem:** Erlaubt anderen System-Usern auf dem Ansible-Controller die temporären Dateien zu lesen.

```yaml
# aktuell — in jedem deploy.yml
vars:
  ansible_shell_allow_world_readable_temp: true
```

**Warum entstanden:** Ansible läuft als root, schreibt Temp-Dateien in `/tmp` mit restriktiven Rechten —
das schlägt fehl wenn der Ziel-User kein root ist. Die Variable ist ein schneller Workaround.

**Warum problematisch:** Wenn Credentials (z.B. vcenter_password) als Ansible-Variablen vorliegen,
könnten sie über `/tmp` von anderen Prozessen gelesen werden.

**Lösung:**

```yaml
vars:
  ansible_remote_tmp: /root/.ansible/tmp   # nur root lesbar, kein world-readable
```

---

## 7. Doppelte Tasks

**In `haproxy-setup.yml`:** Task "Pakete installieren" ist zweimal identisch vorhanden (Zeilen ~20 und ~29).

**In `k8s-setup.yml`:** Task "Prüfen ob Cluster bereits existiert" ist zweimal vorhanden.

**Warum wichtig:** Beide Tasks werden ausgeführt — doppelter API-Call, verwirrend im Ansible-Output,
und beim zweiten Mal ist `changed` immer `false` was falsche Sicherheit suggeriert.

**Fix:** Einfach den duplizierten Task löschen.

---

## 8. Hardcoded Werte die Variablen sein sollten

**Problem:** Werte die sich je nach Umgebung ändern können, sind direkt im Code.

| Datei | Hardcoded Wert | Problem | Besser |
|-------|---------------|---------|--------|
| `haproxy-setup.yml` | `interface: "ens192"` | Funktioniert nur auf VMware mit vmxnet3 | `{{ ansible_default_ipv4.interface }}` |
| `haproxy-setup.yml` | `auth_pass k8shaproxy` | Keepalived-Passwort im Klartext | Variable aus Vault |
| `k8s-setup.yml` | `calico_version: "v3.31.2"` | Nicht zusammen mit `k8s_version` updatebar | `var.calico_version` |
| `k8s-setup.yml` | `vip: "10.x.x.x"` | In 3 Playbooks separat — 3x ändern bei IP-Wechsel | Zentrale `group_vars/all.yml` |
| `HAProxy/main.tf` | `count = 2` | Anzahl LBs nicht konfigurierbar | `var.lb_count` |

**Praktisch für `vip` — zentrale group_vars:**

```yaml
# group_vars/all.yml
vip: "10.x.x.x"
calico_version: "v3.31.2"
```

Alle Playbooks erben diese Variablen automatisch — einmal ändern, überall wirksam.
