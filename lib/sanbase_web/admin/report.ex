defmodule SanbaseWeb.ExAdmin.Report do
  use ExAdmin.Register

  register_resource Sanbase.Report do
    action_items(only: [:show, :edit])

    form report do
      inputs do
        input(report, :name)
        input(report, :description, type: :text)
        input(report, :is_published)
        input(report, :is_pro)
      end
    end
  end
end
