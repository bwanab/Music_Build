defmodule MusicBuild.MixProject do
  use Mix.Project

  def project do
    [
      app: :music_build,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

    defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bwanab/music_build"}
    ]
  end


  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      #{:music_prims, path: "../music_prims", force: true},
      {:music_prims, github: "bwanab/music_prims"},
      {:midifile, github: "bwanab/elixir-midifile"},
      {:better_weighted_random, "~> 0.1"},
      {:csv, "~> 3.2"}
    ]
  end
end
