# Evolution Log — python-client-tls-configuration

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. ssl.create_default_context() baseline + minimum_version=TLSv1_2 hardening; never check_hostname=False / CERT_NONE / _create_unverified_context; load_verify_locations layered on system roots for custom CA; load_cert_chain for mTLS with password via CredentialProvider; httpx + aiohttp + asyncpg + nats + aiokafka integration; cert pinning advanced topic; typed exception wrap of ssl.SSLError → NetworkError, ssl.SSLCertVerificationError → AuthError; mkcert for self-signed test certs (never weaken context).
