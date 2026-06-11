# AWX Survey-Spec dynamisch aus GitLab befüllen (IPAM)

## Hintergrund

Ein AWX Job Template hat ein Survey-Formular mit einem Dropdown "IP Range".
Die verfügbaren Ranges liegen als JSON-Datei in einem GitLab-Repository.
Wird eine Range vergeben, wird sie aus der Datei entfernt — AWX bekommt den
aktualisierten Survey-Spec automatisch per Ansible-Playbook.

```
GitLab (ipam.json)  →  Ansible liest JSON  →  uri: POST → AWX Survey-Spec
                           ↓
                    Range vergeben → JSON updaten → git push → GitLab
```

---

## Voraussetzungen

- AWX erreichbar, Job Template mit Survey bereits angelegt
- GitLab-Projekt mit Schreibzugriff
- AWX-Token (Bearer) und GitLab-Token (PRIVATE-TOKEN) als AWX Credentials hinterlegt

---

## Schritt 1: GitLab-Repository anlegen

Im GitLab ein Projekt `ipam-data` erstellen und folgende Datei committen:

```
# ipam.json
{
  "available": [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24"
  ],
  "assigned": []
}
```

```
git clone https://gitlab.example.com/yourgroup/ipam-data.git
cd ipam-data
# ipam.json anlegen (siehe oben)
git add ipam.json
git commit -m "Initial IPAM data"
git push
```

---

## Schritt 2: Survey-Spec-Playbook erstellen

Dieses Playbook liest die aktuellen Ranges aus GitLab und schreibt sie als
neuen Survey-Spec in AWX.

```
# awx-survey-update.yml
---
- name: AWX Survey-Spec aus GitLab-IPAM aktualisieren
  hosts: localhost
  gather_facts: false

  vars:
    gitlab_url: "https://gitlab.example.com"
    gitlab_project_id: "42"                    # Project-ID aus GitLab
    gitlab_ref: "main"
    awx_url: "https://awx.example.com"
    awx_job_template_id: "7"                   # ID aus AWX

  tasks:
    - name: ipam.json aus GitLab laden
      uri:
        url: "{{ gitlab_url }}/api/v4/projects/{{ gitlab_project_id }}/repository/files/ipam.json/raw?ref={{ gitlab_ref }}"
        headers:
          PRIVATE-TOKEN: "{{ gitlab_token }}"
        return_content: true
      register: gitlab_response

    - name: JSON parsen
      set_fact:
        ipam_data: "{{ gitlab_response.content | from_json }}"

    - name: Verfügbare Ranges anzeigen
      debug:
        msg: "Verfügbar: {{ ipam_data.available }}"

    - name: AWX Survey-Spec aktualisieren
      uri:
        url: "{{ awx_url }}/api/v2/job_templates/{{ awx_job_template_id }}/survey_spec/"
        method: POST
        headers:
          Authorization: "Bearer {{ awx_token }}"
        body_format: json
        body:
          name: "IPAM"
          description: ""
          spec:
            - question_name: "IP Range"
              variable: "ip_range"
              type: "multiplechoice"
              choices: "{{ ipam_data.available | join('\n') }}"
              required: true
        status_code: 200
```

> **Hinweis:** AWX erwartet `POST` (nicht `PATCH`) für `/survey_spec/` — der Spec wird
> komplett ersetzt. Die `choices` sind newline-getrennt.

---

## Schritt 3: Range-Vergabe-Playbook erstellen

Dieses Playbook nimmt eine vergebene Range, entfernt sie aus `available`,
fügt sie in `assigned` ein und pusht die Änderung zurück nach GitLab.
Anschliessend wird direkt der AWX Survey-Spec aktualisiert.

