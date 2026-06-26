defmodule Butteraugli.MixProject do
  use Mix.Project

  def project do
    [
      app: :butteraugli,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Butteraugli perceptual image-difference metric for Elixir (butteraugli NIF)",
      package: package(),
      name: "Butteraugli",
      source_url: "https://github.com/hlindset/butteraugli",
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["BSD-3-Clause"],
      links: %{
        "GitHub" => "https://github.com/hlindset/butteraugli",
        "butteraugli" => "https://github.com/imazen/butteraugli"
      },
      files: ~w(lib native/butteraugli_nif/src native/butteraugli_nif/Cargo.toml
                native/butteraugli_nif/Cargo.lock mix.exs README.md CHANGELOG.md
                checksum-*.exs)
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler_precompiled, "~> 0.9"},
      {:rustler, ">= 0.0.0", optional: true},
      {:vix, "~> 0.31", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
