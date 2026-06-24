defmodule Butteraugli do
  @moduledoc """
  Butteraugli perceptual image-difference metric for Elixir, backed by the
  `butteraugli` Rust crate.

  Butteraugli is a *distance*: lower is better. A `score` below `1.0` means the
  images are perceptually identical, `1.0`–`2.0` is a subtle/borderline
  difference, and above `2.0` is a clearly visible difference. (This is the
  opposite orientation from quality metrics like SSIMULACRA2.)

  Inputs are packed binaries whose layout is chosen with the `:format` option
  (default `:rgb888`):

  | format | element | channels | bytes/pixel | color space |
  | --- | --- | --- | --- | --- |
  | `:rgb888` (default) | `u8` | 3 | 3 | sRGB (gamma) |
  | `:linear_rgb` | `f32` | 3 | 12 | linear RGB |

  Multi-byte elements (`f32`) are **native-endian** (`<<v::native-float-32>>`).
  A binary's size must equal `width * height * channels * bytes_per_element`.

  Comparisons return a `Butteraugli.Result`.

  ## Cancellation

  `compare/5` and `Butteraugli.Reference.compare/3` accept `cancel:` (a
  `Butteraugli.CancelRef`) and `timeout:` (milliseconds); aborted calls return
  `{:error, :cancelled}` or `{:error, :timeout}`. Create a ref with
  `Butteraugli.CancelRef.new/0` and trip it with `cancel/1`.

  The *granularity* differs by path, because the binding polls the ref at
  different points:

    * **`compare/5` on images ≥ 8×8** (either format) checks the ref between
      strips, so it aborts **mid-computation** — a ref cancelled, or a timeout
      firing, partway through a long compare stops it promptly.
    * **Sub-8×8 images and all `Butteraugli.Reference.compare/3`** check the ref
      **once, at the start** of the computation. (Sub-8×8 inputs are padded and
      take the non-strip path; `Butteraugli.Reference.compare/3` uses the
      precomputed reference on purpose — the crate's strip-cancellable reference
      compare discards the precompute and its ~2× speedup.) These honor a ref
      that is *already* cancelled when the call begins — including batch
      cancellation, where cancelling one ref aborts every *subsequent* compare
      that uses it — but a cancel/timeout arriving *after* the computation is
      underway will not interrupt it; that call runs to completion.

  If you must bound the wall-clock of an individual long compare, use `compare/5`
  on a ≥ 8×8 image (it rebuilds the reference each call but is fully cancellable)
  rather than `Butteraugli.Reference`.
  """

  alias Butteraugli.{Cancellation, CancelRef, Native, Result, Validate}

  @type image_data :: binary()
  @type reason ::
          :invalid_dimensions
          | :size_mismatch
          | :dimension_mismatch
          | :unknown_format
          | :invalid_cancel
          | :invalid_timeout
          | :cancelled
          | :timeout
          | {:butteraugli, String.t()}

  @doc """
  Compare a reference and distorted image of the same dimensions.

  Options:
    * `:format` — `:rgb888` (default) or `:linear_rgb`.
    * `:compute_diffmap` — when `true`, the `Result` includes a per-pixel
      `diffmap` binary (default `false`).
    * `:intensity_target` — display brightness in nits (crate default if omitted).
    * `:hf_asymmetry` — high-frequency penalty asymmetry (crate default if omitted).
    * `:cancel` — a `Butteraugli.CancelRef`; cancelling it from another
      process aborts the call with `{:error, :cancelled}`.
    * `:timeout` — positive integer milliseconds; the call returns
      `{:error, :timeout}` if it exceeds that.

  Returns `{:ok, %Butteraugli.Result{}}` or `{:error, reason}`.
  """
  @spec compare(image_data(), image_data(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, Result.t()} | {:error, reason()}
  def compare(reference, distorted, width, height, opts \\ [])
      when is_binary(reference) and is_binary(distorted) do
    format = Keyword.get(opts, :format, :rgb888)
    cancel = Keyword.get(opts, :cancel)
    timeout = Keyword.get(opts, :timeout)

    with :ok <- Validate.format(format),
         :ok <- Validate.dims(width, height),
         :ok <- Validate.size(reference, width, height, format),
         :ok <- Validate.size(distorted, width, height, format),
         :ok <- Validate.cancel(cancel),
         :ok <- Validate.timeout(timeout) do
      Cancellation.run(cancel, timeout, fn resource ->
        Native.compare(
          reference,
          distorted,
          width,
          height,
          format,
          Keyword.get(opts, :intensity_target),
          Keyword.get(opts, :hf_asymmetry),
          Keyword.get(opts, :compute_diffmap, false),
          resource
        )
      end)
      |> Result.from_native()
    end
  end

  @doc """
  Like `compare/5` but returns the bare `Butteraugli.Result` and raises
  `Butteraugli.Error` on failure. Accepts the same options.
  """
  @spec compare!(image_data(), image_data(), pos_integer(), pos_integer(), keyword()) ::
          Result.t()
  def compare!(reference, distorted, width, height, opts \\ []) do
    case compare(reference, distorted, width, height, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise Butteraugli.Error, reason: reason
    end
  end

  @doc """
  Trip a `Butteraugli.CancelRef`, aborting any comparison that uses it.

  Call from any process to cancel an in-flight `compare/5` or
  `Butteraugli.Reference.compare/3` that was passed this ref as `cancel:`.
  Returns `:ok` and is safe to call more than once.
  """
  @spec cancel(CancelRef.t()) :: :ok
  def cancel(%CancelRef{resource: r}), do: Native.token_cancel(r)
end
