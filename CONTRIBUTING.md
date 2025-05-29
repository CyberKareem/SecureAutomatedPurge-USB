# Contributing to Secure Automated Purge USB

Thank you for your interest in contributing! This project welcomes contributions from the community.

## How to Contribute

### Reporting Issues

- Check if the issue already exists
- Include system information (OS, hardware)
- Provide detailed steps to reproduce
- Include error messages and logs

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly
5. Commit with clear messages (`git commit -m 'Add amazing feature'`)
6. Push to your fork (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Code Style

- Use clear variable names
- Comment complex logic
- Follow existing code patterns
- Test your changes

### Testing

Before submitting:
- Build the ISO successfully
- Test in a VM
- Verify all drive types work
- Check error handling

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/SecureAutomatedPurge-USB.git
cd SecureAutomatedPurge-USB

# Create branch
git checkout -b feature/your-feature

# Make changes and test
# ...

# Build ISO
sudo ./build/build_iso.sh
```

## Areas for Contribution

- Additional drive type support
- Improved error handling
- Documentation improvements
- Translation support
- Performance optimizations
- Security enhancements

## Questions?

Feel free to open an issue for discussion!
