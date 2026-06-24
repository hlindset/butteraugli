defmodule Butteraugli.StripParityTest do
  @moduledoc """
  Guards the sRGB strip-with-stop path for ≥8px inputs. Butteraugli is a
  different metric than ssim2 (no portable golden numbers, and no separate
  non-strip reference to diff against), so instead of locking an absolute score
  this asserts the strip one-shot path agrees with the reference path, and that
  sub-8px inputs still score via the non-strip path.
  """
  use ExUnit.Case, async: true
  alias Butteraugli.{Fixtures, Reference, Result}

  test "sRGB strip one-shot (>=8px) agrees with the reference path" do
    ref_img = Fixtures.gradient(64, 64)
    cand = Fixtures.solid(64, 64, {200, 100, 50})
    {:ok, %Result{score: oneshot}} = Butteraugli.compare(ref_img, cand, 64, 64)
    {:ok, ref} = Reference.new(ref_img, 64, 64)
    {:ok, %Result{score: batch}} = Reference.compare(ref, cand)
    assert_in_delta oneshot, batch, 1.0e-4
  end

  # NOTE (deviation from plan): ButteraugliReference::new enforces a minimum 8x8
  # and returns {:error, {:butteraugli, "invalid dimensions: ..."}}} for sub-8px
  # inputs — the crate does not support precomputed references for tiny images.
  # The one-shot path (butteraugli_with_stop) pads internally and works fine.
  # Adjusted: verify one-shot scores (non-strip path taken), and that Reference.new
  # rejects sub-8px rather than incorrectly asserting it succeeds.
  test "an image smaller than 8px still scores via one-shot (non-strip path)" do
    img = Fixtures.gradient(6, 6)
    assert {:ok, %Result{score: oneshot}} = Butteraugli.compare(img, img, 6, 6)
    assert oneshot < 1.0
  end

  test "Reference.new rejects sub-8px images (crate minimum is 8x8)" do
    img = Fixtures.gradient(6, 6)
    assert {:error, {:butteraugli, msg}} = Reference.new(img, 6, 6)
    assert msg =~ "invalid dimensions"
  end
end
