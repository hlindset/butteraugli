defmodule Butteraugli.Result do
  @moduledoc """
  The outcome of a butteraugli comparison.

  `score` is the max-norm perceptual distance — the historical butteraugli
  score, where `< 1.0` is visually identical and `> 2.0` is a visible
  difference. `pnorm_3` is libjxl's 3-norm aggregation of the difference map.
  `diffmap` is `nil` unless the comparison ran with `compute_diffmap: true`, in
  which case it is a packed, native-endian `f32` binary of `width * height`
  values (row-major, single channel) matching the input dimensions.
  """

  @enforce_keys [:score, :pnorm_3]
  defstruct [:score, :pnorm_3, :diffmap]

  @type t :: %__MODULE__{
          score: float(),
          pnorm_3: float(),
          diffmap: binary() | nil
        }

  @doc false
  # Wrap an orchestrated result: a success tuple becomes a Result; any error
  # (already mapped by Butteraugli.Cancellation) passes straight through.
  def from_native({:ok, {score, pnorm_3, diffmap}}),
    do: {:ok, %__MODULE__{score: score, pnorm_3: pnorm_3, diffmap: diffmap}}

  def from_native({:error, reason}), do: {:error, reason}
end
