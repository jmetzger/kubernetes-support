# Ansible-Rollen

## Rollenübersicht

```
roles/
├── k8s_cluster_create/
│   ├── defaults/main.yml
│   ├── tasks/
│   │   ├── main.yml
│   │   ├── gitlab_setup.yml      # IPAM lesen, Ordner anlegen, Dateien schreiben, committen
│   │   └── tofu_apply.yml        # → shared aus k8s_cluster_common
│   └── templates/
│       ├── meta.yaml.j2
│       ├── terraform.tfvars.j2
│       ├── versions.yaml.j2
│       ├── CHANGELOG.md.j2
│       └── main.tf.j2
│
├── k8s_cluster_scale/
│   ├── defaults/main.yml
│   ├── tasks/
│   │   ├── main.yml
│   │   ├── gitlab_update.yml     # tfvars + CHANGELOG aktualisieren, committen
│   │   └── tofu_apply.yml        # → shared
│   └── templates/
│       └── changelog_entry.j2
│
├── k8s_cluster_upgrade/
│   ├── defaults/main.yml
│   ├── tasks/
│   │   ├── main.yml
│   │   ├── preflight.yml         # Version-Checks
│   │   ├── gitlab_update.yml     # tfvars + versions.yaml + CHANGELOG, committen
│   │   └── tofu_apply.yml        # → shared
│   └── templates/
│       └── changelog_entry.j2
│
├── k8s_cluster_destroy/
│   ├── defaults/main.yml
│   └── tasks/
│       ├── main.yml
│       ├── tofu_destroy.yml
│       └── gitlab_cleanup.yml    # IPAM freigeben, Ordner archivieren
│
└── k8s_cluster_common/
    ├── defaults/
    │   └── main.yml              # awx_url, awx_create_template_id
    └── tasks/
        ├── tofu_apply.yml        # von create/scale/upgrade genutzt
        └── update_awx_survey.yml # von create/destroy genutzt
```

---

## defaults/main.yml (gemeinsam für alle Rollen)

```yaml
gitlab_url: "https://gitlab.example.com"
gitlab_project_id: "123"                    # ID von infra/clusters
clusters_repo: "https://oauth2:{{ gitlab_token }}@gitlab.example.com/infra/clusters.git"
repo_local_path: "/tmp/clusters-{{ cluster_name }}"
git_user_name: "AWX Automation"
git_user_email: "awx@example.com"
```

---

## k8s_cluster_create

### tasks/gitlab_setup.yml

```yaml
- name: Clone clusters repository
  ansible.builtin.git:
    repo: "{{ clusters_repo }}"
    dest: "{{ repo_local_path }}"
    version: main

- name: Fail if cluster already exists
  ansible.builtin.fail:
    msg: "Cluster '{{ cluster_name }}' existiert bereits."
  when: (repo_local_path + '/' + cluster_name) is directory

- name: Read IPAM
  ansible.builtin.slurp:
    src: "{{ repo_local_path }}/_network/ipam.yaml"
  register: ipam_raw

- name: Parse IPAM
  ansible.builtin.set_fact:
    ipam: "{{ ipam_raw.content | b64decode | from_yaml }}"

- name: Fail if no available ranges
  ansible.builtin.fail:
    msg: "Keine freien IP-Ranges verfügbar. Bitte _network/ipam.yaml erweitern."
  when: ipam.available | length == 0

- name: Assign first available block
  ansible.builtin.set_fact:
    assigned_haproxy: "{{ ipam.available[0].haproxy }}"
    assigned_cp:      "{{ ipam.available[0].cp }}"
    assigned_workers: "{{ ipam.available[0].workers }}"

- name: Update IPAM
  ansible.builtin.set_fact:
    ipam_updated: >-
      {{
        ipam | combine({
          'available': ipam.available[1:],
          'assignments': ipam.assignments | combine({
            cluster_name: {
              'haproxy': assigned_haproxy,
              'cp':      assigned_cp,
              'workers': assigned_workers
            }
          })
        })
      }}

- name: Write updated IPAM
  ansible.builtin.copy:
    content: "{{ ipam_updated | to_nice_yaml }}"
    dest: "{{ repo_local_path }}/_network/ipam.yaml"

- name: Create cluster folder
  ansible.builtin.file:
    path: "{{ repo_local_path }}/{{ cluster_name }}"
    state: directory
    mode: "0755"

- name: Render cluster files
  ansible.builtin.template:
    src: "{{ item.src }}"
    dest: "{{ repo_local_path }}/{{ cluster_name }}/{{ item.dest }}"
  loop:
    - { src: meta.yaml.j2,          dest: meta.yaml }
    - { src: terraform.tfvars.j2,   dest: terraform.tfvars }
    - { src: versions.yaml.j2,      dest: versions.yaml }
    - { src: CHANGELOG.md.j2,       dest: CHANGELOG.md }

- name: Git config
  ansible.builtin.command:
    cmd: "git config {{ item.key }} {{ item.value }}"
    chdir: "{{ repo_local_path }}"
  loop:
    - { key: "user.name",  value: "{{ git_user_name }}" }
    - { key: "user.email", value: "{{ git_user_email }}" }

- name: Git add, commit, push
  ansible.builtin.shell: |
    git add _network/ipam.yaml {{ cluster_name }}/
    git commit -m "feat: add cluster {{ cluster_name }} (AWX Job #{{ awx_job_id }})"
    git push origin main
  args:
    chdir: "{{ repo_local_path }}"

- name: Update AWX survey — remove assigned block from ip_block choices
  ansible.builtin.include_tasks:
    file: "../../k8s_cluster_common/tasks/update_awx_survey.yml"
  vars:
    survey_action: remove
    survey_ip_block: "{{ assigned_haproxy | regex_replace('\\.0/24$', '') }}"
```

