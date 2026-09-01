defmodule SymphonyElixir.BuildInfo do
  @moduledoc """
  Immutable source and build provenance embedded in a Symphony artifact.

  Release builders should set `SYMPHONY_SOURCE_SHA`, `SYMPHONY_BUILD_ID`, and
  `SYMPHONY_BUILD_TIMESTAMP` before compilation. Missing values remain visibly
  unknown instead of being inferred from the runtime checkout.
  """

  @source_sha System.get_env("SYMPHONY_SOURCE_SHA") || "unknown"
  @build_id System.get_env("SYMPHONY_BUILD_ID") || "unknown"
  @built_at System.get_env("SYMPHONY_BUILD_TIMESTAMP") || "unknown"

  @spec current(keyword()) :: %{
          name: String.t(),
          version: String.t(),
          source_sha: String.t(),
          build_id: String.t(),
          built_at: String.t(),
          host: String.t()
        }
  def current(opts \\ []) do
    application_version =
      Keyword.get_lazy(opts, :application_version, fn ->
        Application.spec(:symphony_elixir, :vsn)
      end)

    hostname_result = Keyword.get_lazy(opts, :hostname_result, &:inet.gethostname/0)

    %{
      name: "symphony",
      version: application_version(application_version),
      source_sha: @source_sha,
      build_id: @build_id,
      built_at: @built_at,
      host: hostname(hostname_result)
    }
  end

  defp application_version(nil), do: "unknown"
  defp application_version(version), do: to_string(version)

  defp hostname({:ok, hostname}), do: to_string(hostname)
  defp hostname(_result), do: "unknown"
end
