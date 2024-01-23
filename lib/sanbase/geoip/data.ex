defmodule Sanbase.Geoip.Data do
  use Ecto.Schema
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

  def country_code_by_ip(ip_address) do
    case find_or_insert(ip_address) do
      {:ok, geoip_data} ->
        geoip_data.country_code

      _ ->
        nil
    end
  end

  def find_or_insert(remote_ip) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_geoip, fn _repo, _changes ->
      case Repo.get_by(__MODULE__, ip_address: remote_ip) do
        nil -> {:ok, :not_found}
        geoip_data -> {:ok, geoip_data}
      end
    end)
    |> Ecto.Multi.run(:create_geoip, fn _repo, %{get_geoip: result} ->
      case result do
        :not_found ->
          case Geoip.fetch_geo_data(remote_ip) do
            {:ok, data} ->
              create(remote_ip, data)

            {:error, _} = error ->
              error
          end

        geoip_data ->
          {:ok, geoip_data}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create_geoip: geoip_data}} -> {:ok, geoip_data}
      {:error, :create_geoip, reason, _changes} -> reason
      _ -> {:error, :unexpected_error}
    end
  end

  def create(remote_ip, data) do
    is_vpn =
      data["security"]["is_proxy"] == true and
        data["security"]["proxy_type"] == "VPN"

    changeset =
      changeset(%__MODULE__{}, %{
        ip_address: remote_ip,
        is_vpn: is_vpn,
        country_name: data["country_name"],
        country_code: data["country_code2"]
      })

    Repo.insert(changeset)
  end
end
