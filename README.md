# PhoenixChannelClient

## Usage
Add `{:phoenixchannelclient, "~> 0.1.0"}` to deps.

## Examples

### Basic usage

```elixir
{:ok, pid} = PhoenixChannelClient.start_link()

{:ok, socket} = PhoenixChannelClient.connect(pid,
  host: "localhost",
  path: "/socket/websocket",
  params: %{token: "something"},
  secure: false,
  heartbeat_interval: 30_000)

channel = PhoenixChannelClient.channel(socket, "room:public", %{name: "Ryo"})

case PhoenixChannelClient.join(channel) do
  {:ok, %{message: message}} -> IO.puts(message)
  {:error, %{reason: reason}} -> IO.puts(reason)
  :timeout -> IO.puts("timeout")
end

case PhoenixChannelClient.push_and_receive(channel, "search", %{query: "Elixir"}, 100) do
  {:ok, %{result: result}} -> IO.puts("#\{length(result)} items")
  {:error, %{reason: reason}} -> IO.puts(reason)
  :timeout -> IO.puts("timeout")
end

receive do
  {"new_msg", message} -> IO.puts(message)
  :close -> IO.puts("closed")
  {:error, error} -> ()
end

:ok = PhoenixChannelClient.leave(channel)
```

### Receiving messages continuously by using GenServer

```elixir
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

handers = %{
  "event1" => fn payload -> Handler.event1(payload) end,
  "event2" => fn payload -> Handler.event2(payload) end
}
ChannelClient.start_link(channel, handlers: handlers)
```
