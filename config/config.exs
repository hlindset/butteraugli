import Config
if config_env() in [:dev, :test], do: config(:butteraugli, force_build: true)
