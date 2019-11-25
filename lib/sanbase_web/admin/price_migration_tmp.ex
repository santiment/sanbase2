defmodule Sanbase.ExAdmin.PriceMigrationTmp do
  use ExAdmin.Register

  register_resource Sanbase.PriceMigrationTmp do
    show _migrated_project do
      attributes_table(all: true)
    end
  end
end
