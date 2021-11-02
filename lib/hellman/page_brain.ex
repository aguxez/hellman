defmodule Hellman.PageBrain do
  @moduledoc """
  🧠🧠🧠🧠🧠🧠🧠🧠
  Handles storage through Mnesia for a given session
  """

  use Task, restart: :transient

  @tables_and_attrs [
    {:session, [:id, :secret, :messages]}
  ]

  def start_link(_) do
    Task.start_link(__MODULE__, :init_tables, [])
  end

  def init_tables do
    :mnesia.create_schema([node()])
    :mnesia.start()

    Enum.each(@tables_and_attrs, fn {table, attrs} ->
      :mnesia.create_table(table, attributes: attrs)
    end)
  end

  def insert_session(session_id) do
    :mnesia.transaction(fn -> :mnesia.write({:session, session_id, nil, []}) end)
  end

  def get_session(session_id) do
    :mnesia.transaction(fn -> :mnesia.read({:session, session_id}) end)
  end

  def add_secret(session_id, secret) do
    :mnesia.transaction(fn ->
      [{:session, _id, _secret, msgs}] = :mnesia.read({:session, session_id})

      :mnesia.write({:session, session_id, secret, msgs})
    end)
  end

  def update_session_msg(session_id, message) do
    :mnesia.transaction(fn ->
      insert_time = DateTime.truncate(DateTime.utc_now(), :second)

      [{:session, _id, secret, msgs}] = :mnesia.read({:session, session_id})

      new_msgs = [{message, insert_time} | msgs]

      :mnesia.write({:session, session_id, secret, new_msgs})
    end)
  end
end
