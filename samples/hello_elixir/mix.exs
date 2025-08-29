defmodule HelloElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :hello_elixir,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      deps: deps(),
      releases: releases(),
      make_cwd: "c_src",
      make_targets: ["all"],
      make_clean: ["clean"],
      make_env: %{}
    ]
  end

  def application do
    [
      mod: {HelloElixir.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.7", runtime: false}
    ]
  end

  defp releases do
    [
      hello_elixir: [
        include_erts: true,
        include_executables_for: [:unix],
        strip_beams: true
      ]
    ]
  end
end
