defmodule Butteraugli.Error do
  @moduledoc "Raised by the `!` variants when a comparison fails."
  defexception [:reason]

  @impl true
  def message(%__MODULE__{reason: reason}) do
    "butteraugli comparison failed: #{inspect(reason)}"
  end
end
