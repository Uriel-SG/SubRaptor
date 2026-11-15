# **SubRaptor**


![SubRaptorLogo](https://github.com/user-attachments/assets/46b08ef6-0fec-4277-b9cf-4a85200be3bc)

*The Fastest Subdomain Enumeration Tool* ⚡

## What is SubRaptor
SubRaptor is a blazing-fast passive subdomain enumeration tool designed for information gathering and reconnaissance. It queries **Subfinder**, **Assetfinder** and **crt.sh** in parallel, then normalizes and deduplicates everything into one clean list.

No packets are sent to the target: all results come from public data sources.

## Why SubRaptor
- Lightning-fast discovery: all sources run in parallel ⚡
- Wider coverage by aggregating multiple sources 🔍
- Clean, pipe-friendly output: results on stdout, logs on stderr 🎯
- Per-source summary showing what each source found (and what only it found)
- Optional DNS resolution and JSON output
- One-command installer that takes care of the dependencies 🛠️

## Versions
| Command | Sources | Dependencies | Use it when |
|---|---|---|---|
| `subraptor` | Subfinder, Assetfinder, crt.sh | Installed automatically by `install.sh` | You want maximum coverage |
| `subraptor-lite` | crt.sh | Only `curl` and `jq` | You want a minimal, dependency-light tool |

## Installation
- Download the tool:
```bash
git clone https://github.com/Uriel-SG/SubRaptor.git
```
- Install SubRaptor:
```bash
cd SubRaptor
bash install.sh
```

Run the installer as a **normal user** (not with `sudo`): it asks for `sudo` only when it needs to install system packages or Go.

The installer checks what is already present and installs only what is missing, from official sources:
- System packages (`curl`, `jq`, `coreutils`, `column`, `getent`) via `apt`, `dnf` or `pacman`
- Go from [go.dev](https://go.dev/dl/), with SHA256 verification (only if missing or older than 1.21)
- `subfinder` and `assetfinder` via `go install`
- `subraptor` and `subraptor-lite` into `~/.local/bin`

Useful installer options:
```bash
bash install.sh -c   # check only: show what is installed/missing, change nothing
bash install.sh -y   # assume "yes" to every confirmation
```

If asked, let the installer add `~/.local/bin` and `~/go/bin` to your `PATH`, then open a new shell.

## Usage
- **Enjoy it!**
```bash
subraptor <example.com>
```

### Options
| Option | Description |
|---|---|
| `-o <file>` | Save results to a file (in addition to stdout) |
| `-f <fmt>` | Output format: `txt` (default) or `json` |
| `-s <list>` | Comma-separated sources: `subfinder,assetfinder,crtsh` (default: all) |
| `-r` | Resolve subdomains (IPv4) and show their IPs |
| `-t <n>` | Threads used for DNS resolution (default: 20) |
| `-T <sec>` | Per-source timeout in seconds (default: 180) |
| `-q` | Quiet: no banner or summary, results only |
| `-h`, `--help` | Show the help |

### Examples
```bash
# Basic enumeration
subraptor example.com

# Save results to a file
subraptor -o subdomains.txt example.com

# Only some sources, with DNS resolution
subraptor -s subfinder,crtsh -r example.com

# JSON output, ready for jq
subraptor -f json -q example.com | jq '.subdomains[].name'

# Feed other tools
subraptor -q example.com | httpx -silent
```

Missing tools are skipped automatically, and the summary table shows the status of every source (`ok`, `missing`, `failed`, `timeout`).

### SubRaptor Lite
The minimal version, using crt.sh only. It supports the same options (except `-s`, `-T` and the multi-source summary):
```bash
subraptor-lite <example.com>
subraptor-lite -r -o subs.txt example.com
```

## Tested on
- Kali Linux
- Parrot OS

## Disclaimer
SubRaptor is intended for security research, OSINT and authorized penetration testing. Only use it on domains you own or have explicit permission to test.
