# GitLab CI/CD Deployment mit OpenTofu

## Warum kein AWX deploy.yml mehr noetig ist

AWX brauchte ein Ansible Playbook als Wrapper, weil AWX nur Playbooks ausfuehren
kann. GitLab CI/CD kann direkt Shell-Befehle ausfuehren — kein Ansible-Wrapper noetig.

```
AWX:
  Survey-Formular → deploy.yml → tofu init → tofu apply

GitLab CI/CD:
  Run pipeline → .gitlab-ci.yml → tofu init → tofu apply
```

---

## Dateistruktur

Die Pipeline ist in separate Dateien aufgeteilt — jeder Workflow fuer sich lesbar
und aenderbar ohne die anderen zu beruehren:

```
.gitlab-ci.yml          ← stages, variables, include
ci/
  packer.yml            ← packer-k8s, packer-haproxy
  opentofu.yml          ← plan, deploy, destroy
```

**Warum `include: local` statt alles in einer Datei:**
Packer-Team und OpenTofu-Team koennen unabhaengig arbeiten.
Ausserdem bleibt jede Datei ueberschaubar.

```yaml
# .gitlab-ci.yml — nur Struktur und Inputs
include:
  - local: 'ci/packer.yml'
  - local: 'ci/opentofu.yml'
```

GitLab merged alle Dateien vor der Auswertung zu einer Konfiguration —
`!reference` funktioniert deshalb auch ueber Dateigrenzen hinweg.

---

## Stages und Jobs

```
packer   →  packer-k8s      (manuell)
             packer-haproxy  (manuell)

plan     →  plan             (manuell)

deploy   →  deploy           (manuell, braucht plan-Artefakt)

destroy  →  destroy          (manuell, unabhaengig)
```

Alle Jobs sind `when: manual` — nur der gewuenschte Job wird angestossen.

---

## Shared Steps mit `!reference`

Statt YAML-Ankern (`*tofu_init`) wird `!reference` verwendet — GitLab-nativ,
fuegt die Befehle als flache Liste ein:

```yaml
# ci/opentofu.yml
.tofu_init:
  script:
    - cd ${TF_ROOT}
    - tofu init ...

plan:
  script:
    - !reference [.tofu_init, script]   # fuegt die init-Befehle hier ein
    - tofu plan ...
```

**Warum nicht `*tofu_init`:** Ein YAML-Anker auf eine Sequenz erzeugt
als List-Item einen verschachtelten Block — GitLab CI erwartet aber eine
flache Liste von Strings und wuerde die Befehle nicht ausfuehren.

---

## Das Formular — "Run pipeline" in GitLab

Packer braucht kein Formular — Template-Namen sind fest in `ci/packer.yml`
hinterlegt. Einfach den Job anstossen.

Fuer OpenTofu werden beim "Run pipeline" die Cluster-Parameter abgefragt:

```
┌─────────────────────────────────────────────────────┐
│  Run pipeline on branch: main                       │
│                                                     │
│  CLUSTER_NAME          [prod-k8s-1                ] │
│  CP_COUNT              [3                         ] │
│  WORKER_COUNT          [3                         ] │
│  HAPROXY_BASE_IP       [10.0.0.20                 ] │
│  CP_BASE_IP            [10.0.0.10                 ] │
│  WORKER_BASE_IP        [10.0.0.30                 ] │
│                                                     │
│                    [ Run pipeline ]                 │
└─────────────────────────────────────────────────────┘
```

---

## Credentials — einmalig in GitLab setzen

Settings → CI/CD → Variables, **masked + protected**:

| Variable                    | Verwendet von                        |
|-----------------------------|--------------------------------------|
| `TF_VAR_vcenter_password`   | OpenTofu + Packer (vcenter_password) |
| `PACKER_SSH_PRIVATE_KEY_FILE` | Packer — Pfad zum SSH Private Key  |

Packer holt sich das Passwort ueber `PKR_VAR_vcenter_password: $TF_VAR_vcenter_password`
im Job — ein Secret fuer beide Tools.

Der SSH Private Key wird benoetigt damit Packer sich nach dem Autoinstall
auf die neue VM verbinden kann. Der zugehoerige Public Key muss in
`packer/k8s/user-data` und `packer/haproxy/user-data` unter `authorized-keys` eingetragen sein.

Alle anderen vSphere-Werte (Server, User, Datacenter etc.) haben
Defaults in `variables.tf` und `variables.pkrvars.json`.

---

## GitLab State Backend — automatisch

Wenn der CI-Job auf demselben GitLab-Server laeuft, stellt GitLab automatisch
alle nötigen Variablen bereit:

| Variable          | Bedeutung       | Woher        |
|-------------------|-----------------|--------------|
| `CI_API_V4_URL`   | GitLab API URL  | automatisch  |
| `CI_PROJECT_ID`   | Projekt-ID      | automatisch  |
| `CI_JOB_TOKEN`    | Auth-Token      | automatisch  |

Der State wird direkt im GitLab-Projekt gespeichert und ist unter
*Operate → Terraform States* sichtbar.

---

## Multi-Cluster: ein Repo, viele Cluster

Jeder Cluster bekommt seinen eigenen State ueber den `CLUSTER_NAME`:

```
gitlab.example.com/.../terraform/state/prod-k8s-1
gitlab.example.com/.../terraform/state/prod-k8s-2
gitlab.example.com/.../terraform/state/dev-k8s-1
```

---

## Ablauf

### Packer — VM-Images bauen (einmalig oder bei Updates)

```
1. "Run pipeline" starten (kein Formular noetig)
         ↓
2. packer-k8s anstossen
   Baut VMk8s-Image in vSphere Content Library
         ↓
3. packer-haproxy anstossen
   Baut VMhaproxy-Image in vSphere Content Library
```

### OpenTofu — Cluster deployen

```
1. "Run pipeline" starten
   CLUSTER_NAME, CP_COUNT, IPs ausfuellen
         ↓
2. plan anstossen
   tofu plan zeigt was erstellt wird
   Plan wird als Artefakt gespeichert (1 Tag gueltig)
         ↓
3. deploy anstossen (nach Plan-Review)
   tofu apply fuehrt exakt den geprueften Plan aus
   HAProxy + Control Plane + Workernodes werden erstellt
         ↓
4. State wird in GitLab unter dem CLUSTER_NAME gespeichert
```

### OpenTofu — Cluster loeschen

```
1. "Run pipeline" starten
   CLUSTER_NAME des Ziel-Clusters eintragen
         ↓
2. destroy anstossen
   tofu destroy liest aus dem State was geloescht wird
   Keine -var Flags noetig — alles steht im State
```
