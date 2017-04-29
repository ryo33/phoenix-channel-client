defmodule PhoenixChannelClientTest do
  use ExUnit.Case
  doctest PhoenixChannelClient

  @name :test
  @host "localhost"
  @path "/socket/websocket"
  @params %{authenticated: "true"}
  @port 4000
  @opts [
    host: @host,
    port: @port,
    path: @path,
    params: @params]

  setup_all do
    IO.puts("Don't forget to run the test server!")
    :ok
  end

  setup do
    on_exit fn ->
      if not is_nil(GenServer.whereis(@name)) do
        GenServer.stop(@name)
      end
    end
    PhoenixChannelClient.start(name: @name)
    :ok
  end

  test "connect successfully" do
    {:ok, _socket} = PhoenixChannelClient.connect(@name, @opts)
  end

  test "fail to connect" do
    params = %{
      authenticated: "false"
    }
    opts = [
      host: @host,
      port: @port,
      path: @path,
      params: params]
    assert PhoenixChannelClient.connect(@name, opts) == {:error, {403, "Forbidden"}}
  end

  test "join successfully" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "ok:topic", %{a: 1})
    assert PhoenixChannelClient.join(channel) == {:ok, %{"topic" => "topic", "params" => %{"a" => 1}}}
  end

  test "fail to join" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "error:topic", %{a: 1})
    assert PhoenixChannelClient.join(channel) == {:error, %{"topic" => "topic", "params" => %{"a" => 1}}}
  end

  test "push and receive ok" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "ok:topic", %{})
    PhoenixChannelClient.join(channel)
    assert PhoenixChannelClient.push_and_receive(channel, "reply_ok:event", %{a: 1}) ==
      {:ok, %{"event" => "event", "params" => %{"a" => 1}}}
  end

  test "push and receive error" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "ok:topic", %{})
    PhoenixChannelClient.join(channel)
    assert PhoenixChannelClient.push_and_receive(channel, "reply_error:event", %{a: 1}) ==
      {:error, %{"event" => "event", "params" => %{"a" => 1}}}
  end

  test "push" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "ok:topic", %{})
    PhoenixChannelClient.join(channel)
    assert PhoenixChannelClient.push(channel, "noreply:event", %{a: 1}) == :ok
  end

  test "push and ignore" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "ok:topic", %{})
    PhoenixChannelClient.join(channel)
    assert PhoenixChannelClient.push(channel, "reply_ok:event", %{a: 1}) == :ok
  end

  test "push and receive with noreply" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "ok:topic", %{})
    PhoenixChannelClient.join(channel)
    assert PhoenixChannelClient.push_and_receive(channel, "noreply:event", %{a: 1}, 20) == :timeout
  end

  test "leave" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "ok:topic", %{})
    PhoenixChannelClient.join(channel)
    assert PhoenixChannelClient.leave(channel) == {:ok, %{}}
  end

  test "unsubscribe properly" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel1 = PhoenixChannelClient.channel(socket, "ok:1", %{})
    channel2 = PhoenixChannelClient.channel(socket, "ok:2", %{})
    PhoenixChannelClient.join(channel1)
    PhoenixChannelClient.join(channel2)
    assert Map.size(get_subscriptions()) == 2
    PhoenixChannelClient.push_and_receive(channel1, "reply_ok:event", %{a: 1})
    assert Map.size(get_subscriptions()) == 2
    PhoenixChannelClient.push(channel2, "noreply:event", %{a: 1})
    assert Map.size(get_subscriptions()) == 2
    PhoenixChannelClient.leave(channel1)
    PhoenixChannelClient.leave(channel2)
    assert Map.size(get_subscriptions()) == 0
  end

  test "timeout on join" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "sleep:1000", %{})
    assert PhoenixChannelClient.join(channel, 100) == :timeout
    assert Map.size(get_subscriptions()) == 0
  end

  test "timeout on push" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "ok:topic", %{})
    PhoenixChannelClient.join(channel, 100)
    assert Map.size(get_subscriptions()) == 1
    assert PhoenixChannelClient.push_and_receive(channel, "sleep:1000", %{a: 1}, 10) == :timeout
    assert Map.size(get_subscriptions()) == 1
  end

  test "receive messages" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    channel = PhoenixChannelClient.channel(socket, "ok:topic", %{})
    PhoenixChannelClient.join(channel)
    PhoenixChannelClient.push(channel, "dispatch:ok:topic", %{event: "event", payload: %{a: 1}})
    assert Map.size(get_subscriptions()) == 1
    assert_receive {"event", %{"a" => 1}}
  end

  test "reconnect" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    pid = get_recv_loop_pid()
    assert Process.alive?(pid)
    assert PhoenixChannelClient.reconnect(socket) == :ok
    refute Process.alive?(pid)
    pid = get_recv_loop_pid()
    assert Process.alive?(pid)
  end

  test "close properly" do
    {:ok, socket} = PhoenixChannelClient.connect(@name, @opts)
    pid = get_recv_loop_pid()
    socket = get_socket()
    assert Process.alive?(pid)
    assert Port.info(socket.socket) != nil
    GenServer.stop(@name)
    refute Process.alive?(pid)
    refute Port.info(socket.socket) != nil
  end

  defp get_subscriptions, do: :sys.get_state(@name).subscriptions
  defp get_recv_loop_pid, do: :sys.get_state(@name).recv_loop_pid
  defp get_socket, do: :sys.get_state(@name).socket
end
