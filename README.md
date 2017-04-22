# PhoenixChannelClient

## Usage
Add `{:phoenixchannelclient, "~> 0.1.0"}` to deps.

## Example
```elixir
{:ok, pid} = PhoenixChannelClient.start_link()

{:ok, socket} = PhoenixChannelClient.connect(pid,
  host: "localhost",
  path: "/socket/websocket",
  params: %{token: "something"},
  secure: false)

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
end

:ok = PhoenixChannelClient.leave(channel)
```
