# Ephemoral Data Directory

This directory will be populated with ephemoral node data created during configuration of the node.

ephemeral/                   # Temporary credential files
├── old_login_key.pw         # Default user login key
├── old_luks_key.pw          # Default LUKS disk unlock key
├── *.txt                    # Generated password and other unique files - after deployment
├── id_ed25519               # Generated ssh privkey - after deployment
└── id_ed25519.pub           # Generated ssh pubkey - after deployment
