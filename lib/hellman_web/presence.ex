defmodule HellmanWeb.Presence do
  @moduledoc false

  use Phoenix.Presence, otp_app: :hellman, pubsub_server: Hellman.PubSub
end
