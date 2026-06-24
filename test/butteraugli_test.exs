defmodule ButteraugliTest do
  use ExUnit.Case, async: true
  alias Butteraugli.{Fixtures, Result}

  test "native library loads" do
    assert Butteraugli.Native.nif_loaded() == true
  end

  describe "compare/5 validation" do
    test "rejects non-positive dimensions" do
      assert {:error, :invalid_dimensions} = Butteraugli.compare(<<>>, <<>>, 0, 10)
      assert {:error, :invalid_dimensions} = Butteraugli.compare(<<>>, <<>>, 10, -1)
    end

    test "rejects a reference binary whose size != w*h*3" do
      good = Fixtures.solid(4, 4, {1, 2, 3})
      bad = Fixtures.solid(4, 3, {1, 2, 3})
      assert {:error, :size_mismatch} = Butteraugli.compare(bad, good, 4, 4)
    end

    test "rejects a distorted binary whose size != w*h*3" do
      good = Fixtures.solid(4, 4, {1, 2, 3})
      bad = Fixtures.solid(4, 3, {1, 2, 3})
      assert {:error, :size_mismatch} = Butteraugli.compare(good, bad, 4, 4)
    end

    test "rejects an unknown format" do
      img = Fixtures.solid(4, 4, {1, 2, 3})
      assert {:error, :unknown_format} = Butteraugli.compare(img, img, 4, 4, format: :bogus)
    end
  end

  describe "compare/5 scoring" do
    test "identical images score near zero (< 1.0)" do
      img = Fixtures.gradient(64, 64)

      assert {:ok, %Result{score: score, pnorm_3: pnorm_3, diffmap: nil}} =
               Butteraugli.compare(img, img, 64, 64)

      assert score < 1.0
      assert is_float(pnorm_3)
    end

    test "different images score higher than identical" do
      a = Fixtures.gradient(64, 64)
      b = Fixtures.solid(64, 64, {128, 128, 128})
      assert {:ok, %Result{score: identical}} = Butteraugli.compare(a, a, 64, 64)
      assert {:ok, %Result{score: different}} = Butteraugli.compare(a, b, 64, 64)
      assert different > identical
    end
  end

  describe "compute_diffmap" do
    test "returns a per-pixel f32 diffmap binary when requested" do
      a = Fixtures.gradient(32, 32)
      b = Fixtures.solid(32, 32, {128, 128, 128})

      assert {:ok, %Result{diffmap: diffmap}} =
               Butteraugli.compare(a, b, 32, 32, compute_diffmap: true)

      assert is_binary(diffmap)
      assert byte_size(diffmap) == 32 * 32 * 4
    end

    test "diffmap is nil by default" do
      img = Fixtures.gradient(16, 16)
      assert {:ok, %Result{diffmap: nil}} = Butteraugli.compare(img, img, 16, 16)
    end

    test "linear_rgb also produces a diffmap when requested" do
      a = Fixtures.gradient_linear_rgb(32, 32)
      b = Fixtures.solid_linear_rgb(32, 32, 0.5)

      assert {:ok, %Result{diffmap: diffmap}} =
               Butteraugli.compare(a, b, 32, 32, format: :linear_rgb, compute_diffmap: true)

      assert byte_size(diffmap) == 32 * 32 * 4
    end
  end

  describe "tuning parameters" do
    test "intensity_target is accepted and returns a Result" do
      a = Fixtures.gradient(64, 64)
      b = Fixtures.solid(64, 64, {128, 128, 128})
      assert {:ok, %Result{score: s}} = Butteraugli.compare(a, b, 64, 64, intensity_target: 250.0)
      assert is_float(s)
    end

    test "hf_asymmetry is accepted and returns a Result" do
      a = Fixtures.gradient(64, 64)
      b = Fixtures.solid(64, 64, {128, 128, 128})
      assert {:ok, %Result{}} = Butteraugli.compare(a, b, 64, 64, hf_asymmetry: 2.0)
    end
  end

  describe "compare!/5" do
    test "returns the bare Result on success" do
      img = Fixtures.gradient(32, 32)
      assert %Result{score: score} = Butteraugli.compare!(img, img, 32, 32)
      assert score < 1.0
    end

    test "raises Butteraugli.Error on bad input" do
      assert_raise Butteraugli.Error, fn -> Butteraugli.compare!(<<>>, <<>>, 0, 0) end
    end

    test "compares linear_rgb input" do
      img = Fixtures.gradient_linear_rgb(32, 32)
      assert %Result{score: score} = Butteraugli.compare!(img, img, 32, 32, format: :linear_rgb)
      assert score < 1.0
    end
  end
end
