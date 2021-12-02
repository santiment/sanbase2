defmodule Sanbase.Insight.Post.Ecto do
  defmacro is_public(post) do
    quote bind_quoted: [post: post] do
      fragment("?.ready_state = 'published' and ?.state = 'approved'", ^post)
    end
  end
end
