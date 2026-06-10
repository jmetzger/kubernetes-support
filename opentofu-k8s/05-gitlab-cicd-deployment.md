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

## GitLab State Backend — automatisch

Wenn der CI-Job auf demselben GitLab-Server laeuft, stellt GitLab automatisch
alle nötigen Variablen bereit — kein einziges Secret muss manuell konfiguriert werden:

| Variable          | Bedeutung       | Woher        |
|-------------------|-----------------|--------------|
| `CI_API_V4_URL`   | GitLab API URL  | automatisch  |
| `CI_PROJECT_ID`   | Projekt-ID      | automatisch  |
| `CI_JOB_TOKEN`    | Auth-Token      | automatisch  |

Der State wird direkt im GitLab-Projekt gespeichert und ist unter
*Operate → Terraform States* sichtbar.

## Multi-Cluster: ein Repo, viele Cluster

Jeder Cluster bekommt seinen eigenen State ueber den `CLUSTER_NAME`:

```
STATE_NAME = "${CLUSTER_NAME}"

gitlab.example.com/.../terraform/state/prod-k8s-1
gitlab.example.com/.../terraform/state/prod-k8s-2
gitlab.example.com/.../terraform/state/dev-k8s-1
```

## Das Formular — "Run pipeline" in GitLab

Der Benutzer startet die Pipeline manuell und fuellt die Variablen aus:

```
┌─────────────────────────────────────────┐
│  Run pipeline on branch: main           │
│                                         │
│  Variables:                             │
│  CLUSTER_NAME      [prod-k8s-1        ] │
│  CP_COUNT          [3                 ] │
│  WORKER_COUNT      [5                 ] │
│  HAPROXY_BASE_IP   [10.0.0.20         ] │
│  CP_BASE_IP        [10.0.0.10         ] │
│  WORKER_BASE_IP    [10.0.0.30         ] │
│                                         │
│              [ Run pipeline ]           │
└─────────────────────────────────────────┘
```

## .gitlab-ci.yml

```yaml
stages:
  - plan
  - deploy

variables:
  TF_ROOT: opentofu/
  # CLUSTER_NAME wird beim "Run pipeline" als Variable mitgegeben
  # und bestimmt den State-Namen — jeder Cluster hat seinen eigenen State

.tofu_init: &tofu_init
  - cd ${TF_ROOT}
  - tofu init
      -backend-config="address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${CLUSTER_NAME}"
      -backend-config="lock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${CLUSTER_NAME}/lock"
      -backend-config="unlock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${CLUSTER_NAME}/lock"
      -backend-config="lock_method=POST"
      -backend-config="unlock_method=DELETE"
      -backend-config="username=gitlab-ci-token"
      -backend-config="password=${CI_JOB_TOKEN}"

plan:
  stage: plan
  image: ghcr.io/opentofu/opentofu:latest
  script:
    - *tofu_init
    - tofu plan
        -var="cp_count=${CP_COUNT}"
        -var="worker_count=${WORKER_COUNT}"
        -var="haproxy_base_ip=${HAPROXY_BASE_IP}"
        -var="cp_base_ip=${CP_BASE_IP}"
        -var="worker_base_ip=${WORKER_BASE_IP}"
        -out=tfplan
  artifacts:
    paths:
      - ${TF_ROOT}/tfplan
  when: manual

deploy:
  stage: deploy
  image: ghcr.io/opentofu/opentofu:latest
  script:
    - *tofu_init
    - tofu apply tfplan
  when: manual
  needs: [plan]
```

## vSphere Credentials — einzige feste CI/CD Variable

Das einzige Secret das manuell in GitLab gesetzt werden muss
(Settings → CI/CD → Variables, masked + protected):

| Variable                  | Wert                |
|---------------------------|---------------------|
| `TF_VAR_vcenter_password` | geheimes-passwort   |

Alle anderen vSphere-Werte (Server, User, Datacenter etc.) haben
Defaults in `variables.tf` und koennen per `TF_VAR_*` ueberschrieben werden.

## Ablauf

```
1. "Run pipeline" starten
   Formular ausfuellen: CLUSTER_NAME, CP_COUNT, IPs...
         ↓
2. plan-Job laeuft
   tofu plan zeigt was erstellt wird
   Plan wird als Artefakt gespeichert
         ↓
3. deploy-Job wartet auf manuelle Bestaetigung
   Jemand prueft den Plan und klickt "Play"
         ↓
4. tofu apply fuehrt exakt den geprueften Plan aus
   HAProxy + Control Plane + Workernodes werden erstellt
         ↓
5. State wird in GitLab unter dem CLUSTER_NAME gespeichert
   Naechstes apply fuer diesen Cluster kennt den Zustand
```
