# Secure Automated Purge USB Utility

**Boot. Confirm. Purge. Done.**

> **Author**: Abdullah Kareem  
> **License**: [MIT License](./LICENSE)  
> **Compliance**: NIST SP 800-88 Rev. 1 – Purge-Level Sanitization  
> **Blog Post**: [Building a NIST-Compliant Boot-and-Nuke USB Tool: Secure Automated Purge](https://medium.com/@cyberkareem/building-a-nist-compliant-boot-and-nuke-usb-tool-secure-automated-purge-1a87e1f73602)

![GitHub release](https://img.shields.io/github/v/release/CyberKareem/SecureAutomatedPurge-USB)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-linux-lightgrey)
![NIST Compliant](https://img.shields.io/badge/NIST%20800--88-Compliant-green)

## Download

**[Download Latest ISO (v1.0.0)](https://github.com/CyberKareem/SecureAutomatedPurge-USB/releases/latest)** | **[All Releases](https://github.com/CyberKareem/SecureAutomatedPurge-USB/releases)**

### Verify Your Download
```bash
# SHA256 checksum verification (update with your actual checksum)
echo "b6a2c4af987ce57f8bea213315071145084e2e890e68058614bba936a92bb9c5  SecureAutomatedPurge-v1.0.0.iso" | sha256sum -c
```

---

## WARNING

**This utility will PERMANENTLY DESTROY ALL DATA on ALL internal drives!**

- **No recovery possible**
- **No undo function**
- **USB drives excluded** (safety feature)
- **Requires explicit confirmation**

---

## Purpose

The **Secure Automated Purge USB Utility** is a bootable Linux ISO that performs **NIST SP 800-88 Rev. 1 compliant** data sanitization on internal drives. It automatically:

1. Detects all internal drives (SATA/NVMe/SAS)
2. Selects optimal purge method per drive type
3. Executes secure erasure with verification
4. Provides detailed audit logs
5. Shuts down upon completion

Perfect for:
- IT departments decommissioning equipment
- Electronics recycling centers
- Security-conscious organizations
- Personal use before selling/donating computers

---

## Features

### Fully Automated
- Boot from USB and follow prompts
- No technical knowledge required
- Automatic drive detection and method selection

### Security Features
- **NIST 800-88 Compliant**: Meets federal standards for data sanitization
- **Multi-method support**: NVMe crypto erase, ATA Secure Erase, 3-pass overwrite
- **Verification**: Post-purge sampling confirms data destruction
- **Audit trail**: Detailed logs for compliance documentation

### Technical Capabilities
- **NVMe drives**: Format with crypto erase (`--ses=2`) or block erase (`--ses=1`)
- **SATA SSDs**: ATA Secure Erase with password protection
- **HDDs**: NIST-compliant 3-pass overwrite with `shred`

### Safety Measures
- USB drives automatically excluded
- Requires typing `ERASE ALL DATA` to proceed
- Shows detailed drive information before purge
- No network connectivity in live environment

---

## Usage Instructions

### Creating Bootable USB

#### Linux/macOS:
```bash
# Find your USB drive (be VERY careful to select the right device)
lsblk  # or: diskutil list (macOS)

# Write ISO to USB (replace /dev/sdX with your USB device)
sudo dd if=live-image-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

#### Windows:
1. Download [Rufus](https://rufus.ie/) or [balenaEtcher](https://www.balena.io/etcher/)
2. Select the ISO file
3. Select your USB drive
4. Click "Write" or "Flash"

### Running the Utility

1. **Insert USB** into target computer
2. **Boot from USB** (may need to change boot order in BIOS/UEFI and disable secure boot)
3. **Wait for automatic startup** (system loads into RAM)
4. **Review drive list** carefully
5. **Type confirmation** exactly: `ERASE ALL DATA`
6. **Wait for completion** (time varies by drive size/type)
7. **System auto-shutdown** when finished

### What to Expect

```
===============================================
SecureAutomatedPurge - NIST 800-88 Purge Utility
Developed by Abdullah Kareem - MIT License
Github.com/CyberKareem
===============================================

Detecting drives...

╔══════════════════════════════════════════╗
                 WARNING                    
This will PERMANENTLY DESTROY ALL DATA      
╚══════════════════════════════════════════╝

Drives to be purged:
• /dev/nvme0n1 - 500GB - Samsung SSD 970 (Serial: S4EVNX0M702146K)
• /dev/sda - 2TB - WDC WD20EZRZ (Serial: WD-WCC4M0KRD8PZ)

To proceed, type: ERASE ALL DATA
Enter confirmation: _
```

---

## Technical Details

### Supported Drive Types

| Drive Type | Detection Method | Purge Method | NIST Reference |
|------------|-----------------|--------------|----------------|
| NVMe SSD | `/dev/nvme*` pattern | `nvme format --ses=2` | SP 800-88 Rev.1 A.11 |
| SATA SSD | rotational=0 | ATA Secure Erase | SP 800-88 Rev.1 A.10 |
| SATA HDD | rotational=1 | 3-pass shred | SP 800-88 Rev.1 A.8 |

### Purge Methods Explained

#### NVMe Crypto Erase
```bash
nvme format /dev/nvme0n1 --ses=2 -f
# Destroys encryption keys, rendering data unrecoverable
# Fastest method: typically < 5 seconds
```

#### ATA Secure Erase
```bash
hdparm --user-master u --security-set-pass p /dev/sda
hdparm --user-master u --security-erase p /dev/sda
# Controller-level erase, bypasses OS
# Speed: ~1 minute per 100GB
```

#### HDD Overwrite
```bash
shred -v -n 3 /dev/sdb
# 3 passes: random, random, zeros
# Speed: ~1 hour per TB
```

### Verification Process

Post-purge, the utility samples drive sectors:
- Start (sector 0)
- Middle (sector count/2)
- End (last sector)

Expected result: all zeros or random data (no readable filesystem)

---

## Building from Source

Don't trust pre-built ISOs? Build your own:

### Prerequisites
```bash
sudo apt update
sudo apt install live-build debootstrap xorriso syslinux-utils mtools
```

### Build Steps
```bash
# Clone repository
git clone https://github.com/CyberKareem/SecureAutomatedPurge-USB.git
cd SecureAutomatedPurge-USB

# Run build process
cd build
./build_iso.sh
```

[Detailed build instructions](./build/README.md)

---

## NIST SP 800-88 Compliance

This utility implements **Purge-level** sanitization as defined in [NIST Special Publication 800-88 Revision 1](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-88r1.pdf):

- **Cryptographic Erase** for self-encrypting drives (Section 3.5)
- **Block Erase** for flash memory (Appendix A.11)
- **Overwrite** for magnetic media (Appendix A.8)
- **Verification** procedures (Section 4.8)

### Compliance Matrix

| NIST Requirement | Implementation |
|-----------------|----------------|
| Target Data Categories | All user data on internal storage |
| Sanitization Level | Purge (suitable for moderate security) |
| Verification Method | Direct sector sampling |
| Documentation | Automated logging to `/var/log/purge_audit/` |

---

## Related Projects

- [BitLocker Cryptographic Erase](https://github.com/CyberKareem/BitLocker-CryptoErase) - Windows-based crypto erase utility

---

## License

This project is licensed under the [MIT License](./LICENSE) - see the file for details.

---

## Security Policy

Found a security issue? Please report it responsibly:
- Email: abdullahalikareem@gmail.com
- GPG Key: [Available on request]

---

## Contributing

Contributions welcome! Please:
- Fork the repository
- Create a feature branch
- Submit a pull request

See [CONTRIBUTING.md](./CONTRIBUTING.md) for details.

---

## Contact & Support

- **Author**: Abdullah Kareem
- **X**: [DM me on X](https://x.com/CyberKareem)
- **LinkedIn**: [Connect on LinkedIn](https://linktr.ee/cyberkareem)
- **Issues**: [GitHub Issues](https://github.com/CyberKareem/SecureAutomatedPurge-USB/issues)
- If this tool helps you, please consider starring the repository!

---

## Acknowledgments

- NIST for SP 800-88 guidelines
- Debian team for live-build framework
- Open source community for drive utilities
- Beta testers and security reviewers

---

**Remember**: With great power comes great responsibility. Always verify you're purging the correct system!

---

<a href="https://www.buymeacoffee.com/cyberkareem" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

