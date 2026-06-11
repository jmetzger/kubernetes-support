# Netzwerk und IPAM

## Konzept

Ein /16-Netz wird in /24-Subnetze aufgeteilt. Jeder Cluster bekommt
drei aufeinanderfolgende /24-Netze — eines für HAProxy, eines für
Control Plane Nodes, eines für Worker Nodes.

```
Base:   10.10.0.0/16

Cluster prod-01:
  HAProxy:        10.10.1.0/24
  Control Plane:  10.10.2.0/24
  Worker:         10.10.3.0/24

Cluster dev-01:
  HAProxy:        10.10.4.0/24
  Control Plane:  10.10.5.0/24
  Worker:         10.10.6.0/24
```

Kapazität: 254 verfügbare /24er → 84 Cluster möglich (3 x /24 pro Cluster).

---

## ipam.yaml

Liegt in `infra/clusters/_network/ipam.yaml`.
Wird von AWX bei create und destroy automatisch aktualisiert.

Freie Ranges stehen explizit als Liste in `available` — so ist auf einen
Blick sichtbar was verfügbar ist. Beim Erstellen wird der erste Eintrag
entnommen, beim Löschen wird der Block wieder ans Ende angehängt.

```yaml
base_network: 10.10.0.0/16
subnet_size: /24

available:
  - haproxy: "10.10.4.0/24"
    cp:      "10.10.5.0/24"
    workers: "10.10.6.0/24"
  - haproxy: "10.10.7.0/24"
    cp:      "10.10.8.0/24"
    workers: "10.10.9.0/24"
  - haproxy: "10.10.10.0/24"
    cp:      "10.10.11.0/24"
    workers: "10.10.12.0/24"

assignments:
  prod-01:
    haproxy: "10.10.1.0/24"
    cp:      "10.10.2.0/24"
    workers: "10.10.3.0/24"
```

Neue Ranges hinzufügen: einfach weitere Einträge in `available` eintragen
und committen — beim nächsten Create stehen sie sofort zur Verfügung.

---

## IPAM-Logik in Ansible

### Cluster erstellen: Range zuweisen

```
1. available leer? → Fehler, ipam.yaml manuell erweitern
2. Ersten Eintrag aus available nehmen
3. Eintrag in assignments schreiben
4. available um ersten Eintrag verkürzen
5. ipam.yaml schreiben + committen
```

```yaml
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
```

### Cluster löschen: Range freigeben

```yaml
- name: Release ranges back to available
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
```

---

## AWX Survey: ip_block Select-Liste

Die `available`-Liste in `ipam.yaml` ist direkt die Quelle für das
`ip_block`-Dropdown im AWX Survey. Der Survey zeigt die haproxy-Adresse
ohne `/24` — Ansible leitet cp und worker automatisch aus dem Block ab.

**Survey-Choices (aus ipam.yaml generiert):**
```
10.10.4.0   →  haproxy: 10.10.4.0/24 | cp: 10.10.5.0/24 | worker: 10.10.6.0/24
10.10.7.0   →  haproxy: 10.10.7.0/24 | cp: 10.10.8.0/24 | worker: 10.10.9.0/24
10.10.10.0  →  haproxy: 10.10.10.0/24 | cp: 10.10.11.0/24 | worker: 10.10.12.0/24
```

Choices aufbauen:
```yaml
ip_block_choices: >-
  {{ ipam.available
     | map(attribute='haproxy')
     | map('regex_replace', '\.0/24$', '')
     | list }}
```

---

## Subnetz-Verwendung

### HAProxy-Netz (x.x.N.0/24)

- HAProxy-Instanzen (typisch 2 für HA)
- Virtuelle IP (VIP) für den API-Server
- Externe Erreichbarkeit des Clusters

### Control Plane-Netz (x.x.N+1.0/24)

- etcd-Nodes
- API-Server-Nodes
- Controller Manager, Scheduler

### Worker-Netz (x.x.N+2.0/24)

- Worker Nodes
- Pod-Traffic bleibt im Worker-Subnetz
- Calico verwaltet Pod-Netz intern

---

## terraform.tfvars: IP-Ranges

Die zugewiesenen Ranges werden automatisch in `terraform.tfvars` eingetragen:

```hcl
haproxy_subnet  = "10.10.4.0/24"
cp_subnet       = "10.10.5.0/24"
worker_subnet   = "10.10.6.0/24"
```

Das OpenTofu-Modul (`tofu-modules/k8s-cluster/variables.tf`) erwartet
diese drei Variablen und erstellt die entsprechenden Netzwerkobjekte
beim Cloud-Provider.
