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

Details mit Erklärungen und Code-Beispielen: [01a-was-gut-ist.md](01a-was-gut-ist.md)

**Kurzübersicht:**

| # | Best Practice | Warum |
|---|---------------|-------|
| 1 | Secrets per AWX Credential Injector | Nie in Git-History oder Logs |
| 2 | Provider-Version gepinnt (`~> 2.6`) | Kein ungewolltes Breaking-Update |
| 3 | IP-Berechnung mit `locals` | Eine Variable ändern → alles passt |
| 4 | Separater State pro Komponente | Worker löschen ohne CP-Risiko |
| 5 | `set -euo pipefail` + `trap ERR` | Packer-Build bricht bei Fehler sauber ab |
| 6 | Idempotente Ansible-Tasks (`creates`, `stat+when`) | Mehrfach ausführbar ohne Schaden |
| 7 | HAProxy + Keepalived HA-Setup | Kein Single Point of Failure am API-Server |

---

## ⚠️ Was verbessert werden sollte

Details mit Erklärungen und Code-Beispielen: [01b-was-verbessert-werden-sollte.md](01b-was-verbessert-werden-sollte.md)

**Kurzübersicht:**

| # | Problem | Lösung | Priorität |
|---|---------|--------|-----------|
| 1 | Provider-Block 3x dupliziert | Modul `modules/vsphere-vm` | Mittel |
| 2 | Backend nur als Env-Variablen | Leerer `backend "http" {}` Block | Mittel |
| 3 | `tofu apply -auto-approve` ohne Plan | `tofu plan -out=tfplan` + manueller Review | Hoch |
| 4 | Kein `.terraform.lock.hcl` | `tofu providers lock` + committen | Mittel |
| 5 | Inkonsistente Variablen (`dns_server` vs `dns_servers`) | Einheitliche Konventionen im Modul | Niedrig |
| 6 | `ansible_shell_allow_world_readable_temp: true` | `ansible_remote_tmp: /root/.ansible/tmp` | Mittel |
| 7 | Doppelte Tasks in Playbooks | Duplikate löschen | Niedrig |
| 8 | Hardcoded Werte (`interface`, `vip`, `calico_version`) | Zentrale `group_vars/all.yml` | Mittel |

---

## ❌ Was behoben werden muss

Details mit Erklärungen und Code-Beispielen: [01c-was-behoben-werden-muss.md](01c-was-behoben-werden-muss.md)

**Kurzübersicht:**

| # | Problem | Risiko | Priorität |
|---|---------|--------|-----------|
| 1 | `PasswordAuthentication yes` im VM-Template | Brute-Force SSH auf alle K8s-Nodes | Hoch |
| 2 | `NOPASSWD:ALL` sudo | SSH-Key kompromittiert = Root auf Node | Hoch |
| 3 | Zwei containerd-Quellen (Docker + Ubuntu) | Stille Überschreibung, kaputtes kubeadm | Hoch |
| 4 | `StrictHostKeyChecking=no` | MITM beim Ansible-Deploy | Mittel |
| 5 | `validate_certs: false` (AWX) | MITM auf AWX-API | Mittel |

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
