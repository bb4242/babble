File.mkdir_p(Path.dirname(JUnitFormatter.get_report_file_path()))
ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])

Application.stop(:babble)
Port.open({:spawn, "epmd -daemon"}, [])
Node.start(:"test-primary@127.0.0.1", :longnames)
:crypto.strong_rand_bytes(24) |> Base.url_encode64() |> String.to_atom() |> Node.set_cookie()
Application.start(:babble)

ExUnit.start()
