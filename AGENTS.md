This is a web application built with the Phoenix web framework.

## Project guidelines

- When you are done with all changes, run the `mix precommit` alias and fix any pending issues
- Use the already included `Req` library for HTTP requests. **Avoid** `:httpoison`, `:tesla` and `:httpc` — Req is the preferred HTTP client for Phoenix apps

### Phoenix v1.8

- **Always** begin LiveView templates with `<Layouts.app flash={@flash} ...>`, which wraps all inner content. `Layouts` is already aliased in `sanbase_web.ex`, so don't alias it again
- If you get errors about a missing `current_scope` assign, the route is in the wrong `live_session` or you didn't pass `current_scope` to `<Layouts.app>`. **Always** fix it by moving the route to the proper `live_session` and passing `current_scope` as needed
- Phoenix v1.8 moved `<.flash_group>` to the `Layouts` module. **Never** call it outside `layouts.ex`
- `core_components.ex` provides `<.icon name="hero-x-mark" class="w-5 h-5"/>` for hero icons. **Always** use `<.icon>`, **never** `Heroicons` modules or similar
- **Always** use the imported `<.input>` component from `core_components.ex` for form inputs — it saves steps and prevents errors. If you pass your own `class`, no default classes are inherited, so your classes must fully style the input

### JS and CSS

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, visually stunning interfaces
- Tailwind v4 **no longer needs a `tailwind.config.js`** and uses a new import syntax in `app.css`. **Always use and maintain it**:

      @import "tailwindcss" source(none);
      @source "../js";
      @source "../../lib/sanbase_web.ex";
      @source "../../lib/sanbase_web";

- **Never** use `@apply` in raw CSS
- **Always** hand-write your own Tailwind-based components instead of using daisyUI, for a unique, world-class design
- Only the `app.js` and `app.css` bundles are supported:
  - You cannot reference external vendored script `src` or link `href` in the layouts
  - Import vendor deps into `app.js` and `app.css` to use them
  - **Never write inline `<script>` tags in templates** (use colocated hooks, see below)

### UI/UX & design

- **Produce world-class UI** focused on usability, aesthetics and modern design principles
- Add **subtle micro-interactions** (button hover effects, smooth transitions)
- Ensure **clean typography, spacing and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states and smooth page transitions

## Elixir

- Lists **do not support index-based access** via the access syntax:

      # INVALID
      mylist = ["blue", "green"]
      mylist[i]

      # VALID — use Enum.at, pattern matching or List
      Enum.at(mylist, i)

- Variables are immutable but can be rebound. For block expressions (`if`, `case`, `cond`, ...) you **must** bind the result to a variable to use it — rebinding inside the expression has no effect outside it:

      # INVALID: rebinding inside the `if`, the result is never assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: bind the result of the `if`
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file — it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`struct[:field]`) on structs; they don't implement Access by default. Access fields directly (`my_struct.field`) or use higher-level APIs where they exist, such as `Ecto.Changeset.get_field/2` for changesets
- The standard library covers date and time — check the docs for `Time`, `Date`, `DateTime` and `Calendar`. **Never** install extra dependencies unless asked, except `date_time_parser` for date/time parsing
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names end with `?` and don't start with `is_`. Reserve names like `is_thing` for guards
- OTP primitives like `DynamicSupervisor` and `Registry` require a name in the child spec, e.g. `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. Most of the time pass `timeout: :infinity`

## Mix

- Read a task's docs and options (`mix help task_name`) before using it
- To debug test failures, run a single file with `mix test test/my_test.exs` or rerun failures with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** it unless you have a good reason

## Tests

- **Always** use `start_supervised!/1` to start processes in tests — it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests:
  - To wait for a process to finish, **always** monitor it and assert on the DOWN message:

        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

  - To synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages

## Phoenix

- Router `scope` blocks take an optional alias that is prefixed to every route inside. Keep this in mind to avoid duplicate module prefixes — you **never** need your own `alias` for routes:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index  # points to AppWeb.Admin.UserLive
      end

- `Phoenix.View` is no longer needed or included — don't use it

## Ecto

- **Always** preload associations in queries when templates access them (e.g. `message.user.email`)
- Remember `import Ecto.Query` and other supporting modules in `seeds.exs`
- `Ecto.Schema` fields use `:string` even for `:text` columns: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **does not support `:allow_nil`**. It isn't needed: validations only run when the field has a non-nil change
- **Always** use `Ecto.Changeset.get_field(changeset, :field)` to read changeset fields
- Programmatically set fields such as `user_id` must **not** be listed in `cast` or similar (security). Set them explicitly when creating the struct
- **Always** generate migrations with `mix ecto.gen.migration migration_name_using_underscores` so the correct timestamp and conventions are applied

## Phoenix HTML (HEEx)

- Templates **always** use `~H` or `.html.heex` files, **never** `~E`
- **Always** build forms with the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1`. **Never** use the outdated `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for`
- **Always** add unique DOM IDs to key elements (forms, buttons, etc.) so tests can use them: `<.form for={@form} id="product-form">`
- For app-wide template imports/aliases, add them to the `html_helpers` block in `sanbase_web.ex`; they become available to all LiveViews, LiveComponents and modules that `use SanbaseWeb, :html`
- Elixir has `if/else` but **no `else if` or `elsif`**. **Always** use `cond` or `case` for multiple conditions:

      <%!-- INVALID --%>
      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

      <%!-- VALID --%>
      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- Literal `{` or `}` need an annotation. To show a code snippet in `<pre>` or `<code>`, **always** add `phx-no-curly-interpolation` to the parent tag. Inside it you can use `{` and `}` unescaped, and `<%= ... %>` still works:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

