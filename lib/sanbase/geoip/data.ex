defmodule Sanbase.Geoip.Data do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias Sanbase.Repo
  alias Sanbase.Geoip

  schema "geoip_data" do
    field(:ip_address, :string)
    field(:is_vpn, :boolean)
    field(:country_name, :string)
    field(:country_code, :string)

    timestamps()
  end

  @doc false
  def changeset(geoip_data, attrs) do
    geoip_data
    |> cast(attrs, [:ip_address, :is_vpn, :country_name, :country_code])
    |> validate_required([:ip_address, :is_vpn, :country_name, :country_code])
  end

  def find_or_insert(remote_ip) do
    case Repo.get_by(__MODULE__, ip_address: remote_ip) do
      nil ->
        case Geoip.fetch_geo_data(remote_ip) do
          {:ok, data} ->
            is_vpn =
              data["security"]["is_proxy"] == true and data["security"]["proxy_type"] == "VPN"

            changeset =
              changeset(%__MODULE__{}, %{
                ip_address: remote_ip,
                is_vpn: is_vpn,
                country_name: data["country_name"],
                country_code: data["country_code2"]
              })

            Repo.insert(changeset)

          {:error, _} = error ->
            error
        end

      geoip_data ->
        {:ok, geoip_data}
    end
  end
end
