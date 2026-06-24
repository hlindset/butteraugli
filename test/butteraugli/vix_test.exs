defmodule Butteraugli.VixTest do
  use ExUnit.Case, async: true

  @moduletag :vix

  alias Vix.Vips.{Image, Operation}
  alias Butteraugli.Result

  test "compare/2 scores identical Vix images near zero (< 1.0)" do
    {:ok, img} = Image.new_from_buffer(black_png())
    assert {:ok, %Result{score: score}} = Butteraugli.Vix.compare(img, img)
    assert score < 1.0
  end

  # NOTE (deviation from plan): the plan used the 4x4 black PNG here, but
  # ButteraugliReference::new enforces a minimum 8x8 — same constraint as the
  # native path. Using an 8x8 solid black image instead.
  test "reference/1 builds a :rgb888 Reference usable with Reference.compare/2" do
    bin = :binary.copy(<<0, 0, 0>>, 8 * 8)
    {:ok, img8} = Image.new_from_binary(bin, 8, 8, 3, :VIPS_FORMAT_UCHAR)
    img = Operation.copy!(img8, interpretation: :VIPS_INTERPRETATION_sRGB)
    assert {:ok, %Butteraugli.Reference{format: :rgb888} = ref} = Butteraugli.Vix.reference(img)
    {:ok, bin_out} = Image.write_to_binary(rgb888(img))
    assert {:ok, %Result{score: score}} = Butteraugli.Reference.compare(ref, bin_out)
    assert score < 1.0
  end

  test "compare/2 reuses a precomputed reference against a Vix candidate" do
    bin = gradient_rgb888(64, 64)
    {:ok, img8} = Image.new_from_binary(bin, 64, 64, 3, :VIPS_FORMAT_UCHAR)
    img8 = Operation.copy!(img8, interpretation: :VIPS_INTERPRETATION_sRGB)

    {:ok, ref} = Butteraugli.Vix.reference(img8)

    # Identical candidate scores near zero.
    assert {:ok, %Result{score: identical}} = Butteraugli.Vix.compare(ref, img8)
    assert identical < 1.0

    # Heavier degradation => larger perceptual distance => higher score.
    light = Operation.gaussblur!(img8, 0.5)
    heavy = Operation.gaussblur!(img8, 3.0)
    assert {:ok, %Result{score: light_score}} = Butteraugli.Vix.compare(ref, light)
    assert {:ok, %Result{score: heavy_score}} = Butteraugli.Vix.compare(ref, heavy)
    assert heavy_score > light_score

    # The precompute path matches the rebuild-every-call path within epsilon.
    assert {:ok, %Result{score: pair_score}} = Butteraugli.Vix.compare(img8, heavy)
    assert_in_delta heavy_score, pair_score, 0.01
  end

  # A deterministic gradient RGB888 binary (varies per pixel).
  defp gradient_rgb888(width, height) do
    for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
      <<rem(x, 256), rem(y, 256), rem(x + y, 256)>>
    end
  end

  # Flatten a (possibly RGBA) Vix image to a packed 8-bit, 3-band sRGB image.
  defp rgb888(img) do
    colour = Operation.colourspace!(img, :VIPS_INTERPRETATION_sRGB)
    flat = if Image.has_alpha?(colour), do: Operation.flatten!(colour), else: colour
    Operation.cast!(flat, :VIPS_FORMAT_UCHAR)
  end

  # A 4x4 black PNG.
  defp black_png do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEUlEQVR4nGNgYGD4z0AkYBxVCAAxAQH/JLAB+QAAAABJRU5ErkJggg=="
    )
  end
end
