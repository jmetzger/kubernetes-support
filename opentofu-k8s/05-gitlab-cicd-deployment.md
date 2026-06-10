# GitLab CI/CD Deployment mit OpenTofu

## Warum kein AWX deploy.yml mehr noetig ist

AWX brauchte ein Ansible Playbook als Wrapper, weil AWX nur Playbooks ausfuehren
kann. GitLab CI/CD kann direkt Shell-Befehle ausfuehren — kein Ansible-Wrapper noetig.

```
AWX:
  deploy.yml → tofu init → tofu apply

GitLab CI/CD:
  .gitlab-ci.yml → tofu init → tofu apply   (direkter)
```

## GitLab State Backend — automatisch

Wenn der CI-Job auf demselben GitLab-Server laeuft, stellt GitLab automatisch
alle nötigen Variablen bereit — kein einziges Secret muss manuell gesetzt werden:

| Variable | Bedeutung | Woher |
|---|---|---|
| `CI_API_V4_URL` | GitLab API URL | automatisch |
| `CI_PROJECT_ID` | Projekt-ID | automatisch |
| `CI_JOB_TOKEN` | Auth-Token fuer den Job | automatisch |

Der State wird direkt im GitLab-Projekt gespeichert und ist unter
*Operate → Terraform States* sichtbar.

## .gitlab-ci.yml

```yaml
stages:
  - plan
  - deploy

variables:
  STATE_NAME: k8s-cluster
  TF_ROOT: opentofu/

plan:
  stage: plan
  image: ghcr.io/opentofu/opentofu:latest
  script:
    - cd ${TF_ROOT}
    - tofu init
        -backend-config="address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}"
        -backend-config="lock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}/lock"
        -backend-config="unlock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}/lock"
        -backend-config="lock_method=POST"
        -backend-config="unlock_method=DELETE"
        -backend-config="username=gitlab-ci-token"
        -backend-config="password=${CI_JOB_TOKEN}"
    - tofu plan -out=tfplan
  artifacts:
    paths:
      - ${TF_ROOT}/tfplan
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

deploy:
  stage: deploy
  image: ghcr.io/opentofu/opentofu:latest
  script:
    - cd ${TF_ROOT}
    - tofu init
        -backend-config="address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}"
        -backend-config="lock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}/lock"
        -backend-config="unlock_address=${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${STATE_NAME}/lock"
        -backend-config="lock_method=POST"
        -backend-config="unlock_method=DELETE"
        -backend-config="username=gitlab-ci-token"
        -backend-config="password=${CI_JOB_TOKEN}"
    - tofu apply tfplan
  when: manual
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## vSphere Credentials — einzige manuelle Variables

Die einzigen Secrets die manuell in GitLab gesetzt werden muessen
(Settings → CI/CD → Variables, masked + protected):

| Variable | Beispielwert |
|---|---|
| `TF_VAR_vcenter_password` | geheimes-passwort |

Alle anderen vSphere-Werte haben Defaults in `variables.tf` und koennen
bei Bedarf ebenfalls als `TF_VAR_*` Variables ueberschrieben werden.

## Ablauf

```
1. Push auf main
      ↓
2. plan-Job laeuft automatisch
   tofu plan zeigt was sich aendert
   Plan wird als Artefakt gespeichert
      ↓
3. deploy-Job wartet auf manuelle Bestaetigung (when: manual)
   Jemand schaut den Plan an und klickt "Play"
      ↓
4. tofu apply fuehrt exakt den geprueften Plan aus
   HAProxy + Control Plane + Workernode werden erstellt
      ↓
5. State wird in GitLab gespeichert
   Naechstes apply kennt den aktuellen Zustand
```
