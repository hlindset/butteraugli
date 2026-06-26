# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Butteraugli.compare/5` and `compare!/5` — compute the butteraugli perceptual
  difference between two packed-binary images, returning a `Butteraugli.Result`
  with `score` (max-norm distance), `pnorm_3` (libjxl 3-norm aggregation), and
  an optional `diffmap`.
- `Butteraugli.Reference` — `new/4`, `new!/4`, `compare/3`, `compare!/3` for
  reusing one prepared reference across many candidates (~2× faster per compare
  in a quality-search loop). `compare/3` takes `prefer: :speed | :memory`
  (default `:speed`); `:memory` runs a strip-bounded walker with bounded peak
  memory and per-strip cancellation, trading away the speedup.
- Input formats selectable via the `:format` option: `:rgb888` (default, `u8`
  sRGB) and `:linear_rgb` (`f32` linear RGB).
- Tuning parameters `:intensity_target` (display brightness in nits, crate
  default `80.0`) and `:hf_asymmetry` (added-vs-removed high-frequency weighting,
  crate default `1.0`). On `Butteraugli.Reference` these are baked in at
  `new/4` time.
- Optional difference map via `:compute_diffmap` (default `false`). Diffmaps are
  cropped back to the input size; images smaller than 8×8 are padded up to
  butteraugli's 8×8 floor and scored.
- Cooperative cancellation: `Butteraugli.CancelRef.new/0` and
  `Butteraugli.cancel/1`. The metric runs on a dirty scheduler and polls the
  cancel ref at strip boundaries, freeing the CPU promptly. A cancel ref is
  single-use and can cover a whole batch.
- Wall-clock timeouts via the `:timeout` option, returning `{:error, :timeout}`.
- Optional Vix integration (`Butteraugli.Vix.compare/2`, `Butteraugli.Vix.reference/2`),
  available when `:vix` is a dependency; images are coerced to 8-bit sRGB.
- Precompiled NIFs via `rustler_precompiled` for `aarch64`/`x86_64` macOS,
  `gnu`/`musl` Linux, and `x86_64` Windows, across NIF versions 2.15–2.17, so
  the Rust toolchain is not required on covered targets.

### Notes

- `butteraugli` is pinned to a git revision because the cooperative-cancellation
  API (`*_with_stop`) has not yet landed in a crates.io release. This will move
  to a versioned dependency once available.
- The underlying crate is a port of Google's butteraugli implementation from
  libjxl.

[Unreleased]: https://github.com/hlindset/butteraugli/commits/main