```
# ipam-assign.yml
---
- name: IP-Range vergeben und IPAM + AWX aktualisieren
  hosts: localhost
  gather_facts: false

  vars:
    gitlab_url: "https://gitlab.example.com"
    gitlab_project_id: "42"
    gitlab_ref: "main"
    awx_url: "https://awx.example.com"
    awx_job_template_id: "7"
    assigned_range: "10.0.1.0/24"             # wird per Survey übergeben

  tasks:
    - name: ipam.json aus GitLab laden
      uri:
        url: "{{ gitlab_url }}/api/v4/projects/{{ gitlab_project_id }}/repository/files/ipam.json/raw?ref={{ gitlab_ref }}"
        headers:
          PRIVATE-TOKEN: "{{ gitlab_token }}"
        return_content: true
      register: gitlab_response

    - name: JSON parsen
      set_fact:
        ipam_data: "{{ gitlab_response.content | from_json }}"

    - name: Range aus available entfernen
      set_fact:
        ipam_updated:
          available: "{{ ipam_data.available | difference([assigned_range]) }}"
          assigned: "{{ ipam_data.assigned + [assigned_range] }}"

    - name: Aktualisierten JSON-Inhalt base64-kodieren
      set_fact:
        ipam_json_b64: "{{ ipam_updated | to_nice_json | b64encode }}"

    - name: ipam.json in GitLab aktualisieren
      uri:
        url: "{{ gitlab_url }}/api/v4/projects/{{ gitlab_project_id }}/repository/files/ipam.json"
        method: PUT
        headers:
          PRIVATE-TOKEN: "{{ gitlab_token }}"
        body_format: json
        body:
          branch: "{{ gitlab_ref }}"
          content: "{{ ipam_json_b64 }}"
          encoding: "base64"
          commit_message: "IPAM: {{ assigned_range }} vergeben"
        status_code: 200

    - name: AWX Survey-Spec mit neuer Liste aktualisieren
      uri:
        url: "{{ awx_url }}/api/v2/job_templates/{{ awx_job_template_id }}/survey_spec/"
        method: POST
        headers:
          Authorization: "Bearer {{ awx_token }}"
        body_format: json
        body:
          name: "IPAM"
          description: ""
          spec:
            - question_name: "IP Range"
              variable: "ip_range"
              type: "multiplechoice"
              choices: "{{ ipam_updated.available | join('\n') }}"
              required: true
        status_code: 200
```

---

## Schritt 4: Lokal synchronisieren (optional)

Wer die JSON-Datei lieber lokal bearbeitet statt über die GitLab API:

```
git clone https://gitlab.example.com/yourgroup/ipam-data.git
cd ipam-data

# Range manuell entfernen, dann:
git add ipam.json
git commit -m "IPAM: 10.0.1.0/24 vergeben"
git push
```

Danach `awx-survey-update.yml` ausführen — liest die neue Version aus GitLab und
aktualisiert AWX.

---

## Schritt 5: AWX Credentials einrichten

In AWX zwei Custom Credentials anlegen:

| Credential | Typ | Env-Variable |
|---|---|---|
| AWX API Token | Custom (Bearer) | `AWX_TOKEN` |
| GitLab Token | Custom (PRIVATE-TOKEN) | `GITLAB_TOKEN` |

Im Playbook über `lookup('env', 'AWX_TOKEN')` abrufbar — oder als `extra_vars`.

---

## Test

```
# Survey-Spec initial befüllen
ansible-playbook awx-survey-update.yml \
  -e awx_token=$AWX_TOKEN \
  -e gitlab_token=$GITLAB_TOKEN

# Range vergeben (10.0.1.0/24 entfernen)
ansible-playbook ipam-assign.yml \
  -e awx_token=$AWX_TOKEN \
  -e gitlab_token=$GITLAB_TOKEN \
  -e assigned_range=10.0.1.0/24
```

AWX Survey vorher:
```
10.0.1.0/24
10.0.2.0/24
10.0.3.0/24
```

AWX Survey nachher:
```
10.0.2.0/24
10.0.3.0/24
```

GitLab `ipam.json` nachher:
```
{
  "available": ["10.0.2.0/24", "10.0.3.0/24"],
  "assigned":  ["10.0.1.0/24"]
}
```

---

## Zusammenfassung

| Playbook | Zweck |
|---|---|
| `awx-survey-update.yml` | Survey-Spec aus GitLab in AWX schreiben (read-only) |
| `ipam-assign.yml` | Range vergeben + GitLab + AWX aktualisieren |