### templates/terraform.tfvars.j2

```hcl
cluster_name          = "{{ cluster_name }}"
kubernetes_version    = "{{ k8s_version }}"
k8s_distro            = "{{ k8s_distro }}"
worker_count          = {{ worker_count }}
worker_flavor         = "{{ worker_flavor }}"
control_plane_count   = {{ cp_count }}
calico_version        = "{{ calico_version }}"
containerd_version    = "{{ containerd_version }}"

haproxy_subnet        = "{{ assigned_haproxy }}"
cp_subnet             = "{{ assigned_cp }}"
worker_subnet         = "{{ assigned_workers }}"
```

### templates/versions.yaml.j2

```yaml
kubernetes:
  distribution: {{ k8s_distro }}
  version: "{{ k8s_version }}"
calico:
  version: "{{ calico_version }}"
containerd:
  version: "{{ containerd_version }}"
```

### templates/CHANGELOG.md.j2

```markdown
# Cluster {{ cluster_name }}

## {{ ansible_date_time.date }} | Erstellt
- K8s: {{ k8s_distro }} {{ k8s_version }}
- Worker: {{ worker_count }} x {{ worker_flavor }}
- Control Plane: {{ cp_count }} Nodes
- Calico: {{ calico_version }} / containerd: {{ containerd_version }}
- Netz haproxy: {{ assigned_haproxy }} / cp: {{ assigned_cp }} / worker: {{ assigned_workers }}
- AWX Job: #{{ awx_job_id }} ({{ awx_job_template_name }}) — {{ awx_user_name }}
```

---

## k8s_cluster_scale

### tasks/gitlab_update.yml

```yaml
- name: Clone repository
  ansible.builtin.git:
    repo: "{{ clusters_repo }}"
    dest: "{{ repo_local_path }}"
    version: main

- name: Fail if cluster does not exist
  ansible.builtin.fail:
    msg: "Cluster '{{ cluster_name }}' nicht gefunden."
  when: not (repo_local_path + '/' + cluster_name) is directory

- name: Read current worker_count
  ansible.builtin.slurp:
    src: "{{ repo_local_path }}/{{ cluster_name }}/terraform.tfvars"
  register: current_tfvars_raw

- name: Parse current worker_count
  ansible.builtin.set_fact:
    current_worker_count: >-
      {{ current_tfvars_raw.content | b64decode
         | regex_search('worker_count\s+=\s+(\d+)', '\1') | first }}

- name: Fail if no change
  ansible.builtin.fail:
    msg: "worker_count ist bereits {{ worker_count }}."
  when: worker_count | string == current_worker_count | string

- name: Update worker_count in tfvars
  ansible.builtin.lineinfile:
    path: "{{ repo_local_path }}/{{ cluster_name }}/terraform.tfvars"
    regexp: '^worker_count\s+='
    line: "worker_count          = {{ worker_count }}"

- name: Append CHANGELOG entry
  ansible.builtin.blockinfile:
    path: "{{ repo_local_path }}/{{ cluster_name }}/CHANGELOG.md"
    insertafter: EOF
    block: |

      ## {{ ansible_date_time.date }} | Scale
      - Worker Nodes: {{ current_worker_count }} → {{ worker_count }}
      - AWX Job: #{{ awx_job_id }} ({{ awx_job_template_name }}) — {{ awx_user_name }}
    marker: ""

- name: Git add, commit, push
  ansible.builtin.shell: |
    git config user.name "{{ git_user_name }}"
    git config user.email "{{ git_user_email }}"
    git add {{ cluster_name }}/
    git commit -m "feat: scale {{ cluster_name }} workers {{ current_worker_count }} → {{ worker_count }} (AWX Job #{{ awx_job_id }})"
    git push origin main
  args:
    chdir: "{{ repo_local_path }}"
```

