defmodule Sanbase.Billing.Invoices.Download do
  def run() do
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
    from = Timex.beginning_of_month(year, month) |> Timex.to_datetime() |> DateTime.to_unix()
    to = Timex.end_of_month(year, month) |> Timex.to_datetime() |> DateTime.to_unix()

    invoices =
      list_invoices([], %{created: %{gte: from, lte: to}, limit: 100, status: "paid"})
      |> Enum.filter(&(&1.total > 0 or abs(&1.starting_balance) > 0))

    IO.puts("Number of invoices for #{year}_#{month}: #{length(invoices)}")

    invoices =
      invoices
      |> Enum.map(fn inv ->
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
    {:ok, _zipfile} = :zip.create(zipname |> to_charlist(), invoices)
    IO.puts("***************** result zipfile: #{zipname}")

    zipname
  end

  def extract_filename(response) do
    header =
      response.headers
      |> Enum.into(%{})
      |> Map.get("Content-Disposition")

    Regex.run(~r/filename=\"([^"]+)\"/, header)
    |> Enum.at(1)
  end

  def list_invoices(acc, %{starting_after: _next} = args) do
    case do_list(args) do
      [] ->
        acc

      list ->
        next = Enum.at(list, -1) |> Map.get(:id)
        list_invoices(acc ++ list, Map.put(args, :starting_after, next))
    end
  end

  def list_invoices([], args) do
    list = do_list(args)
    next = Enum.at(list, -1) |> Map.get(:id)
    list_invoices(list, Map.put(args, :starting_after, next))
  end

  def do_list(params) do
    Sanbase.StripeApi.list_invoices(params)
    |> elem(1)
    |> Map.get(:data, [])
    |> Enum.map(fn invoice ->
      Map.split(invoice, [
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
