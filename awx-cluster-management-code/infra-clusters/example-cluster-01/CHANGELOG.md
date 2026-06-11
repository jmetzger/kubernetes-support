# Cluster example-cluster-01

## 2026-06-11 | Erstellt
- K8s: rke2 1.30
- Worker: 3 x c3.large
- Control Plane: 3 Nodes
- Calico: 3.27.0 / containerd: 1.7.13
- Netz haproxy: 10.10.1.0/24 / cp: 10.10.2.0/24 / worker: 10.10.3.0/24
- AWX Job: #1337 (k8s-cluster-create) — jmetzger
