// Read the vault encryption key that lumo-tamer stored in the OS keychain
// (Windows Credential Manager) via keytar.
// Usage: node tools/read-vault-key.mjs [service] [account]
// Note: when called as a script, argv[0]=node, argv[1]=script path,
// so explicit service/account start at argv[2]/argv[3].
// If no explicit arguments are given, service/account are read dynamically
// from config.defaults.yaml (the copy in dist/ first, then the repo root one).
// Prints the Base64 key (no trailing newline) or exits 1 when not found.
import keytar from 'keytar';
import { readFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { parse } from 'yaml';

// Resolve the project root (this file lives in tools/).
const thisFile = fileURLToPath(import.meta.url);
const projectRoot = dirname(dirname(thisFile));

function loadKeychainFromDefaults() {
    const candidates = [
        join(projectRoot, 'dist', 'config.defaults.yaml'), // copied by start-auth.ps1
        join(projectRoot, 'config.defaults.yaml'),         // repo root fallback
    ];
    for (const path of candidates) {
        if (!existsSync(path)) continue;
        try {
            const doc = parse(readFileSync(path, 'utf8'));
            const vault = doc?.auth?.vault;
            if (vault?.keychain?.service && vault?.keychain?.account) {
                return { service: vault.keychain.service, account: vault.keychain.account };
            }
        } catch {
            // try next candidate
        }
    }
    return { service: 'lumo-tamer', account: 'vault-key' };
}

const { service, account } = loadKeychainFromDefaults();
const serviceArg = process.argv[2];
const accountArg = process.argv[3];
const effService = serviceArg || service;
const effAccount = accountArg || account;

const password = await keytar.getPassword(effService, effAccount);
if (password) {
    process.stdout.write(password);
    process.exit(0);
}
process.exit(1);