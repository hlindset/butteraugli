defmodule Butteraugli.ReferenceTest do
  use ExUnit.Case, async: true
  alias Butteraugli.{Fixtures, Reference, Result}

  test "new/4 + compare/2 returns Results with the expected ordering" do
    ref_img = Fixtures.gradient(64, 64)
    cand = Fixtures.solid(64, 64, {128, 128, 128})

    assert {:ok, ref} = Reference.new(ref_img, 64, 64)
    assert {:ok, %Result{score: identical}} = Reference.compare(ref, ref_img)
    assert {:ok, %Result{score: different}} = Reference.compare(ref, cand)
    assert identical < 1.0
    assert different > identical
  end

  test "new/4 + compare/2 matches one-shot compare/5 within epsilon" do
    ref_img = Fixtures.gradient(64, 64)
    cand = Fixtures.solid(64, 64, {200, 100, 50})

    {:ok, %Result{score: oneshot}} = Butteraugli.compare(ref_img, cand, 64, 64)
    {:ok, ref} = Reference.new(ref_img, 64, 64)
    {:ok, %Result{score: batch}} = Reference.compare(ref, cand)

    assert_in_delta oneshot, batch, 1.0e-4
  end

  test "compare/2 rejects a candidate of the wrong size" do
    {:ok, ref} = Reference.new(Fixtures.gradient(64, 64), 64, 64)
    assert {:error, :size_mismatch} = Reference.compare(ref, Fixtures.solid(32, 32, {0, 0, 0}))
  end

  test "new/4 validates dimensions and size" do
    assert {:error, :invalid_dimensions} = Reference.new(<<>>, 0, 0)
    assert {:error, :size_mismatch} = Reference.new(Fixtures.solid(4, 3, {0, 0, 0}), 4, 4)
  end

  test "compute_diffmap baked at new/4 yields per-pixel diffmaps" do
    ref_img = Fixtures.gradient(32, 32)
    cand = Fixtures.solid(32, 32, {10, 20, 30})
    {:ok, ref} = Reference.new(ref_img, 32, 32, compute_diffmap: true)
    assert {:ok, %Result{diffmap: diffmap}} = Reference.compare(ref, cand)
    assert byte_size(diffmap) == 32 * 32 * 4
  end

  describe "bang variants" do
    test "new!/4 returns a reference and compare!/2 returns a bare Result" do
      ref = Reference.new!(Fixtures.gradient(32, 32), 32, 32)
      assert %Reference{} = ref
      assert %Result{score: s} = Reference.compare!(ref, Fixtures.gradient(32, 32))
      assert s < 1.0
    end

    test "new!/4 raises on bad input" do
      assert_raise Butteraugli.Error, fn -> Reference.new!(<<>>, 0, 0) end
    end

    test "new!/4 raises on an unknown format" do
      assert_raise Butteraugli.Error, fn ->
        Reference.new!(Fixtures.gradient(8, 8), 8, 8, format: :bogus)
      end
    end

    test "compare!/2 raises on a wrong-size candidate" do
      ref = Reference.new!(Fixtures.gradient(16, 16), 16, 16)
      assert_raise Butteraugli.Error, fn -> Reference.compare!(ref, <<0, 1, 2>>) end
    end
  end

  # {format, reference binary, a different candidate binary}
  @parity_cases [
    {:rgb888, Fixtures.gradient(64, 64), Fixtures.solid(64, 64, {128, 128, 128})},
    {:linear_rgb, Fixtures.gradient_linear_rgb(64, 64), Fixtures.solid_linear_rgb(64, 64, 0.5)}
  ]

  for {fmt, ref_img, cand} <- @parity_cases do
    @fmt fmt
    @ref_img ref_img
    @cand cand

    test "new/4 + compare/2 matches one-shot compare for #{fmt}" do
      {:ok, %Result{score: oneshot}} = Butteraugli.compare(@ref_img, @cand, 64, 64, format: @fmt)
      {:ok, ref} = Reference.new(@ref_img, 64, 64, format: @fmt)
      {:ok, %Result{score: batch}} = Reference.compare(ref, @cand)

      assert_in_delta oneshot, batch, 1.0e-4
    end
  end

  test "new/4 rejects an unknown format" do
    assert {:error, :unknown_format} =
             Reference.new(Fixtures.gradient(8, 8), 8, 8, format: :bogus)
  end
end
