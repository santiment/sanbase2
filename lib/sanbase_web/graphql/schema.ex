defmodule SanbaseWeb.Graphql.Schema do
  use Absinthe.Schema
  use Absinthe.Ecto, repo: Sanbase.Repo

  alias Sanbase.Auth.{User, EthAccount}
  alias SanbaseWeb.Graphql.AccountResolver
  alias SanbaseWeb.Graphql.ProjectResolver

  import_types SanbaseWeb.Graphql.AccountTypes
  import_types SanbaseWeb.Graphql.ProjectTypes

  query do
    field :current_user, :user do
      resolve &AccountResolver.current_user/3
    end

    field :all_projects, list_of(:project) do
      arg :only_project_transparency, :boolean

      resolve &ProjectResolver.all_projects/3
    end

    field :project, :project do
      arg :id, non_null(:id)
      arg :only_project_transparency, :boolean # this is to filter the wallets

      resolve &ProjectResolver.project/3
    end
  end

  mutation do
    field :eth_login, :login do
      arg :signature, non_null(:string)
      arg :address, non_null(:string)
      arg :message_hash, non_null(:string)

      resolve &AccountResolver.eth_login/2
    end

    field :change_email, :user do
      arg :email, non_null(:string)

      resolve &AccountResolver.change_email/3
    end

    field :follow_project, :user do
      arg :project_id, non_null(:integer)

      resolve &AccountResolver.follow_project/3
    end

    field :unfollow_project, :user do
      arg :project_id, non_null(:integer)

      resolve &AccountResolver.unfollow_project/3
    end
  end
end
