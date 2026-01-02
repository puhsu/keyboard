# ZMK Firmware Deep Dive: Ergohaven Velvet V3 UI

Personal documentation for understanding the complete ZMK build and firmware process.

---

## Table of Contents

1. [Core Concepts: Board vs Shield](#core-concepts-board-vs-shield)
2. [Your Setup: Velvet V3 UI Architecture](#your-setup-velvet-v3-ui-architecture)
3. [Split Keyboard Communication](#split-keyboard-communication)
4. [Why Only Flashing One Half Works](#why-only-flashing-one-half-works)
5. [The Repository Structure](#the-repository-structure)
6. [Understanding the Two Repositories](#understanding-the-two-repositories)
7. [West Manifests & Version Pinning](#west-manifests--version-pinning)
8. [Version Conflict Resolution (Deep Dive)](#version-conflict-resolution-deep-dive)
9. [Local Building (for Nix)](#local-building-for-nix)
10. [ZMK Versioning](#zmk-versioning)
11. [The Build Process](#the-build-process)
12. [Flashing Firmware](#flashing-firmware)
13. [ZMK Studio: Live Keymap Editing](#zmk-studio-live-keymap-editing)
14. [Configuration Files Explained](#configuration-files-explained)
15. [Common Operations](#common-operations)

---

## Core Concepts: Board vs Shield

ZMK uses a **modular architecture** separating the microcontroller from the keyboard layout:

### Board
A **board** represents the PCB containing the **microcontroller unit (MCU)**. Think of it as the "brain" of the keyboard.

For Ergohaven keyboards, the board is defined at:
```
ergohaven-zmk/boards/arm/ergohaven/
```

Key files:
- `ergohaven.dts` - Device tree source (hardware description)
- `ergohaven-pinctrl.dtsi` - Pin control definitions
- `ergohaven_defconfig` - Default kernel/ZMK configuration
- `ergohaven.yaml` - Hardware metadata

The Ergohaven board is a **custom nRF52840-based** controller (ARM Cortex-M4F, Bluetooth 5.0).

### Shield
A **shield** represents the **keyboard PCB itself** - the physical layout, key matrix, and any additional hardware (displays, encoders, trackballs).

Your Velvet V3 UI shield is defined at:
```
ergohaven-zmk/boards/shields/velvet_v3_ui/
```

Key files:
- `velvet_v3_ui.dtsi` - Main device tree (key matrix, peripherals)
- `velvet_v3_ui_layout.dtsi` - Physical key layout definition
- `velvet_v3_ui_left.overlay` - Left half hardware config
- `velvet_v3_ui_right.overlay` - Right half hardware config
- `Kconfig.shield` - Shield-specific build options

### Why This Separation Matters

This modularity means:
1. **Same board, different shields**: One MCU design works with multiple keyboard layouts
2. **Firmware reuse**: Core ZMK features don't need to know about your specific keyboard
3. **Clear boundaries**: Hardware changes in the shield don't affect MCU-level code

---

## Your Setup: Velvet V3 UI Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        VELVET V3 UI SPLIT                           │
├───────────────────────────────┬─────────────────────────────────────┤
│         LEFT HALF             │           RIGHT HALF                │
│        (Peripheral)           │           (Central)                 │
├───────────────────────────────┼─────────────────────────────────────┤
│  • Sends keypresses to right  │  • Receives from left via BLE       │
│  • Cannot connect to host     │  • Processes ALL keymap logic       │
│  • Has own battery/MCU        │  • Connects to host (USB/BLE)       │
│  • No keymap processing       │  • Stores the active keymap         │
│                               │  • Has trackball (UI variant)       │
└───────────────────────────────┴─────────────────────────────────────┘
```

**Critical difference from standard ZMK**: Most split keyboards have **left as central**. The Velvet V3 UI has **RIGHT as central** because the trackball is on the right side and requires direct host communication.

This means:
- **Keymap changes**: Flash RIGHT half only
- **Configuration changes**: May need both halves
- **USB connection**: Always to the RIGHT half

---

## Split Keyboard Communication

### The Central-Peripheral Model

```
┌──────────┐    Bluetooth LE   ┌──────────┐    USB/BLE    ┌──────────┐
│   LEFT   │ ←───────────────→ │  RIGHT   │ ←──────────→  │   HOST   │
│(Periph.) │   ~3.75ms avg     │(Central) │               │(Computer)│
└──────────┘                   └──────────┘               └──────────┘
     │                              │
     ▼                              ▼
  Keypress                    Keymap Processing
  Detection                   HID Event Generation
  Only                        Host Communication
```

### How Split Communication Works

1. **Left half** detects a keypress
2. Sends raw key position over Bluetooth to right half
3. **Right half** receives position, looks up keymap, generates HID event
4. Sends HID event to computer over USB or Bluetooth

### Latency Impact

- Split communication adds **~3.75ms average** (worst case 7.5ms)
- This is why the central handles all processing - minimizes round trips

### Automatic Pairing

First time both halves power on together, they automatically pair. The bonding info is stored in flash memory. If pairing fails:
1. Clear bonds on both halves (settings reset firmware)
2. Power both halves on simultaneously
3. They'll re-pair automatically

---

## Why Only Flashing One Half Works

This is the key insight:

```
┌─────────────────────────────────────────────────────────────────┐
│                    WHERE THINGS LIVE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   KEYMAP (.keymap file):        → Processed on CENTRAL (right)  │
│   - Layer definitions                                           │
│   - Key bindings                                                │
│   - Behaviors                                                   │
│   - Combos                                                      │
│                                                                 │
│   CONFIGURATION (.conf file):                                   │
│   - Power settings              → Both halves                   │
│   - Bluetooth TX power          → Both halves                   │
│   - Sleep timeout               → Both halves                   │
│   - Battery reporting           → Both halves                   │
│                                                                 │
│   HARDWARE OVERLAY (.overlay):                                  │
│   - Pin assignments             → Specific half                 │
│   - Peripheral configs          → Specific half                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### When to Flash What

| Change Type          | Flash Left | Flash Right | Why                         |
|----------------------|------------|-------------|-----------------------------|
| Keymap changes       | No         | **Yes**     | Right processes all keymaps |
| Add/remove layers    | No         | **Yes**     | Keymap logic on right       |
| Change behaviors     | No         | **Yes**     | Keymap logic on right       |
| Power/sleep settings | Yes        | Yes         | Both need config            |
| Bluetooth settings   | Yes        | Yes         | Both have radios            |
| Trackball settings   | No         | **Yes**     | Only right has trackball    |
| Reset bonding        | Yes        | Yes         | Clear both sides            |

**For your Velvet V3 UI: Keymap changes only need the RIGHT (central) half flashed.**

---

## The Repository Structure

Ergohaven uses a **two-repository architecture**:

### 1. ergohaven-zmk (ZMK Module)
```
https://github.com/ergohaven/ergohaven-zmk
│
├── boards/
│   ├── arm/ergohaven/          # MCU/board definition
│   │   ├── ergohaven.dts       # Device tree
│   │   ├── ergohaven_defconfig # Default config
│   │   └── ...
│   │
│   └── shields/                # Keyboard definitions
│       ├── velvet_v3_ui/       # YOUR KEYBOARD
│       │   ├── velvet_v3_ui.dtsi
│       │   ├── velvet_v3_ui_left.overlay
│       │   ├── velvet_v3_ui_right.overlay
│       │   └── ...
│       ├── velvet_v3/
│       ├── imperial44/
│       ├── k03/
│       ├── op36/
│       └── trackball/
│
├── config/
│   └── west.yml                # ZMK version pinning
│
└── .github/workflows/          # Build automation
```

### 2. ergohaven-zmk-config (User Configuration)
```
https://github.com/ergohaven/ergohaven-zmk-config
│
├── config/
│   ├── velvet_v3_ui.keymap     # YOUR KEYMAP
│   ├── velvet_v3_ui.conf       # YOUR CONFIG
│   ├── velvet_v3_ui.json       # Layout metadata (for editors)
│   ├── west.yml                # Points to ergohaven-zmk module
│   └── ...
│
├── build.yaml                  # Build matrix definition
│
└── .github/workflows/
    └── build.yml               # CI/CD pipeline
```

### How They Connect

```
ergohaven-zmk-config/config/west.yml
         │
         ▼ imports
ergohaven-zmk/config/west.yml
         │
         ▼ imports
zmkfirmware/zmk (v0.3.0)
         │
         ▼ imports
zephyr RTOS + dependencies
```

---


## Understanding the Two Repositories

Ergohaven uses two separate repositories that serve different purposes. Understanding this distinction is crucial for customization and reproducible builds.

### Quick Comparison

| Aspect               | ergohaven-zmk                      | ergohaven-zmk-config                      |
|----------------------|------------------------------------|-------------------------------------------|
| **Purpose**          | ZMK Module (hardware definitions)  | User config template                      |
| **Should you fork?** | No (use as dependency)             | Yes                                       |
| **Contains**         | Board/shield definitions, drivers  | Keymaps, .conf files                      |
| **Version tracking** | Pins ZMK to v0.3.0                 | Tracks ergohaven-zmk@main                 |
| **URL**              | github.com/ergohaven/ergohaven-zmk | github.com/ergohaven/ergohaven-zmk-config |

### ergohaven-zmk (The Module)

This is a **Zephyr module** that extends ZMK with Ergohaven-specific hardware support. You typically don't fork this repository - it's pulled in automatically as a dependency.

**What it contains:**
- `boards/arm/ergohaven/` - nRF52840-based MCU board definition (the "brain")
- `boards/shields/` - 10 keyboard shields:
  - velvet_v3, velvet_v3_ui (your keyboard)
  - op36, k03, imperial44
  - trackball, qube (accessories)
- Device tree files defining hardware (key matrices, displays, trackball sensor)
- `config/west.yml` - **The source of truth for all dependency versions**

**External module dependencies:**
- `zmk-pmw3610-driver@eh` - Trackball driver (PMW3610 optical sensor)
- `ergohaven-zmk-qube@eh` - Qube dongle display support (ST7789V)
- `zmk-raw-hid@main` - Raw HID communication for advanced features

**When to modify this repo:** Only if you're fixing hardware bugs, adding support for new keyboards, or contributing upstream.

### ergohaven-zmk-config (User Config)

This is a **fork-able template repository** for your personal keyboard configuration. This is what you customize.

**What it contains:**
- `config/*.keymap` - Key bindings and layer definitions
- `config/*.conf` - Firmware settings (sleep, BLE power, battery reporting)
- `config/west.yml` - Points to ergohaven-zmk as a dependency
- `config/*.json` - Layout metadata for visual editors
- `.github/workflows/build.yml` - CI/CD that builds firmware on push

**Standard workflow:**
1. Fork this repository to your GitHub account
2. Edit keymap/config files in `config/`
3. Push changes to trigger GitHub Actions build
4. Download compiled `.uf2` firmware from Actions artifacts
5. Flash to keyboard

### Dependency Chain

```
Your fork of ergohaven-zmk-config
         │
         │ config/west.yml imports:
         ▼
ergohaven/ergohaven-zmk (module)
         │
         │ config/west.yml imports:
         ├─→ zmkfirmware/zmk@v0.3.0 (core firmware)
         ├─→ ergohaven/zmk-pmw3610-driver@eh (trackball)
         ├─→ ergohaven/ergohaven-zmk-qube@eh (display)
         └─→ ergohaven/zmk-raw-hid@main (HID)
                   │
                   ▼
         zmk/app/west.yml imports:
                   │
                   ▼
         Zephyr RTOS + HAL + toolchain
```

### Decision Guide: Which Repo Do I Need?

| I want to...                    | Which repo?          | Action                          |
|---------------------------------|----------------------|---------------------------------|
| Change my keymap                | ergohaven-zmk-config | Fork and edit `config/*.keymap` |
| Change power/BLE settings       | ergohaven-zmk-config | Edit `config/*.conf`            |
| Fix a bug in shield definition  | ergohaven-zmk        | Submit PR to upstream           |
| Add support for new keyboard    | ergohaven-zmk        | Submit PR to upstream           |
| Understand how hardware works   | ergohaven-zmk        | Read-only exploration           |
| Build with specific ZMK version | Both                 | See version pinning below       |

---


## West Manifests & Version Pinning

Understanding how West manages dependencies is essential for reproducible builds, especially if you're planning to wrap ZMK builds in Nix or another build system.

### What is West?

West is Zephyr's meta-tool for managing multi-repository workspaces. It:
- Reads `west.yml` manifest files to define dependencies
- Fetches and updates repositories from multiple remotes
- Provides build commands that integrate with CMake

**Key commands:**
```bash
west init -l config    # Initialize workspace using config/west.yml
west update            # Fetch all dependencies
west zephyr-export     # Export Zephyr CMake package
west build             # Build firmware
```

### How ZMK Version Pinning Works

As of June 2025, ZMK introduced semantic versioning (per [zmk.dev/blog/2025/06/20/pinned-zmk](https://zmk.dev/blog/2025/06/20/pinned-zmk)):

- **Format:** vX.Y.Z (e.g., v0.3.0)
- **Tags like `v0.3`** auto-update to latest patch (v0.3.1, etc.) - good for security fixes
- **Specific tags like `v0.3.0`** never change - good for reproducibility
- **Breaking changes** reserved for major/minor version bumps
- **`main` branch** - bleeding edge, may break unexpectedly

### Current Ergohaven Pinning Strategy

**ergohaven-zmk/config/west.yml** (the source of truth):
```yaml
manifest:
  remotes:
    - name: zmkfirmware
      url-base: https://github.com/zmkfirmware
    - name: ergohaven
      url-base: https://github.com/ergohaven
  projects:
    - name: zmk
      remote: zmkfirmware
      revision: v0.3.0          # ← PINNED to specific ZMK version
      import: app/west.yml
    - name: zmk-pmw3610-driver
      remote: ergohaven
      revision: eh              # ← Branch, not version tag
    - name: ergohaven-zmk-qube
      remote: ergohaven
      revision: eh
    - name: zmk-raw-hid
      remote: ergohaven
      revision: main
  self:
    path: config
```

**ergohaven-zmk-config/config/west.yml**:
```yaml
manifest:
  remotes:
    - name: ergohaven
      url-base: https://github.com/ergohaven
  projects:
    - name: ergohaven-zmk
      remote: ergohaven
      revision: main            # ← Always tracks latest (NOT pinned!)
      import: config/west.yml   # ← Cascading import
  self:
    path: config
```

### Implications for Reproducible Builds

**Problem:** The default ergohaven-zmk-config uses `revision: main`, meaning every `west update` might fetch different code.

**For Nix/reproducible builds**, pin to a specific commit or release tag:

```yaml
# In your forked ergohaven-zmk-config/config/west.yml
projects:
  - name: ergohaven-zmk
    remote: ergohaven
    revision: 2025.11.30     # Use a release tag
    # OR
    revision: 7022ac9abc123  # Use a specific commit hash
    import: config/west.yml
```

**GitHub Actions also needs pinning** in `.github/workflows/build.yml`:
```yaml
# Change this:
uses: ergohaven/ergohaven-zmk/.github/workflows/build-user-config.yml@main

# To this:
uses: ergohaven/ergohaven-zmk/.github/workflows/build-user-config.yml@2025.11.30
```

### How to Pin for Reproducible Builds

1. **Find desired ergohaven-zmk release tag:**
   - Visit https://github.com/ergohaven/ergohaven-zmk/releases
   - Note the tag (e.g., `2025.11.30`)

2. **Edit `config/west.yml`:**
   ```yaml
   revision: 2025.11.30  # Instead of 'main'
   ```

3. **Edit `.github/workflows/build.yml`:**
   ```yaml
   uses: ergohaven/ergohaven-zmk/.github/workflows/build-user-config.yml@2025.11.30
   ```

4. **Commit and push** - your builds are now reproducible

---


## Version Conflict Resolution (Deep Dive)

This section explains how West handles (or doesn't handle) version conflicts when different modules declare different dependency versions. This is critical to understand if you're debugging build issues or creating reproducible builds.

### The Core Problem

Consider this scenario in Ergohaven's ecosystem:

| Component | Declares ZMK Version | Declares Zephyr Version |
|-----------|---------------------|------------------------|
| ergohaven-zmk | v0.3.0 | (inherited: v3.5.0+zmk-fixes) |
| zmk-raw-hid | **main** | (inherited: v4.1.0+zmk-fixes) |
| zmk-pmw3610-driver | (none) | (none) |

**The Zephyr gap is massive:** v3.5.0 → v4.1.0 spans 4 minor versions with significant API changes.

### West's Resolution Strategy: "First Wins"

**West does NOT have a dependency resolver like npm, cargo, or pip.** It uses a simple "first definition wins" strategy:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    WEST RESOLUTION RULES                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Manifests are processed in import order (depth-first)               │
│                                                                         │
│  2. FIRST definition of a project WINS                                  │
│     - If ergohaven-zmk defines zmk@v0.3.0 first                        │
│     - Any later definition of zmk (e.g., zmk@main) is IGNORED          │
│                                                                         │
│  3. NO compatibility checking                                           │
│     - West doesn't verify API compatibility                            │
│     - West doesn't warn about version mismatches                       │
│     - West doesn't have version ranges (^1.0, ~2.3, etc.)              │
│                                                                         │
│  4. NO lockfile equivalent                                              │
│     - No west.lock like package-lock.json                              │
│     - Reproducibility requires manual pinning                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### The Import vs No-Import Distinction

This is the key mechanism that prevents (or causes) conflicts:

```yaml
# ergohaven-zmk/config/west.yml
projects:
  - name: zmk
    remote: zmkfirmware
    revision: v0.3.0
    import: app/west.yml       # ← HAS import: manifest is processed

  - name: zmk-pmw3610-driver
    remote: ergohaven
    revision: eh               # ← NO import: just fetches code

  - name: zmk-raw-hid
    remote: ergohaven
    revision: main             # ← NO import: just fetches code
```

**What happens with `import:`:**
- West processes the module's west.yml
- Dependencies are added to the resolution chain
- "First wins" applies if conflicts exist

**What happens WITHOUT `import:`:**
- West ONLY fetches the repository code
- Module's west.yml is **COMPLETELY IGNORED**
- Module's declared dependencies have **NO effect**
- Module is compiled against whatever versions exist in workspace

### Case Study: zmk-raw-hid

The `zmk-raw-hid` module has its own `config/west.yml`:

```yaml
# zmk-raw-hid/config/west.yml (EXISTS but IGNORED!)
manifest:
  remotes:
  - name: zmkfirmware
    url-base: https://github.com/zmkfirmware
  projects:
  - name: zmk
    remote: zmkfirmware
    revision: main              # ← Wants ZMK main branch!
    import: app/west.yml
  self:
    path: config
```

**But ergohaven-zmk lists it WITHOUT import:**
```yaml
  - name: zmk-raw-hid
    remote: ergohaven
    revision: main             # ← NO "import:" directive
```

**Result:**
1. West fetches zmk-raw-hid's code
2. West **never reads** zmk-raw-hid's config/west.yml
3. zmk-raw-hid's preference for `zmk@main` is silently ignored
4. zmk-raw-hid gets compiled against `zmk@v0.3.0` (whatever's in workspace)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    THE SILENT OVERRIDE                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  zmk-raw-hid DECLARES:        zmk@main     (Zephyr 4.1.0)              │
│  zmk-raw-hid RECEIVES:        zmk@v0.3.0   (Zephyr 3.5.0)              │
│                                                                         │
│  The module's west.yml is completely bypassed.                         │
│  No warning. No error. Silent version substitution.                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Module Manifest Status Summary

| Module | Has west.yml? | Declares ZMK | Ergohaven imports it? | Version Actually Used |
|--------|---------------|--------------|----------------------|----------------------|
| zmk | Yes | N/A (is ZMK) | **Yes** | **v0.3.0** (source of truth) |
| zmk-pmw3610-driver | No | None | No | v0.3.0 (workspace) |
| ergohaven-zmk-qube | Unknown | Unknown | No | v0.3.0 (workspace) |
| zmk-raw-hid | **Yes** | **main** | **No** | v0.3.0 (workspace) |

### Why This Doesn't Break (Usually)

Ergohaven's setup works because of careful coordination:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    WHY IT WORKS FOR ERGOHAVEN                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. MAINTAINED FORKS WITH `@eh` BRANCHES                                │
│     • zmk-pmw3610-driver@eh is tested against v0.3.0                   │
│     • ergohaven-zmk-qube@eh is tested against v0.3.0                   │
│     • These branches exist specifically for compatibility              │
│                                                                         │
│  2. CI/CD INTEGRATION TESTING                                           │
│     • GitHub Actions builds all shields on every push                  │
│     • If a module breaks with v0.3.0, the build fails                  │
│     • Breakage is caught before release                                │
│                                                                         │
│  3. API STABILITY (for zmk-raw-hid@main)                               │
│     • Raw HID APIs may be stable across Zephyr versions               │
│     • Or Ergohaven got lucky with no breaking changes                  │
│     • Or they patch issues in their fork as needed                     │
│                                                                         │
│  4. EXPLICIT VERSION CONTROL                                            │
│     • ergohaven-zmk pins zmk to v0.3.0 explicitly                      │
│     • No accidental drift to incompatible versions                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Potential Failure Modes

When module-version mismatches occur, you may see:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    FAILURE MODES                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  BUILD-TIME FAILURES (obvious, easy to debug)                          │
│  • Missing Zephyr APIs: function doesn't exist in v3.5.0              │
│  • Changed function signatures: wrong number/type of arguments         │
│  • Device tree binding mismatches: schema validation fails            │
│  • Kconfig option doesn't exist: CONFIG_XYZ unknown                   │
│                                                                         │
│  RUNTIME FAILURES (subtle, hard to debug)                              │
│  • API behavior changed between versions                               │
│  • Timing assumptions no longer valid                                  │
│  • Memory layout differences cause corruption                          │
│  • Interrupts handled differently                                      │
│                                                                         │
│  SILENT BREAKAGE (worst case)                                          │
│  • Feature works but produces wrong results                            │
│  • Edge cases not handled correctly                                    │
│  • Rare conditions trigger undefined behavior                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Risk Assessment by Scenario

| Scenario | Risk Level | What Happens |
|----------|------------|--------------|
| Use ergohaven's config as-is | **Low** | Ergohaven tests this combination |
| Replace `@eh` with `@main` for a driver | **High** | Likely build failures (Zephyr mismatch) |
| Update ergohaven-zmk to ZMK main | **High** | `@eh` modules may need updates |
| Use third-party ZMK module | **Medium** | May target wrong ZMK/Zephyr version |
| Update ZMK without updating modules | **High** | API mismatches likely |
| Add `import:` to a module entry | **Varies** | Could cause "first wins" conflicts |

### What Would Happen If Ergohaven Added Imports?

If `ergohaven-zmk/config/west.yml` added imports for modules:

```yaml
# Hypothetical: What if import was added?
projects:
  - name: zmk
    remote: zmkfirmware
    revision: v0.3.0
    import: app/west.yml           # Processed FIRST

  - name: zmk-raw-hid
    remote: ergohaven
    revision: main
    import: config/west.yml        # Processed SECOND (hypothetical)
```

**Result:** zmk-raw-hid's west.yml would be processed, but its `zmk@main` definition would be **ignored** because `zmk@v0.3.0` was already defined. The "first wins" rule still applies.

The only way zmk-raw-hid could "win" is if it were listed and imported **before** the zmk project—which would break the entire build since zmk-raw-hid depends on zmk.

### Recommendations for Custom Builds

**If you're forking for your own use:**

1. **Stick with `@eh` branches** - They're tested together
2. **Don't add `import:` to module entries** - You'll get the same versions anyway
3. **If updating ZMK version**, test all modules for compatibility
4. **Pin everything for reproducibility** - Branches can change

**If you're wrapping in Nix:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    NIX REPRODUCIBILITY CHECKLIST                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  □ Pin ergohaven-zmk to release tag or commit hash                     │
│  □ Pin ergohaven-zmk-config to release tag or commit hash              │
│  □ Note: @eh and @main branches are FLOATING (not reproducible)        │
│  □ ZMK v0.3.0 IS pinned (good)                                         │
│  □ Zephyr version derived from ZMK pin (transitively stable)           │
│  □ Hash west workspace after `west update` for verification            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Takeaways

1. **West doesn't resolve conflicts** - It uses "first definition wins"
2. **No import = manifest ignored** - Module code is fetched but its dependencies are bypassed
3. **Ergohaven mitigates this through coordination** - `@eh` branches are tested together
4. **zmk-raw-hid's west.yml declares zmk@main** - But this is silently ignored
5. **The system is fragile** - Works because of careful manual coordination, not automatic resolution
6. **For your own builds** - Use the tested combinations or be prepared to debug

---


## Local Building (for Nix)

If you want to build firmware locally (instead of using GitHub Actions), or wrap the build process in Nix, here's what you need to know.

### Prerequisites

**Option 1: Native installation**
- Zephyr SDK (ARM GCC toolchain)
- Python 3 with: `west`, `cmake`, `ninja`, `pyelftools`
- CMake 3.20+

**Option 2: Docker (recommended)**
```bash
docker pull zmkfirmware/zmk-build-arm:stable
```

### Build Commands Sequence

```bash
# 1. Clone your config repo (or your fork)
git clone https://github.com/YOUR_USER/ergohaven-zmk-config
cd ergohaven-zmk-config

# 2. Initialize west workspace (reads config/west.yml)
west init -l config

# 3. Fetch all dependencies (ZMK, Zephyr, HAL, modules)
# This downloads ~2GB to: modules/, zmk/, zephyr/, bootloader/
west update

# 4. Export Zephyr CMake package
pwest zephyr-export

# 5. Build for specific target
# Example: Velvet V3 UI right half with ZMK Studio support
west build -s zmk/app -b ergohaven -- \
  -DSHIELD="velvet_v3_ui_right" \
  -DZMK_CONFIG="${PWD}/config" \
  -DCONFIG_ZMK_STUDIO=y

# 6. Find your firmware
ls build/zephyr/zmk.uf2
```

### Build Targets (build.yaml)

The `build.yaml` file defines all available build targets. Each entry specifies:

```yaml
include:
  - board: ergohaven           # MCU board (always "ergohaven")
    shield: velvet_v3_ui_right # Keyboard shield
    snippet: studio-rpc-usb-uart  # Optional: ZMK Studio support
    cmake-args: -DCONFIG_ZMK_STUDIO=y
```

**Key shield options for Velvet V3 UI:**

| Shield                                 | Description                                      |
|----------------------------------------|--------------------------------------------------|
| `velvet_v3_ui_left`                    | Left half (peripheral) - rarely needs reflashing |
| `velvet_v3_ui_right`                   | Right half (central) - **your main target**      |
| `velvet_v3_ui_qube qube dongle_screen` | Qube dongle variant with display                 |

**With Russian layout:**

| Shield               | Keymap              | Description              |
|----------------------|---------------------|--------------------------|
| `velvet_v3_ui_left`  | `velvet_v3_ui_ruen` | Left half, RU/EN layout  |
| `velvet_v3_ui_right` | `velvet_v3_ui_ruen` | Right half, RU/EN layout |

### For Nix Wrapping

Key inputs to capture in your Nix derivation:

1. **Manifest parsing:** `config/west.yml` defines all git dependencies
2. **Fetched sources:** `west update` downloads to:
   - `modules/` - Zephyr modules (HAL, CMSIS, etc.)
   - `zmk/` - ZMK core firmware
   - `zephyr/` - Zephyr RTOS
   - `bootloader/` - MCUboot (if enabled)

3. **Build inputs:**
   - Source: `-s zmk/app`
   - Board: `-b ergohaven`
   - Shield: `-DSHIELD="velvet_v3_ui_right"`
   - Config: `-DZMK_CONFIG=/path/to/config`

4. **Output:** `build/zephyr/zmk.uf2`

**Nix considerations:**
- Pin all `revision` values to commits/tags (not branches like `main` or `eh`)
- The Docker image `zmkfirmware/zmk-build-arm:stable` contains all toolchain dependencies
- Cache `west update` output as a fixed-output derivation based on west.yml hash
- Consider using west's `--mr` flag for manifest-revision locking

---


## ZMK Versioning

### Version Sources

ZMK versioning happens at multiple levels:

```
┌─────────────────────────────────────────────────────────────────┐
│                       VERSION HIERARCHY                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. ERGOHAVEN FIRMWARE VERSION                                  │
│     Format: YYYY.MM.DD (e.g., 2025.11.30)                      │
│     Source: GitHub releases at ergohaven/ergohaven-zmk          │
│     This is what Ergohaven publishes as "new firmware"          │
│                                                                 │
│  2. ZMK CORE VERSION                                            │
│     Format: vX.Y.Z (e.g., v0.3.0)                              │
│     Source: ergohaven-zmk/config/west.yml                       │
│     Currently pinned to: v0.3.0                                 │
│                                                                 │
│  3. ZEPHYR RTOS VERSION                                         │
│     Embedded in ZMK, you don't control this directly            │
│                                                                 │
│  4. CUSTOM MODULES                                              │
│     - zmk-pmw3610-driver (trackball driver)                    │
│     - ergohaven-zmk-qube (dongle support)                      │
│     - zmk-raw-hid (raw HID communication)                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### How to Check Your Current Version

**Option 1: Check the release you downloaded**
Your .uf2 filename should indicate the version if from official releases.

**Option 2: ZMK Studio**
Connect via ZMK Studio - it shows firmware version info.

**Option 3: Build metadata**
If you built yourself, check your west.yml revision references.

### Updating ZMK Version

To update the core ZMK version:
1. Edit `ergohaven-zmk/config/west.yml`
2. Change `revision: v0.3.0` to desired version
3. Rebuild firmware

**Warning**: Version updates may introduce breaking changes. Check ZMK changelog first.

---

## The Build Process

### GitHub Actions Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                       BUILD PIPELINE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. TRIGGER                                                     │
│     - Push to repository                                        │
│     - Pull request                                              │
│     - Manual workflow dispatch                                  │
│                                                                 │
│  2. PARSE build.yaml                                            │
│     - Extract board/shield combinations                         │
│     - Identify keymap files                                     │
│     - Apply cmake arguments                                     │
│                                                                 │
│  3. FOR EACH TARGET (parallel):                                 │
│     a. Checkout code                                            │
│     b. Initialize west workspace                                │
│     c. Fetch ZMK + modules                                      │
│     d. Run cmake configure                                      │
│     e. Compile with Zephyr toolchain                           │
│     f. Generate .uf2 firmware file                             │
│                                                                 │
│  4. UPLOAD ARTIFACTS                                            │
│     - Firmware files available for download                     │
│     - Named: {shield}_{side}.uf2                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Build Matrix (from build.yaml)

For Velvet V3 UI, these targets are built:

| Shield | Board | Keymap | Output |
|--------|-------|--------|--------|
| velvet_v3_ui_left | ergohaven | velvet_v3_ui | velvet_v3_ui_left.uf2 |
| velvet_v3_ui_right | ergohaven | velvet_v3_ui | velvet_v3_ui_right.uf2 |
| velvet_v3_ui_qube | ergohaven | velvet_v3_ui | (dongle variant) |

Each build includes:
- `-DCONFIG_ZMK_STUDIO=y` (enables ZMK Studio support)
- `studio-rpc-usb-uart` snippet (USB communication for Studio)

### Local Building (Optional)

```bash
# 1. Clone your config repo
git clone https://github.com/ergohaven/ergohaven-zmk-config
cd ergohaven-zmk-config

# 2. Initialize west workspace
west init -l config
west update

# 3. Build for Velvet V3 UI right half
west build -s zmk/app -b ergohaven -- \
  -DSHIELD=velvet_v3_ui_right \
  -DZMK_CONFIG="${PWD}/config" \
  -DCONFIG_ZMK_STUDIO=y

# 4. Find firmware at build/zephyr/zmk.uf2
```

---

## Flashing Firmware

### Step-by-Step Flashing Process

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLASHING PROCEDURE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. ENTER BOOTLOADER MODE                                       │
│     - Connect half via USB                                      │
│     - Double-click reset button quickly                         │
│     - LED should indicate bootloader mode                       │
│                                                                 │
│  2. DETECT DRIVE                                                │
│     - A removable drive appears (like a USB stick)              │
│     - Named something like "ERGOHAVEN" or "NRF52BOOT"          │
│                                                                 │
│  3. COPY FIRMWARE                                               │
│     - Drag correct .uf2 file to the drive                      │
│     - LEFT half  → *_left.uf2                                  │
│     - RIGHT half → *_right.uf2                                 │
│                                                                 │
│  4. AUTOMATIC REBOOT                                            │
│     - Keyboard reboots automatically after copy completes       │
│     - Drive disappears                                          │
│                                                                 │
│  5. VERIFY                                                      │
│     - Keyboard should be functional                             │
│     - Test keymap changes                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### File Naming Convention

```
velvet_v3_ui_left.uf2   → Left (peripheral) half
velvet_v3_ui_right.uf2  → Right (central) half - YOUR MAIN FLASH TARGET
```

### Common Flashing Scenarios

**Scenario 1: Changed keymap only**
```
Flash: RIGHT half only
File:  velvet_v3_ui_right.uf2
```

**Scenario 2: Changed configuration (power, BLE settings)**
```
Flash: BOTH halves
Files: velvet_v3_ui_left.uf2, velvet_v3_ui_right.uf2
```

**Scenario 3: Upgrading ZMK version**
```
Flash: BOTH halves
Files: Both .uf2 files from new build
Order: Either half first, doesn't matter
```

**Scenario 4: Keyboards won't connect to each other**
```
Flash: BOTH halves with settings_reset firmware
Then:  Flash BOTH halves with normal firmware
       Power both on simultaneously to re-pair
```

---

## ZMK Studio: Live Keymap Editing

ZMK Studio allows **runtime keymap changes without reflashing**.

### What It Is

- Web app: https://zmk.studio/
- Native apps available for Windows, macOS, Linux
- Connect via USB (or BLE on Linux/native apps)

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                      ZMK STUDIO FLOW                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ZMK Studio App                                                │
│        │                                                        │
│        ▼                                                        │
│   USB/UART Connection (studio-rpc-usb-uart snippet)            │
│        │                                                        │
│        ▼                                                        │
│   RIGHT HALF (central)                                          │
│        │                                                        │
│        ▼                                                        │
│   Runtime Keymap Storage (flash memory)                         │
│                                                                 │
│   Changes take effect IMMEDIATELY                               │
│   Persist across reboots                                        │
│   Can restore to "stock" (compiled) keymap anytime             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Capabilities

| Feature | Supported |
|---------|-----------|
| Change key bindings | Yes |
| Rename layers | Yes |
| Assign behaviors | Yes (predefined) |
| Add new layers | No (must be in firmware) |
| Create new behaviors | No |
| Change hardware config | No (requires reflash) |

### Important Warning

> Once you use ZMK Studio to modify your keymap, changes to your `.keymap` file **will not apply** unless you "Restore Stock Settings" in Studio first.

Studio changes live in a separate storage area and take precedence over compiled keymap.

---

## Configuration Files Explained

### Your Velvet V3 UI Files

#### velvet_v3_ui.keymap
```c
// Defines all your key bindings, layers, behaviors
// Located: ergohaven-zmk-config/config/velvet_v3_ui.keymap

#include <behaviors.dtsi>
#include <dt-bindings/zmk/keys.h>
#include <dt-bindings/zmk/bt.h>

/ {
    keymap {
        compatible = "zmk,keymap";

        default_layer {
            bindings = <
                &kp Q &kp W &kp E ...
            >;
        };

        nav_layer { ... };
        sym_layer { ... };
        // ... up to 11 layers in your config
    };
};
```

#### velvet_v3_ui.conf
```ini
# Runtime configuration
# Located: ergohaven-zmk-config/config/velvet_v3_ui.conf

# Power Management
CONFIG_ZMK_SLEEP=y
CONFIG_ZMK_IDLE_SLEEP_TIMEOUT=600000  # 10 minutes

# Battery
CONFIG_ZMK_BATTERY_REPORTING=y
CONFIG_ZMK_BATTERY_REPORT_INTERVAL=60

# Bluetooth
CONFIG_BT_CTLR_TX_PWR_PLUS_8=y  # Max TX power

# Split keyboard
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y
```

#### velvet_v3_ui.json
```json
// Layout metadata for visual editors (not used in build)
// Describes physical key positions for tools like ZMK Studio
```

### Configuration Hierarchy

```
Board defaults (ergohaven_defconfig)
         ↓
Shield defaults (Kconfig.defconfig)
         ↓
User config (velvet_v3_ui.conf)  ← YOUR CUSTOMIZATIONS
         ↓
Final configuration
```

---

## Common Operations

### Operation 1: Customize Your Keymap

1. Fork `ergohaven/ergohaven-zmk-config`
2. Edit `config/velvet_v3_ui.keymap`
3. Push to trigger GitHub Actions build
4. Download `velvet_v3_ui_right.uf2` from Actions artifacts
5. Flash RIGHT half only

### Operation 2: Update to Latest Ergohaven Firmware

1. Go to https://github.com/ergohaven/ergohaven-zmk/releases
2. Download latest `velvet_v3_ui_*.uf2` files
3. Flash both halves
4. If using ZMK Studio, may need to reconfigure

### Operation 3: Update ZMK Core Version

1. Fork `ergohaven/ergohaven-zmk`
2. Edit `config/west.yml`, change `revision: v0.3.0` to new version
3. Update your config repo's `west.yml` to point to your fork
4. Build and test thoroughly (breaking changes possible)

### Operation 4: Reset Everything

1. Download `settings_reset*.uf2` from releases
2. Flash both halves with reset firmware
3. Flash both halves with normal firmware
4. Power both on together to re-pair

### Operation 5: Check Firmware Version

- Connect via ZMK Studio
- Or check which release you downloaded
- Or check `west.yml` in your build config

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────────────┐
│                    VELVET V3 UI QUICK REF                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CENTRAL HALF:        Right (has trackball)                     │
│  PERIPHERAL HALF:     Left                                      │
│                                                                 │
│  KEYMAP CHANGES:      Flash right only                          │
│  CONFIG CHANGES:      Flash both                                │
│  VERSION UPDATES:     Flash both                                │
│                                                                 │
│  BOOTLOADER:          Double-click reset button                 │
│  FIRMWARE FORMAT:     .uf2 (drag & drop)                       │
│                                                                 │
│  ZMK VERSION:         v0.3.0 (check west.yml)                  │
│  ERGOHAVEN VERSION:   YYYY.MM.DD format                        │
│                                                                 │
│  LIVE EDITING:        ZMK Studio (zmk.studio)                  │
│  PAIRING ISSUES:      Flash settings_reset, then normal FW     │
│                                                                 │
│  YOUR KEYMAP:         config/velvet_v3_ui.keymap               │
│  YOUR CONFIG:         config/velvet_v3_ui.conf                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Glossary

| Term | Definition |
|------|------------|
| **Board** | MCU/controller definition (the "brain") |
| **Shield** | Keyboard PCB definition (the "body") |
| **Central** | Split half that processes keymaps and talks to host |
| **Peripheral** | Split half that sends raw keypresses to central |
| **West** | Zephyr's meta-tool for managing repositories |
| **Device Tree** | Hardware description language used by Zephyr/ZMK |
| **UF2** | USB Flashing Format - drag-and-drop firmware files |
| **Bootloader** | Mode that accepts new firmware |
| **ZMK Studio** | Runtime keymap editor (no reflashing needed) |
| **Qube** | Ergohaven's wireless dongle system |

---

*Document generated for Ergohaven Velvet V3 UI keyboard*
*ZMK Core Version: v0.3.0*
*Last updated: 2026-01-01*
