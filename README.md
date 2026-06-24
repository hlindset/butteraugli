# butteraugli

[Butteraugli](https://github.com/imazen/butteraugli) perceptual
image-difference metric for Elixir, backed by the `butteraugli` Rust crate
(BSD-3-Clause) via Rustler.

> **Note:** this binding pins `butteraugli` to a **git revision** because the
> cooperative-cancellation API (`*_with_stop`) is not yet in a crates.io release
> (latest is 0.9.3). This does not prevent publishing to Hex; consumers who
> build the NIF from source fetch the pinned rev from GitHub, while precompiled-
> NIF users are unaffected. The dep can move to `version = "0.9.4"` once it ships.

## Installation

```elixir
def deps do
  [{:butteraugli, github: "hlindset/butteraugli"}]
end
```

## Usage

Inputs are packed binaries; the layout is selected with the `:format` option
(default `:rgb888`). Butteraugli is a **distance**: lower is better. A score
below `1.0` is perceptually identical, `1.0`–`2.0` is a subtle difference, and
above `2.0` is a clearly visible difference.

| format | element | channels | bytes/pixel | color space |
| --- | --- | --- | --- | --- |
| `:rgb888` (default) | `u8` | 3 | 3 | sRGB (gamma) |
| `:linear_rgb` | `f32` | 3 | 12 | linear RGB |

Multi-byte elements are native-endian.

```elixir
{:ok, %Butteraugli.Result{score: score}} =
  Butteraugli.compare(ref_rgb, dist_rgb, width, height)
```

`Butteraugli.Result` carries `score` (max-norm distance), `pnorm_3` (libjxl
3-norm aggregation), and `diffmap`. The `diffmap` is `nil` unless you opt in:

```elixir
{:ok, %Butteraugli.Result{diffmap: diffmap}} =
  Butteraugli.compare(ref, dist, width, height, compute_diffmap: true)
# diffmap: packed native-endian f32, width*height values, matching input dims.
```

Tuning parameters fall back to crate defaults when omitted:

```elixir
Butteraugli.compare(ref, dist, w, h, intensity_target: 250.0, hf_asymmetry: 1.5)
```

For a quality-search loop comparing many candidates against one original, reuse
the reference. Tuning parameters are baked into the reference at build time:

```elixir
{:ok, ref} = Butteraugli.Reference.new(original_rgb, width, height)
{:ok, s1} = Butteraugli.Reference.compare(ref, candidate1_rgb)
{:ok, s2} = Butteraugli.Reference.compare(ref, candidate2_rgb)
```

### Cancellation

`compare/5` and `Reference.compare/3` accept `cancel:` (a
`Butteraugli.CancelRef`) and `timeout:` (milliseconds):

```elixir
cancel_ref = Butteraugli.CancelRef.new()
# ... from another process, on client disconnect / deadline:
Butteraugli.cancel(cancel_ref)

# aborted calls return {:error, :cancelled} or {:error, :timeout}
Butteraugli.compare(ref, dist, w, h, cancel: cancel_ref, timeout: 5_000)
```

A cancel ref is single-use and can cover a whole batch.

**Granularity.** The default sRGB `compare/5` on images ≥ 8×8 checks the ref
between strips, so it aborts **mid-computation**. The other paths — `:linear_rgb`,
sub-8×8 images, and all `Reference.compare/3` — check the ref **once at the
start** of the computation (the crate has no strip-wise stop for these): they
abort a ref that is already cancelled when the call begins (so batch
cancellation works — cancel once, every subsequent compare aborts), but do not
interrupt a compare already underway. To bound the wall-clock of one long
compare, use the sRGB `compare/5` path rather than a precomputed reference.

### With Vix

If `:vix` is a dependency, pass images directly (coerced to 8-bit sRGB):

```elixir
{:ok, %Butteraugli.Result{}} = Butteraugli.Vix.compare(ref_image, dist_image)
```

## Accuracy

Scores come from [`butteraugli`](https://github.com/imazen/butteraugli), a
maintained Rust port of libjxl's butteraugli. Treat the absolute value as
"butteraugli as computed by this crate." The metric is well-behaved and
monotonic (identical images score near 0; perceptual degradation raises the
score), which is what matters for relative use such as a quality-search loop.

## Status

v0.1 supports 8-bit sRGB and linear-f32 RGB input, an optional per-pixel
difference map, the `intensity_target` / `hf_asymmetry` tuning parameters, and
cooperative cancellation (`cancel:` / `timeout:`).

## Releasing

Precompiled NIFs are built by the GitHub release workflow on a `v*` tag. Before
publishing, generate the checksum file the package references:

```bash
mix rustler_precompiled.download Butteraugli.Native --all --print
```

This writes `checksum-Elixir.Butteraugli.Native.exs`, which MUST be included in
the published package (it is already listed in `mix.exs` `:files`).

### Building from source

A Rust toolchain is only needed if you build the NIF locally instead of using a
precompiled artifact — i.e. on a target not covered by the release matrix, or
when forcing a build with `BUTTERAUGLI_BUILD=1`.

## License

This wrapper is released under BSD-3-Clause, matching `butteraugli`.
