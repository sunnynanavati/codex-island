# Security

The release-preparation milestone is not a publicly signed/notarized release. Use artifacts only from a source you trust. The application reads sensitive local task content and should never be granted unnecessary permissions.

Report suspected vulnerabilities privately to the repository maintainers using GitHub's private vulnerability reporting if it is enabled after publication. No reporting address has been established yet; do not publish exploit details or secrets in a public issue while arranging a private channel.

Include the affected version, a minimal synthetic reproduction, and the impact. Never include real credentials, Codex databases, or rollout files. Signing certificates and notarization credentials belong in the macOS Keychain or protected CI secrets, not the repository.
