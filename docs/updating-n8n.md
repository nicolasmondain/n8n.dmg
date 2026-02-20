# Updating the Bundled n8n Version

## Procedure

1. Check the latest stable version at <https://docs.n8n.io/release-notes/>
2. Edit `config.sh` at the project root and update `N8N_VERSION`:
   ```bash
   N8N_VERSION="X.Y.Z"
   ```
3. Rebuild:
   ```bash
   make clean && make
   ```
4. Test the generated DMG (`dist/n8n-local-installer.dmg`) on a fresh install.
5. Commit the change:
   ```bash
   git add config.sh
   git commit -m "build(config): bump n8n to X.Y.Z"
   ```

## Notes

- The version is defined once in `config.sh` — all scripts source it automatically.
- `scripts/bundle-n8n.sh` runs `npm install n8n@${N8N_VERSION}` for both arm64 and x64 architectures. If the version you set doesn't exist on npm, the build will fail at this step.
- Major version bumps (e.g. 1.x to 2.x) may require a newer Node.js runtime. Check n8n's requirements and update `NODE_VERSION` in `config.sh` if needed.
- After a major upgrade, verify that the LaunchAgent and CLI helper (`n8n-dmg.sh`) still work correctly, as n8n CLI flags or environment variables may have changed.
