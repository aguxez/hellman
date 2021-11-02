defmodule HellmanWeb.PageLive.Index do
  @moduledoc false

  use HellmanWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    send(self(), :fetch_sessions)
    {:ok, assign(socket, :sessions, [])}
  end

  @impl true
  def handle_info(:fetch_sessions, socket) do
    session_fn = fn -> :mnesia.match_object({:session, :_, :_, :_}) end

    sessions =
      session_fn
      |> :mnesia.transaction()
      |> elem(1)
      |> Enum.map(fn {_, id, _, _} -> id end)

    Process.send_after(self(), :fetch_sessions, 1500)

    {:noreply, assign(socket, :sessions, sessions)}
  end

  @impl true
  def handle_event("create_random", _params, socket) do
    Hellman.PageBrain.insert_session(Ecto.UUID.generate())
    send(self(), :fetch_sessions)
    {:noreply, socket}
  end
end
