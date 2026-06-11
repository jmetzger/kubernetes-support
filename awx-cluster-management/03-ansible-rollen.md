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
    └── tasks/
        └── tofu_apply.yml        # von create/scale/upgrade genutzt
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

- name: Assign IP ranges (freed first, otherwise next_free_octet)
  ansible.builtin.set_fact:
    assigned_haproxy: >-
      {{ ipam.freed[0].haproxy if ipam.freed | length > 0
         else '10.10.' + ipam.next_free_octet | string + '.0/24' }}
    assigned_cp: >-
      {{ ipam.freed[0].cp if ipam.freed | length > 0
         else '10.10.' + (ipam.next_free_octet + 1) | string + '.0/24' }}
    assigned_workers: >-
      {{ ipam.freed[0].workers if ipam.freed | length > 0
         else '10.10.' + (ipam.next_free_octet + 2) | string + '.0/24' }}

- name: Update IPAM
  ansible.builtin.set_fact:
    ipam_updated: >-
      {{
        ipam | combine({
          'assignments': ipam.assignments | combine({
            cluster_name: {
              'haproxy': assigned_haproxy,
              'cp':      assigned_cp,
              'workers': assigned_workers
            }
          }),
          'freed': ipam.freed[1:] if ipam.freed | length > 0 else ipam.freed,
          'next_free_octet': ipam.next_free_octet + 3 if ipam.freed | length == 0
                             else ipam.next_free_octet
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

## AWX-Variablen (automatisch verfügbar)

AWX injiziert diese Variablen automatisch in jeden Job:

| Variable | Inhalt |
|---|---|
| `awx_job_id` | ID des laufenden Jobs |
| `awx_job_template_id` | ID des Job Templates |
| `awx_job_template_name` | Name des Job Templates |
| `awx_user_name` | AWX-Benutzer der den Job gestartet hat |
