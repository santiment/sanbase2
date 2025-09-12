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

    IO.puts("Fetching invoices for #{year}_#{month} from #{from} to #{to}")

    # WORKAROUND: Remove status filter since it's not working, fetch all and filter manually
    all_invoices = list_invoices([], %{created: %{gte: from, lte: to}, limit: 100})
    IO.puts("Total invoices retrieved from Stripe: #{length(all_invoices)}")

    # Filter for paid status manually
    paid_invoices = Enum.filter(all_invoices, &(&1.status == "paid"))
    IO.puts("Paid invoices after manual filtering: #{length(paid_invoices)}")

    # Apply the existing business logic filter
    invoices = Enum.filter(paid_invoices, &(&1.total > 0 or abs(&1.starting_balance) > 0))
    IO.puts("Final invoices after business logic filtering: #{length(invoices)}")

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

  def debug_only({month, year}) do
    from = Timex.beginning_of_month(year, month) |> Timex.to_datetime() |> DateTime.to_unix()
    to = Timex.end_of_month(year, month) |> Timex.to_datetime() |> DateTime.to_unix()

    IO.puts("=== DEBUG MODE for #{year}_#{month} ===")
    IO.puts("Date range: #{from} to #{to}")

    # Fetch ALL invoices regardless of status
    all_invoices_all_status = list_invoices([], %{created: %{gte: from, lte: to}, limit: 100})
    IO.puts("All invoices (any status): #{length(all_invoices_all_status)}")

    # Status breakdown
    status_counts =
      all_invoices_all_status
      |> Enum.group_by(& &1.status)
      |> Enum.map(fn {status, invoices} -> {status, length(invoices)} end)

    IO.puts("Status breakdown: #{inspect(status_counts)}")

    # Try different status queries to debug the issue
    IO.puts("\n=== TESTING STATUS QUERIES ===")

    # Test with different status values
    for status <- ["paid", :paid] do
      IO.puts("Testing status: #{inspect(status)}")
      invoices = list_invoices([], %{created: %{gte: from, lte: to}, limit: 100, status: status})
      IO.puts("  Result count: #{length(invoices)}")
    end

    # Test manually filtering paid invoices from all invoices
    manual_paid = Enum.filter(all_invoices_all_status, &(&1.status == "paid"))
    IO.puts("Manual filter for paid status: #{length(manual_paid)}")

    # Let's also try without limit to see if that's an issue
    paid_no_limit = list_invoices([], %{created: %{gte: from, lte: to}, status: "paid"})
    IO.puts("Paid invoices without limit: #{length(paid_no_limit)}")

    # Check filtering on manually filtered paid invoices
    manual_filtered = Enum.filter(manual_paid, &(&1.total > 0 or abs(&1.starting_balance) > 0))
    IO.puts("Manual paid invoices after filtering: #{length(manual_filtered)}")

    # Sample some manually filtered invoices
    IO.puts("\nSample manually filtered paid invoices:")

    manual_filtered
    |> Enum.take(3)
    |> Enum.each(fn inv ->
      IO.puts(
        "  ID: #{inv.id}, Total: #{inv.total}, Starting Balance: #{inv.starting_balance}, Status: #{inv.status}"
      )
    end)

    # Print full structure of first manually filtered invoice
    if length(manual_filtered) > 0 do
      first_invoice = List.first(manual_filtered)
      IO.puts("\n=== FULL MANUAL FILTERED INVOICE STRUCTURE ===")
      IO.inspect(first_invoice, pretty: true, limit: :infinity)
      IO.puts("=== END INVOICE STRUCTURE ===")
    end

    :debug_complete
  end

  def compare_invoices_vs_charges({month, year}) do
    from = Timex.beginning_of_month(year, month) |> Timex.to_datetime() |> DateTime.to_unix()
    to = Timex.end_of_month(year, month) |> Timex.to_datetime() |> DateTime.to_unix()

    IO.puts("=== COMPARISON: Invoices vs Charges for #{year}_#{month} ===")

    # Get invoices
    invoices = list_invoices([], %{created: %{gte: from, lte: to}, limit: 100, status: "paid"})
    IO.puts("Total paid invoices: #{length(invoices)}")

    # Get charges (payments) - using similar logic from stripe_sync.ex
    charges = list_charges([], %{created: %{gte: from, lte: to}, limit: 100})
    IO.puts("Total charges/payments: #{length(charges)}")

    # Check if charges have invoices
    charges_with_invoices = Enum.filter(charges, & &1.invoice)
    charges_without_invoices = Enum.filter(charges, &is_nil(&1.invoice))

    IO.puts("Charges with invoices: #{length(charges_with_invoices)}")
    IO.puts("Charges without invoices: #{length(charges_without_invoices)}")

    IO.puts("\nSample charges without invoices:")

    charges_without_invoices
    |> Enum.take(3)
    |> Enum.each(fn charge ->
      IO.puts("  Charge ID: #{charge.id}, Amount: #{charge.amount}, Customer: #{charge.customer}")
    end)

    :comparison_complete
  end

  def list_charges(acc, %{starting_after: _next} = args) do
    case do_list_charges_with_metadata(args) do
      {[], _has_more} ->
        acc

      {list, false} ->
        acc ++ list

      {list, true} ->
        new_acc = acc ++ list
        next = Enum.at(list, -1) |> Map.get(:id)
        list_charges(new_acc, Map.put(args, :starting_after, next))
    end
  end

  def list_charges([], args) do
    case do_list_charges_with_metadata(args) do
      {[], _has_more} ->
        []

      {list, false} ->
        list

      {list, true} ->
        next = Enum.at(list, -1) |> Map.get(:id)
        list_charges(list, Map.put(args, :starting_after, next))
    end
  end

  def do_list_charges_with_metadata(params) do
    case Sanbase.StripeApi.list_charges(params) do
      {:ok, response} ->
        charges =
          response
          |> Map.get(:data, [])
          |> Enum.map(fn charge ->
            Map.split(charge, [
              :id,
              :customer,
              :amount,
              :status,
              :created,
              :invoice
            ])
            |> elem(0)
          end)

        has_more = Map.get(response, :has_more, false)
        {charges, has_more}

      {:error, _error} ->
        {[], false}
    end
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
    case do_list_with_metadata(args) do
      {[], _has_more} ->
        acc

      {list, false} ->
        acc ++ list

      {list, true} ->
        new_acc = acc ++ list
        next = Enum.at(list, -1) |> Map.get(:id)
        list_invoices(new_acc, Map.put(args, :starting_after, next))
    end
  end

  def list_invoices([], args) do
    case do_list_with_metadata(args) do
      {[], _has_more} ->
        []

      {list, false} ->
        list

      {list, true} ->
        next = Enum.at(list, -1) |> Map.get(:id)
        list_invoices(list, Map.put(args, :starting_after, next))
    end
  end

  def inspect_raw_invoice({month, year}) do
    from = Timex.beginning_of_month(year, month) |> Timex.to_datetime() |> DateTime.to_unix()
    to = Timex.end_of_month(year, month) |> Timex.to_datetime() |> DateTime.to_unix()

    IO.puts("=== INSPECTING RAW STRIPE INVOICE RESPONSE ===")

    case Sanbase.StripeApi.list_invoices(%{
           created: %{gte: from, lte: to},
           limit: 1,
           status: "paid"
         }) do
      {:ok, response} ->
        IO.puts("Response keys: #{inspect(Map.keys(response))}")
        IO.puts("Has more: #{Map.get(response, :has_more, false)}")
        IO.puts("Data length: #{length(Map.get(response, :data, []))}")

        if length(Map.get(response, :data, [])) > 0 do
          first_invoice = List.first(Map.get(response, :data, []))
          IO.puts("\n=== RAW INVOICE FIELDS ===")
          IO.puts("Available fields: #{inspect(Map.keys(first_invoice))}")
          IO.puts("\n=== FULL RAW INVOICE ===")
          IO.inspect(first_invoice, pretty: true, limit: :infinity)
          IO.puts("=== END RAW INVOICE ===")
        end

      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end

    :inspection_complete
  end

  def do_list_with_metadata(params) do
    case Sanbase.StripeApi.list_invoices(params) do
      {:ok, response} ->
        invoices =
          response
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

        has_more = Map.get(response, :has_more, false)
        {invoices, has_more}

      {:error, _error} ->
        {[], false}
    end
  end

  def do_list(params) do
    {invoices, _has_more} = do_list_with_metadata(params)
    invoices
  end
end
