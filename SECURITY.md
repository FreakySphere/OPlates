# Security Policy

## Supported version

Security and privacy fixes are provided for the latest public OPlates release.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Do not post a sensitive vulnerability, exploit details, private data or credentials in a public issue.

Use [GitHub private vulnerability reporting](https://github.com/FreakySphere/OPlates/security/advisories/new) when it is available. If it is not available, contact **FreakySphere** privately through the official GitHub profile and provide only enough public information to establish a private channel.

Please include:

- the affected OPlates version;
- the 3.3.5a client environment;
- clear reproduction steps;
- the expected and actual behavior;
- the potential impact;
- a suggested fix, if known.

You should receive an acknowledgement when the report is seen. Please allow reasonable time to investigate and prepare a release before public disclosure.

## Scope

Security reports may include:

- unexpected code execution caused by OPlates data handling;
- unsafe import/profile parsing;
- accidental disclosure of sensitive local data;
- malicious links or compromised release artifacts;
- dependency vulnerabilities that affect the bundled addon at runtime.

Normal gameplay bugs, incorrect icons and feature requests belong in the public [issue tracker](https://github.com/FreakySphere/OPlates/issues).

Never include account credentials, private-server credentials, authentication tokens or personal wallet secrets in any report.
