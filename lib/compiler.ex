defmodule Mix.Tasks.Compile.Lumen do
  use Mix.Task.Compiler

  @recursive true
  @manifest "compile.lumen"
  @switches [force: :boolean]

  @manifest_vsn 1

  def manifests() do
    [manifest_path()]
  end

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    manifest = manifest_path()
    build_dir = Mix.Project.build_path()
    beams = 
      Path.wildcard(Path.join(build_dir, "lib/*/ebin/*.beam"))
    compile(manifest, beams, opts)
  end

  def clean() do
    manifest = manifest_path()
    Enum.each(read_manifest(manifest), fn {file, _} -> File.rm(file) end)
    File.rm(manifest)
  end

  defp compile(manifest, beams, opts) do
    stale = for {:stale, src, dest} <- extract_targets(beams, opts), do: {src, dest}

    # Get the previous entries from the manifest
    timestamp = :calendar.universal_time()
    entries = read_manifest(manifest)

    # Files to remove are the ones in the manifest
    # but they no longer have a source
    removed =
      MapSet.new(Enum.map(entries, fn {_, dest} -> dest end))
      |> MapSet.difference(MapSet.new(beams))

    # Remove manifest entries with no source
    Enum.each(removed, &File.rm/1)
    verbose = opts[:verbose]

    # Clear stale and removed files from manifest
    entries =
      Enum.reject(entries, fn {dest, _warnings} ->
        MapSet.member?(removed, dest) || Enum.any?(stale, fn {_, stale_dest} -> dest == stale_dest end)
    end)

    if opts[:all_warnings], do: show_warnings(entries)

    if stale == [] && MapSet.size(removed) == 0 do
      {:noop, manifest_warnings(entries)}
    else
      Mix.Utils.compiling_n(length(stale), "beam")

      # Compile stale files and print the results
      {status, new_entries, errors} =
        do_compile(stale, timestamp, verbose)

      write_manifest(manifest, entries ++ new_entries, timestamp)

      case status do
        :ok ->
          {:ok, []}

        :error ->
          {:error, errors}
      end
    end
  end

  defp do_compile(stale, timestamp, verbose) do
    do_compile(stale, timestamp, verbose, {:ok, [], []})
  end

  defp do_compile([{input, output} | rest], timestamp, verbose, {status, entries, errors}) do
    with {:ok, forms} <- extract_abstract_code(input) do

      # Format the forms to the same listing format as +dabstr
      {:ok, pid} = StringIO.open("")
      :beam_listing.module(pid, forms)
      {:ok, {_, abstr}} = StringIO.close(pid)

      File.write!(output, abstr)
      verbose && Mix.shell().info("Compiled #{input}")
      do_compile(rest, timestamp, verbose, {status, [{output, []} | entries], errors})
    else
      {:error, reason} ->
        error =
          %Mix.Task.Compiler.Diagnostic{
            file: input,
            severity: :error,
            message: "#{reason}",
            position: nil,
            compiler_name: "lumen",
            details: nil,
          }
        do_compile(rest, timestamp, verbose, {:error, entries, [error | errors]})
    end
  end
  defp do_compile([], _timestamp, _verbose, result), do: result

  defp extract_abstract_code(path) do
    chunks = :beam_lib.chunks(String.to_charlist(path), [:abstract_code])
    case chunks do
      {:ok, {_mod, [abstract_code: {:raw_abstract_v1, forms}]}} ->
        {:ok, forms}
      {:error, mod, reason} ->
        {:error, mod.format_error(reason)}
    end
  end

  defp extract_targets(beams, opts) do
    force = opts[:force] || false

    for beam <- beams do
      app = app_name_from_path(beam)
      module = module_name_from_path(beam)
      dest_dir = Path.join([Mix.Project.build_path(), "lumen", app, "src"])
      target = Path.join(dest_dir, module <> ".abstr")

      # Ensure target dir exists
      :ok = File.mkdir_p!(dest_dir)

      if force || Mix.Utils.stale?([beam], [target]) do
        {:stale, beam, target}
      else
        {:ok, beam, target}
      end
    end
  end


  # expecting ../<app>/ebin/<module>.beam
  defp module_name_from_path(path) do
    path |> Path.basename() |> Path.rootname()
  end

  # expecting ../<app>/ebin/<module>.beam
  defp app_name_from_path(path) do
    path |> Path.dirname() |> Path.dirname() |> Path.basename()
  end

  # The manifest file contains a list of {dest, warnings} tuples
  defp read_manifest(file) do
    try do
      file |> File.read!() |> :erlang.binary_to_term()
    rescue
      _ -> []
    else
      {@manifest_vsn, data} when is_list(data) -> data
      _ -> []
    end
  end

  defp write_manifest(file, entries, timestamp) do
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, :erlang.term_to_binary({@manifest_vsn, entries}))
    File.touch!(file, timestamp)
  end

  defp manifest_warnings(entries) do
    Enum.flat_map(entries, fn {_, warnings} ->
      to_diagnostics(warnings, :warning)
    end)
  end

  defp to_diagnostics(warnings_or_errors, severity) do
    for {file, issues} <- warnings_or_errors,
        {line, module, data} <- issues do
      %Mix.Task.Compiler.Diagnostic{
        file: Path.absname(file),
        position: line,
        message: to_string(module.format_error(data)),
        severity: severity,
        compiler_name: to_string(module),
        details: data
      }
    end
  end

  defp show_warnings(entries) do
    for {_, warnings} <- entries,
        {file, issues} <- warnings,
        {line, module, message} <- issues do
      IO.puts("#{file}:#{line}: Warning: #{module.format_error(message)}")
    end
  end

  defp manifest_path, do: Path.join(Mix.Project.manifest_path, @manifest)
end
