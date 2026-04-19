<p align="center"
          
![alt text](https://github.com/renzi25031469/Massnuclei/blob/main/banner_Image.png?raw=true)

</p>

<p align="center">
  <img src="https://img.shields.io/badge/bash-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white"/>
  <img src="https://img.shields.io/badge/masscan-required-red?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/nuclei-required-blue?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/linux-supported-green?style=for-the-badge&logo=linux&logoColor=white"/>
  <img src="https://img.shields.io/badge/license-MIT-orange?style=for-the-badge"/>
</p>

<p align="center">
  <b>Automated Masscan + Nuclei scanner for port scanning and vulnerability detection.</b><br/><br/>
  <i>⚠ Use only on systems you own or have explicit authorization to test. ⚠</i>
</p>

---

## 📌 About

**MassNuclei** is a Bash tool that combines the power of **Masscan** (ultra-fast port scanner) with **Nuclei** (template-based vulnerability scanner) into a single automated pipeline.

In a single run, the tool scans for open ports on the provided host list and feeds the results directly into Nuclei, which applies vulnerability templates and generates reports in both TXT and JSON. It includes self-diagnosis for common issues such as missing `libpcap` and gateway MAC resolution failures.

Perfect for Bug Bounty (public and private programs) and large-scale internal security audits.

---

## ✨ Features

- ✅ Full pipeline: Masscan → Nuclei in a single command
- ✅ **Background execution** support with `nohup` and PID tracking
- ✅ Auto-fix for missing `libpcap` (apt/yum)
- ✅ Automatic gateway MAC resolution via `/proc/net/arp` and `arping`
- ✅ Results exported in both **TXT** and **JSON**
- ✅ Configurable severity filtering (critical, high, medium, low, unknown)
- ✅ Full per-session execution log
- ✅ Host, open port, and vulnerability count summary

---

## 📋 Requirements

| Dependency    | Installation                                                                 |
|---------------|------------------------------------------------------------------------------|
| `masscan`     | `sudo apt install masscan`                                                   |
| `nuclei`      | `go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest`        |
| `libpcap`     | `sudo apt install libpcap-dev` *(auto-installed if missing)*                 |
| `python3`     | included on most Linux systems                                               |
| `arping`      | `sudo apt install arping` *(optional, improves MAC resolution)*              |

> **Note:** Masscan requires **root privileges** for raw packet capture.

---

## 🚀 Usage

```bash
sudo ./massnuclei.sh [options] <hosts_file>
```

### Options

| Flag                      | Description                                                         |
|---------------------------|---------------------------------------------------------------------|
| `-b`, `--background`      | Run in background using `nohup`                                    |
| `-o`, `--output <dir>`    | Output directory (default: `./output_<timestamp>`)                 |
| `-r`, `--rate <n>`        | Masscan packet rate (default: `10000`)                             |
| `-s`, `--severity <list>` | Nuclei severities (default: `critical,high,medium,low,unknown`)    |
| `-c`, `--concurrency <n>` | Nuclei concurrency (default: `50`)                                 |
| `-p`, `--ports <range>`   | Port range to scan (default: `1-65535`)                            |
| `--no-txt`                | Skip TXT output (JSON only)                                        |
| `-h`, `--help`            | Show help                                                          |

### Examples

```bash
# Full scan against all hosts
sudo ./massnuclei.sh targets.txt

# Background execution with custom output directory
sudo ./massnuclei.sh -b -o /tmp/scan targets.txt

# Critical and high severities only, reduced rate
sudo ./massnuclei.sh --rate 5000 --severity critical,high targets.txt

# Scan specific ports with high concurrency
sudo ./massnuclei.sh -p 80,443,8080,8443 -c 100 targets.txt

# Follow background execution in real time
tail -f /tmp/scan/nohup.log
```

### Hosts file format (`targets.txt`)

```
192.168.1.0/24
10.0.0.1
10.0.0.5
203.0.113.10
```

---

## 📁 Output Structure

```
output_YYYYMMDD_HHMMSS/
├── masscan.log              # Raw Masscan output (-oL format)
├── nuclei_input.txt         # host:port pairs extracted for Nuclei
├── nuclei_resultados.txt    # Vulnerabilities found (TXT)
├── nuclei_resultados.json   # Vulnerabilities found (JSON)
├── scan.log                 # Full execution log
├── scan.pid                 # Process PID (background mode)
└── nohup.log                # nohup output (background mode)
```

---

## ⚙️ How It Works

```
[hosts.txt]
     │
     ▼
 ┌─────────┐     open ports        ┌──────────────┐
 │ Masscan │  ──────────────────►  │ nuclei_input │
 └─────────┘                       └──────┬───────┘
                                          │
                                          ▼
                                      ┌────────┐
                                      │ Nuclei │
                                      └───┬────┘
                              ┌───────────┴───────────┐
                              ▼                       ▼
                        results.txt            results.json
```

**Stage 0 — Pre-checks:** verifies and fixes `libpcap`; resolves the gateway MAC so Masscan can work correctly in routed environments.

**Stage 1 — Masscan:** scans the defined ports on all hosts in the input file and saves open ports in `host:port` format.

**Stage 2 — Nuclei:** receives the `host:port` list and applies vulnerability templates according to the configured severities, exporting the results.

**Stage 3 — Summary:** displays and logs a consolidated execution summary with host, port, and vulnerability counts.

---

## 🛡️ Self-Diagnosis

The tool automatically detects and fixes two common issues:

**Missing libpcap** — Required for Masscan to function. The script attempts automatic installation via `apt-get` or `yum` and creates the `libpcap.so` symlink if needed.

**Unresolved gateway MAC** — Masscan needs the gateway MAC to send raw packets. The script attempts resolution via `/proc/net/arp`, falls back to `arping`, and as a last resort uses broadcast MAC (`FF-FF-FF-FF-FF-FF`).

---

## ⚠️ Legal Disclaimer

This tool is intended **exclusively** for educational purposes and security auditing on systems **you own or have explicit written authorization to test**. Unauthorized use against third-party systems is **illegal** and may result in civil and criminal penalties. The author assumes no responsibility for misuse of this tool.

---

## 👤 Author

Developed by **Renzi**

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
