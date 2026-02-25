# SSH-Public-Keys aus openbao verwenden 

## Konzept

```
OpenBao KV:
  kv/servers/webserver01/ssh-keys  → [pubkey1, pubkey2]
  kv/servers/dbserver01/ssh-keys   → [pubkey1, pubkey3]
```

Cloud-Init holt beim Booten die Keys für seine Rolle und schreibt sie in `authorized_keys`.

---

## Setup

**Keys in OpenBao ablegen:**
```bash
bao kv put kv/servers/webserver01/ssh-keys \
  key1="ssh-ed25519 AAAA... jochen@laptop" \
  key2="ssh-ed25519 BBBB... admin@office"
```

**AppRole für den Server anlegen** (damit sich der Server authentifizieren kann):
```bash
bao auth enable approle
bao policy write server-ssh-reader - <<EOF
path "kv/data/servers/{{identity.entity.name}}/ssh-keys" {
  capabilities = ["read"]
}
EOF
bao write auth/approle/role/provisioning \
  token_policies="server-ssh-reader" \
  token_ttl=5m
```

---

## Cloud-Init Script

```bash
#!/bin/bash
BAO_ADDR="https://bao.example.com"
ROLE_ID="<role-id>"
SECRET_ID="<secret-id>"
SERVER_NAME="webserver01"

# Authentifizieren
TOKEN=$(curl -s $BAO_ADDR/v1/auth/approle/login \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" \
  | jq -r '.auth.client_token')

# Keys holen und in authorized_keys schreiben
curl -s -H "X-Vault-Token: $TOKEN" \
  $BAO_ADDR/v1/kv/data/servers/$SERVER_NAME/ssh-keys \
  | jq -r '.data.data | to_entries[].value' \
  >> /root/.ssh/authorized_keys

chmod 600 /root/.ssh/authorized_keys
```

---

## Bewertung

**Vorteile:** Zentrale Verwaltung, Keys pro Server steuerbar, Audit-Log wer wann was abgerufen hat.

**Schwachstelle:** `SECRET_ID` muss irgendwie in die Cloud-Init gelangen (z.B. über DigitalOcean User Data oder Metadata-Service). Das ist der klassische **Bootstrap-Trust-Problem** — du kannst das mit einem kurzlebigen Response-Wrapping-Token lösen:

```bash
# Einmal-Token generieren, der nur einmal einlösbar ist
bao write -wrap-ttl=5m -f auth/approle/role/provisioning/secret-id
```

Diesen Wrapped Token gibst du in cloud-init mit — er ist nur 5 Minuten gültig und einmalig einlösbar.
