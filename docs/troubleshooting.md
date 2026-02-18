# Troubleshooting

## n8n doesn't start after install

Open the native app and use **Service > View Logs** to check for errors.

From the terminal:

```bash
n8n-dmg status
n8n-dmg logs
```

## Port already in use

```bash
lsof -i :5678
```

## Change the port

Reinstall from the DMG — the installer will prompt for a new port. Or pass it directly:

```bash
bash /Volumes/n8n\ Installer/.payload/install.sh --port=3000
```

## Service won't stop

```bash
launchctl bootout gui/$(id -u)/com.n8n.local
```

## Manual LaunchAgent control

```bash
# Start
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.n8n.local.plist

# Stop
launchctl bootout gui/$(id -u)/com.n8n.local
```

## Database issues after upgrade

If n8n fails to start after upgrading from an older version (schema mismatch), reset the database:

```bash
rm ~/.n8n/database.sqlite
```

This will remove all workflows and credentials — back up the file first if needed.
