defmodule Sanbase.ExAdmin.Model.ExchangeAddress do
  use ExAdmin.Register

  alias Sanbase.Repo
  alias Sanbase.Model.ExchangeAddress

  register_resource ExchangeAddress do
    form exchange_address do
      inputs do
        content do
          raw("CSV Format: address,name,source,comments,is dex,infrastructure id")
        end

        input(exchange_address, :csv, type: :text, label: "paste CSV")
      end
    end

    controller do
      before_filter(:process_csv, only: [:create, :update])
    end
  end

  def process_csv(conn, %{exchange_address: %{csv: csv}}) when not is_nil(csv) do
    csv
    |> String.replace("\r", "")
    |> CSVLixir.Reader.read()
    |> Enum.reject(fn x -> x == [] end)
    |> Enum.map(&update_or_create_eth_address/1)
    |> Enum.each(&Repo.insert_or_update!/1)

    {conn, %{exchange_address: %{}}}
  end

  def process_csv(conn, params), do: {conn, params}

  def update_or_create_eth_address([address, name, source, comments, is_dex, infrastructure_id]) do
    Repo.get_by(ExchangeAddress, address: address)
    |> case do
      nil ->
        %ExchangeAddress{}
        |> ExchangeAddress.changeset(%{
          address: address,
          name: name,
          source: source,
          comments: comments,
          is_dex: is_dex,
          infrastructure_id: infrastructure_id
        })

      exch_address ->
        exch_address
        |> ExchangeAddress.changeset(%{
          name: name || exch_address.name,
          source: source || exch_address.source,
          comments: comments || exch_address.comments,
          is_dex: is_dex || exch_address.is_dex,
          infrastructure_id: infrastructure_id || exch_address.infrastructure_id
        })
    end
  end
end
