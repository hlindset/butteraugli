defmodule Butteraugli.Cancellation do
  @moduledoc false
  # Shared cancellation/timeout orchestration for compare and Reference.compare.

  alias Butteraugli.CancelRef

  # `invoke` is a 1-arity fun taking the ref resource (or nil) and returning
  # the raw native result: {:ok, {score, pnorm_3, diffmap}}
  #                        | {:error, :cancelled} | {:error, {:failed, msg}}.
  @spec run(CancelRef.t() | nil, pos_integer() | nil, (reference() | nil -> term())) ::
          {:ok, {float(), float(), binary() | nil}}
          | {:error, :cancelled | :timeout | {:butteraugli, String.t()}}
  def run(cancel, nil, invoke) do
    resource = token_resource(cancel)
    invoke.(resource) |> map_result(:not_timed_out)
  end

  def run(cancel, timeout, invoke) when is_integer(timeout) and timeout > 0 do
    ref = cancel || CancelRef.new()
    parent = self()
    tag = make_ref()

    # The caller blocks in the dirty NIF and cannot clean up while parked there,
    # so the canceller is wired with mutual monitoring: it exits if the parent
    # dies mid-NIF (no orphan living for the full timeout), and the parent's
    # status receive can't block forever if the canceller dies abnormally.
    {canceller, cref} =
      spawn_monitor(fn ->
        parent_ref = Process.monitor(parent)

        receive do
          {:done, ^tag} -> send(parent, {:status, tag, :not_timed_out})
          {:DOWN, ^parent_ref, :process, ^parent, _} -> :ok
        after
          timeout ->
            Butteraugli.cancel(ref)
            send(parent, {:status, tag, :timed_out})
        end
      end)

    result = invoke.(ref.resource)
    send(canceller, {:done, tag})

    status =
      receive do
        {:status, ^tag, s} -> s
        {:DOWN, ^cref, :process, _, _} -> :not_timed_out
      end

    Process.demonitor(cref, [:flush])
    map_result(result, status)
  end

  defp token_resource(%CancelRef{resource: r}), do: r
  defp token_resource(nil), do: nil

  defp map_result({:ok, value}, _status), do: {:ok, value}
  defp map_result({:error, :cancelled}, :timed_out), do: {:error, :timeout}
  defp map_result({:error, :cancelled}, _status), do: {:error, :cancelled}
  defp map_result({:error, {:failed, message}}, _status), do: {:error, {:butteraugli, message}}
end
