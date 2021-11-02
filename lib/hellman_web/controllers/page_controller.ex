defmodule HellmanWeb.PageController do
  use HellmanWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
