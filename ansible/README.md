# Ansible: VM-Config-Export

Sammelt **vor dem Backup-Lauf** die Konfiguration aller VMs per SSH ein und legt sie unter `/srv/vm-backups/ansible/<vm>` ab. Der Backup-Container (siehe `../backup/`) nimmt das Verzeichnis als `/data/vm-config` auf und sichert es mit restic-Tags `vm-config:<name>`.

## Zweck

Der Export ist der **Bauplan** für einen VM-Neuaufbau (Tier 1/2 der Backup-Strategie):

- System-Facts (Netzwerk, IPs, Disks, OS-Version)
- Paketliste (`dpkg --get-selections`)
- Relevante `/etc`-Teile (Netzwerk, fstab, hosts, eigene systemd-Units, cron.d)
- Docker-Compose-Stapel inkl. `.env`
- Optional: eigene Config-Pfade pro VM (per Host-Var `config_dirs`)

## Setup

```bash
cd ansible
cp inventory.ini.example inventory.ini          # Hostnamen + IPs anpassen
cp host_vars/docker-vm.yml.example host_vars/<vm>.yml   # pro VM eine Datei
cp ansible.cfg.example ansible.cfg
sudo mkdir -p /srv/vm-backups && sudo chmod 700 /srv/vm-backups

# SSH-Key des Backup-Hosts auf alle VMs verteilen (einmalig)
ssh-copy-id root@<vm>

# Testlauf
ansible-playbook site.yml
```

## Zeitplan

systemd (auf dem Docker-Host), **02:30 Uhr**, also 30 min vor dem Backup-Lauf um 03:00:

```bash
sudo cp ansible/systemd/homelab-ansible-export*.{service,timer} /etc/systemd/system/
sudo sed -i 's|/srv/homelab/ansible|/PFAD/ZU/homelab/ansible|' /etc/systemd/system/homelab-ansible-export.service
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-ansible-export.timer
```

## Hinweise

- **Secrets:** Exporte können `.env`-Dateien und Passwörter enthalten. `inventory.ini`, `host_vars/*` und der Export unter `/srv/vm-backups` sind Klartext — Verzeichnis mit `chmod 700`, und echte Inventory/Host-Var-Dateien nicht committen (nur die `.example`-Templates).
- **UIDs/GIDs:** Der Export läuft als root, `ansible.builtin.synchronize` (rsync `-a`) erhält Berechtigungen und numerische IDs. Beim Restore `tar --numeric-owner -p` verwenden.
- **Ignorierte Fehler:** Nicht jede VM hat netplan/systemd-Units; fehlende Pfade werden übersprungen, damit ein Playbook-Lauf nicht komplett abbricht.
- Zielzustand wäre, die VMs komplett in Ansible zu deklarieren; dieser Export ist das Sicherheitsnetz für den unmodellierten Rest.