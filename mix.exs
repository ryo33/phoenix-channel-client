defmodule PhoenixChannelClient.Mixfile do
  use Mix.Project

  def project do
    [app: :phoenixchannelclient,
     description: "Phoenix Channel Client",
     package: package(),
     version: "0.1.2",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def package do
    [name: :phoenixchannelclient,
     licenses: ["MIT"],
     maintainers: ["Ryo Hashiguchi"],
     links: %{"GitHub" => "https://github.com/ryo33/phoenix-channel-client"}]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:socket, "~> 0.3.11"},
     {:poison, "~> 2.0"},
     {:flow, "~> 0.11"},
     {:test_server, path: "test_server", only: :test},
     {:ex_doc, "~> 0.14", only: :dev, runtime: false}]
  end
end
