# Hunk mode, for agents: `mix format --dot-formatter .formatter.agent.exs FILE`. Keeps Quokka's
# rewrites inside the lines just written; the module-wide ones (directive sorting, alias lifting,
# autosort) wait for a plain `mix format`, after which the agent re-reads the file.
{base, _} = Code.eval_file(Path.join(__DIR__, ".formatter.exs"))
module_wide = [:module_directives, :autosort, :configs]

Keyword.update(base, :quokka, [exclude: module_wide], fn quokka ->
  Keyword.update(quokka, :exclude, module_wide, &(&1 ++ module_wide))
end)
