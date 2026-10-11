# LSL 0.9.0 BETA — Linux x86_64 release evidence

These reports describe the exact staged native binaries, before publication.
`build.json` proves byte-identical frontend and backend fixed points.
`verification.json` records the complete maintained corpus, both fixed points,
isolated 0.8.9 migration/reinstall/rollback, image hardening, public CLI and
43 native regressions. All required gates passed; sources and binaries were
unchanged during verification. The developer installation was not modified.

Build times are correctness diagnostics under desktop load, not isolated
performance benchmarks. The separate benchmark from 4046082 is maintained in
`tools/qbe/LUXIR_BENCHMARK_20261011.md`: the common compiler workload takes
41.4% longer than 0.8.9, while eight measured programs execute faster.

GPU hardware is optional and was not requested by this release preflight.
Signed stable-channel archive installation is a separate gate; this BETA is
published as a Gitea prerelease with SHA-256 checksums, without replacing the
signed 0.8.9 channel. Stable metadata was sampled before publication.

`archive-build.json` and `archive-verification.json` additionally describe an
offline rebuild from an unpacked source release candidate and relocated binary
bundle checks. Final downloadable archive hashes are in release SHA256SUMS.

Frontend, backend, direct driver and configure tool also match byte-for-byte
after rebuilding in another directory. CLI, installer and test runner embed
absolute standard-library diagnostic paths, so their cross-directory hashes
differ. These differences are recorded, and relocated CLI, installation and
frontend self-host are tested separately; cross-directory bit identity is not
claimed for those three tools.
