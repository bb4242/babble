# Configure JUnit test report
File.mkdir_p(Path.dirname(JUnitFormatter.get_report_file_path()))
ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])

# Babble requires knowing the node it's running on, so restart it after
# we turn the node into a distributed node
Application.stop(:babble)
Port.open({:spawn, "epmd -daemon"}, [])
Node.start(:"test-master@127.0.0.1", :longnames)
:crypto.strong_rand_bytes(24) |> Base.url_encode64() |> String.to_atom() |> Node.set_cookie()
Application.start(:babble)

# Run tests
ExUnit.start()
