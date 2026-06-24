if Code.ensure_loaded?(Vix.Vips.Image) do
  defmodule Butteraugli.Vix do
    @moduledoc """
    Convenience wrappers that accept `Vix.Vips.Image` structs.

    Only compiled when the optional `:vix` dependency is available. Images are
    coerced to packed 8-bit sRGB (`:rgb888`), flattening any alpha channel.
    """

    alias Vix.Vips.{Image, Operation}
    alias Butteraugli.Result

    @doc """
    Compare a Vix candidate against a reference.

    With two images, the reference is rebuilt every call. With a precomputed
    `Butteraugli.Reference` as the first argument, it is reused against the
    candidate (the reference's baked-in tuning parameters apply). Pass the same
    options as `Butteraugli.compare/5` (`:compute_diffmap`, `:intensity_target`,
    `:hf_asymmetry`, `:cancel`, `:timeout`); `:format` is always `:rgb888` here.
    For the precompute form only `:cancel`/`:timeout` apply.
    """
    @spec compare(Image.t(), Image.t(), keyword()) ::
            {:ok, Result.t()} | {:error, term()}
    @spec compare(Butteraugli.Reference.t(), Image.t(), keyword()) ::
            {:ok, Result.t()} | {:error, term()}
    def compare(reference, distorted, opts \\ [])

    def compare(%Image{} = reference, %Image{} = distorted, opts) do
      with {:ok, {ref_bin, w, h}} <- coerce(reference),
           {:ok, {dist_bin, ^w, ^h}} <- coerce(distorted) do
        Butteraugli.compare(ref_bin, dist_bin, w, h, Keyword.put(opts, :format, :rgb888))
      else
        {:ok, {_bin, _w2, _h2}} -> {:error, :dimension_mismatch}
        other -> other
      end
    end

    def compare(%Butteraugli.Reference{} = reference, %Image{} = distorted, opts) do
      with {:ok, {bin, _w, _h}} <- coerce(distorted) do
        Butteraugli.Reference.compare(reference, bin, opts)
      end
    end

    @doc """
    Build a `Butteraugli.Reference` from a Vix image (coerced to `:rgb888`).

    Accepts the same tuning options as `Butteraugli.Reference.new/4`
    (`:intensity_target`, `:hf_asymmetry`, `:compute_diffmap`).
    """
    @spec reference(Image.t(), keyword()) :: {:ok, Butteraugli.Reference.t()} | {:error, term()}
    def reference(%Image{} = image, opts \\ []) do
      with {:ok, {bin, w, h}} <- coerce(image) do
        Butteraugli.Reference.new(bin, w, h, Keyword.put(opts, :format, :rgb888))
      end
    end

    # Coerce to packed 8-bit sRGB, flattening alpha.
    defp coerce(%Image{} = image) do
      colour = Operation.colourspace!(image, :VIPS_INTERPRETATION_sRGB)
      flat = if Image.has_alpha?(colour), do: Operation.flatten!(colour), else: colour
      cast = Operation.cast!(flat, :VIPS_FORMAT_UCHAR)

      case Image.write_to_binary(cast) do
        {:ok, bin} -> {:ok, {bin, Image.width(cast), Image.height(cast)}}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
