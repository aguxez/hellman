defmodule HellmanWeb.PageLive.Session do
  @moduledoc false

  use HellmanWeb, :live_view

  alias Hellman.{PubSub, PageBrain}
  alias HellmanWeb.Presence

  @p :crypto.strong_rand_bytes(15)
  @g :crypto.strong_rand_bytes(15)

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    Phoenix.PubSub.subscribe(PubSub, topic(session_id))

    private = rand_value()
    public = get_public_key(private)

    new_socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:user_count, :maps.size(Presence.list(topic(session_id))))
      |> assign(:own_keys, %{
        private: private,
        public: public
      })
      |> assign(:ext_keys, %{})

    # This will help to let know other users of the topic know other participants' keys
    {:ok, _} = Presence.track(self(), topic(session_id), socket.id, %{keys: %{public: public}})

    Phoenix.PubSub.broadcast(
      PubSub,
      topic(session_id),
      {:user_added, %{user: socket.id, public_key: public}}
    )

    send(self(), {:fetch_available_keys, session_id})

    {:ok, new_socket}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "presence_diff",
          topic: topic,
          payload: %{joins: joins, leaves: leaves}
        },
        socket
      ) do
    new_user_count = socket.assigns.user_count + :maps.size(joins) - :maps.size(leaves)

    if new_user_count == 2 do
      Phoenix.PubSub.broadcast(PubSub, topic, :start_exchange)
    end

    {:noreply, assign(socket, user_count: new_user_count, readable_secret: nil, secret: nil)}
  end

  @impl true
  def handle_info({:user_added, %{user: user, public_key: public_key}}, socket) do
    current_keys = Map.get(socket, :ext_keys, %{})

    new_socket =
      assign(socket, :ext_keys, Map.merge(current_keys, %{user => %{public_key: public_key}}))

    {:noreply, new_socket}
  end

  @impl true
  def handle_info({:fetch_available_keys, session_id}, socket) do
    existing_keys =
      session_id
      |> topic()
      |> Presence.list()
      |> Enum.reject(fn {user, _} -> user == socket.id end)
      |> Enum.map(fn {user, %{metas: metas}} ->
        {user, %{public_key: hd(metas).keys.public}}
      end)
      |> Enum.into(%{})

    {:noreply, assign(socket, :ext_keys, existing_keys)}
  end

  @impl true
  def handle_info(
        :start_exchange,
        %{assigns: %{session_id: session_id, ext_keys: ext_keys, own_keys: own_keys}} = socket
      ) do
    # We only need other's party public key to generate the secret
    # Fetch the secret from the storage, if not, create and save it for future use
    {secret, messages} =
      case PageBrain.get_session(session_id) do
        {:atomic, [{:session, _, nil, messages}]} ->
          {generate_and_save_new_secret(session_id, ext_keys, own_keys), messages}

        {:atomic, [{:session, _, secret, messages}]} ->
          {secret, messages}

        {:atomic, []} ->
          {generate_and_save_new_secret(session_id, ext_keys, own_keys), []}
      end

    new_socket =
      socket
      |> assign(:readable_secret, Base.encode64(secret))
      |> assign(:secret, secret)
      |> assign(:messages, decrypt_messages(messages, secret))

    {:noreply, new_socket}
  end

  @impl true
  def handle_info({:new_message, payload, sender_id}, socket) do
    new_socket =
      if socket.id == sender_id do
        socket
      else
        assign(socket, :messages, [payload | socket.assigns.messages])
      end

    {:noreply, new_socket}
  end

  @impl true
  def handle_event("create_message", %{"chat" => %{"message" => ""}}, socket) do
    #  No empty messages, though the HTML has the textarea as required
    {:noreply, socket}
  end

  @impl true
  def handle_event("create_message", %{"chat" => %{"message" => message}}, socket) do
    encrypted_message = Plug.Crypto.MessageVerifier.sign(message, socket.assigns.secret)

    PageBrain.update_session_msg(socket.assigns.session_id, encrypted_message)
    payload = {message, DateTime.truncate(DateTime.utc_now(), :second)}

    Phoenix.PubSub.broadcast(
      PubSub,
      topic(socket.assigns.session_id),
      {:new_message, payload, socket.id}
    )

    {:noreply, assign(socket, :messages, [payload | socket.assigns.messages])}
  end

  defp topic(session_id), do: "session:" <> session_id

  defp rand_value, do: :crypto.strong_rand_bytes(15)

  defp get_public_key(private), do: :crypto.mod_pow(@g, private, @p)

  defp generate_and_save_new_secret(session_id, ext_keys, own_keys) do
    secret =
      Enum.reduce(ext_keys, <<>>, fn {_user, %{public_key: public}}, _acc ->
        :crypto.mod_pow(public, own_keys.private, @p)
      end)

    PageBrain.add_secret(session_id, secret)
    secret
  end

  defp decrypt_messages([_ | _] = messages, secret) do
    Enum.map(messages, fn {message, date} ->
      case Plug.Crypto.MessageVerifier.verify(message, secret) do
        {:ok, readable} -> {readable, date}
        :error -> {"[THIS MESSAGE HAS BEEN COMPROMISED]", date}
      end
    end)
  end
end
