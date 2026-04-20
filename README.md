# picrawler-bootstrap

One-shot bootstrap script for **Raspberry Pi Zero 2 W (64-bit Raspberry Pi OS)** + **SunFounder PiCrawler**.

## Bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/halr9000/picrawler-bootstrap/main/picrawler-setup.sh | bash -s -- --headless
```

Interactive (prompts before each step):

```bash
curl -fsSL https://raw.githubusercontent.com/halr9000/picrawler-bootstrap/main/picrawler-setup.sh | bash
```

---

## Packing List

| Module | Description |
|---|---|
| `syspkgs` | apt system packages (build-essential, python3, i2c-tools, ffmpeg, …) |
| `hwgroups` | Adds user to `gpio`, `i2c`, `spi` groups + udev rule for `/dev/gpiomem` |
| `nvm` | Node Version Manager v0.40.1 |
| `node` | Node.js LTS via nvm |
| `pnpm` | pnpm package manager |
| `uv` | uv + uvx Python toolchain |
| `robot-hat` | SunFounder robot-hat Python library |
| `vilib` | SunFounder vilib vision library (picamera2 branch) |
| `picrawler` | SunFounder picrawler library |
| `demos` | [claw9000-demos](https://github.com/halr9000/claw9000-demos) cloned to `~/claw9000-demos` |
| `i2samp` | i2s amplifier / speaker support |
| `interfaces` | Enables I2C + camera via raspi-config |
| `profile` | Adds NVM/pnpm PATH entries to `~/.bashrc` |

---

## CLI options

```
--headless          Non-interactive; auto-answer yes to all prompts
--skip  <modules>   Comma-separated modules to skip
--only  <modules>   Run only these modules (skips all others)
--list              Print all module names and exit
--help              Show usage
```

Examples:

```bash
# Skip two packages
./picrawler-setup.sh --skip vilib,uv

# Only re-run hardware group setup
./picrawler-setup.sh --only hwgroups

# Fully automated first-boot (stock Pi OS has passwordless sudo by default)
curl -fsSL https://raw.githubusercontent.com/halr9000/picrawler-bootstrap/main/picrawler-setup.sh | bash -s -- --headless
```

---

## Post-install sequence

When all modules complete without errors the script automatically:

1. **Smoke test** — runs `~/claw9000-demos/demos/stand_bob_sit.py` via `sudo` so GPIO works before re-login (robot sits → stands → bobs × 3 → sits, ~15 sec).
2. **Generates `/opt/picrawler/tada.wav`** — a short C→E→G chime using ffmpeg.
3. **Installs `picrawler-tada.service`** — a systemd oneshot that plays the chime 5 seconds after every boot (after `aplay.service`).
4. **Reboots in 5 seconds** — press Ctrl-C to cancel.

---

## Hardware

- Raspberry Pi Zero 2 W — quad-core Cortex-A53 @ 1 GHz, **512 MB RAM**
- SunFounder PiCrawler — 12-servo quadruped with Robot HAT, ultrasonic sensor, camera, speaker

---

## After reboot

```bash
# Verify I2C (should show Robot HAT address, typically 0x14 or 0x17)
i2cdetect -y 1

# Run a demo (no sudo needed after group membership takes effect post-reboot)
cd ~/claw9000-demos
python3 demos/stand_bob_sit.py
```

---

## Related

- [claw9000-demos](https://github.com/halr9000/claw9000-demos) — demo programs for the PiCrawler
- [SunFounder PiCrawler docs](https://docs.sunfounder.com/projects/pi-crawler/en/latest/)
- [robot-hat](https://github.com/sunfounder/robot-hat)
- [vilib](https://github.com/sunfounder/vilib/tree/picamera2)
