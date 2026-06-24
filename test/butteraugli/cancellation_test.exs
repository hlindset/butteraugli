defmodule Butteraugli.CancellationTest do
  # async: false — the cross-process/timeout tests run large comparisons whose
  # wall-clock must dominate the cancel/timer; running them serially keeps dirty
  # schedulers uncontended so timing stays predictable.
  use ExUnit.Case, async: false
  alias Butteraugli.{CancelRef, Fixtures, Reference, Result}

  test "compare/5 with a pre-cancelled token returns {:error, :cancelled}" do
    img = Fixtures.gradient(512, 512)
    tok = CancelRef.new()
    :ok = Butteraugli.cancel(tok)
    assert {:error, :cancelled} = Butteraugli.compare(img, img, 512, 512, cancel: tok)
  end

  test "Reference.compare/3 with a pre-cancelled token returns {:error, :cancelled}" do
    img = Fixtures.gradient(512, 512)
    {:ok, ref} = Reference.new(img, 512, 512)
    tok = CancelRef.new()
    :ok = Butteraugli.cancel(tok)
    assert {:error, :cancelled} = Reference.compare(ref, img, cancel: tok)
  end

  test "a live token does not affect the result" do
    a = Fixtures.gradient(64, 64)
    b = Fixtures.solid(64, 64, {200, 100, 50})
    tok = CancelRef.new()
    {:ok, %Result{score: plain}} = Butteraugli.compare(a, b, 64, 64)
    {:ok, %Result{score: with_tok}} = Butteraugli.compare(a, b, 64, 64, cancel: tok)
    # 1.0e-4 (not 1.0e-9): butteraugli builds with rayon by default, so a bare
    # score may differ in the low bits run-to-run from parallel FP reduction. A
    # token must not change the score meaningfully — 1.0e-4 still catches that.
    assert_in_delta plain, with_tok, 1.0e-4
  end

  test "a live token does not affect Reference.compare" do
    a = Fixtures.gradient(64, 64)
    b = Fixtures.solid(64, 64, {200, 100, 50})
    {:ok, ref} = Reference.new(a, 64, 64)
    tok = CancelRef.new()
    {:ok, %Result{score: plain}} = Reference.compare(ref, b)
    {:ok, %Result{score: with_tok}} = Reference.compare(ref, b, cancel: tok)
    # 1.0e-4 (not 1.0e-9): butteraugli builds with rayon by default, so a bare
    # score may differ in the low bits run-to-run from parallel FP reduction. A
    # token must not change the score meaningfully — 1.0e-4 still catches that.
    assert_in_delta plain, with_tok, 1.0e-4
  end

  test "cancelling from another process aborts an in-flight compare" do
    # 3000x3000 (~9 MP): the metric runs well past the ~10 ms head start below,
    # so the cancel reliably lands mid-flight on idle CI too.
    big = Fixtures.solid(3000, 3000, {123, 50, 200})

    {full_us, {:ok, _}} = :timer.tc(fn -> Butteraugli.compare(big, big, 3000, 3000) end)

    tok = CancelRef.new()
    parent = self()

    task =
      Task.async(fn ->
        send(parent, :started)
        Butteraugli.compare(big, big, 3000, 3000, cancel: tok)
      end)

    assert_receive :started, 1000
    Process.sleep(10)
    Butteraugli.cancel(tok)

    {abort_us, result} = :timer.tc(fn -> Task.await(task, 30_000) end)
    assert {:error, :cancelled} = result
    # Proves the abort was mid-flight, not run-to-completion.
    assert abort_us < full_us / 2
  end

  test "cancelling from another process aborts an in-flight :linear_rgb compare" do
    # Same rationale as the sRGB mid-flight test above. As of butteraugli
    # 4e78d6d, :linear_rgb ≥ 8×8 takes the strip path (butteraugli_linear_strip_with_stop),
    # so a cancel lands mid-flight rather than once-at-entry.
    big = Fixtures.solid_linear_rgb(3000, 3000, 0.5)
    opts = [format: :linear_rgb]

    {full_us, {:ok, _}} = :timer.tc(fn -> Butteraugli.compare(big, big, 3000, 3000, opts) end)

    tok = CancelRef.new()
    parent = self()

    task =
      Task.async(fn ->
        send(parent, :started)
        Butteraugli.compare(big, big, 3000, 3000, [cancel: tok] ++ opts)
      end)

    assert_receive :started, 1000
    Process.sleep(10)
    Butteraugli.cancel(tok)

    {abort_us, result} = :timer.tc(fn -> Task.await(task, 30_000) end)
    assert {:error, :cancelled} = result
    # Proves the abort was mid-flight, not run-to-completion.
    assert abort_us < full_us / 2
  end

  # NOTE (deviation from plan): ButteraugliReference::compare_with_stop checks
  # the stop signal only ONCE at entry (before any heavy computation). Mid-flight
  # cancellation of Reference.compare does NOT abort reliably — if the signal
  # arrives after that single check, the comparison runs to completion.
  # This is a documented crate characteristic ("stop is checked once at the
  # outermost per-scale boundary"). The pre-cancelled token path (tested above)
  # works correctly. This test is replaced with a note about the limitation.
  test "Reference.compare/3 cancellation at entry is caught (mid-flight not guaranteed)" do
    # The crate checks stop once at entry. A pre-cancelled token is caught;
    # a token cancelled mid-flight may or may not be caught depending on timing.
    # Verify the entry-check path is wired correctly (already covered above).
    img = Fixtures.solid(64, 64, {123, 50, 200})
    {:ok, ref} = Reference.new(img, 64, 64)
    tok = CancelRef.new()
    :ok = Butteraugli.cancel(tok)
    assert {:error, :cancelled} = Reference.compare(ref, img, cancel: tok)
  end

  test "Reference.compare/3 prefer: :memory yields the same score as :speed" do
    a = Fixtures.gradient(300, 300)
    b = Fixtures.solid(300, 300, {200, 100, 50})
    {:ok, ref} = Reference.new(a, 300, 300)
    {:ok, %Result{score: speed}} = Reference.compare(ref, b, prefer: :speed)
    {:ok, %Result{score: memory}} = Reference.compare(ref, b, prefer: :memory)
    # 1.0e-4: same rayon FP-reduction nondeterminism note as the live-token tests.
    assert_in_delta speed, memory, 1.0e-4
  end

  test "Reference.compare/3 with prefer: :memory aborts an in-flight compare" do
    # The default :speed (warm) path checks the token only at entry, so it cannot
    # be cancelled mid-flight; :memory uses the strip walker, which can. 3000x3000
    # runs well past the ~10 ms head start, so the cancel lands mid-flight.
    big = Fixtures.solid(3000, 3000, {123, 50, 200})
    {:ok, ref} = Reference.new(big, 3000, 3000)

    {full_us, {:ok, _}} = :timer.tc(fn -> Reference.compare(ref, big, prefer: :memory) end)

    tok = CancelRef.new()
    parent = self()

    task =
      Task.async(fn ->
        send(parent, :started)
        Reference.compare(ref, big, cancel: tok, prefer: :memory)
      end)

    assert_receive :started, 1000
    Process.sleep(10)
    Butteraugli.cancel(tok)

    {abort_us, result} = :timer.tc(fn -> Task.await(task, 30_000) end)
    assert {:error, :cancelled} = result
    # Proves the abort was mid-flight, not run-to-completion.
    assert abort_us < full_us / 2
  end

  test "an invalid :prefer value is rejected" do
    a = Fixtures.gradient(64, 64)
    b = Fixtures.solid(64, 64, {200, 100, 50})
    {:ok, ref} = Reference.new(a, 64, 64)
    assert {:error, :invalid_prefer} = Reference.compare(ref, b, prefer: :fastest)
  end

  test "a cancelled token aborts every subsequent comparison" do
    a = Fixtures.gradient(64, 64)
    b = Fixtures.solid(64, 64, {200, 100, 50})
    tok = CancelRef.new()
    :ok = Butteraugli.cancel(tok)

    assert {:error, :cancelled} = Butteraugli.compare(a, b, 64, 64, cancel: tok)
    assert {:error, :cancelled} = Butteraugli.compare(a, b, 64, 64, cancel: tok)
  end

  test "compare!/5 raises on cancellation" do
    img = Fixtures.gradient(256, 256)
    tok = CancelRef.new()
    :ok = Butteraugli.cancel(tok)

    assert_raise Butteraugli.Error, fn ->
      Butteraugli.compare!(img, img, 256, 256, cancel: tok)
    end
  end

  test "Reference.compare!/3 raises on cancellation" do
    img = Fixtures.gradient(256, 256)
    {:ok, ref} = Reference.new(img, 256, 256)
    tok = CancelRef.new()
    :ok = Butteraugli.cancel(tok)
    assert_raise Butteraugli.Error, fn -> Reference.compare!(ref, img, cancel: tok) end
  end

  test "an invalid :cancel value is rejected" do
    img = Fixtures.gradient(64, 64)
    assert {:error, :invalid_cancel} = Butteraugli.compare(img, img, 64, 64, cancel: :nope)
  end

  test "compare/5 returns {:error, :timeout} when it exceeds :timeout" do
    big = Fixtures.solid(2500, 2500, {10, 20, 30})
    assert {:error, :timeout} = Butteraugli.compare(big, big, 2500, 2500, timeout: 1)
  end

  test "Reference.compare/3 returns {:error, :timeout} when it exceeds :timeout" do
    big = Fixtures.solid(2500, 2500, {10, 20, 30})
    {:ok, ref} = Reference.new(big, 2500, 2500)
    assert {:error, :timeout} = Reference.compare(ref, big, timeout: 1)
  end

  test "a generous :timeout returns the same score as no timeout" do
    a = Fixtures.gradient(64, 64)
    b = Fixtures.solid(64, 64, {200, 100, 50})
    {:ok, %Result{score: plain}} = Butteraugli.compare(a, b, 64, 64)
    {:ok, %Result{score: timed}} = Butteraugli.compare(a, b, 64, 64, timeout: 60_000)
    # 1.0e-4: see the live-token note above (rayon FP-reduction nondeterminism).
    assert_in_delta plain, timed, 1.0e-4
  end

  test "external cancel during a timed call is reported as :cancelled, not :timeout" do
    big = Fixtures.solid(3000, 3000, {1, 2, 3})
    tok = CancelRef.new()
    parent = self()

    task =
      Task.async(fn ->
        send(parent, :started)
        Butteraugli.compare(big, big, 3000, 3000, cancel: tok, timeout: 60_000)
      end)

    assert_receive :started, 1000
    Process.sleep(10)
    Butteraugli.cancel(tok)

    assert {:error, :cancelled} = Task.await(task, 30_000)
  end

  test "compare!/5 raises on timeout" do
    big = Fixtures.solid(2500, 2500, {10, 20, 30})

    assert_raise Butteraugli.Error, fn ->
      Butteraugli.compare!(big, big, 2500, 2500, timeout: 1)
    end
  end

  test "an invalid :timeout value is rejected" do
    img = Fixtures.gradient(64, 64)
    assert {:error, :invalid_timeout} = Butteraugli.compare(img, img, 64, 64, timeout: 0)
    assert {:error, :invalid_timeout} = Butteraugli.compare(img, img, 64, 64, timeout: -5)
    assert {:error, :invalid_timeout} = Butteraugli.compare(img, img, 64, 64, timeout: 1.5)
    assert {:error, :invalid_timeout} = Butteraugli.compare(img, img, 64, 64, timeout: "100")
  end
end
