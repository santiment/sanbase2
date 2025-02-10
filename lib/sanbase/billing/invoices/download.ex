defmodule Sanbase.Billing.Invoices.Download do
  @moduledoc false
  def run do
    now = DateTime.utc_now()

    for year <- 2020..now.year, month <- 1..12 do
      if year == now.year and month > now.month do
        :ok
      else
        get({month, year})
      end
    end
  end

  def get({month, year}) do
    from = year |> Timex.beginning_of_month(month) |> Timex.to_datetime() |> DateTime.to_unix()
    to = year |> Timex.end_of_month(month) |> Timex.to_datetime() |> DateTime.to_unix()

    invoices =
      []
      |> list_invoices(%{created: %{gte: from, lte: to}, limit: 100, status: "paid"})
      |> Enum.filter(&(&1.total > 0 or abs(&1.starting_balance) > 0))

    IO.puts("Number of invoices for #{year}_#{month}: #{length(invoices)}")

    invoices =
      Enum.map(invoices, fn inv ->
        # label = if inv.starting_balance == 0, do: "fiat", else: "crypto"
        url = inv.invoice_pdf
        IO.puts("#{year}_#{month} fetching url: #{url}")

        response =
          HTTPoison.get!(url, [],
            follow_redirect: true,
            hackney: [{:force_redirect, true}],
            timeout: 20_000,
            recv_timeout: 20_000
          )

        filename = extract_filename(response)
        filedata = Map.get(response, :body)
        {to_charlist(filename), filedata}
      end)

    zipname = "#{year}_#{month}.zip"
    {:ok, _zipfile} = zipname |> to_charlist() |> :zip.create(invoices)
    IO.puts("***************** result zipfile: #{zipname}")

    zipname
  end

  def extract_filename(response) do
    header =
      response.headers
      |> Map.new()
      |> Map.get("Content-Disposition")

    ~r/filename=\"([^"]+)\"/
    |> Regex.run(header)
    |> Enum.at(1)
  end

  def list_invoices(acc, %{starting_after: _next} = args) do
    case do_list(args) do
      [] ->
        acc

      list ->
        next = list |> Enum.at(-1) |> Map.get(:id)
        list_invoices(acc ++ list, Map.put(args, :starting_after, next))
    end
  end

  def list_invoices([], args) do
    list = do_list(args)
    next = list |> Enum.at(-1) |> Map.get(:id)
    list_invoices(list, Map.put(args, :starting_after, next))
  end

  def do_list(params) do
    params
    |> Sanbase.StripeApi.list_invoices()
    |> elem(1)
    |> Map.get(:data, [])
    |> Enum.map(fn invoice ->
      invoice
      |> Map.split([
        :id,
        :customer,
        :total,
        :starting_balance,
        :status,
        :created,
        :invoice_pdf
      ])
      |> elem(0)
    end)
  end
end
