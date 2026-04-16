defmodule CortexEx.MCP.Tools.Tests do
  @moduledoc false

  def tools do
    [
      %{
        name: "run_impacted_tests",
        description: """
        Runs the test files that correspond to the given changed files.
        For each file like `lib/foo/bar.ex`, attempts to find and run
        `test/foo/bar_test.exs`. Files that don't have a corresponding
        test file are skipped. Returns combined test output.
        """,
        inputSchema: %{
          type: "object",
          required: ["files"],
          properties: %{
            files: %{
              type: "array",
              items: %{type: "string"},
              description: "List of changed source files (e.g., ['lib/my_app/accounts.ex'])"
            }
          }
        },
        callback: &run_impacted_tests/1
      },
      %{
        name: "run_stale_tests",
        description: """
        Runs `mix test --stale` which uses the Elixir compiler's stale
        detection to run only tests affected by recent changes.
        Returns test output with pass/fail counts and duration.
        """,
        inputSchema: %{type: "object", properties: %{}},
        callback: &run_stale_tests/1
      }
    ]
  end

  def run_impacted_tests(%{"files" => files}) when is_list(files) do
    test_files =
      files
      |> Enum.map(&file_to_test/1)
      |> Enum.filter(&File.exists?/1)
      |> Enum.uniq()

    if test_files == [] do
      {:ok, "No corresponding test files found for changed files."}
    else
      run_tests(test_files)
    end
  rescue
    e -> {:error, "run_impacted_tests failed: #{Exception.message(e)}"}
  end

  def run_impacted_tests(_), do: {:error, "files parameter is required (must be a list)"}

  def run_stale_tests(_args) do
    try do
      {output, exit_code} = System.cmd("mix", ["test", "--stale"], stderr_to_stdout: true)
      {:ok, "Exit: #{exit_code}\n\n#{output}"}
    rescue
      e -> {:error, "run_stale_tests failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Maps a source file to its corresponding test file path.

  ## Examples

      iex> CortexEx.MCP.Tools.Tests.file_to_test("lib/my_app/accounts.ex")
      "test/my_app/accounts_test.exs"

      iex> CortexEx.MCP.Tools.Tests.file_to_test("lib/foo/bar/baz.ex")
      "test/foo/bar/baz_test.exs"
  """
  def file_to_test(file) when is_binary(file) do
    file
    |> String.replace(~r/^lib\//, "test/")
    |> String.replace(~r/\.ex$/, "_test.exs")
  end

  defp run_tests(files) do
    args = ["test" | files]
    {output, exit_code} = System.cmd("mix", args, stderr_to_stdout: true)
    {:ok, "Exit: #{exit_code}\n\nTest files: #{Enum.join(files, ", ")}\n\n#{output}"}
  end
end