- Class attrs support lists, and you **must** use the `[...]` syntax for multiple or conditional classes. **Always** wrap `if` inside `{...}` expressions in parens:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

      <%!-- INVALID: missing [ and ] raises a compile error --%>
      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...

- **Never** use `<% Enum.each %>` or non-`for` comprehensions to generate template content. **Always** use `<%= for item <- @collection do %>`
- **Always** use HEEx comments: `<%!-- comment --%>`
- Interpolation: `<%= ... %>` **only** works in tag bodies. **Always** use `{...}` in attributes and for values in tag bodies, and `<%= ... %>` for block constructs (`if`, `cond`, `case`, `for`) in tag bodies:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

      <%!-- INVALID: syntax error --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>

## Phoenix LiveView

- **Never** use the deprecated `live_redirect` and `live_patch`. Use `<.link navigate={href}>` and `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` in LiveViews
- **Avoid LiveComponents** unless you have a strong, specific need
- Name LiveViews with a `Live` suffix, like `AppWeb.WeatherLive`. The default `:browser` scope is **already aliased** with `AppWeb`, so the route is just `live "/weather", WeatherLive`

### Streams

- **Always** use streams for collections instead of assigning plain lists, to avoid memory ballooning and runtime termination:
  - append N items: `stream(socket, :messages, [new_msg])`
  - reset with new items (e.g. filtering): `stream(socket, :messages, [new_msg], reset: true)`
  - prepend: `stream(socket, :messages, [new_msg], at: -1)`
  - delete: `stream_delete(socket, :messages, msg)`
- In the template, the parent element **must** have `phx-update="stream"` and a DOM id, and children consume `@streams.stream_name`, using the stream id as their DOM id:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- Streams are **not enumerable** — no `Enum.filter/2` or `Enum.reject/2`. To filter, prune or refresh items, **refetch the data and re-stream the whole collection with `reset: true`**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         |> stream(:messages, messages, reset: true)}
      end

- Streams **don't support counting or empty states**. Track counts in a separate assign. For empty states, use Tailwind — this only works if the empty state is the only other element alongside the `:for`:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

- When an assign change should affect content inside streamed items, you **must** re-stream those items along with the assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # re-insert so the @editing_message_id check re-renders for this item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

  And in the template:

      <div id="messages" phx-update="stream">
        <div :for={{id, message} <- @streams.messages} id={id} class="flex group">
          {message.username}
          <%= if @editing_message_id == message.id do %>
            <.form for={@edit_form} id="edit-form-#{message.id}" phx-submit="save_edit">
              ...
            </.form>
          <% end %>
        </div>
      </div>

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"`

### JavaScript interop

- If a `phx-hook` manages its own DOM, you **must** also set `phx-update="ignore"`
- **Always** give a `phx-hook` element a unique DOM id, otherwise compilation fails

Hooks come in two flavors: colocated hooks defined inline in HEEx, and external hooks passed to the `LiveSocket` constructor.

#### Colocated hooks

**Never** write raw `<script>` tags in HEEx — they're incompatible with LiveView. **Always** use a colocated hook (`:type={Phoenix.LiveView.ColocatedHook}`). They're bundled into `app.js` automatically, and their names **must** start with `.`:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

#### External hooks

External hooks (`<div id="myhook" phx-hook="MyHook">`) **must** be placed in `assets/js/` and passed to the `LiveSocket` constructor:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

#### Pushing events

Use `push_event/3` to send data to a hook. **Always** rebind or return the socket so the event isn't lost:

    socket = push_event(socket, "my_event", %{...})

    # or
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

The hook receives it with `this.handleEvent`:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

Clients can push to the server and get a reply with `this.pushEvent`:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

    # server side
    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

### LiveView tests

- Use `Phoenix.LiveViewTest` and `LazyHTML` (included) for assertions. Drive form tests with `render_submit/2` and `render_change/2`
- Plan tests step by step, splitting major cases into small, isolated files. Start with tests that check content exists, then add interaction tests
- **Always** reference the DOM IDs you added in templates in `element/2`, `has_element?/2`, selectors, etc.
- **Never** test against raw HTML. **Always** use `element/2`, `has_element?/2` and similar: `assert has_element?(view, "#my-form")`
- Prefer testing for key elements over text content (which changes), and outcomes over implementation details
- Components like `<.form>` may produce different HTML than you expect. Test against the actual output, not your mental model
- When debugging selector failures, print the actual HTML but narrow it with `LazyHTML` selectors:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Forms

**From params** — `to_form/1` treats a map as form params with string keys. Use `:as` to nest them:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

**From changesets** — data, params, errors and the `:as` name all come from the changeset. For a `MyApp.Users.User` schema, submitted params arrive as `%{"user" => user_params}`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

In the template, pass the form assign to `<.form>` and **always** give it a unique DOM id:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

**Avoiding form errors:**

- **Always** assign the form with `to_form/2` in the LiveView and use `<.input>` in the template. The UI should **always** be driven by a `to_form/2` assign derived from a changeset
- **Never** access the changeset in the template — `<.form for={@changeset}>` or `@changeset[:field]` will cause errors
- **Never** use `<.form let={f} ...>`. **Always** use `<.form for={@form} ...>` and reference fields as `@form[:field]`
