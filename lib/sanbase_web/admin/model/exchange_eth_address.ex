defmodule Sanbase.ExAdmin.Model.ExchangeEthAddress do
  use ExAdmin.Register

  alias Sanbase.Repo
  alias Sanbase.Model.ExchangeEthAddress

  register_resource ExchangeEthAddress do
    form exchange_eth_address do
      inputs do
        content do
          """
          <div>
          Paste CSV in the following format:
          <ul>
            <li>Format: <b>address*</b>,<b>name*</b>,<b>source</b>,<b>comments</b>,<b>is dex</b>,<b>infrastructure id</b></li>
            <li>Required: address, name</li>
            <li>Column titles should be ommited</li>
            <li>Example:
              <pre>0x123f35fae36d75b1e72770e244f6595b68501234,Kyber,,\n0x1234465f45eac01389dbb3045206c1d07c123456,Another one,,</pre>
            </li>
          </ul>
          </div>
          """
        end

        input(exchange_eth_address, :csv, type: :text, label: "paste CSV")
      end
    end

    controller do
      before_filter(:process_csv, only: [:create, :update])
    end
  end

  def process_csv(conn, %{exchange_eth_address: %{csv: csv}} = params) when not is_nil(csv) do
    csv
    |> String.replace("\r", "")
    |> CSVLixir.Reader.read()
    |> Enum.reject(fn x -> x == [] end)
    |> Enum.map(&update_or_create_eth_address/1)
    |> Enum.each(&Repo.insert_or_update!/1)

    {conn, %{exchange_eth_address: %{}}}
  end

  def process_csv(conn, params), do: {conn, params}

  def update_or_create_eth_address([address, name, source, comments, is_dex, infrastructure_id]) do
    Repo.get_by(ExchangeEthAddress, address: address)
    |> case do
      nil ->
        %ExchangeEthAddress{}
        |> ExchangeEthAddress.changeset(%{
          address: address,
          name: name,
          source: source,
          comments: comments,
          is_dex: is_dex,
          infrastructure_id: infrastructure_id
        })

      exch_address ->
        exch_address
        |> ExchangeEthAddress.changeset(%{
          name: name || exch_address.name,
          source: source || exch_address.source,
          comments: comments || exch_address.comments,
          is_dex: is_dex || exch_address.is_dex,
          infrastructure_id: infrastructure_id || exch_address.infrastructure_id
        })
    end
  end
end
