defmodule Butteraugli.Native do
  @moduledoc false

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :butteraugli,
    crate: "butteraugli_nif",
    base_url: "https://github.com/hlindset/butteraugli/releases/download/v#{version}",
    version: version,
    force_build:
      System.get_env("BUTTERAUGLI_BUILD") in ["1", "true"] or
        Application.compile_env(:butteraugli, :force_build, false),
    nif_versions: ["2.15", "2.16", "2.17"],
    targets: ~w(
      aarch64-apple-darwin
      x86_64-apple-darwin
      x86_64-unknown-linux-gnu
      aarch64-unknown-linux-gnu
      x86_64-unknown-linux-musl
      aarch64-unknown-linux-musl
      x86_64-pc-windows-msvc
    )

  def nif_loaded, do: :erlang.nif_error(:nif_not_loaded)

  def token_new, do: :erlang.nif_error(:nif_not_loaded)

  def token_cancel(_token), do: :erlang.nif_error(:nif_not_loaded)

  def compare(_ref, _dist, _w, _h, _fmt, _intensity, _hf, _diffmap, _cancel),
    do: :erlang.nif_error(:nif_not_loaded)

  def reference_new(_src, _w, _h, _fmt, _intensity, _hf, _diffmap),
    do: :erlang.nif_error(:nif_not_loaded)

  def reference_compare(_ref, _dist, _cancel), do: :erlang.nif_error(:nif_not_loaded)
end
