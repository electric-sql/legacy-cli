defmodule ElectricCli.Progress do
  @moduledoc """
  Run a function whilst displaying progress information.

  When the function is executing, we display the loading text, prefixed by
  animated loading dots. When done, we display the success or failure message
  accordingly.

  ## Examples

    iex> Progress.run("Sleeping ...", fn -> :timer.sleep(1000) end)
    :ok

    iex> Progress.run("Preparing ...", "Prepared.", fn -> :timer.sleep(1000) end)
    :ok

    iex> Progress.run([text: "Lining ...", frame: :lines], fn -> :timer.sleep(1000) end)
    :ok

    iex> with :ok <- Progress.run("Sleeping", "Slept.", fn -> :timer.sleep(2000) end) do
           Progress.run("Getting out of bed", fn -> :timer.sleep(2000) end)
         end

  If the function being run returns `:error` or `{:error, _}` then the done message
  will be the failure message. Otherwise it will be the success message.

  The failure and success messages can be text, or functions that take the
  return value and the options as arguments.
  """

  alias CliSpinners.Spinner
  alias CliSpinners.Utils, as: SpinnerUtils

  @spinner_config [
    done: :remove
  ]

  @defaults [
    frames: :dots,
    text: "Loading",
    success: "Done.",
    failure: :derive,
    min_duration_ms: if(Mix.env() == :test, do: 0, else: 1000)
  ]

  def run(func) do
    run([], func)
  end

  def run(text, success, min_duration_ms, func)
      when is_binary(text) and is_integer(min_duration_ms) do
    run([text: text, success: success, min_duration_ms: min_duration_ms], func)
  end

  def run(text, min_duration_ms, func) when is_binary(text) and is_integer(min_duration_ms) do
    run([text: text, min_duration_ms: min_duration_ms], func)
  end

  def run(text, success, func) when is_binary(text) do
    run([text: text, success: success], func)
  end

  def run(text, func) when is_binary(text) do
    run([text: text], func)
  end

  def run(overrides, func) do
    options = Keyword.merge(@defaults, overrides)

    wrapped_func =
      case options[:min_duration_ms] do
        min_duration_ms when is_integer(min_duration_ms) and min_duration_ms > 0 ->
          fn ->
            run_for_min_duration(func, min_duration_ms)
          end

        _alt ->
          func
      end

    config =
      options
      |> Keyword.take([:frames, :text])
      |> Keyword.merge(@spinner_config)

    config =
      case String.ends_with?(config[:text], "…") do
        false ->
          Keyword.put(config, :text, "#{config[:text]} … ")

        true ->
          config
      end

    config
    |> Spinner.render(wrapped_func)
    |> handle_result(options)
  end

  defp run_for_min_duration(func, min_duration_ms)
       when is_function(func) and is_integer(min_duration_ms) do
    t1 = Time.utc_now()

    retval = func.()

    ms_elapsed =
      Time.utc_now()
      |> Time.diff(t1, :microsecond)
      |> Kernel./(1_000)
      |> Kernel.trunc()

    ms_remaining = min_duration_ms - ms_elapsed

    if ms_remaining > 0 do
      :timer.sleep(ms_remaining)
    end

    retval
  end

  defp handle_result(:error = result, options) do
    render_done(options[:failure], result, options)
  end

  defp handle_result({:error, _} = result, options) do
    render_done(options[:failure], result, options)
  end

  defp handle_result(result, options) do
    render_done(options[:success], result, options)
  end

  defp render_done(func, result, options) when is_function(func) do
    result
    |> func.(options)
    |> render_done(result, nil)
  end

  defp render_done(:derive, result, options) do
    "#{options[:text]} failed."
    |> render_done(result, nil)
  end

  defp render_done(text, result, _options) when is_binary(text) do
    :ok = IO.write([SpinnerUtils.ansi_prefix(), text, "\n"])

    result
  end

  defp render_done(false, result, _options) do
    result
  end
end
