defmodule Sanbase.ExternalServices.Coinmarketcap.Utils do
  # After invocation of this function the process should execute `Process.exit(self(), :normal)`
  # There is no meaningful result to be returned here. If it does not exit
  # this case should return a special case and it should be handeled so the
  # `last_updated` is not updated when no points are written
  def wait_rate_limit(%Tesla.Env{status: 429, headers: headers}, rate_limiting_server) do
    wait_period =
      case Enum.find(headers, &match?({"retry-after", _}, &1)) do
        {_, wait_period} -> wait_period |> String.to_integer()
        _ -> 1
      end

    wait_until = Timex.shift(Timex.now(), seconds: wait_period)
    Sanbase.ExternalServices.RateLimiting.Server.wait_until(rate_limiting_server, wait_until)
  end

  def san_contract_to_project_map() do
    get_or_compute_function(:san_contract_to_project_map, &compute_contract_to_project_map/0, 600)
  end

  def cmc_contract_to_cmc_id_map() do
    get_or_compute_function(
      :cmc_contract_to_cmc_id_map,
      &compute_cmc_contract_to_cmc_id_map/0,
      600
    )
  end

  def cmc_id_to_project_map() do
    get_or_compute_function(:cmc_contract_to_cmc_id_map, &compute_cmc_id_to_project_map/0, 600)
  end

  # Private functions

  defp compute_contract_to_project_map() do
    Sanbase.Project.List.projects(preload: [:contract_addresses, :infrastructure])
    |> Enum.flat_map(fn project ->
      project.contract_addresses |> Enum.map(fn ca -> {String.downcase(ca.address), project} end)
    end)
    |> Map.new()
  end

  defp compute_cmc_id_to_project_map() do
    Sanbase.Project.List.projects(preload: [:latest_coinmarketcap_data, :infrastructure])
    |> Enum.filter(& &1.coinmarketcap_id)
    |> Enum.map(&{&1.coinmarketcap_id, &1})
    |> Map.new()
  end

  defp compute_cmc_contract_to_cmc_id_map() do
    json = read_cmc_metadata()

    json
    |> Enum.flat_map(fn {_integer_id, map} ->
      map["contract_address"]
      |> Enum.map(fn %{"contract_address" => address, "platform" => %{"name" => platform_name}} ->
        {String.downcase(address),
         %{
           "platform_name" => platform_name,
           "infrastructure" => @cmc_platform_name_to_infrastructure[platform_name],
           "slug" => map["slug"]
         }}
      end)
    end)
    |> Enum.reject(fn {_addr, %{"infrastructure" => infr}} -> is_nil(infr) end)
    |> Enum.reduce(%{}, fn {addr, m}, acc ->
      Map.update(
        acc,
        addr,
        [m],
        &[m | &1]
      )
    end)
  end

  defp get_or_compute_function(key, function, ttl_seconds)
       when is_function(function, 0) and is_integer(ttl_seconds) do
    case :persistent_term.get(key, nil) do
      nil ->
        data = function.()

        :persistent_term.put(key, {contract_to_project, DateTime.utc_now()})

        data

      {data, added_at} ->
        if DateTime.diff(DateTime.utc_now(), added_at, :minute) > 10 do
          data = function.()

          :persistent_term.put(
            key,
            {data, DateTime.utc_now()}
          )

          data
        else
          data
        end
    end
  end
end
