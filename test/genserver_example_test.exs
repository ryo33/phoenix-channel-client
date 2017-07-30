defmodule PhoenixChannelClient.GenServerExampleText do
  use ExUnit.Case

  defmodule ChannelClient do
    use GenServer
    def start_link(channel, opts) do
      GenServer.start_link(__MODULE__, [channel: channel, opts: opts], name: __MODULE__)
    end
    def init([channel: channel, opts: opts]) do
      state = %{
        handlers: opts[:handlers]
      }
      case PhoenixChannelClient.join(channel) do
        {:ok, _} -> {:ok, state}
        {:error, reason} -> {:stop, reason}
        :timeout -> {:stop, :timeout}
      end
    end
    def handle_info({event, payload}, state) do
      case Map.get(state.handlers, event) do
        handler when not is_nil(handler) -> handler.(payload)
        _ -> :ok
      end
      {:noreply, state}
    end
  end

  @host "localhost"
  @path "/socket/websocket"
  @params %{authenticated: "true"}
  @port 4000
  @opts [
    host: @host,
    port: @port,
    path: @path,
    params: @params]

  test "example" do
    mypid = self()
    {:ok, pid} = PhoenixChannelClient.start_link()
    {:ok, socket} = PhoenixChannelClient.connect(pid, @opts)
    topic = "timer"
    params = %{}
    channel = PhoenixChannelClient.channel(socket, topic, params)
    handlers = %{
      "timer" => fn payload ->
        send mypid, {"timer", payload}
      end
    }
    ChannelClient.start_link(channel, handlers: handlers)
    assert_receive {"timer", %{"count" => 1}}
    assert_receive {"timer", %{"count" => 2}}
    assert_receive {"timer", %{"count" => 3}}
  end
end
