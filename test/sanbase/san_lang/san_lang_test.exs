defmodule Sanbase.SanLangTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.SanLang

  test "literal values are evaluated to themselves" do
    assert SanLang.eval!("1") == 1
    assert SanLang.eval!("3.14") == 3.14
    assert SanLang.eval!(~s|"a string"|) == "a string"
  end

  test "lists" do
    assert SanLang.eval!("[]") == []
    assert SanLang.eval!("[1, 2, 3]") == [1, 2, 3]
    assert SanLang.eval!("[1, 2, 3.14]") == [1, 2, 3.14]
    assert SanLang.eval!("[1, 2, 3.14, \"a string\"]") == [1, 2, 3.14, "a string"]
    assert SanLang.eval!("[1,2,[3,4,[[[5]]]]]") == [1, 2, [3, 4, [[[5]]]]]
  end

  test "env vars are pulled from the environment" do
    env = Environment.new()
    env = Environment.put_env_bindings(env, %{"a" => 1, "b" => "some string value"})

    assert SanLang.eval!("@a", env) == 1
    assert SanLang.eval!("@b", env) == "some string value"
  end

  test "access operator" do
    env = Environment.new()

    env =
      Environment.put_env_bindings(env, %{
        "slugs" => %{"bitcoin" => %{"github_orgs" => ["bitcoin-core-dev", "bitcoin"]}}
      })

    assert SanLang.eval!(~s|@slugs["bitcoin"]|, env) == %{
             "github_orgs" => ["bitcoin-core-dev", "bitcoin"]
           }

    # The access operator can be chained
    assert SanLang.eval!(~s|@slugs["bitcoin"]["github_orgs"]|, env) == [
             "bitcoin-core-dev",
             "bitcoin"
           ]
  end

  test "simple comparisons" do
    assert SanLang.eval!("1 > 2") == false
    assert SanLang.eval!("1 > 0") == true
    assert SanLang.eval!("1 >= 2") == false
    assert SanLang.eval!("5 >= 5") == true
    assert SanLang.eval!("1 == 2") == false
    assert SanLang.eval!("1024 == 1024") == true
    assert SanLang.eval!("1 != 2") == true
    assert SanLang.eval!("10 != 10") == false
  end

  test "simple booleans" do
    assert SanLang.eval!("true") == true
    assert SanLang.eval!("false") == false
    assert SanLang.eval!("true and false") == false
    assert SanLang.eval!("true and true") == true
    assert SanLang.eval!("true or false") == true
    assert SanLang.eval!("false or false") == false
  end

  test "arithmetic" do
    assert SanLang.eval!("1 + 2") == 3
    assert SanLang.eval!("1 - 2") == -1
    assert SanLang.eval!("2 * 3") == 6
    assert SanLang.eval!("1 + 2 * 3 + 10") == 17
    # The function div/2 is used for integer division
    assert SanLang.eval!("6 / 2") == 3.0
    assert SanLang.eval!("6 / 4") == 1.5
  end

  test "combining arithmetic, boolean comparisons and function calls" do
    assert SanLang.eval!("20 > 5 and 10 < 20") == true
    assert SanLang.eval!("pow(2, 10) > 1000") == true
    assert SanLang.eval!("pow(2, 10) < 1000") == false
    assert SanLang.eval!("pow(2, 10) == 1024") == true
    assert SanLang.eval!("20 + 5 > 24") == true
    assert SanLang.eval!("20 + 5 > 24 and 20 + 5 < 30") == true
    assert SanLang.eval!("20 + 5  * 2 > 29 and 20 + 5 < 30") == true
  end

  test "named function calls with literal args" do
    assert SanLang.eval!("pow(2, 10)") == 1024
    assert SanLang.eval!("div(6, 4)") == 1
  end

  test "map/2" do
    env = Environment.new()

    env =
      Environment.put_env_bindings(env, %{
        "data" => [1, 2, 3]
      })

    assert SanLang.eval!("map(@data, fn x -> x * 2 end)", env) == [2, 4, 6]
    assert SanLang.eval!("map(@data, fn val -> val end)", env) == [1, 2, 3]
  end

  test "filter/2" do
    env = Environment.new()

    env =
      Environment.put_env_bindings(env, %{
        "data" => [%{"key" => 1}, %{"key" => 2}, %{"key" => 3}],
        "data2" => [1, 2, 3.14, 4, 5, 6.15]
      })

    assert SanLang.eval!(~s|filter(@data, fn x -> x["key"] >= 3 end)|, env) == [%{"key" => 3}]
    assert SanLang.eval!(~s|filter(@data2, fn x -> x >= 3 end)|, env) == [3.14, 4, 5, 6.15]
    assert SanLang.eval!(~s|filter(@data2, fn x -> x > 3 and x <= 5.5 end)|, env) == [3.14, 4, 5]
  end

  test "map/2 + flat_map/2 + map_keys/1" do
    env = Environment.new()

    env =
      Environment.put_env_bindings(env, %{
        "projects" => %{
          "bitcoin" => %{"github_organizations" => ["bitcoin", "bitcoin-core-dev"]},
          "santiment" => %{"github_organizations" => ["santiment"]}
        }
      })

    assert SanLang.eval!(
             ~s|flat_map(map_keys(@projects), fn slug -> @projects[slug]["github_organizations"] end)|,
             env
           ) == ["bitcoin", "bitcoin-core-dev", "santiment"]

    assert SanLang.eval!(
             ~s|map(map_keys(@projects), fn slug -> @projects[slug]["github_organizations"] end)|,
             env
           ) == [["bitcoin", "bitcoin-core-dev"], ["santiment"]]
  end

  test "arithmetic, env vars and access operator" do
    env =
      Environment.new()
      |> Environment.put_env_bindings(%{"pi" => 3.14, "vals" => %{"pi" => 3.14}})

    assert SanLang.eval!("@pi * 1000", env) == 3140.0
    assert SanLang.eval!(~s|@vals["pi"] * 1000|, env) == 3140.0
  end
end
