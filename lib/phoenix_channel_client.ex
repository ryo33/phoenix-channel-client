defmodule PhoenixChannelClient do
  use GenServer

  defmodule Channel do
    defstruct [:socket, :topic, :params]
  end

  defmodule Socket do
    defstruct [:server_name]
  end

  defmodule Subscription do
    defstruct [:name, :pid, :matcher, :mapper]
  end

  alias Elixir.Socket.Web, as: WebSocket

  @type channel :: %Channel{}
  @type socket :: %Socket{}
  @type subscription :: %Subscription{}

  @type ok_result :: {:ok, term}
  @type error_result :: {:error, term}
  @type timeout_result :: :timeout
  @type result :: ok_result | error_result | timeout_result
  @type send_result :: :ok | {:error, term}
  @type connect_error :: {:error, term}

  @default_timeout 5000
  @max_timeout 60000 # 1 minute

  @phoenix_vsn Application.get_env(:phoenix_channel_client, PhoenixChannelClient)[:vsn]

  @event_join "phx_join"
  @event_reply "phx_reply"
  @event_leave "phx_leave"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def start(opts \\ []) do
    GenServer.start(__MODULE__, :ok, opts)
  end

  def init(_opts) do
    initial_state = %{
      ref: 0,
      socket: nil,
      recv_loop_pid: nil,
      subscriptions: %{},
      connection_address: nil,
      connection_opts: nil
    }
    {:ok, initial_state}
  end

  @doc """
  Connects to the specified websocket.

  ### Options
  * `:host`
  * `:port`
  * `:path`
  * `:params`
  """
  @spec connect(term, keyword) :: {:ok, socket} | connect_error
  def connect(name, opts) do
    case GenServer.call(name, {:connect, opts}) do
      :ok -> {:ok, %Socket{server_name: name}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reconnect(socket) :: :ok | connect_error
  def reconnect(socket) do
    GenServer.call(socket.server_name, :reconnect)
  end

  @spec channel(socket, String.t, map) :: channel
  def channel(socket, topic, params \\ %{}) do
    %Channel{
      socket: socket,
      topic: topic,
      params: params
    }
  end

  @spec join(channel, number) :: result
  def join(channel, timeout \\ @default_timeout) do
    subscription = channel_subscription_key(channel)
    matcher = fn %{topic: topic} ->
      topic === channel.topic
    end
    mapper = fn %{event: event, payload: payload} -> {event, payload} end
    subscribe(channel.socket.server_name, subscription, matcher, mapper)
    case push_and_receive(channel, @event_join, channel.params, timeout) do
      :timeout ->
        unsubscribe(channel.socket.server_name, subscription)
        :timeout
      x -> x
    end
  end

  @spec leave(channel, number) :: send_result
  def leave(channel, timeout \\ @default_timeout) do
    subscription = channel_subscription_key(channel)
    unsubscribe(channel.socket.server_name, subscription)
    push_and_receive(channel, @event_leave, %{}, timeout)
  end

  @spec push(channel, String.t, map) :: send_result
  def push(channel, event, payload) do
    ref = GenServer.call(channel.socket.server_name, :make_ref)
    do_push(channel, event, payload, ref)
  end

  @spec push_and_receive(channel, String.t, map, number) :: result
  def push_and_receive(channel, event, payload, timeout \\ @default_timeout) do
    ref = GenServer.call(channel.socket.server_name, :make_ref)
    subscription = reply_subscription_key(ref)
    task = Task.async(fn ->
      matcher = fn %{topic: topic, event: event, ref: msg_ref} ->
        topic === channel.topic and event === @event_reply and msg_ref === ref
      end
      mapper = fn %{payload: payload} -> payload end
      subscribe(channel.socket.server_name, subscription, matcher, mapper)
      do_push(channel, event, payload, ref)
      receive do
        payload ->
          case payload do
            %{"status" => "ok", "response" => response} ->
              {:ok, response}
            %{"status" => "error", "response" => response} ->
              {:error, response}
          end
      after
        timeout -> :timeout
      end
    end)
    try do
      result = Task.await(task, @max_timeout)
    after
      unsubscribe(channel.socket.server_name, subscription)
    end
  end

  defp do_push(channel, event, payload, ref) do
    obj = %{
      topic: channel.topic,
      event: event,
      payload: payload,
      ref: ref
    }
    json = Poison.encode!(obj)
    socket = GenServer.call(channel.socket.server_name, :socket)
    WebSocket.send!(socket, {:text, json})
  end

  defp subscribe(name, key, matcher, mapper) do
    subscription = %Subscription{name: key, matcher: matcher, mapper: mapper, pid: self()}
    GenServer.cast(name, {:subscribe, subscription})
    subscription
  end

  defp unsubscribe(name, %Subscription{name: key}) do
    unsubscribe(name, key)
  end
  defp unsubscribe(name, key) do
    GenServer.cast(name, {:unsubscribe, key})
  end

  defp channel_subscription_key(channel), do: "channel_#{channel.topic}"
  defp reply_subscription_key(ref), do: "reply_#{ref}"

  defp spawn_recv_loop(socket) do
    pid = self()
    spawn(fn ->
      for _ <- Stream.cycle([:ok]) do
        case WebSocket.recv!(socket) do
          {:text, data} ->
            send pid, {:text, data}
          {:ping, _} ->
            WebSocket.send!(socket, {:pong, ""})
          {:close, _, _} ->
            send pid, :close
        end
      end
    end)
  end

  defp recv_loop(socket) do
  end

  defp do_connect(address, opts, state) do
    socket = state.socket
    if not is_nil(socket) do
      WebSocket.close(socket)
    end
    pid = state.recv_loop_pid
    if not is_nil(pid) and Process.alive?(pid) do
      Process.exit(pid, :kill)
    end
    case WebSocket.connect(address, opts) do
      {:ok, socket} ->
        pid = spawn_recv_loop(socket)
        state = %{state |
          socket: socket,
          recv_loop_pid: pid}
        {:reply, :ok, state}
      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  # Callbacks

  def handle_call({:connect, opts}, _from, state) do
    {host, opts} = Keyword.pop(opts, :host)
    {port, opts} = Keyword.pop(opts, :port)
    {path, opts} = Keyword.pop(opts, :path, "/")
    {params, opts} = Keyword.pop(opts, :params, %{})
    params = Map.put(params, :vsn, @phoenix_vsn) |> URI.encode_query()
    path = "#{path}?#{params}"
    opts = Keyword.put(opts, :path, path)
    address = if not is_nil(port) do
      {host, port}
    else
      host
    end
    state = %{state |
      connection_address: address,
      connection_opts: opts}
    do_connect(address, opts, state)
  end

  def handle_call(:reconnect, _from, state) do
    %{
      connection_address: address,
      connection_opts: opts
    } = state
    do_connect(address, opts, state)
  end

  def handle_call(:make_ref, _from, state) do
    ref = state.ref
    state = Map.update!(state, :ref, &(&1 + 1))
    {:reply, ref, state}
  end

  def handle_call(:socket, _from, state) do
    {:reply, state.socket, state}
  end

  def handle_cast({:subscribe, subscription}, state) do
    state = put_in(state, [:subscriptions, subscription.name], subscription)
    {:noreply, state}
  end

  def handle_cast({:unsubscribe, key}, state) do
    state = Map.update!(state, :subscriptions, fn subscriptions ->
      Map.delete(subscriptions, key)
    end)
    {:noreply, state}
  end

  def handle_info({:text, json}, state) do
    %{
      "event" => event,
      "topic" => topic,
      "payload" => payload,
      "ref" => ref
    } = Poison.decode!(json)
    obj = %{
      event: event,
      topic: topic,
      payload: payload,
      ref: ref
    }
    filter = fn {_key, %Subscription{matcher: matcher}} ->
      matcher.(obj)
    end
    mapper = fn {_key, %Subscription{pid: pid, mapper: mapper}} ->
      {pid, mapper.(obj)}
    end
    sender = fn {pid, message} ->
      send pid, message
    end
    state.subscriptions
    |> Flow.from_enumerable()
    |> Flow.filter_map(filter, mapper)
    |> Flow.each(sender)
    |> Flow.run()
    {:noreply, state}
  end
end
