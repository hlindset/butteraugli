defmodule Butteraugli.FormatsTest do
  use ExUnit.Case, async: true
  alias Butteraugli.{Fixtures, Result}

  @dim 64

  # {format, reference binary, a visibly different binary}
  @cases [
    {:rgb888, Fixtures.gradient(@dim, @dim), Fixtures.solid(@dim, @dim, {128, 128, 128})},
    {:linear_rgb, Fixtures.gradient_linear_rgb(@dim, @dim),
     Fixtures.solid_linear_rgb(@dim, @dim, 0.5)}
  ]

  for {fmt, ref_bin, alt_bin} <- @cases do
    @fmt fmt
    @ref_bin ref_bin
    @alt_bin alt_bin

    describe "format #{fmt}" do
      test "identical images score near zero (< 1.0)" do
        assert {:ok, %Result{score: s}} =
                 Butteraugli.compare(@ref_bin, @ref_bin, @dim, @dim, format: @fmt)

        assert s < 1.0
      end

      test "different images score higher than identical" do
        {:ok, %Result{score: same}} =
          Butteraugli.compare(@ref_bin, @ref_bin, @dim, @dim, format: @fmt)

        {:ok, %Result{score: diff}} =
          Butteraugli.compare(@ref_bin, @alt_bin, @dim, @dim, format: @fmt)

        assert diff > same
      end

      test "rejects a wrong-size binary" do
        assert {:error, :size_mismatch} =
                 Butteraugli.compare(@ref_bin, <<0, 1, 2>>, @dim, @dim, format: @fmt)
      end
    end
  end

  test "unknown format is rejected" do
    img = Fixtures.gradient(8, 8)
    assert {:error, :unknown_format} = Butteraugli.compare(img, img, 8, 8, format: :bogus)
  end

  test "default format is :rgb888" do
    img = Fixtures.gradient(64, 64)

    assert {:ok, %Result{score: with_opt}} =
             Butteraugli.compare(img, img, 64, 64, format: :rgb888)

    assert {:ok, %Result{score: default}} = Butteraugli.compare(img, img, 64, 64)
    # in_delta, not ==: both calls take the identical path, but rayon FP-reduction
    # order can jitter the low bits, so don't assert bit-exact equality.
    assert_in_delta with_opt, default, 1.0e-4
  end

  # A 1-byte prefix makes binary_part return a sub-binary at a misaligned byte
  # offset; the linear_rgb path must copy into an aligned buffer and not crash.
  defp misaligned(bin), do: binary_part(<<0>> <> bin, 1, byte_size(bin))

  test "scores an unaligned :linear_rgb sub-binary without crashing" do
    base = Fixtures.gradient_linear_rgb(16, 16)
    shifted = misaligned(base)
    assert byte_size(shifted) == byte_size(base)

    assert {:ok, %Result{score: s}} =
             Butteraugli.compare(shifted, shifted, 16, 16, format: :linear_rgb)

    assert s < 1.0
  end
end
