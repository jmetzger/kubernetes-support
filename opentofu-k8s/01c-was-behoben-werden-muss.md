# Was behoben werden muss — OpenTofu K8s

Sicherheitsrelevante Punkte mit hoher Priorität.

---

## 1. `PasswordAuthentication yes` im VM-Template

**Problem:** Alle aus dem Packer-Template geklonten VMs erlauben SSH-Login mit Passwort.

**Warum kritisch:** Brute-Force-Angriffe direkt möglich. In einem K8s-Cluster reicht ein
kompromittierter Node für Lateral Movement — von dort aus ist etcd, der API-Server
und alle Workloads erreichbar.

**Aktuell in `user-data`:**
```yaml
ssh:
  allow-pw: true
late-commands:
  - "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /target/etc/ssh/sshd_config"
```

**Fix:**
```yaml
ssh:
  install-server: true
  allow-pw: false                    # ← nur Key-Auth
  authorized-keys:
    - "{{ ssh_public_key }}"         # ← aus Variable, nicht hardcoded
late-commands:
  - "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /target/etc/ssh/sshd_config"
```

**Praktisch:** SSH-Public-Key als Packer-Variable übergeben — jede Umgebung (Prod/Staging)
kann einen eigenen Key verwenden ohne das Template neu zu bauen.

---

## 2. `NOPASSWD:ALL` sudo für ubuntu-User

**Problem:** Jeder mit SSH-Zugang zum Node hat implizit vollen Root-Zugriff ohne Passwort.

**Warum kritisch:** Kompromittierter SSH-Key = sofortiger Root auf dem Node =
Zugriff auf kubelet-Credentials, etcd-Daten, alle Pod-Secrets.

**Aktuell in `user-data`:**
```bash
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu
```

**Fix — nur benötigte Befehle freigeben:**
```bash
# Für Ansible-Verwaltung benötigt:
echo 'ubuntu ALL=(ALL) NOPASSWD: /usr/bin/kubeadm, /usr/bin/kubectl, /bin/systemctl, /usr/bin/apt-get' \
  > /target/etc/sudoers.d/ubuntu
```

**Oder:** Ansible mit einem dedizierten Service-Account betreiben der nur die
notwendigen Rechte hat — nicht mit dem interaktiven `ubuntu`-User.

---

## 3. Zwei verschiedene containerd-Quellen

**Problem:** Packer und Ansible installieren containerd aus unterschiedlichen Quellen.

| | Packer `03-containerd.sh` | Ansible `k8s-setup.yml` |
|---|---|---|
| Paket | `containerd.io` | `containerd` |
| Quelle | Docker-Repo | Ubuntu-Default-Repo |
| Version | Aktueller (z.B. 1.7.x) | Älter (Ubuntu-Paket) |
| Konfigpfad | `/etc/containerd/` | `/etc/containerd/` |

**Warum kritisch:** Das Ansible-Playbook läuft auf VMs die bereits Packer-containerd haben.
Je nach Reihenfolge und APT-Konfiguration kann das Ubuntu-Paket das Docker-Paket überschreiben —
mit einer älteren Version und anderen Standardkonfigurationen.

Symptom: `kubeadm init` schlägt fehl mit kryptischen Fehlern rund um CRI-Sockets.

**Fix — einheitlich Docker-Repo in beiden:**

```yaml
# k8s-setup.yml — statt apt install containerd:
- name: Docker GPG Key hinzufügen
  shell: |
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  args:
    creates: /etc/apt/keyrings/docker.gpg

- name: Docker Repo hinzufügen
  copy:
    dest: /etc/apt/sources.list.d/docker.list
    content: |
      deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable

- name: containerd.io installieren
  apt:
    name: containerd.io
    state: present
    update_cache: true
```

**Oder:** containerd komplett im Packer-Template installieren und im Ansible-Playbook
nur noch konfigurieren (SystemdCgroup aktivieren) — kein zweiter Install-Schritt.

---

## 4. `StrictHostKeyChecking=no` im Ansible-Inventory

**Problem:** SSH-Host-Schlüssel werden nicht verifiziert.

```yaml
# aktuell in generate-inventory.yml
ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
```

**Warum kritisch:** Ein Angreifer könnte sich als K8s-Node ausgeben (MITM).
Ansible würde sich verbinden, Credentials übertragen und Commands ausführen —
ohne Warnung.

**Fix — `known_hosts` beim Deploy befüllen:**

```yaml
- name: SSH Fingerprint der neuen VMs einsammeln
  known_hosts:
    name: "{{ ansible_host }}"
    key: "{{ lookup('pipe', 'ssh-keyscan -H ' + ansible_host) }}"
    path: ~/.ssh/known_hosts
    state: present
  delegate_to: localhost
  loop: "{{ groups['all'] }}"
```

Dieser Task läuft einmalig nach dem VM-Deploy — danach ist `StrictHostKeyChecking` (Default: `yes`) sicher nutzbar.

---

## 5. `validate_certs: false` im AWX-Inventory-Sync

**Problem:** Das TLS-Zertifikat von AWX wird bei API-Calls nicht geprüft.

```yaml
# aktuell in sync-awx-inventory.yml
uri:
  validate_certs: false
```

**Warum kritisch:** MITM-Angriff möglich — jemand könnte AWX-API-Calls abfangen
und manipulieren (z.B. falsches Inventory zurückliefern).

**Fix Option A — gültiges Zertifikat für AWX:**
```yaml
uri:
  validate_certs: true   # Standard, kein extra Parameter nötig
```

**Fix Option B — interne CA explizit angeben:**
```yaml
uri:
  validate_certs: true
  ca_path: /etc/ssl/certs/interne-ca.pem
```

Das interne CA-Zertifikat kann per Ansible auf alle Nodes verteilt werden:
```yaml
- name: Internes CA-Zertifikat installieren
  copy:
    src: files/interne-ca.pem
    dest: /usr/local/share/ca-certificates/interne-ca.crt
  notify: update-ca-certificates
```
