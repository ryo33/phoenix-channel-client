defmodule TestServer.PageController do
  use TestServer.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
