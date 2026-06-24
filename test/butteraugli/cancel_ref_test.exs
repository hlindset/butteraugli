defmodule Butteraugli.CancelRefNativeTest do
  use ExUnit.Case, async: true
  alias Butteraugli.Native

  test "token_new/0 returns a resource reference" do
    assert is_reference(Native.token_new())
  end

  test "token_cancel/1 returns :ok and is idempotent" do
    tok = Native.token_new()
    assert :ok = Native.token_cancel(tok)
    assert :ok = Native.token_cancel(tok)
  end
end

defmodule Butteraugli.CancelRefTest do
  use ExUnit.Case, async: true
  alias Butteraugli.CancelRef

  test "new/0 returns a struct wrapping a resource" do
    cancel_ref = CancelRef.new()
    assert %CancelRef{resource: r} = cancel_ref
    assert is_reference(r)
  end

  test "Butteraugli.cancel/1 returns :ok" do
    cancel_ref = CancelRef.new()
    assert :ok = Butteraugli.cancel(cancel_ref)
  end
end
