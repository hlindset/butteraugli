defmodule Butteraugli.CancelRef do
  @moduledoc """
  A cancellation handle for aborting an in-flight `Butteraugli.compare/5` or
  `Butteraugli.Reference.compare/3`.

  The ref is a neutral primitive — *you* assign it meaning. Create one with
  `new/0`, pass it as `cancel: cancel_ref`, and call `Butteraugli.cancel/1` from
  any process (e.g. a client-disconnect monitor or a search deadline) to abort
  the comparison. The aborted call returns `{:error, :cancelled}`.

  A ref is **single-use**: once cancelled it stays cancelled. One ref can cover a
  whole batch — cancelling it aborts the in-flight comparison and makes every
  subsequent comparison using it return `{:error, :cancelled}` at once.
  """

  alias Butteraugli.Native

  @enforce_keys [:resource]
  defstruct [:resource]

  @type t :: %__MODULE__{resource: reference()}

  @doc "Create a fresh, live (not-yet-cancelled) cancel ref."
  @spec new() :: t()
  def new(), do: %__MODULE__{resource: Native.token_new()}
end
