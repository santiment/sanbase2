defmodule Sanbase.ExAdmin.ScheduleRescrapePrices do
  use ExAdmin.Register

  register_resource Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice do
    form srp do
      inputs do
        input(srp, :from)
        input(srp, :to)
        input(srp, :logo_url)

        input(
          srp,
          :project,
          collection: from(p in Sanbase.Model.Project, order_by: p.name) |> Sanbase.Repo.all()
        )
      end
    end
  end
end
