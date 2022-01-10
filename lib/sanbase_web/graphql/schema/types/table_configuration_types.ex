defmodule SanbaseWeb.Graphql.TableConfigurationTypes do
  use Absinthe.Schema.Notation

  enum :table_configuration_type_enum do
    value(:project)
    value(:blockchain_address)
  end

  input_object :table_configuration_input_object do
    field(:type, :table_configuration_type_enum)
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean)
    field(:columns, :json)
    field(:page_size, :integer)
  end

  object :table_configuration do
    field(:id, non_null(:integer))
    field(:type, :table_configuration_type_enum)
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean)
    field(:page_size, :integer)
    field(:columns, :json)

    field :user, non_null(:public_user) do
      resolve(&SanbaseWeb.Graphql.Resolvers.UserResolver.user_no_preloads/3)
    end

    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end
end
