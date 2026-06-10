# Setup-Anleitung

## 1. Einmalig: Secrets verschluesseln

```
# Passwort festlegen und merken (kommt spaeter nach GitLab)
ansible-vault encrypt group_vars/all/secrets.yml
```

## 2. GitLab CI/CD Variables setzen

Unter: Settings -> CI/CD -> Variables

| Variable            | Wert                        | Masked | Protected |
|---------------------|-----------------------------|--------|-----------|
| VAULT_PASSWORD      | dein-vault-passwort         | ja     | ja        |
| SSH_PRIVATE_KEY     | Inhalt von ~/.ssh/id_ed25519| ja     | ja        |
| SSH_PRIVATE_KEY_PROD| Prod SSH Key                | ja     | ja        |

## 3. Lokal testen

```
ansible-playbook site.yml -i inventory/hosts.yml --ask-vault-pass
```

## 4. Secret rotieren

```
# Altes Passwort eingeben, neues setzen
ansible-vault rekey group_vars/all/secrets.yml

# Dann in GitLab Variable VAULT_PASSWORD aktualisieren
```

## 5. Neues Secret hinzufuegen

```
ansible-vault edit group_vars/all/secrets.yml
# Zeile hinzufuegen, speichern
git add group_vars/all/secrets.yml
git commit -m "add new secret (encrypted)"
```
