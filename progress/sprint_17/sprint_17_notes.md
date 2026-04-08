# Sprint 17 — Notes

## `[DEFAULT]` stanza vs `SLI_TEST` in the Node OCI SDK

**Context:** `oci-profile-setup` may append a `[DEFAULT]` section that mirrors the active packed profile (e.g. `[SLI_TEST]`) when the restored `~/.oci/config` had no `[DEFAULT]` block.

**Why this is not a substitute for passing the profile name:** The application and SDK **do** use the requested profile (`SLI_TEST`) via `ConfigFileAuthenticationDetailsProvider` / `SessionAuthDetailProvider` with an explicit profile string—same idea as `oci --profile SLI_TEST`.

**Why the duplicate stanza exists:** `oci-common`’s `ConfigFileReader` parses the **whole** file and emits **`console.info("No DEFAULT profile was specified in the configuration")`** whenever there is **no `[DEFAULT]` section**, even if authentication is correctly driven by `[SLI_TEST]`. That message is **misleading** in CI where secrets are intentionally **single-profile** packs.

**Summary:** The `[DEFAULT]` mirror is a **log-noise / file-shape** workaround for the SDK parser, **not** a fix for “the SDK cannot take `SLI_TEST`.” Credentials stay aligned with the verified profile; `[DEFAULT]` is an alias of the same stanza so the parser stops warning.
