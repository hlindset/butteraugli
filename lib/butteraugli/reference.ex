defmodule Butteraugli.Reference do
  @moduledoc """
  A precomputed butteraugli reference image for efficient batch comparison.

  Build one with `new/4`, then call `compare/2` repeatedly against candidate
  images of the same dimensions and format. This reuses the reference's internal
  XYB pyramid and is roughly twice as fast per comparison as
  `Butteraugli.compare/5` — ideal for a quality-search loop comparing many
  encodings against one original.

  Tuning parameters (`:intensity_target`, `:hf_asymmetry`, `:compute_diffmap`)
  are fixed when the reference is built — the underlying crate bakes them into
  the precomputed reference — so every `compare/2` against a given reference uses
  the same settings. If `compute_diffmap: true` was passed to `new/4`, each
  result carries a `diffmap`.

  Cancellation granularity on a reference compare depends on `compare/3`'s
  `:prefer` option:

    * `:prefer` `:speed` (default) — the warm precomputed path. Cancellation
      (`:cancel`/`:timeout`) is checked **once, at the start** of each call: it
      aborts a ref that is already cancelled when the call begins (including
      batch cancellation — cancel one ref to abort every subsequent compare that
      uses it), but does **not** interrupt a compare already running.
    * `:prefer` `:memory` — the strip-bounded walker. Cancellation is checked
      **per strip**, so a `cancel`/`timeout` arriving mid-compare aborts
      promptly, at the cost of the precompute speedup.

  `:speed` is the default because reusing the precomputed reference is the whole
  point of `Butteraugli.Reference` (~2× per call); reach for `:memory` only when
  you need bounded peak memory or mid-flight cancellation. See `Butteraugli` for
  the full granularity matrix.
  """

  alias Butteraugli.{Cancellation, Native, Result, Validate}

  @enforce_keys [:resource, :width, :height, :format]
  defstruct [:resource, :width, :height, :format]

  @type t :: %__MODULE__{
          resource: reference(),
          width: pos_integer(),
          height: pos_integer(),
          format: atom()
        }

  @doc """
  Precompute a reference from a packed binary.

  Options: `:format` (default `:rgb888`), `:intensity_target`, `:hf_asymmetry`,
  `:compute_diffmap` (default `false`). These are baked into the reference.

  The image must be at least 8×8; the precompute path rejects smaller images
  with `{:error, {:butteraugli, _}}`. (The one-shot `Butteraugli.compare/5`
  pads sub-8×8 inputs internally and has no such restriction.)
  """
  @spec new(Butteraugli.image_data(), pos_integer(), pos_integer(), keyword()) ::
          {:ok, t()} | {:error, Butteraugli.reason()}
  def new(source, width, height, opts \\ []) when is_binary(source) do
    format = Keyword.get(opts, :format, :rgb888)

    with :ok <- Validate.format(format),
         :ok <- Validate.dims(width, height),
         :ok <- Validate.size(source, width, height, format),
         {:ok, resource} <-
           map_native(
             Native.reference_new(
               source,
               width,
               height,
               format,
               Keyword.get(opts, :intensity_target),
               Keyword.get(opts, :hf_asymmetry),
               Keyword.get(opts, :compute_diffmap, false)
             )
           ) do
      {:ok, %__MODULE__{resource: resource, width: width, height: height, format: format}}
    end
  end

  @doc """
  Compare a candidate against the precomputed reference (same format and
  dimensions).

  Options:
    * `:cancel` — a `Butteraugli.CancelRef`.
    * `:timeout` — positive integer milliseconds.
    * `:prefer` — `:speed` (default) or `:memory`, choosing how the comparison
      runs:
      * `:speed` — reuse the precomputed reference pyramid. Roughly **twice as
        fast** per call, but cancellation/timeout is checked **once, at the
        start** only (mid-flight cancellation is *not* honored).
      * `:memory` — run the strip-bounded walker instead: **bounded peak
        memory** and **per-strip mid-flight cancellation** (a `cancel`/`timeout`
        arriving partway through aborts promptly). This recomputes the reference
        side per strip, so it gives up the precompute speedup — expect it to be
        roughly as slow as a one-shot `Butteraugli.compare/5`.

  Both modes return the same score (modulo low-bit floating-point differences).
  Returns `{:ok, %Butteraugli.Result{}}` or `{:error, reason}`.
  """
  @spec compare(t(), Butteraugli.image_data(), keyword()) ::
          {:ok, Result.t()} | {:error, Butteraugli.reason()}
  def compare(%__MODULE__{} = ref, distorted, opts \\ []) when is_binary(distorted) do
    cancel = Keyword.get(opts, :cancel)
    timeout = Keyword.get(opts, :timeout)
    prefer = Keyword.get(opts, :prefer, :speed)

    with :ok <- Validate.size(distorted, ref.width, ref.height, ref.format),
         :ok <- Validate.cancel(cancel),
         :ok <- Validate.timeout(timeout),
         :ok <- Validate.prefer(prefer) do
      use_strips = prefer == :memory

      Cancellation.run(cancel, timeout, fn resource ->
        Native.reference_compare(ref.resource, distorted, resource, use_strips)
      end)
      |> Result.from_native()
    end
  end

  @doc "Like `new/4` but returns the reference or raises `Butteraugli.Error`."
  @spec new!(Butteraugli.image_data(), pos_integer(), pos_integer(), keyword()) :: t()
  def new!(source, width, height, opts \\ []) do
    case new(source, width, height, opts) do
      {:ok, ref} -> ref
      {:error, reason} -> raise Butteraugli.Error, reason: reason
    end
  end

  @doc "Like `compare/3` but returns the bare `Result` or raises `Butteraugli.Error`."
  @spec compare!(t(), Butteraugli.image_data(), keyword()) :: Result.t()
  def compare!(%__MODULE__{} = ref, distorted, opts \\ []) do
    case compare(ref, distorted, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise Butteraugli.Error, reason: reason
    end
  end

  defp map_native({:ok, value}), do: {:ok, value}

  defp map_native({:error, message}) when is_binary(message),
    do: {:error, {:butteraugli, message}}
end