---

## k8s_cluster_upgrade

### tasks/preflight.yml

```yaml
- name: Clone repository
  ansible.builtin.git:
    repo: "{{ clusters_repo }}"
    dest: "{{ repo_local_path }}"
    version: main

- name: Fail if cluster does not exist
  ansible.builtin.fail:
    msg: "Cluster '{{ cluster_name }}' nicht gefunden."
  when: not (repo_local_path + '/' + cluster_name) is directory

- name: Read current kubernetes_version
  ansible.builtin.slurp:
    src: "{{ repo_local_path }}/{{ cluster_name }}/terraform.tfvars"
  register: current_tfvars_raw

- name: Parse current version
  ansible.builtin.set_fact:
    current_k8s_version: >-
      {{ current_tfvars_raw.content | b64decode
         | regex_search('kubernetes_version\s+=\s+"([^"]+)"', '\1') | first }}

- name: Fail on same version
  ansible.builtin.fail:
    msg: "Cluster läuft bereits auf {{ target_version }}."
  when: current_k8s_version == target_version

- name: Fail on downgrade
  ansible.builtin.fail:
    msg: "Downgrade nicht erlaubt: {{ current_k8s_version }} → {{ target_version }}"
  when: target_version is version(current_k8s_version, '<')

- name: Parse minor versions
  ansible.builtin.set_fact:
    current_minor: "{{ current_k8s_version.split('.')[1] | int }}"
    target_minor:  "{{ target_version.split('.')[1] | int }}"

- name: Fail on minor version skip
  ansible.builtin.fail:
    msg: >
      Minor-Version-Skip nicht erlaubt: {{ current_k8s_version }} → {{ target_version }}.
      Bitte schrittweise upgraden.
  when: (target_minor | int) - (current_minor | int) > 1
```

### tasks/gitlab_update.yml

```yaml
- name: Update kubernetes_version in tfvars
  ansible.builtin.lineinfile:
    path: "{{ repo_local_path }}/{{ cluster_name }}/terraform.tfvars"
    regexp: '^kubernetes_version\s+='
    line: 'kubernetes_version    = "{{ target_version }}"'

- name: Update versions.yaml
  ansible.builtin.lineinfile:
    path: "{{ repo_local_path }}/{{ cluster_name }}/versions.yaml"
    regexp: '^\s+version:.*'
    line: '  version: "{{ target_version }}"'

- name: Append CHANGELOG entry
  ansible.builtin.blockinfile:
    path: "{{ repo_local_path }}/{{ cluster_name }}/CHANGELOG.md"
    insertafter: EOF
    block: |

      ## {{ ansible_date_time.date }} | K8s Upgrade
      - K8s Version: {{ current_k8s_version }} → {{ target_version }}
      - AWX Job: #{{ awx_job_id }} ({{ awx_job_template_name }}) — {{ awx_user_name }}
    marker: ""

- name: Git add, commit, push
  ansible.builtin.shell: |
    git config user.name "{{ git_user_name }}"
    git config user.email "{{ git_user_email }}"
    git add {{ cluster_name }}/
    git commit -m "feat: upgrade {{ cluster_name }} {{ current_k8s_version }} → {{ target_version }} (AWX Job #{{ awx_job_id }})"
    git push origin main
  args:
    chdir: "{{ repo_local_path }}"
```

---

## k8s_cluster_common: tofu_apply.yml

Wird von create, scale und upgrade per `include_tasks` genutzt.

