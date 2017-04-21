defmodule PhoenixChannelClient.Mixfile do
  use Mix.Project

  def project do
    [app: :phoenix_channel_client,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:socket, "~> 0.3.11"},
     {:poison, "~> 2.0"},
     {:flow, "~> 0.11"},
     {:test_server, path: "test_server", only: :test}]
  end
end
