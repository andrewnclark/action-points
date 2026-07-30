# `:eval` is the classification evaluation suite in `test/eval`: real API
# calls, model output rather than application logic, and so excluded from the
# default run and from any automated one. It is run deliberately, and always
# when the extraction prompt changes — see its @moduledoc.
ExUnit.start(exclude: [:eval])
Ecto.Adapters.SQL.Sandbox.mode(ActionPoints.Repo, :manual)
