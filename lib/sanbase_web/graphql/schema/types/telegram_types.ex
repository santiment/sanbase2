defmodule SanbaseWeb.Graphql.TelegramTypes do
  use Absinthe.Schema.Notation

  object :telegram_data do
    field(:datetime, non_null(:datetime))
    field(:members_count, :integer)
  end
end