```yaml
- name: Create temp working directory
  ansible.builtin.tempfile:
    state: directory
    prefix: "tofu_{{ cluster_name }}_"
  register: tofu_workdir

- name: Generate main.tf from template
  ansible.builtin.template:
    src: "{{ role_path }}/../k8s_cluster_create/templates/main.tf.j2"
    dest: "{{ tofu_workdir.path }}/main.tf"
  vars:
    module_version: "{{ (lookup('file', repo_local_path + '/' + cluster_name + '/meta.yaml') | from_yaml).module_version }}"

- name: Copy terraform.tfvars into workdir
  ansible.builtin.copy:
    src: "{{ repo_local_path }}/{{ cluster_name }}/terraform.tfvars"
    dest: "{{ tofu_workdir.path }}/terraform.tfvars"
    remote_src: true

- name: tofu init
  ansible.builtin.command:
    cmd: tofu init
    chdir: "{{ tofu_workdir.path }}"
  environment:
    TF_HTTP_USERNAME: "oauth2"
    TF_HTTP_PASSWORD: "{{ gitlab_token }}"

- name: tofu plan
  ansible.builtin.command:
    cmd: tofu plan -out=tfplan -var-file=terraform.tfvars
    chdir: "{{ tofu_workdir.path }}"
  environment:
    TF_HTTP_USERNAME: "oauth2"
    TF_HTTP_PASSWORD: "{{ gitlab_token }}"
  register: tofu_plan_output

- name: Show plan
  ansible.builtin.debug:
    var: tofu_plan_output.stdout_lines

- name: tofu apply
  ansible.builtin.command:
    cmd: tofu apply -auto-approve tfplan
    chdir: "{{ tofu_workdir.path }}"
  environment:
    TF_HTTP_USERNAME: "oauth2"
    TF_HTTP_PASSWORD: "{{ gitlab_token }}"

- name: Cleanup temp workdir
  ansible.builtin.file:
    path: "{{ tofu_workdir.path }}"
    state: absent
```

---

## k8s_cluster_destroy

### Besonderheiten

- **Safety-Check:** Cluster-Name muss im Survey zweimal eingegeben werden
- `tofu destroy` läuft im selben temporären Arbeitsverzeichnis wie apply
- IP-Ranges werden in `ipam.yaml` als `freed` zurückgegeben
- Cluster-Ordner wird **archiviert**, nicht gelöscht — History bleibt erhalten

### Rollenstruktur

```
roles/
└── k8s_cluster_destroy/
    ├── defaults/
    │   └── main.yml
    ├── tasks/
    │   ├── main.yml
    │   ├── preflight.yml         # Existenz + Safety-Check
    │   ├── tofu_destroy.yml      # tofu destroy im temp workdir
    │   └── gitlab_cleanup.yml    # IPAM freigeben, Ordner archivieren, committen
    └── templates/
        └── destroyed.yaml.j2
```

### tasks/main.yml

```yaml
- ansible.builtin.import_tasks: preflight.yml
- ansible.builtin.import_tasks: tofu_destroy.yml
- ansible.builtin.import_tasks: gitlab_cleanup.yml
```

### tasks/preflight.yml

```yaml
- name: Clone repository
  ansible.builtin.git:
    repo: "{{ clusters_repo }}"
    dest: "{{ repo_local_path }}"
    version: main

- name: Fail if cluster does not exist
  ansible.builtin.fail:
    msg: "Cluster '{{ cluster_name }}' nicht gefunden."
  when: not (repo_local_path + '/' + cluster_name) is directory

# Safety: Survey verlangt zweimalige Eingabe des Cluster-Namens
- name: Fail if confirmation does not match
  ansible.builtin.fail:
    msg: >
      Sicherheitscheck fehlgeschlagen: '{{ confirm_cluster_name }}'
      stimmt nicht mit '{{ cluster_name }}' überein.
  when: confirm_cluster_name != cluster_name
```

### tasks/tofu_destroy.yml

```yaml
- name: Create temp working directory
  ansible.builtin.tempfile:
    state: directory
    prefix: "tofu_destroy_{{ cluster_name }}_"
  register: tofu_workdir

- name: Read module_version from meta.yaml
  ansible.builtin.slurp:
    src: "{{ repo_local_path }}/{{ cluster_name }}/meta.yaml"
  register: meta_raw

- name: Parse module_version
  ansible.builtin.set_fact:
    module_version: "{{ (meta_raw.content | b64decode | from_yaml).module_version }}"

- name: Generate main.tf from template
  ansible.builtin.template:
    src: "{{ role_path }}/../k8s_cluster_create/templates/main.tf.j2"
    dest: "{{ tofu_workdir.path }}/main.tf"

- name: Copy terraform.tfvars into workdir
  ansible.builtin.copy:
    src: "{{ repo_local_path }}/{{ cluster_name }}/terraform.tfvars"
    dest: "{{ tofu_workdir.path }}/terraform.tfvars"
    remote_src: true

- name: tofu init
  ansible.builtin.command:
    cmd: tofu init
    chdir: "{{ tofu_workdir.path }}"
  environment:
    TF_HTTP_USERNAME: "oauth2"
    TF_HTTP_PASSWORD: "{{ gitlab_token }}"

- name: tofu destroy
  ansible.builtin.command:
    cmd: tofu destroy -auto-approve -var-file=terraform.tfvars
    chdir: "{{ tofu_workdir.path }}"
  environment:
    TF_HTTP_USERNAME: "oauth2"
    TF_HTTP_PASSWORD: "{{ gitlab_token }}"
  register: tofu_destroy_output

- name: Show destroy output
  ansible.builtin.debug:
    var: tofu_destroy_output.stdout_lines

- name: Cleanup temp workdir
  ansible.builtin.file:
    path: "{{ tofu_workdir.path }}"
    state: absent
```

