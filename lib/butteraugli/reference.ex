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

  Cancellation (`:cancel`/`:timeout`) on a reference compare is checked **once,
  at the start** of each call. This binding uses the warm precomputed path on
  purpose: the crate does expose a strip-cancellable reference compare, but it
  discards the precomputed reference (recomputing the reference side per strip),
  defeating the ~2× speedup that is the whole point of `Butteraugli.Reference`.
  So a reference compare aborts a ref that is already cancelled when the call
  begins (including batch cancellation: cancel one ref to abort every subsequent
  compare that uses it), but does **not** interrupt a compare that is already
  running. If you need mid-flight cancellation, use `Butteraugli.compare/5` on a
  ≥ 8×8 image. See `Butteraugli` for the full granularity matrix.
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

  Accepts `:cancel` (a `Butteraugli.CancelRef`) and `:timeout`
  (milliseconds), checked once at the start of the call (see the moduledoc and
  `Butteraugli` for the cancellation granularity matrix).
  Returns `{:ok, %Butteraugli.Result{}}` or `{:error, reason}`.
  """
  @spec compare(t(), Butteraugli.image_data(), keyword()) ::
          {:ok, Result.t()} | {:error, Butteraugli.reason()}
  def compare(%__MODULE__{} = ref, distorted, opts \\ []) when is_binary(distorted) do
    cancel = Keyword.get(opts, :cancel)
    timeout = Keyword.get(opts, :timeout)

    with :ok <- Validate.size(distorted, ref.width, ref.height, ref.format),
         :ok <- Validate.cancel(cancel),
         :ok <- Validate.timeout(timeout) do
      Cancellation.run(cancel, timeout, fn resource ->
        Native.reference_compare(ref.resource, distorted, resource)
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
