defmodule SanbaseWeb.GenericAdmin.EmailExclusionList do
  alias Sanbase.Email.EmailExclusionList

  @schema_module EmailExclusionList

  def schema_module, do: @schema_module

  def resource do
    %{
      actions: [:new, :edit, :delete],
      index_fields: [
        :id,
        :email,
        :reason,
        :inserted_at,
        :updated_at
      ],
      edit_fields: [
        :email,
        :reason
      ],
      new_fields: [
        :email,
        :reason
      ],
      fields_override: %{
        email: %{
          type: :email
        },
        reason: %{
          type: :textarea
        }
      }
    }
  end
end
