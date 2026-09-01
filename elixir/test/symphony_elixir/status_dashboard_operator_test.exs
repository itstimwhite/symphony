defmodule SymphonyElixir.StatusDashboardOperatorTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.{BuildInfo, DeliveryHistory, StatusDashboard}

  @ansi ~r/\e\[[0-9;]*m/
  @now ~U[2026-09-01 15:40:00Z]

  test "running rows keep stable id, title, lifecycle, and current action separate" do
    snapshot =
      {:ok,
       %{
         running: [
           %{
             identifier: "JOV-5721",
             title: "PR 16561: add live rendered component evaluation",
             state: "In Progress",
             codex_total_tokens: 12_345,
             runtime_seconds: 90,
             turn_count: 2,
             last_codex_event: :notification,
             last_codex_message: %{
               event: :notification,
               message: %{
                 "method" => "codex/event/exec_command_begin",
                 "params" => %{"msg" => %{"command" => "pnpm test component-ship-gate"}}
               }
             }
           }
         ],
         retrying: [],
         blocked: [],
         recent_landed: [],
         codex_totals: %{input_tokens: 12_000, output_tokens: 345, total_tokens: 12_345, seconds_running: 90},
         rate_limits: nil,
         artifact: artifact_receipt()
       }}

    plain =
      snapshot
      |> StatusDashboard.format_snapshot_content_for_test(0.0, 430, @now)
      |> strip_ansi()

    assert plain =~ "ID"
    assert plain =~ "TITLE"
    assert plain =~ "LIFECYCLE"
    assert plain =~ "ACTION"
    assert plain =~ "JOV-5721"
    assert plain =~ "PR 16561: add live rendered component evaluation"
    assert plain =~ "Verifying"
    assert plain =~ "command started: pnpm test component-ship-gate"
  end

  test "running rows use honest fallbacks instead of replacing the title with the action" do
    row =
      StatusDashboard.format_running_summary_for_test(
        %{
          identifier: "JOV-1",
          title: nil,
          state: "In Progress",
          codex_total_tokens: 0,
          runtime_seconds: 0,
          turn_count: 0,
          last_codex_event: nil,
          last_codex_message: nil
        },
        180
      )
      |> strip_ansi()

    assert row =~ "JOV-1"
    assert row =~ "(untitled)"
    assert row =~ "Bootstrapping"
    assert row =~ "Waiting for first event"
  end

  test "lifecycle classification only promotes states supported by action evidence" do
    assert StatusDashboard.lifecycle_for_test("In Progress", nil, nil) == "Bootstrapping"
    assert StatusDashboard.lifecycle_for_test("Merging", :notification, "waiting in merge queue") == "Queued"
    assert StatusDashboard.lifecycle_for_test("In Progress", :notification, "running Playwright dogfood") == "Dogfooding"
    assert StatusDashboard.lifecycle_for_test("In Progress", :notification, "editing status dashboard") == "Building"
    assert StatusDashboard.lifecycle_for_test("In Progress", :notification, "thinking about the issue") == "Active"
    refute StatusDashboard.lifecycle_for_test("Done", :notification, "turn completed") == "Landed"
  end

  test "recent landed section renders at most five native merges with whole-minute age and proof tiers" do
    recent_landed =
      for minute <- 1..6 do
        %{
          identifier: "PR ##{17_000 + minute}",
          title: "Merged item #{minute}",
          disposition: "Landed",
          merged_at: DateTime.add(@now, -minute * 60, :second),
          proof: %{source: true, ci: minute == 1, deployment: false, runtime: false, dogfood: false}
        }
      end

    snapshot =
      {:ok,
       %{
         running: [],
         retrying: [],
         blocked: [],
         recent_landed: recent_landed,
         codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
         rate_limits: nil,
         artifact: artifact_receipt()
       }}

    plain =
      snapshot
      |> StatusDashboard.format_snapshot_content_for_test(0.0, 430, @now)
      |> strip_ansi()

    assert plain =~ "Recent landed · native merge proof"
    assert plain =~ "PR #17001"
    assert plain =~ "1 min ago"
    assert plain =~ "source✓ ci✓ deploy— runtime— dogfood—"
    assert plain =~ "PR #17005"
    refute plain =~ "PR #17006"
  end

  test "artifact receipt is visible in the persistent header" do
    line = StatusDashboard.format_artifact_receipt_for_test(artifact_receipt()) |> strip_ansi()

    assert line =~ "Artifact: symphony 0.0.2"
    assert line =~ "source 119f28a"
    assert line =~ "build gem-20260901-1540"
    assert line =~ "built 2026-09-01T15:40:00Z"
    assert line =~ "host gem"
  end

  test "build receipt keeps missing compile and host provenance visibly unknown" do
    assert %{version: "unknown", host: "unknown"} =
             BuildInfo.current(application_version: nil, hostname_result: {:error, :unavailable})

    assert %{version: "0.0.2", host: "gem"} =
             BuildInfo.current(application_version: ~c"0.0.2", hostname_result: {:ok, ~c"gem"})
  end

  test "delivery history accepts only native merged_at evidence and keeps proof tiers separate" do
    body = [
      %{
        "number" => 16_883,
        "title" => "fix(ci): preserve queue proof",
        "html_url" => "https://github.com/JovieInc/Jovie/pull/16883",
        "merged_at" => "2026-09-01T15:20:00Z",
        "merge_commit_sha" => "4083927"
      },
      %{
        "number" => 16_884,
        "title" => "closed without merge",
        "html_url" => "https://github.com/JovieInc/Jovie/pull/16884",
        "merged_at" => nil,
        "merge_commit_sha" => nil
      }
    ]

    assert [entry] = DeliveryHistory.parse_github_pulls_for_test(body)
    assert entry.identifier == "PR #16883"
    assert entry.disposition == "Landed"
    assert entry.proof == %{source: true, ci: false, deployment: false, runtime: false, dogfood: false}
    assert entry.merge_commit_sha == "4083927"
  end

  test "delivery history turns request crashes into retryable errors" do
    assert {:error, {:request_failed, %RuntimeError{message: "boom"}}} =
             DeliveryHistory.fetch("JovieInc/Jovie", request_fun: fn _opts -> raise "boom" end)
  end

  test "delivery history validates repositories and GitHub responses" do
    assert {:error, :invalid_repository} = DeliveryHistory.fetch("not-a-repository")
    assert {:error, :invalid_repository} = DeliveryHistory.fetch(:not_a_repository, [])

    assert {:error, {:request_failed, {:throw, :boom}}} =
             DeliveryHistory.fetch("JovieInc/Jovie", request_fun: fn _opts -> throw(:boom) end)

    assert {:error, {:github_status, 503}} =
             DeliveryHistory.fetch("JovieInc/Jovie",
               request_fun: fn _opts -> {:ok, %Req.Response{status: 503, body: %{}}} end
             )

    assert {:error, {:invalid_github_response, :unexpected}} =
             DeliveryHistory.fetch("JovieInc/Jovie", request_fun: fn _opts -> {:ok, :unexpected} end)

    assert {:ok, []} =
             DeliveryHistory.fetch("JovieInc/Jovie",
               request_fun: fn _opts -> {:ok, %Req.Response{status: 200, body: []}} end
             )
  end

  test "delivery history skips malformed bodies and merge timestamps" do
    assert DeliveryHistory.parse_github_pulls_for_test(:invalid) == []

    assert DeliveryHistory.parse_github_pulls_for_test([
             %{"number" => 16_885, "title" => "bad timestamp", "merged_at" => "not-a-date"}
           ]) == []
  end

  defp artifact_receipt do
    %{
      name: "symphony",
      version: "0.0.2",
      source_sha: "119f28a",
      build_id: "gem-20260901-1540",
      built_at: "2026-09-01T15:40:00Z",
      host: "gem"
    }
  end

  defp strip_ansi(value), do: Regex.replace(@ansi, value, "")
end
