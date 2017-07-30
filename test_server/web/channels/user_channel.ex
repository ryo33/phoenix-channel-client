defmodule TestServer.UserChannel do
  use Phoenix.Channel

  def join("ok:" <> topic, params, socket) do
    {:ok, %{topic: topic, params: params}, socket}
  end

  def join("error:" <> topic, params, socket) do
    {:error, %{topic: topic, params: params}}
  end

  def join("sleep:" <> topic, params, socket) do
    IO.inspect(topic)
    :timer.sleep(String.to_integer(topic))
    {:ok, %{topic: topic, params: params}, socket}
  end

  def join("timer", params, socket) do
    :timer.send_after(1, {:timer, 1})
    {:ok, socket}
  end
  def handle_info({:timer, count}, socket) do
    if count < 3 do
      :timer.send_after(1, {:timer, count+1})
    end
    push socket, "timer", %{count: count}
    {:noreply, socket}
  end

  def handle_in("reply_ok:" <> event, params, socket) do
    {:reply, {:ok, %{event: event, params: params}}, socket}
  end

  def handle_in("sleep:" <> event, params, socket) do
    :timer.sleep(String.to_integer(event))
    {:reply, {:ok, %{event: event, params: params}}, socket}
  end

  def handle_in("reply_error:" <> event, params, socket) do
    {:reply, {:error, %{event: event, params: params}}, socket}
  end

  def handle_in("noreply:" <> _event, _params, socket) do
    {:noreply, socket}
  end

  def handle_in("dispatch:" <> topic, %{"event" => event, "payload" => payload}, socket) do
    TestServer.Endpoint.broadcast! topic, event, payload
    {:noreply, socket}
  end
end
