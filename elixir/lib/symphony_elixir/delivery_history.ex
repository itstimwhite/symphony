defmodule SymphonyElixir.DeliveryHistory do
  @moduledoc """
  Fetches recent native GitHub merge evidence for the operator dashboard.

  A pull request is reported as landed only when GitHub supplies a non-null
  `merged_at`. Other proof tiers remain false unless a stronger evidence source
  explicitly supplies them.
  """

  @github_api "https://api.github.com"
  @github_accept "application/vnd.github+json"
  @github_api_version "2022-11-28"
  @recent_limit 5

  @type landing :: %{
          identifier: String.t(),
          title: String.t(),
          disposition: String.t(),
          merged_at: DateTime.t(),
          merge_commit_sha: String.t() | nil,
          url: String.t() | nil,
          proof: %{
            source: boolean(),
            ci: boolean(),
            deployment: boolean(),
            runtime: boolean(),
            dogfood: boolean()
          }
        }

  @spec fetch(String.t(), keyword()) :: {:ok, [landing()]} | {:error, term()}
  def fetch(repository, opts \\ [])

  @spec fetch(String.t(), keyword()) :: {:ok, [landing()]} | {:error, term()}
  def fetch(repository, opts) when is_binary(repository) do
    with :ok <- validate_repository(repository),
         {:ok, response} <- request(repository, opts),
         :ok <- validate_response(response) do
      {:ok, parse_github_pulls(response.body)}
    end
  end

  def fetch(_repository, _opts), do: {:error, :invalid_repository}

  @doc false
  @spec parse_github_pulls_for_test(term()) :: [landing()]
  def parse_github_pulls_for_test(body), do: parse_github_pulls(body)

  defp request(repository, opts) do
    request_fun = Keyword.get(opts, :request_fun, &Req.get/1)
    api_base = Keyword.get(opts, :api_base, @github_api)

    try do
      request_fun.(
        url: "#{api_base}/repos/#{repository}/pulls",
        params: [state: "closed", sort: "updated", direction: "desc", per_page: 30],
        headers: [
          {"accept", @github_accept},
          {"x-github-api-version", @github_api_version},
          {"user-agent", "symphony-operator-dashboard"}
        ],
        receive_timeout: Keyword.get(opts, :receive_timeout, 10_000),
        decode_body: true
      )
    rescue
      error -> {:error, {:request_failed, error}}
    catch
      kind, reason -> {:error, {:request_failed, {kind, reason}}}
    end
  end

  defp validate_response(%Req.Response{status: 200, body: body}) when is_list(body), do: :ok
  defp validate_response(%Req.Response{status: status}), do: {:error, {:github_status, status}}
  defp validate_response(response), do: {:error, {:invalid_github_response, response}}

  defp validate_repository(repository) do
    if Regex.match?(~r/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/, repository) do
      :ok
    else
      {:error, :invalid_repository}
    end
  end

  defp parse_github_pulls(body) when is_list(body) do
    body
    |> Enum.reduce([], fn pull, entries ->
      case parse_landing(pull) do
        {:ok, landing} -> [landing | entries]
        :skip -> entries
      end
    end)
    |> Enum.sort_by(& &1.merged_at, {:desc, DateTime})
    |> Enum.take(@recent_limit)
  end

  defp parse_github_pulls(_body), do: []

  defp parse_landing(%{"number" => number, "title" => title, "merged_at" => merged_at} = pull)
       when is_integer(number) and is_binary(title) and is_binary(merged_at) do
    case DateTime.from_iso8601(merged_at) do
      {:ok, merged_at, _offset} ->
        {:ok,
         %{
           identifier: "PR ##{number}",
           title: title,
           disposition: "Landed",
           merged_at: merged_at,
           merge_commit_sha: Map.get(pull, "merge_commit_sha"),
           url: Map.get(pull, "html_url"),
           proof: %{source: true, ci: false, deployment: false, runtime: false, dogfood: false}
         }}

      _ ->
        :skip
    end
  end

  defp parse_landing(_pull), do: :skip
end
