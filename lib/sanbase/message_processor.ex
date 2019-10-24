defmodule Sanbase.MessageProcessor do
  def handle_messages(messages) do
    for %{key: key, value: value} = message <- messages do
      IO.inspect(message)
      IO.puts("#{key}: #{value}")
    end

    # Important!
    :ok
  end

  def handle_message(%{key: key, value: value} = message) do
    IO.inspect(message)
    IO.puts("#{key}: #{value}")

    emd = Jason.decode!(value)

    emd =
      emd
      |> Enum.map(fn {k, v} -> {Regex.replace(~r/_(\d+)/, k, "\\1"), v} end)
      |> Enum.into(%{})

    emd = for {key, val} <- emd, into: %{}, do: {String.to_atom(key), val}
    emd = emd |> Map.put(:timestamp, DateTime.from_unix!(floor(emd.timestamp), :millisecond))

    Absinthe.Subscription.publish(SanbaseWeb.Endpoint, emd,
      exchange_market_depth: emd.source <> emd.symbol
    )

    Absinthe.Subscription.publish(SanbaseWeb.Endpoint, emd, exchange_market_depth: emd.source)

    # Important!
    :ok
  end
end
