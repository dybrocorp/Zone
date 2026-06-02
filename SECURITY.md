# Security Policy for Zone

## Reporting Security Vulnerabilities

If you discover a security vulnerability in Zone, please **do not** open a public GitHub issue. Instead, please report it responsibly to:

📧 **Email**: security@dybrocorp.com

Please include:
- Description of the vulnerability
- Steps to reproduce (if applicable)
- Potential impact
- Suggested fix (if you have one)

We will acknowledge receipt of your report within 48 hours and will strive to provide an update within 7 days.

## Security Best Practices

### Cryptography
- Zone uses **X25519** for key exchange
- **ChaCha20-Poly1305** for end-to-end encryption
- **Ed25519** for digital signatures
- **PBKDF2** for key derivation

### Data Protection
- All messages are encrypted end-to-end
- No personal data (email/phone) required
- Anonymous identity via ZONE-ID
- User data is encrypted at rest

### Backend Security
- PostgreSQL with Row Level Security (RLS)
- Supabase authentication
- Secure key storage via flutter_secure_storage

### Dependencies
All dependencies are regularly reviewed and kept up-to-date. Monitor security advisories for:
- `cryptography`
- `supabase_flutter`
- `flutter_reactive_ble`

## Security Scanning

This repository uses:
- ✅ GitHub Dependabot for vulnerability detection
- ✅ Code scanning with advanced security features

## Version Support

| Version | Status | Notes |
|---------|--------|-------|
| 1.0.4+ | Supported | Current stable release |
| < 1.0.4 | Unsupported | Please upgrade |

## Reporting Process

1. **Email** security@dybrocorp.com with details
2. **Do not** disclose the vulnerability publicly until we've had time to patch
3. **Wait** for our response before publishing details
4. **Credit** will be given to responsible researchers

## Security Updates

- **v1.0.4**: Mesh network P2P encryption improvements
- **v1.0.2**: Enhanced key handover security
- **v1.0.1**: Initial security audit completion

---

**Last Updated**: 2026-05-29  
**Maintained by**: DYBROCORP Security Team
