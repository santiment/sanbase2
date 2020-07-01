defmodule SanbaseWeb.Graphql.TableConfigurationTypes do
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias SanbaseWeb.Graphql.SanbaseRepo

  input_object :table_configuration_input_object do
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean)
    field(:columns, :json)
    field(:page_size, :integer)
  end

  object :table_configuration do
    field(:id, non_null(:integer))
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean)
    field(:page_size, :integer)
    field(:columns, :json)

    field(:user, :user, resolve: dataloader(SanbaseRepo))

    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end
end
