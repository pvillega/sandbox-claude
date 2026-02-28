# Sandbox Claude Code

Run Claude Code agents in fully isolated Incus containers on **macOS** (via OrbStack VM) or **native Linux**. Enable YOLO mode with confidence -- your host filesystem, credentials, and network stay untouched. Each container gets its own filesystem, Docker daemon, workspace, dedicated SSH deploy key, bidirectional port forwarding, and egress filtering.

## Key Features

- **Fully isolated Incus containers** -- agents cannot touch your host filesystem, credentials, or network
- **Works on macOS (OrbStack) and native Linux** -- all commands auto-detect the platform
- **Instant container creation** via btrfs copy-on-write snapshots of golden images
- **Pre-built stacks** for Rust, Python, Node, Go, and .NET (or add your own)
- **Per-container deploy keys and SSH agent** -- private keys never touch the container's disk
- **Domain-based egress filtering** -- restrict HTTPS traffic to an approved allowlist
- **Bidirectional port forwarding** -- access container services from your host and vice versa

## Quickstart

### macOS Quickstart

**Prerequisite:** Install [OrbStack](https://orbstack.dev/) (`brew install orbstack`).

```bash
# 1. Clone and install
git clone https://github.com/you/sandbox-claude.git
cd sandbox-claude
./install.sh                # Symlinks bin/* into ~/.local/bin

# 2. One-time setup (creates OrbStack VM, installs Incus, builds golden images)
sandbox-setup               # Takes ~10 minutes the first time
```

### Linux Quickstart

```bash
# 1. Clone and install
git clone https://github.com/you/sandbox-claude.git
cd sandbox-claude
./install.sh                # Symlinks bin/* into ~/.local/bin

# 2. Install Linux prerequisites (requires sudo, then log out/in)
sudo sandbox-linux-prereqs  # Installs iptables, curl, gpg, git, gh; adds you to incus-admin

# 3. One-time setup (installs Incus + Squid on host, builds golden images)
sandbox-setup               # Takes ~10 minutes the first time
```

### Common Steps (both platforms)

```bash
# 3. Create a sandbox for your project
sandbox-create my-project git@github.com:me/my-repo.git --stack rust

# 4. Authenticate Claude inside the container
sandbox-login my-project

# 5. Open a shell to verify everything
sandbox my-project

# 6. Run Claude Code in YOLO mode
sandbox my-project --claude

# 7. When done, stop or destroy
sandbox-stop my-project       # Stop (preserves container, can restart)
sandbox-stop my-project --rm  # Destroy (removes container + deploy key)
```

## Table of Contents

- [Architecture](#architecture)
- [Platform Support](#platform-support)
- [Prerequisites](#prerequisites)
- [Commands Reference](#commands-reference)
- [GitHub Deploy Keys](#github-deploy-keys)
- [Stacks](#stacks)
- [Port Allocation](#port-allocation)
- [Configuration](#configuration)
  - [Environment Variables](#environment-variables)
  - [Domain-Based Egress Filtering](#domain-based-egress-filtering)
- [Security Model](#security-model)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)
- [License](#license)

## Architecture

The sandbox uses a layered isolation model. On macOS there are three layers; on Linux the VM layer is skipped:

```
macOS path:
  macOS (safe, never touched by agents)
   +-- OrbStack machine "sandbox" (lightweight Ubuntu Noble VM)
        +-- Incus (btrfs storage pool, incusbr0 bridge) → containers

Linux path:
  Linux host (safe, agents confined to Incus containers)
   +-- Incus (btrfs storage pool, incusbr0 bridge) → containers
```

```
Golden images (shared across both platforms):
  +-- golden-base/ready     (Docker, Claude Code, SSH, git, Python 3)
  +-- golden-rust/ready     (base + Rust toolchain + quality tools)
  +-- golden-python/ready   (base + Poetry, uv, ruff, mypy, etc.)
  +-- golden-node/ready     (base + Node.js 22, npm, pnpm, yarn, bun, eslint, etc.)
  +-- golden-go/ready       (base + Go, golangci-lint, govulncheck)
  +-- golden-dotnet/ready   (base + .NET SDK, dotnet tools)

Agent containers (instant btrfs copy-on-write clones):
  +-- agent-proj-alpha      (clone of golden-rust)
  +-- agent-proj-beta       (clone of golden-node)
  +-- agent-proj-gamma      (clone of golden-python)
  +-- ...
```

**Port forwarding** is bidirectional:

```
macOS (2 hops):
  Incus container → Incus proxy device → OrbStack VM → OrbStack auto-forward → macOS localhost

Linux (1 hop):
  Incus container → Incus proxy device → Linux host localhost
```

Golden images are btrfs snapshots. Creating a new container is an instant copy-on-write clone -- no reinstalling packages, no waiting.

## Platform Support

The sandbox works on both **macOS** (via OrbStack) and **native Linux** hosts:

| | macOS | Linux |
|---|---|---|
| VM layer | OrbStack (Ubuntu Noble) | None (direct host) |
| Container runtime | Incus inside VM | Incus on host |
| Squid proxy | Inside VM | On host |
| Port forwarding | Container → VM → macOS (2 hops) | Container → host (1 hop) |
| Setup | `sandbox-setup` creates VM + installs everything | `sandbox-setup` installs directly on host |

All `sandbox-*` commands auto-detect the platform and adjust their behavior. No flags or configuration needed.

## Prerequisites

### macOS

| Requirement | How to install | Why |
|---|---|---|
| **macOS** (Apple Silicon or Intel) | -- | Host OS |
| **OrbStack** | `brew install orbstack` | Lightweight Linux VM runtime |

### Linux

Run `sudo sandbox-linux-prereqs` to install everything in this table automatically (except Incus and Squid, which are handled by `sandbox-setup`).

| Requirement | How to install | Why |
|---|---|---|
| **Linux** (Ubuntu 22.04+ or Debian 12+) | -- | Host OS |
| **Incus** | See [Zabbly repo](https://github.com/zabbly/incus) | Container runtime (auto-installed by `sandbox-setup`) |
| **Squid** | `apt install squid-openssl` | Egress filtering (auto-installed by `sandbox-setup`) |
| **Root or sudo** | -- | Required for iptables and Incus setup |
| **`incus-admin` group** | `sudo sandbox-linux-prereqs` or `sudo usermod -aG incus-admin $USER` | Required for non-root Incus access |
| **`iptables`** | `sudo sandbox-linux-prereqs` or `apt install iptables` | Required for egress filtering |
| **`curl`, `gpg`, `git`** | `sudo sandbox-linux-prereqs` or `apt install curl gnupg git` | Required by `sandbox-setup` for Incus installation |

### Both Platforms

| Requirement | How to install | Why |
|---|---|---|
| **GitHub CLI (`gh`)** | `brew install gh` / `apt install gh` | Deploy key automation |
| **Admin access** on target repos | -- | Required to register deploy keys |
| **16 GB RAM** (recommended) | -- | VM + containers + Docker daemons |

## Commands Reference

### Overview

| Command | Purpose |
|---|---|
| `sandbox-linux-prereqs` | Linux only: install system packages and configure group membership before `sandbox-setup` |
| `sandbox-setup` | One-time: create VM (macOS) or install directly (Linux), set up Incus, build golden images, apply egress rules |
| `sandbox-create` | Create a new agent container from a golden image |
| `sandbox` | Session entry point: shell, Claude, or arbitrary command |
| `sandbox-list` | List all containers with health status |
| `sandbox-expose` | Expose additional ports bidirectionally |
| `sandbox-login` | Authenticate Claude Code via OAuth inside a container |
| `sandbox-stop` | Stop and optionally remove a container |
| `sandbox-nuke` | Destroy all agent containers (nuclear option) |

---

### sandbox-linux-prereqs

Install Linux prerequisites for `sandbox-setup`. Idempotent -- safe to re-run. **Linux only; requires sudo.**

```
sudo sandbox-linux-prereqs
```

**What it does:**

1. Installs system packages if missing: `iptables`, `curl`, `gnupg`, `git`
2. Adds the official GitHub CLI apt repository and installs `gh` if missing
3. Creates the `incus-admin` group if it doesn't exist and adds the current user to it
4. Warns if a logout/login is required for group membership to take effect

This script does **not** install Incus or Squid -- those are handled by `sandbox-setup`.

---

### sandbox-setup

One-time infrastructure setup. Idempotent -- safe to re-run.

```
sandbox-setup [--rebuild <stack>]
```

| Flag | Description |
|---|---|
| `--rebuild <stack>` | Force rebuild of a specific golden image (e.g. `base`, `rust`, `all`) |

**What it does:**

1. Validates prerequisites (OrbStack on macOS; Incus on Linux; `gh`, `ssh-keygen` on both)
2. On macOS: creates OrbStack machine `sandbox` (Ubuntu Noble) -- skips if exists. On Linux: skips VM creation
3. Installs Incus (inside VM on macOS, directly on host on Linux; Zabbly repo, btrfs backend, `incusbr0` bridge) -- skips if installed
4. Applies default egress iptables rules on `incusbr0`
5. Builds golden images: runs `stacks/base.sh` first, then each variant stack. Skips stacks that already have a `ready` snapshot

```bash
# First time setup
sandbox-setup

# Rebuild just the Rust golden image (e.g., after updating stacks/rust.sh)
sandbox-setup --rebuild rust

# Rebuild everything from scratch
sandbox-setup --rebuild all
```

---

### sandbox-create

Create a new agent container.

```
sandbox-create <name> [repo-url] [flags]
```

| Flag | Description | Default |
|---|---|---|
| `--stack <name>` | Golden image to use | `base` |
| `--branch <name>` | Git branch to checkout after cloning | Repo default branch |
| `--from <name>` | Copy repo URL and stack from an existing container | -- |
| `--ssh-key <path>` | Use a specific SSH key instead of auto-generating a deploy key | Auto-generate |
| `--slot <n>` | Force a specific port slot (1-99) | Auto-assign |
| `--cpu <n>` | CPU core limit | No limit (shares VM) |
| `--memory <size>` | Memory limit (e.g., `8GiB`) | No limit (shares VM) |
| `--env KEY=VALUE` | Extra environment variable (repeatable) | -- |
| `--restrict-domains` | Enable domain-based HTTPS egress filtering with default allowlist | Off (all HTTPS allowed) |
| `--domains-file <path>` | Enable domain filtering with a custom allowlist file | Bundled `anthropic-default.txt` |

**Steps performed:**

1. Validates the golden image exists for the chosen stack
2. Auto-assigns the next free slot (or validates a manually provided slot)
3. If a repo URL is provided and `--ssh-key` is not set: auto-generates an ed25519 deploy key and registers it on GitHub via `gh`
4. Clones the golden image snapshot (instant btrfs copy-on-write)
5. Applies resource limits if `--cpu` or `--memory` are set
6. Adds Incus proxy devices for SSH, App, and Alt ports
7. Starts the container
8. Sets up a dedicated ssh-agent in the sandbox environment (OrbStack VM on macOS, host on Linux) and mounts the socket into the container
9. Injects environment variables from `~/.sandbox/env` and any `--env` overrides into `/root/.bashrc`
10. If `--restrict-domains` is set: configures Squid SNI filtering, iptables NAT redirect, and QUIC blocking for this container
11. Clones the repo into `/workspace/project` (with `--branch` if specified)
12. Stores metadata (stack, repo, slot, restrict-domains) in Incus config for later retrieval
13. Prints connection info

```bash
# Minimal -- just a scratch container
sandbox-create scratch

# Typical usage -- project with a specific stack
sandbox-create proj-alpha git@github.com:me/alpha.git --stack rust

# Branch from an existing container (inherits repo URL and stack)
sandbox-create proj-alpha-hotfix --from proj-alpha --branch hotfix/auth-fix

# Custom resources for a heavy build
sandbox-create big-build git@github.com:me/monorepo.git --stack node --cpu 8 --memory 16GiB

# Manual SSH key (for repos where deploy keys can't be used)
sandbox-create proj git@github.com:me/repo.git --ssh-key ~/.ssh/my_key

# Extra env vars
sandbox-create proj git@github.com:me/repo.git --env DB_HOST=localhost --env DB_PORT=5432

# Restrict HTTPS egress to default allowlist (Anthropic's Claude Code web domains)
sandbox-create proj git@github.com:me/repo.git --restrict-domains

# Restrict HTTPS egress to a custom allowlist
sandbox-create proj git@github.com:me/repo.git --domains-file ~/my-domains.txt

# Domain restriction is inherited with --from
sandbox-create proj-hotfix --from proj --branch hotfix/auth
```

---

### sandbox

Session entry point. Opens a shell, runs Claude Code, or executes a command inside one or more containers. When multiple containers are specified, a tmux session is created with a pane for each.

```
sandbox <name> [name2...] [flags]
```

| Flag | Description |
|---|---|
| `--claude` | Run Claude Code instead of a shell |
| `--cmd "<command>"` | Run a specific command |

All sessions use `incus exec` (via `orb run` on macOS, directly on Linux) -- no SSH dependency.

```bash
# Shell into one container
sandbox proj-alpha

# tmux session with shells in two containers
sandbox proj-alpha proj-beta

# Run Claude Code in one container
sandbox proj-alpha --claude

# Run Claude Code in multiple containers (tmux, one per pane)
sandbox proj-alpha proj-beta --claude

# Run a command in one container
sandbox proj-alpha --cmd "git status"

# Run the same command across multiple containers
sandbox proj-alpha proj-beta --cmd "git status"
```

---

### sandbox-list

List all containers with health status.

```
sandbox-list
```

No flags. Produces a table like:

```
CONTAINER              STATE     SLOT  SSH   APP   ALT   EXTRA          EGRESS     DOCKER  AGENT  CLAUDE  REPO
agent-proj-alpha       Running   1     2201  8001  9001  5432,6379      filtered   ok      ok     auth'd  me/alpha (main)
agent-proj-beta        Running   2     2202  8002  9002  -              open       ok      no-key no-auth me/beta (main)
agent-proj-gamma       Stopped   3     2203  8003  9003  3000           open       -       -      -       me/gamma (dev)
```

**Health check columns** (checked via `incus exec` into running containers):

| Column | Meaning |
|---|---|
| EGRESS | Domain filtering: `filtered` (restricted allowlist) or `open` (all HTTPS allowed) |
| DOCKER | `docker info` succeeds: `ok`, fails: `err` |
| AGENT | `ssh-add -l` succeeds: `ok`, no keys loaded: `no-key`, no socket: `none` |
| CLAUDE | Auth token in `~/.claude/`: `auth'd`, missing: `no-auth` |
| REPO | Shortened git remote URL + current branch |
| EXTRA | Comma-separated list of additionally exposed ports |

Stopped containers show `-` for all health columns.

---

### sandbox-expose

Expose additional ports bidirectionally (inbound from host to container AND outbound from container to external network).

```
sandbox-expose <name> <port> [protocol]
```

| Argument | Description | Default |
|---|---|---|
| `<name>` | Container name (without `agent-` prefix) | Required |
| `<port>` | Port number to expose | Required |
| `[protocol]` | `tcp`, `udp`, or `both` | `tcp` |

**What it does:**

- **Inbound**: Creates an Incus proxy device so `host:port` reaches the container
- **Outbound**: Adds a per-container iptables rule so the container can reach external services on that port

Both directions are opened in a single command.

```bash
# Expose PostgreSQL (TCP both directions)
sandbox-expose proj-alpha 5432

# Expose a UDP port
sandbox-expose proj-alpha 5432 udp

# Expose both TCP and UDP
sandbox-expose proj-alpha 5432 both
```

---

### sandbox-login

Authenticate Claude Code via OAuth inside a container.

```
sandbox-login <name>
```

**Steps:**

1. Adds a temporary Incus proxy device for the OAuth callback port
2. Runs `claude login` inside the container via `incus exec`
3. You complete the OAuth flow in your browser (macOS) or locally (Linux)
4. The auth token is stored in the container's `~/.claude/` directory (persists across restarts)
5. Removes the temporary proxy device
6. Confirms success

---

### sandbox-stop

Stop and optionally remove a container.

```
sandbox-stop <name> [--rm]
```

| Flag | Description |
|---|---|
| `--rm` | Also remove the container, its deploy key from GitHub, and the local key pair |

**Without `--rm`:**
- Stops the container
- Kills the ssh-agent
- Deploy key stays on GitHub (container can be restarted later)

**With `--rm`:**
- Stops the container
- Kills the ssh-agent
- Removes the deploy key from GitHub via `gh repo deploy-key delete`
- Deletes the local key pair from `~/.sandbox/keys/`
- Deletes the container

```bash
# Stop (preserves state, can restart)
sandbox-stop proj-alpha

# Full teardown
sandbox-stop proj-alpha --rm
```

---

### sandbox-nuke

Destroy all agent containers. Requires interactive confirmation.

```
sandbox-nuke [--all]
```

| Flag | Description |
|---|---|
| `--all` | Also destroy golden images (requires re-running `sandbox-setup`) |

**Without `--all`:** Destroys all `agent-*` containers, cleans up their deploy keys and ssh-agents. Golden images are preserved.

**With `--all`:** Also destroys golden images. Full reset -- run `sandbox-setup` again to rebuild.

Prompts for confirmation by typing `yes`.

```bash
# Remove all agent containers, keep golden images
sandbox-nuke

# Full nuclear reset -- everything gone
sandbox-nuke --all
```

## GitHub Deploy Keys

### Automatic Lifecycle

When you create a container with a repo URL (and no `--ssh-key` flag), the deploy key lifecycle is fully automated:

**On `sandbox-create`:**

1. Generates an ed25519 key pair at `~/.sandbox/keys/deploy_<name>`
2. Registers the public key on GitHub via `gh repo deploy-key add -R <org/repo> -t "sandbox-<name>" -w` (the `-w` flag grants write/push access)
3. Spawns a dedicated ssh-agent process in the sandbox environment (OrbStack VM on macOS, host on Linux) with its socket at `/tmp/sandbox-agent-<container>.sock`
4. Adds the private key to the agent via `ssh-add`
5. Mounts the agent socket into the container as an Incus disk device at `/run/ssh-agent.sock`
6. Sets `SSH_AUTH_SOCK=/run/ssh-agent.sock` in the container's `/root/.bashrc`

**On `sandbox-stop`:**

- Kills the ssh-agent and removes the socket
- The deploy key remains on GitHub so the container can be restarted

**On `sandbox-stop --rm`:**

- Kills the ssh-agent and removes the socket
- Removes the deploy key from GitHub via `gh repo deploy-key delete`
- Deletes the local key pair from `~/.sandbox/keys/`

### Security Properties

- Private key material never touches the container's disk -- it lives only in the ssh-agent's memory
- Each deploy key is scoped to a single repository (enforced by GitHub)
- Each container has its own ssh-agent process -- containers cannot see each other's keys
- Deploy keys have write access (`-w` flag) so Claude can push commits
- Keys are automatically cleaned up from GitHub when a container is destroyed with `--rm`

### Manual Key Override

For repos where deploy keys cannot be used (org policy restrictions, monorepo setups, etc.):

```bash
sandbox-create proj git@github.com:me/repo.git --ssh-key ~/.ssh/my_key
```

This skips the `gh` automation entirely and uses the provided key directly. The key is loaded into a dedicated ssh-agent the same way, but no deploy key is registered on GitHub, and no cleanup is performed on `--rm`.

## Stacks

Golden images are pre-built container snapshots with all tooling installed. Creating a new container from a golden image is instant (btrfs copy-on-write clone).

### Available Stacks

| Stack | Image Name | Includes | Quality/Coverage Tools |
|---|---|---|---|
| **base** | `golden-base` | Docker CE + docker-compose-plugin, Claude Code (native binary), Python 3 + pip + venv, git, tmux, openssh-server, ripgrep, jq, htop, wget, unzip, build-essential, ca-certificates | -- |
| **rust** | `golden-rust` | Everything in base + Rust stable toolchain via rustup | clippy (linting), rustfmt (formatting), cargo-tarpaulin (coverage), cargo-audit (security) |
| **python** | `golden-python` | Everything in base + Poetry, uv | ruff (linting + formatting), mypy (type checking), bandit (security), coverage (code coverage) |
| **node** | `golden-node` | Everything in base + Node.js 22 LTS, npm, pnpm, yarn, bun | c8 (V8-native coverage), eslint (linting), prettier (formatting) |
| **go** | `golden-go` | Everything in base + Go latest stable | golangci-lint (meta-linter), govulncheck (security), `go tool cover` (built-in coverage) |
| **dotnet** | `golden-dotnet` | Everything in base + .NET SDK (latest LTS) | dotnet-coverage (coverage), `dotnet format` (built-in formatting), dotnet-sonarscanner (quality analysis), security analyzers via NuGet |

### Adding a Custom Stack

1. Create a new file `stacks/<name>.sh`. The script runs inside a container that already has the base stack installed.

```bash
#!/usr/bin/env bash
# stacks/elixir.sh -- Elixir toolchain + quality tools
# Runs INSIDE container after base.sh
set -e
export DEBIAN_FRONTEND=noninteractive

echo "Installing Elixir stack..."

# Add Erlang Solutions repo
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
dpkg -i erlang-solutions_2.0_all.deb
apt-get update
apt-get install -y esl-erlang elixir

# Quality tools
mix local.hex --force
mix local.rebar --force
mix archive.install hex phx_new --force

echo "Elixir stack complete"
```

2. Make it executable:

```bash
chmod +x stacks/elixir.sh
```

3. Rebuild golden images to include it:

```bash
sandbox-setup --rebuild elixir
```

4. Use it:

```bash
sandbox-create my-elixir-app git@github.com:me/app.git --stack elixir
```

## Port Allocation

Each container is assigned a **slot** (1-99). Slots are auto-assigned by default (lowest available) or manually specified with `--slot`.

### Slot-Based Port Scheme

| Port Type | Formula | Range | Purpose |
|---|---|---|---|
| **SSH** | 2200 + slot | 2201-2299 | SSH access to container |
| **App** | 8000 + slot | 8001-8099 | Primary application port (maps to container port 8080) |
| **Alt** | 9000 + slot | 9001-9099 | Secondary application port (maps to container port 9090) |

For example, a container in slot 3 gets:

- SSH: `localhost:2203`
- App: `localhost:8003` (maps to container `127.0.0.1:8080`)
- Alt: `localhost:9003` (maps to container `127.0.0.1:9090`)

### Extra Ports

Use `sandbox-expose` to open additional ports beyond the standard three. Extra ports are mapped 1:1 (host port = container port) and also open outbound access for that port.

```bash
# Open PostgreSQL port
sandbox-expose proj-alpha 5432

# Open Redis port
sandbox-expose proj-alpha 6379

# Both show up in sandbox-list under the EXTRA column
sandbox-list
# ... EXTRA: 5432,6379
```

## Configuration

### Environment Variables

#### The `~/.sandbox/env` File

Create `~/.sandbox/env` to define environment variables that are automatically injected into every container:

```bash
# ~/.sandbox/env
ANTHROPIC_API_KEY=sk-ant-...
GITHUB_TOKEN=ghp_...
MY_CUSTOM_VAR=some-value
```

This file is read by `sandbox-create` and injected into each container's `/root/.bashrc`. Variables persist across container restarts.

#### Per-Container Overrides with `--env`

Add or override environment variables for a specific container:

```bash
sandbox-create proj git@github.com:me/repo.git \
  --env DATABASE_URL=postgres://localhost/mydb \
  --env REDIS_URL=redis://localhost:6379
```

The `--env` flag is repeatable. Values provided via `--env` take precedence over values in `~/.sandbox/env`.

#### Layering Order

1. `~/.sandbox/env` -- loaded first, applies to all containers
2. `--env KEY=VALUE` -- per-container overrides, applied after

#### env.example Reference

A typical `~/.sandbox/env` file:

```bash
# Required for Claude Code
ANTHROPIC_API_KEY=sk-ant-your-key-here

# Optional: GitHub token for API access inside containers
GITHUB_TOKEN=ghp_your-token-here

# Optional: Custom variables for your projects
NODE_ENV=development
RUST_LOG=debug
```

The `~/.sandbox/` directory (including `env` and `keys/`) lives outside the repo entirely and is never committed.

### Domain-Based Egress Filtering

By default, containers can reach any HTTPS endpoint. Use `--restrict-domains` to limit HTTPS egress to an approved domain allowlist, matching the security model Anthropic uses for Claude Code web containers.

#### How It Works

When a container is created with `--restrict-domains`:

1. **Squid proxy** (installed in the VM on macOS, on host on Linux, by `sandbox-setup`) receives the container's HTTPS/HTTP traffic via iptables NAT PREROUTING redirect
2. Squid **peeks at the TLS ClientHello** to read the SNI (Server Name Indication) — the domain the client is connecting to
3. Squid checks the SNI against the container's **per-container domain allowlist**
4. **Allowed**: Squid splices the connection through (no decryption, no MITM, no CA cert needed)
5. **Denied**: Squid resets the connection (TCP RST)
6. **QUIC bypass** is prevented: UDP port 443 is blocked for restricted containers

This is **not DNS filtering** — it inspects the actual TLS handshake, so it works regardless of how the IP was resolved (hardcoded IPs, CDN shared IPs, etc.).

Unrestricted containers are completely unaffected — their traffic never touches Squid.

#### Usage

```bash
# Use the bundled default allowlist (Anthropic's ~190 domains)
sandbox-create my-project git@github.com:me/repo.git --restrict-domains

# Use a custom allowlist
sandbox-create my-project git@github.com:me/repo.git --domains-file ~/my-domains.txt

# Check filtering status
sandbox-list
# EGRESS column shows "filtered" or "open"

# Inherited when using --from
sandbox-create my-hotfix --from my-project --branch hotfix/auth
```

#### Domain File Format

```
# Comments start with #
# Blank lines are ignored

# Exact match — only this domain
registry.npmjs.org

# Wildcard match — domain + all subdomains
.googleapis.com

# Inline comments
pypi.org      # Python packages
```

A leading dot (`.example.com`) matches `example.com` and all subdomains (`*.example.com`). Without the dot, only the exact domain matches.

#### Allowlist Resolution Order

1. **Explicit `--domains-file <path>`** — used if provided
2. **`~/.sandbox/allowed-domains.txt`** — user override (applies to all containers)
3. **`domains/anthropic-default.txt`** — bundled default (~190 domains from Anthropic's Claude Code web container list)

#### Default Allowlist Categories

The bundled `anthropic-default.txt` includes domains for:

| Category | Examples |
|---|---|
| Anthropic services | `api.anthropic.com`, `claude.ai` |
| Version control | GitHub, GitLab, Bitbucket |
| Container registries | Docker Hub, GCR, GHCR, ECR, MCR |
| Cloud platforms | AWS, GCP, Azure, Oracle |
| Package managers | npm, PyPI, RubyGems, crates.io, Go proxy, Maven, NuGet, Hex, pub.dev, CocoaPods, CPAN, Hackage |
| Linux repos | Ubuntu archives, Launchpad PPAs |
| Dev tools | Kubernetes, HashiCorp, Anaconda, Apache, Eclipse, Node.js |
| Monitoring | Sentry, Datadog, Statsig |
| CDNs/mirrors | SourceForge, Packagecloud |
| Schemas | JSON Schema, SchemaStore |
| MCP | `*.modelcontextprotocol.io` |

#### Customising the Allowlist

To override the default for all containers, create `~/.sandbox/allowed-domains.txt`:

```bash
# Start from the bundled default and add your domains
cp domains/anthropic-default.txt ~/.sandbox/allowed-domains.txt
echo "my-internal-registry.corp.com" >> ~/.sandbox/allowed-domains.txt
```

Or create a project-specific file and pass it with `--domains-file`.

## Security Model

### What IS Protected

| Boundary | Protection |
|---|---|
| **Host filesystem** (macOS / Linux) | Agents run inside Incus containers (inside an OrbStack VM on macOS, directly on host on Linux). No host filesystem access whatsoever. |
| **Per-container isolation** | Each container is a separate Incus system container with its own filesystem, process tree, and network namespace. At the network level, `security.port_isolation=true` on the default profile sets the kernel's `IFLA_BRPORT_ISOLATED` flag on each container's veth — containers can only communicate with the bridge gateway (for DNS/DHCP/NAT), not with each other. Combined with `security.ipv4_filtering` and `security.ipv6_filtering` for anti-spoofing. |
| **SSH private keys** | Private keys live only in ssh-agent memory (inside the OrbStack VM on macOS, on the host on Linux). Key material never touches the container's disk. |
| **Deploy key scoping** | Each deploy key is scoped to a single GitHub repository. A compromised container cannot access other repos. |
| **Egress filtering** | Default iptables rules on `incusbr0` DROP all outbound traffic except DNS (53), HTTP (80), HTTPS (443), and SSH (22). Containers cannot reach arbitrary services unless explicitly opened with `sandbox-expose`. |
| **Domain-based HTTPS filtering** | Containers created with `--restrict-domains` can only reach HTTPS endpoints on an approved domain allowlist. Uses Squid in SNI peek/splice mode (inspects TLS ClientHello, no decryption/MITM). QUIC (UDP 443) is blocked for restricted containers. Fail-closed: if Squid is down, traffic hits a closed port. |
| **Port isolation** | Extra ports opened via `sandbox-expose` are per-container (keyed on container IP). Opening port 5432 on `proj-alpha` does not open it for `proj-beta`. |

### What is NOT Protected by Default

| Risk | Details |
|---|---|
| **VM/Host kernel access** | All containers share the same kernel (OrbStack VM on macOS, host on Linux). A container escape (unlikely but theoretically possible) would give access to the VM (macOS) or host (Linux). On macOS, the VM provides an additional isolation boundary. |
| **Env var exposure** | Environment variables injected via `~/.sandbox/env` or `--env` are written to `/root/.bashrc` inside the container. An agent can read them. This is by design (agents need API keys to function), but be aware. |
| **Deploy key write access** | Deploy keys are created with `-w` (write) access. An agent can push to the repo it was created for. |
| **HTTPS traffic content** | Without `--restrict-domains`, egress filtering allows all HTTPS traffic — agents can reach any HTTPS endpoint. Use `--restrict-domains` to limit HTTPS egress to an approved domain allowlist (see [Domain-Based Egress Filtering](#domain-based-egress-filtering)). |
| **Persistent container state** | Stopping a container preserves its filesystem. Anything the agent wrote remains until the container is destroyed with `--rm`. |

## Troubleshooting

### Common Issues

#### Docker Not Working Inside Container

**Symptom:** `docker: Cannot connect to the Docker daemon` or similar errors.

**Cause:** Docker-in-Incus requires specific security settings on the container.

**Fix:** Golden images are created with the correct security flags (`security.nesting=true`, `security.syscalls.intercept.mknod=true`, `security.syscalls.intercept.setxattr=true`). If Docker still fails:

```bash
# Shell into the container and check Docker service
sandbox proj-alpha --cmd "systemctl status docker"

# Restart Docker daemon
sandbox proj-alpha --cmd "systemctl restart docker"

# If the container was created without proper flags, recreate it
sandbox-stop proj-alpha --rm
sandbox-create proj-alpha git@github.com:me/alpha.git --stack rust
```

#### Cannot Access Ports from Host

**Symptom:** `curl localhost:8001` times out or refuses connection.

**Cause:** On macOS, the port forwarding chain has two hops (container -> OrbStack -> macOS). On Linux, one hop (container -> host). A break at either hop causes failures.

**Fix:**

```bash
# 1. Check that the container is running
sandbox-list

# 2. Verify the app is listening inside the container
sandbox proj-alpha --cmd "ss -tlnp | grep 8080"

# 3. Verify the Incus proxy device exists
sandbox proj-alpha --cmd "exit"  # just confirm you can connect

# macOS only: check OrbStack is forwarding
orb run -m sandbox incus config device show agent-proj-alpha
orb run -m sandbox ss -tlnp | grep 8001
```

Your app must listen on `0.0.0.0` (not `127.0.0.1`) inside the container for port forwarding to work through the Incus proxy device.

#### Disk Space Issues

**Symptom:** Containers fail to start or builds fail with "no space left on device".

**Fix:**

```bash
# Check disk usage
# macOS:
orb run -m sandbox df -h
orb run -m sandbox btrfs filesystem usage /
# Linux:
df -h
btrfs filesystem usage /  # if using btrfs

# Remove stopped containers to reclaim space
sandbox-nuke

# Nuclear option: destroy everything and rebuild
sandbox-nuke --all
sandbox-setup
```

#### Resource Limits

By default, containers share the VM's (macOS) or host's (Linux) resources without hard limits. If an agent is consuming too much:

```bash
# Create with limits
sandbox-create proj git@github.com:me/repo.git --cpu 4 --memory 8GiB

# Or set limits on an existing container (requires stop/start)
# macOS:
orb run -m sandbox incus config set agent-proj limits.cpu=4
orb run -m sandbox incus config set agent-proj limits.memory=8GiB
orb run -m sandbox incus restart agent-proj
# Linux:
incus config set agent-proj limits.cpu=4
incus config set agent-proj limits.memory=8GiB
incus restart agent-proj
```

#### Rebuilding Golden Images

If a golden image becomes stale (outdated packages, broken dependencies):

```bash
# Rebuild a specific stack
sandbox-setup --rebuild rust

# Rebuild everything (base + all variants)
sandbox-setup --rebuild all
```

Existing containers are NOT affected by golden image rebuilds. Only new containers created after the rebuild will use the updated image.

#### Deploy Key Issues

**Symptom:** `git push` fails with "Permission denied (publickey)".

```bash
# 1. Check the ssh-agent has a key loaded
sandbox proj-alpha --cmd "ssh-add -l"

# 2. Test SSH connectivity to GitHub
sandbox proj-alpha --cmd "ssh -T git@github.com"

# 3. Check if the deploy key exists on GitHub
gh repo deploy-key list -R me/alpha

# 4. If the key was removed manually from GitHub, recreate the container
sandbox-stop proj-alpha --rm
sandbox-create proj-alpha git@github.com:me/alpha.git --stack rust
```

**Symptom:** `sandbox-create` fails with "Failed to add deploy key".

- Verify you have admin access on the target repo
- Verify `gh auth status` shows a valid session
- For org repos, check if the org has restrictions on deploy keys

#### Claude Auth Issues

**Symptom:** Claude reports it is not authenticated.

```bash
# Re-run the login flow
sandbox-login proj-alpha

# Verify auth token exists
sandbox proj-alpha --cmd "ls -la ~/.claude/"
```

The auth token is stored inside the container at `~/.claude/` and persists across container restarts. It is lost only when the container is destroyed with `--rm`.

### macOS Issues

#### OrbStack VM Not Starting

```bash
# Check OrbStack status
orb list

# Try restarting the sandbox machine
orb stop sandbox
orb start sandbox

# If the machine is corrupted, recreate it (destroys all containers)
orb delete sandbox
sandbox-setup
```

### Linux Issues

#### Incus Permission Denied

**Symptom:** `incus list` fails with permission errors.

**Fix:** Ensure your user is in the `incus-admin` group:

```bash
sudo usermod -aG incus-admin $USER
newgrp incus-admin  # or log out and back in
```

#### Outbound Interface Not Detected

**Symptom:** `sandbox-setup` fails during egress filtering, or containers have no internet access.

**Cause:** The outbound network interface is detected from the default route. If no default route exists, detection fails.

**Fix:**

```bash
# Check your default route
ip -4 route show default

# If missing, add one (adjust interface name)
sudo ip route add default via <gateway-ip> dev <interface>
```

## Testing

The project includes a test suite with unit tests for pure functions and integration tests that validate security properties (egress filtering, container isolation, port forwarding) using real Incus containers.

See [`tests/README.md`](tests/README.md) for prerequisites and how to run the tests.

```bash
./tests/run-tests.sh unit         # Fast unit tests (~1s)
./tests/run-tests.sh integration  # Integration tests with real containers (~2-5min)
./tests/run-tests.sh              # Both
```

## Project Structure

```
sandbox-claude/
+-- bin/
|   +-- sandbox              # Session entry (shell/claude/cmd, auto-tmux)
|   +-- sandbox-linux-prereqs  # Linux only: install prereqs (iptables, gh, etc.)
|   +-- sandbox-setup        # One-time: OrbStack VM + Incus + golden images + egress
|   +-- sandbox-create       # Create container
|   +-- sandbox-stop         # Stop/remove container
|   +-- sandbox-nuke         # Destroy all containers
|   +-- sandbox-list         # List containers with health
|   +-- sandbox-expose       # Expose extra ports (bidirectional)
|   +-- sandbox-login        # Claude OAuth login flow
+-- domains/
|   +-- anthropic-default.txt  # Default domain allowlist (~190 domains)
+-- lib/
|   +-- sandbox-common.sh    # Shared functions (slot mgmt, deploy keys, ssh-agent, env, domain filtering)
+-- stacks/
|   +-- base.sh              # Core golden image
|   +-- rust.sh              # Rust additions
|   +-- python.sh            # Python additions
|   +-- node.sh              # Node additions
|   +-- go.sh                # Go additions
|   +-- dotnet.sh            # .NET additions
+-- tests/
|   +-- run-tests.sh          # Test runner (unit, integration, or all)
|   +-- unit/                 # Fast tests for pure functions
|   +-- integration/          # Tests using real Incus containers
|   +-- fixtures/             # Test data (domain allowlists, etc.)
|   +-- test_helper/          # Shared BATS helpers
+-- install.sh               # Symlinks bin/* into ~/.local/bin
+-- .gitignore
```

## License

MIT