### tasks/gitlab_cleanup.yml

```yaml
- name: Read IPAM
  ansible.builtin.slurp:
    src: "{{ repo_local_path }}/_network/ipam.yaml"
  register: ipam_raw

- name: Parse IPAM
  ansible.builtin.set_fact:
    ipam: "{{ ipam_raw.content | b64decode | from_yaml }}"

- name: Release IP ranges back to available
  ansible.builtin.set_fact:
    ipam_updated: >-
      {{
        ipam | combine({
          'assignments': ipam.assignments | dict2items
                         | rejectattr('key', 'equalto', cluster_name)
                         | items2dict,
          'available': ipam.available + [ ipam.assignments[cluster_name] ]
        })
      }}

- name: Write updated IPAM
  ansible.builtin.copy:
    content: "{{ ipam_updated | to_nice_yaml }}"
    dest: "{{ repo_local_path }}/_network/ipam.yaml"

- name: Render destroyed.yaml
  ansible.builtin.template:
    src: destroyed.yaml.j2
    dest: "{{ repo_local_path }}/{{ cluster_name }}/destroyed.yaml"

- name: Create _archived directory
  ansible.builtin.file:
    path: "{{ repo_local_path }}/_archived"
    state: directory
    mode: "0755"

- name: Archive cluster folder
  ansible.builtin.command:
    cmd: >
      mv {{ cluster_name }}
      _archived/{{ cluster_name }}-{{ ansible_date_time.date }}
    chdir: "{{ repo_local_path }}"

- name: Git config
  ansible.builtin.command:
    cmd: "git config {{ item.key }} {{ item.value }}"
    chdir: "{{ repo_local_path }}"
  loop:
    - { key: "user.name",  value: "{{ git_user_name }}" }
    - { key: "user.email", value: "{{ git_user_email }}" }

- name: Git add, commit, push
  ansible.builtin.shell: |
    git add _network/ipam.yaml
    git add _archived/
    git rm -r {{ cluster_name }}/ 2>/dev/null || true
    git commit -m "feat: destroy cluster {{ cluster_name }} (AWX Job #{{ awx_job_id }})"
    git push origin main
  args:
    chdir: "{{ repo_local_path }}"

- name: Update AWX survey — add released block back to ip_block choices
  ansible.builtin.include_tasks:
    file: "../../k8s_cluster_common/tasks/update_awx_survey.yml"
  vars:
    survey_action: add
    survey_ip_block: "{{ released_ip_block }}"
```

### templates/destroyed.yaml.j2

```yaml
destroyed_at: "{{ ansible_date_time.iso8601 }}"
destroyed_by: "{{ awx_user_name }}"
awx_job_id: "{{ awx_job_id }}"
awx_job_template_name: "{{ awx_job_template_name }}"
```

### Ergebnis in infra/clusters

```
infra/clusters/
├── _network/
│   └── ipam.yaml              ← Ranges wieder in freed
├── _archived/
│   └── prod-01-2026-08-20/    ← archivierter Cluster-Ordner
│       ├── meta.yaml
│       ├── terraform.tfvars
│       ├── versions.yaml
│       ├── CHANGELOG.md
│       └── destroyed.yaml     ← wann + von wem gelöscht
└── dev-01/                    ← noch aktive Cluster
    └── ...
```

### AWX Survey für k8s-cluster-destroy

| Frage | Variable | Typ | Pflicht |
|---|---|---|---|
| Cluster Name | `cluster_name` | Text | ja |
| Bestätigung (Name nochmals eingeben) | `confirm_cluster_name` | Text | ja |

---

## AWX-Variablen (automatisch verfügbar)

AWX injiziert diese Variablen automatisch in jeden Job:

| Variable | Inhalt |
|---|---|
| `awx_job_id` | ID des laufenden Jobs |
| `awx_job_template_id` | ID des Job Templates |
| `awx_job_template_name` | Name des Job Templates |
| `awx_user_name` | AWX-Benutzer der den Job gestartet hat |
