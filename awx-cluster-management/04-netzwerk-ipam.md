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

Nächste freie Range beginnt bei: 10.10.7.0
```

Kapazität: 254 verfügbare /24er → 84 Cluster möglich (3 x /24 pro Cluster).

---

## ipam.yaml

Liegt in `infra/clusters/_network/ipam.yaml`.
Wird von AWX bei create und destroy automatisch aktualisiert.

```yaml
base_network: 10.10.0.0/16
subnet_size: /24

assignments:
  prod-01:
    haproxy:  "10.10.1.0/24"
    cp:       "10.10.2.0/24"
    workers:  "10.10.3.0/24"
  dev-01:
    haproxy:  "10.10.4.0/24"
    cp:       "10.10.5.0/24"
    workers:  "10.10.6.0/24"

# Freigegebene Ranges nach cluster-destroy (werden bevorzugt wiederverwendet)
freed: []

next_free_octet: 7
```

---

## IPAM-Logik in Ansible

### Cluster erstellen: Range zuweisen

```
1. Gibt es Einträge in freed?
   JA  → ersten Eintrag aus freed nehmen, freed verkürzen
   NEIN → next_free_octet verwenden, next_free_octet += 3

2. Zuweisung in assignments eintragen
3. ipam.yaml schreiben + committen (zusammen mit cluster-Ordner)
```

```yaml
- name: Assign ranges
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
```

### Cluster löschen: Range freigeben

```yaml
- name: Release ranges back to freed
  ansible.builtin.set_fact:
    ipam_updated: >-
      {{
        ipam | combine({
          'assignments': ipam.assignments | dict2items
                         | rejectattr('key', 'equalto', cluster_name)
                         | items2dict,
          'freed': ipam.freed + [ ipam.assignments[cluster_name] ]
        })
      }}
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
haproxy_subnet  = "10.10.1.0/24"
cp_subnet       = "10.10.2.0/24"
worker_subnet   = "10.10.3.0/24"
```

Das OpenTofu-Modul (`tofu-modules/k8s-cluster/variables.tf`) erwartet
diese drei Variablen und erstellt die entsprechenden Netzwerkobjekte
beim Cloud-Provider.
