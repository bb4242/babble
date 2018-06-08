defmodule Babble.Transports.UdpMulticast do
  use GenServer

  @multicast_port 42_042
  @multicast_addr {239, 42, 42, 10}
  @multicast_ttl 1

  @hmac_size 4

  @registry_name UdpRegistry

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send(recipient_id, message) do
    GenServer.cast(__MODULE__, {:send, recipient_id, message})
  end

  def register_listener(message_id) do
    Registry.register(@registry_name, message_id, nil)
  end

  @impl true
  def init(_opts) do
    # Start a registry for message listeners
    {:ok, _} = Registry.start_link(keys: :unique, name: @registry_name)

    # Get IPv4 address of all system interfaces
    {:ok, interfaces} = :inet.getifaddrs()

    all_ipv4_addrs =
      for {iface, flags} <- interfaces, {:addr, addr = {_, _, _, _}} <- flags, do: {iface, addr}

    # Only pick one address per interface if the interface has several
    ipv4_addrs = all_ipv4_addrs |> Map.new() |> Map.values()

    # Open a multicast socket on each interface
    sockets =
      for addr <- ipv4_addrs do
        {:ok, socket} =
          :gen_udp.open(@multicast_port, [
            :binary,
            active: true,
            ip: @multicast_addr,
            reuseaddr: true,
            broadcast: true,
            multicast_ttl: @multicast_ttl,
            multicast_loop: false,
            multicast_if: addr,
            add_membership: {@multicast_addr, addr}
          ])

        socket
      end

    {:ok, sockets}
  end

  @impl true
  def handle_cast({:send, recipient_id, message}, sockets) do
    msg_bytes = encode_message(recipient_id, message)

    for socket <- sockets do
      :gen_udp.send(socket, @multicast_addr, @multicast_port, msg_bytes)
    end

    {:noreply, sockets}
  end

  @impl true
  def handle_info({:udp, _socket, _ip, _port, packet}, sockets) do
    case decode_message(packet) do
      {:ok, message_id, message} ->
        for {pid, _} <- Registry.lookup(@registry_name, message_id), do: Kernel.send(pid, message)

      {:error, _} ->
        nil
    end

    {:noreply, sockets}
  end

  # Helper functions

  defp hmac(payload) do
    :crypto.hmac(:sha256, Atom.to_charlist(Node.get_cookie()), payload, @hmac_size)
  end

  defp encode_message(recipient_id, message) do
    payload = :erlang.term_to_binary(message, compressed: 9)
    envelope = <<recipient_id::8-unsigned-integer>> <> payload
    hmac(envelope) <> envelope
  end

  defp decode_message(<<hmac::4-binary, envelope::binary>>) do
    if hmac(envelope) == hmac do
      <<recipient_id::8-unsigned-integer, payload::binary>> = envelope
      {:ok, recipient_id, :erlang.binary_to_term(payload)}
    else
      {:error, "Bad HMAC"}
    end
  end

  defp decode_message(_) do
    {:error, "Invalid message length"}
  end
end
