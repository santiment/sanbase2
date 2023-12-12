defmodule Sanbase.Geoip.Data do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Repo
  alias Sanbase.Geoip

  alias Sanbase.Billing.Plan

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

  def eligible_for_ppp?(ip_address) do
    case find_or_insert(ip_address) do
      {:ok, geoip_data} ->
        # Turkey
        geoip_data.country_code in ["TR"] and geoip_data.is_vpn == false

      _ ->
        false
    end
  end

  # Purchasing power parity settings.
  def ppp_settings(geoip_data) do
    percent_symbol = Plan.country_ppp_plan_map() |> Map.get(geoip_data.country_code)
    percent_off = Plan.symbol_to_percent_map() |> Map.get(percent_symbol)

    plans = Plan.ppp_plans_for_country(geoip_data.country_code)

    %{
      is_eligible_for_ppp: true,
      plans: plans,
      country: geoip_data.country_name,
      percent_off: percent_off
    }
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
    case Repo.get_by(__MODULE__, ip_address: remote_ip) do
      nil ->
        case Geoip.fetch_geo_data(remote_ip) do
          {:ok, data} ->
            create(remote_ip, data)

          {:error, _} = error ->
            error
        end

      geoip_data ->
        {:ok, geoip_data}
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
