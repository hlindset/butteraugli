# butteraugli

[Butteraugli](https://github.com/imazen/butteraugli) perceptual
image-difference metric for Elixir, backed by the
[`butteraugli`](https://crates.io/crates/butteraugli) Rust crate via Rustler.
The crate is a port of Google's butteraugli implementation from
[libjxl](https://github.com/libjxl/libjxl).

> **Note:** this binding currently pins `butteraugli` to a git revision
> because the cooperative-cancellation API (`*_with_stop`) has not yet landed
> in a crates.io release. We will switch to a proper versioned as soon as
> possible.

## What is Butteraugli?

Butteraugli estimates the perceived difference between two images using a model
of human vision. Unlike simple pixel-wise metrics (PSNR, MSE), butteraugli
accounts for:

- **Opsin dynamics**: Photosensitive chemical responses in the retina
- **XYB color space**: Hybrid opponent/trichromatic representation
- **Visual masking**: How image features hide or reveal differences
- **Multi-scale analysis**: UHF, HF, MF, LF frequency bands

## Quality Thresholds

| Score     | Interpretation                          |
| --------- | --------------------------------------- |
| < 1.0     | Images appear identical to most viewers |
| 1.0 - 2.0 | Subtle differences may be noticeable    |
| > 2.0     | Visible differences between images      |

## Installation

```elixir
def deps do
  [{:butteraugli, github: "hlindset/butteraugli"}]
end
```

## Usage

Inputs are packed binaries; the layout is selected with the `:format` option
(default `:rgb888`).

| format              | element | color space  | use case                     |
| ------------------- | ------- | ------------ | ---------------------------- |
| `:rgb888` (default) | `u8`    | sRGB (gamma) | Standard 8-bit images        |
| `:linear_rgb`       | `f32`   | linear RGB   | HDR, 16-bit, float pipelines |

```elixir
{:ok, %Butteraugli.Result{score: score}} =
  Butteraugli.compare(ref_rgb, dist_rgb, width, height)
```

`Butteraugli.Result` carries `score` (max-norm distance), `pnorm_3` (libjxl
3-norm aggregation), and `diffmap`. Images smaller than 8x8 are padded up to
butteraugli's floor (8x8) and scored. Diffmaps are cropped back to the input
size before being returned.

The `diffmap` is `nil` unless you opt in:

```elixir
{:ok, %Butteraugli.Result{diffmap: diffmap}} =
  Butteraugli.compare(ref, dist, width, height, compute_diffmap: true)
```

Two tuning parameters adjust the perceptual model:

- `intensity_target` — display brightness in nits the images are assumed to be
  viewed at (crate default `80.0`).
- `hf_asymmetry` — multiplier weighting how added vs. removed high-frequency
  detail is penalized (crate default `1.0`). Values above `1.0` penalize new
  high-frequency artifacts (ringing, blocking) more than blurring; values below
  `1.0` do the reverse.

```elixir
Butteraugli.compare(ref, dist, w, h, intensity_target: 250.0, hf_asymmetry: 1.5)
```

Both fall back to crate defaults when omitted.

For a quality-search loop comparing many candidates against one original, reuse
the reference. Tuning parameters are baked into the reference at build time:

```elixir
{:ok, ref} = Butteraugli.Reference.new(original_rgb, width, height)
{:ok, s1} = Butteraugli.Reference.compare(ref, candidate1_rgb)
{:ok, s2} = Butteraugli.Reference.compare(ref, candidate2_rgb)
```

`Butteraugli.Reference.compare/3` takes `prefer: :speed | :memory` (default
`:speed`). `:speed` reuses the precomputed reference (~2x faster, cancellation
checked only at the start); `:memory` runs a strip-bounded walker with bounded
peak memory and per-strip mid-flight cancellation, giving up the speedup. See
[Cancellation](#cancellation).

### Cancellation

`Butteraugli.compare/5` and `Butteraugli.Reference.compare/3` accept `cancel:`
(a `Butteraugli.CancelRef`) and `timeout:` (milliseconds):

```elixir
cancel_ref = Butteraugli.CancelRef.new()

# ... from another process, on client disconnect / deadline:
Butteraugli.cancel(cancel_ref)

# aborted calls return {:error, :cancelled} or {:error, :timeout}
Butteraugli.compare(ref, dist, w, h, cancel: cancel_ref, timeout: 5_000)
```

A cancel ref is single-use and can cover a whole batch.

#### Granularity

`Butteraugli.compare/5` on images >= 8x8 (either format) checks the ref between
strips, so it aborts mid-computation. Two paths check the ref once at the start
instead: sub-8x8 images (padded onto the non-strip path) and
`Butteraugli.Reference.compare/3` with the default `prefer: :speed` (which
reuses the precomputed reference for the ~2x speedup). These abort a ref that
is already cancelled when the call begins (so batch cancellation works — cancel
once, every subsequent compare aborts), but do not interrupt a compare already
underway. `Butteraugli.Reference.compare/3` with `prefer: :memory` opts into the
strip-bounded walker, which aborts mid-computation (per strip) at the cost of
the speedup.

So to let a `cancel:`/`timeout:` interrupt one long compare partway through
(bounding its wall-clock), use `Butteraugli.compare/5` (which only does strip
processing) on a >= 8x8 image or `Reference.compare(ref, dist, prefer: :memory)`.

### With Vix

If `:vix` is a dependency, you can pass images directly (coerced to 8-bit sRGB):

```elixir
{:ok, %Butteraugli.Result{}} = Butteraugli.Vix.compare(ref_image, dist_image)
```

## Releasing

Precompiled NIFs are built by the GitHub release workflow on a `v*` tag. Before
publishing, generate the checksum file the package references:

```bash
mix rustler_precompiled.download Butteraugli.Native --all --print
```

### Building from source

A Rust toolchain is only needed if you build the NIF locally instead of using a
precompiled artifact — i.e. on a target not covered by the release matrix, or
when forcing a build with `BUTTERAUGLI_BUILD=1`.

## License

This wrapper is released under BSD-3-Clause, matching `butteraugli`.
