# Examples

Add one share link:

```bash
wproxyctl node add 'vless://UUID@example.com:443?security=tls&type=ws&path=%2Fws&sni=example.com#Example'
sudo wproxyctl nm sync
```

Add and update a subscription:

```bash
wproxyctl sub add 'https://example.com/sub'
wproxyctl sub update
sudo wproxyctl nm sync
```

Open the graphical manager:

```bash
wproxy-manager
```

Check status and latency:

```bash
wproxyctl status --json
wproxyctl node ping --all
```
