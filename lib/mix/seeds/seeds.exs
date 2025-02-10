# Run with:
# INSIGHTS_DISCORD_NOTIFICATION_ENABLED=false CLICKHOUSE_REPO_ENABLED=false mix run lib/mix/seeds/seeds.exs
import Sanbase.Factory
import Sanbase.Factory.Helper

alias Sanbase.Alert.UserTrigger
alias Sanbase.Insight.Post
alias Sanbase.UserList

:ok = Mix.Task.run("database_safety", [])

Faker.start()

# Seed the rand so all runs will lead to the same results
seed_tuple = {715_566_094, 2_738_681_417, 417_273_525}
:rand.seed(:exsplus, seed_tuple)
:random.seed(seed_tuple)

####################
##      Users     ##
####################
users =
  Enum.map(1..20, fn _ ->
    insert(:user)
  end)

rand_user = fn -> Enum.random(users) end

####################
##    Projects    ##
####################
erc20_projects =
  Enum.map(1..30, fn _ ->
    insert(:random_erc20_project)
  end)

projects = erc20_projects ++ Enum.map(1..50, fn _ -> insert(:random_project) end)

rand_erc20_project = fn -> Enum.random(erc20_projects) end
rand_project = fn -> Enum.random(projects) end

rand_projects_sublist = fn ->
  projects |> Enum.shuffle() |> Enum.take(:rand.uniform(length(projects)))
end

####################
##   Watchlists   ##
####################
watchlists =
  Enum.map(1..30, fn _ ->
    user = rand_user.()
    watchlist_projects = rand_projects_sublist.()

    watchlist =
      UserList.create_user_list(user, %{
        name: Faker.Cat.En.registry(),
        list_items: Enum.map(watchlist_projects, fn p -> %{project_id: p.id} end)
      })
  end)

####################
##     Alerts     ##
####################

user_triggers =
  Enum.map(1..30, fn _ ->
    user = rand_user.()
    trigger_settings = rand_trigger_settings(rand_project, rand_erc20_project)

    {:ok, trigger} =
      UserTrigger.create_user_trigger(user, %{
        title: Faker.Cat.En.registry(),
        is_public: Enum.random([true, false]),
        cooldown: rand_interval(),
        settings: trigger_settings
      })

    trigger
  end)

####################
##    Insights    ##
####################
rand_insight = fn user ->
  Post.create(user, %{
    title: Faker.Pokemon.name() <> " in " <> Faker.Pokemon.location(),
    short_desc: Faker.Lorem.Shakespeare.En.hamlet(),
    text: Faker.StarWars.En.quote() <> "\n\n" <> Faker.StarWars.En.quote()
  })
end

unpublished_insights =
  Enum.map(1..10, fn _ ->
    user = rand_user.()

    {:ok, insight} = rand_insight.(user)
    insight
  end)

insights =
  Enum.map(1..30, fn _ ->
    user = rand_user.()

    {:ok, insight} = rand_insight.(user)
    {:ok, insight} = Post.publish(insight.id, user.id)
    insight
  end)
