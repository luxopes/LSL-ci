# LSL 0.9.1 — Linux x86_64 release evidence

These reports describe the exact staged native binaries, before publication.

- `build.json` proves byte-identical frontend and backend fixed points
  (`build_release.py --seed` with the already self-hosted 0.9.1 frontend; the
  0.9.0 seed generates different code, so its first generation cannot match).
- `verification.json` is the complete `verify_release.py` preflight: maintained
  corpus with both fixed points, managed installation, isolated 0.8.9
  migration with two reinstalls and two rollbacks, image hardening, public CLI
  and the registered native regressions. All gates passed.
- `native-image.json` and `original-runner.json` are the detailed reports of
  the image and original-corpus gates.
- `performance-vs-0.9.0.json` holds every sample of the CPU-time comparison
  against the published 0.9.0 BETA binaries (user+sys time of each child,
  21 alternating rounds, same machine). Medians: compile −3.3 % to +1.0 %
  across nine inputs, run of eight benchmark programs equal or faster except
  noisy single-run outliers. Repeated 60–100-run checks pinned to one core
  (`taskset`) confirmed float_loop, allocation_gc and dictionary_access at
  equal or better speed. The common 0.8.9 compiler source compiled in
  9.11 s (0.9.0) versus 9.11 s (0.9.1), medians of seven alternating runs.

The machine is a desktop laptop (Ryzen 5 5500U, frequency scaling, other
applications running); single samples vary by up to ±10 %, so only medians
and distributions are meaningful.

Release builds are reproducible across directories for the CLI as well:
standard-library and compiler source paths are stored relative to the
installation, so the CLI built from another directory is byte-identical.

GPU hardware is optional and was not requested by this preflight. Signed
stable-channel publication is performed separately in LuxAI/LSL-Releases.
