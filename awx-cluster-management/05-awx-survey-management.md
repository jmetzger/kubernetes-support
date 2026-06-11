# AWX Survey Management

## Problem

AWX-Survey-Choices sind statisch — sie ändern sich nicht automatisch
wenn ein Cluster erstellt oder gelöscht wird. Der verfügbare IP-Block
muss nach jedem Create aus dem Dropdown entfernt werden, nach jedem
Destroy wieder hinzugefügt werden.

Außerdem: AWX kennt für `/survey_spec/` **nur POST** — kein PATCH, kein PUT.
Jeder POST überschreibt den kompletten Spec. Die Rolle muss daher immer
den aktuellen Spec per GET lesen, nur die Choices anpassen, und alles
zurückschreiben.

Siehe auch: [AWX Survey-Spec dynamisch aus GitLab befüllen](../ansible/awx-ipam-survey.md)

---

## Survey-Feld: IP-Block Auswahl

Der Survey von `k8s-cluster-create` hat ein Dropdown-Feld `ip_block`.
Jede Choice repräsentiert einen freien Dreier-Block (/24 für haproxy,
cp und worker). Ansible leitet die drei Subnetze automatisch ab.

**Beispiel Choices im Survey:**

```
10.10.1.0  →  haproxy: 10.10.1.0/24 | cp: 10.10.2.0/24 | worker: 10.10.3.0/24
10.10.4.0  →  haproxy: 10.10.4.0/24 | cp: 10.10.5.0/24 | worker: 10.10.6.0/24
10.10.7.0  →  haproxy: 10.10.7.0/24 | cp: 10.10.8.0/24 | worker: 10.10.9.0/24
```

Im Survey ist nur der erste Wert sichtbar (`10.10.1.0`). Ansible berechnet:

```yaml
assigned_haproxy: "{{ ip_block | regex_replace('/.*', '') }}.0/24"
assigned_cp:      "{{ (ip_block.split('.')[2] | int + 1) }}.0/24"  # +1
assigned_workers: "{{ (ip_block.split('.')[2] | int + 2) }}.0/24"  # +2
```

---

## Wann wird der Survey aktualisiert?

| Ereignis | Aktion |
|---|---|
| Cluster create erfolgreich | verwendeten Block aus Choices entfernen |
| Cluster destroy erfolgreich | freigegebenen Block zu Choices hinzufügen |

Die Survey-Aktualisierung passiert am **Ende** des jeweiligen Ansible-Jobs,
nachdem IPAM und GitLab bereits aktualisiert wurden.

---

## Shared Task: update_awx_survey.yml

Liegt in `k8s_cluster_common/tasks/update_awx_survey.yml`.
Wird von create und destroy per `include_tasks` aufgerufen.

**Übergabevariablen:**

| Variable | Beschreibung |
|---|---|
| `survey_action` | `remove` (nach create) oder `add` (nach destroy) |
| `survey_ip_block` | der betroffene Block, z.B. `10.10.1.0` |

```yaml
# k8s_cluster_common/tasks/update_awx_survey.yml

- name: GET current survey spec from AWX
  ansible.builtin.uri:
    url: "{{ awx_url }}/api/v2/job_templates/{{ awx_create_template_id }}/survey_spec/"
    method: GET
    headers:
      Authorization: "Bearer {{ awx_token }}"
  register: current_survey

- name: Parse current ip_block choices into list
  ansible.builtin.set_fact:
    current_choices: >-
      {{ (current_survey.json.spec
          | selectattr('variable', 'equalto', 'ip_block')
          | list | first).choices.split('\n') | select | list }}

- name: Remove block from choices (after create)
  ansible.builtin.set_fact:
    updated_choices: >-
      {{ current_choices | reject('equalto', survey_ip_block) | list }}
  when: survey_action == 'remove'

- name: Add block back to choices (after destroy)
  ansible.builtin.set_fact:
    updated_choices: >-
      {{ (current_choices + [survey_ip_block]) | sort }}
  when: survey_action == 'add'

- name: Rebuild full survey spec with updated choices
  ansible.builtin.set_fact:
    updated_spec: >-
      {{
        current_survey.json.spec | map('combine',
          {'choices': updated_choices | join('\n')}
          if item.variable == 'ip_block' else {}
        ) | list
      }}
  loop: "{{ current_survey.json.spec }}"
  loop_control:
    loop_var: item

- name: POST updated survey spec back to AWX
  ansible.builtin.uri:
    url: "{{ awx_url }}/api/v2/job_templates/{{ awx_create_template_id }}/survey_spec/"
    method: POST
    headers:
      Authorization: "Bearer {{ awx_token }}"
    body_format: json
    body:
      name: "{{ current_survey.json.name }}"
      description: "{{ current_survey.json.description }}"
      spec: "{{ updated_spec }}"
    status_code: 200
```

---

## Einbindung in k8s_cluster_create

Am Ende von `gitlab_setup.yml`, nachdem IPAM committed wurde:

```yaml
- name: Update AWX survey — remove assigned block
  ansible.builtin.include_tasks:
    file: "../../k8s_cluster_common/tasks/update_awx_survey.yml"
  vars:
    survey_action: remove
    survey_ip_block: "{{ assigned_haproxy | regex_replace('\\.0/24$', '') }}"
```

## Einbindung in k8s_cluster_destroy

Am Ende von `gitlab_cleanup.yml`, nachdem IPAM committed wurde:

```yaml
- name: Read released block from IPAM assignments (before cleanup)
  ansible.builtin.set_fact:
    released_ip_block: >-
      {{ ipam.assignments[cluster_name].haproxy | regex_replace('\.0/24$', '') }}

- name: Update AWX survey — add released block back
  ansible.builtin.include_tasks:
    file: "../../k8s_cluster_common/tasks/update_awx_survey.yml"
  vars:
    survey_action: add
    survey_ip_block: "{{ released_ip_block }}"
```

---

## Konfiguration: AWX Job Template IDs

Die Template-ID für `k8s-cluster-create` wird in `defaults/main.yml`
der common-Rolle hinterlegt:

```yaml
# k8s_cluster_common/defaults/main.yml
awx_url: "https://awx.example.com"
awx_create_template_id: "42"    # Job Template ID von k8s-cluster-create in AWX
```

Der AWX-Token kommt als AWX Credential und wird als `awx_token` injiziert.

---

## Initialer Survey-Aufbau

Beim ersten Einrichten muss der Survey einmalig mit allen verfügbaren
Blöcken befüllt werden. Dafür liest ein Ansible Playbook die `ipam.yaml`
und schreibt alle Einträge aus `available` als Choices in den Survey.

```yaml
# playbooks/awx-survey-init.yml
---
- name: AWX Survey initialisieren aus ipam.yaml
  hosts: localhost
  gather_facts: false

  tasks:
    - name: Clone clusters repo
      ansible.builtin.git:
        repo: "{{ clusters_repo }}"
        dest: "/tmp/clusters-init"
        version: main

    - name: Read IPAM
      ansible.builtin.slurp:
        src: "/tmp/clusters-init/_network/ipam.yaml"
      register: ipam_raw

    - name: Parse IPAM
      ansible.builtin.set_fact:
        ipam: "{{ ipam_raw.content | b64decode | from_yaml }}"

    - name: Build choices from available list
      ansible.builtin.set_fact:
        all_choices: >-
          {{ ipam.available
             | map(attribute='haproxy')
             | map('regex_replace', '\.0/24$', '')
             | list }}

    - name: GET current survey spec
      ansible.builtin.uri:
        url: "{{ awx_url }}/api/v2/job_templates/{{ awx_create_template_id }}/survey_spec/"
        method: GET
        headers:
          Authorization: "Bearer {{ awx_token }}"
      register: current_survey

    - name: POST updated choices
      ansible.builtin.uri:
        url: "{{ awx_url }}/api/v2/job_templates/{{ awx_create_template_id }}/survey_spec/"
        method: POST
        headers:
          Authorization: "Bearer {{ awx_token }}"
        body_format: json
        body:
          name: "{{ current_survey.json.name }}"
          description: "{{ current_survey.json.description }}"
          spec: >-
            {{
              current_survey.json.spec | map('combine',
                {'choices': all_choices | join('\n')}
                if item.variable == 'ip_block' else {}
              ) | list
            }}
        status_code: 200
      loop: "{{ current_survey.json.spec }}"
      loop_control:
        loop_var: item
```

---

## Zusammenfassung: Wer aktualisiert was

```
k8s-cluster-create abgeschlossen
    → ipam.yaml: Block in assignments, aus freed entfernt  (GitLab)
    → AWX Survey: Block aus ip_block-Choices entfernt      (AWX API)

k8s-cluster-destroy abgeschlossen
    → ipam.yaml: Block aus assignments, in freed           (GitLab)
    → AWX Survey: Block zu ip_block-Choices hinzugefügt    (AWX API)
```

GitLab und AWX-Survey sind immer synchron — beide zeigen denselben Stand.
