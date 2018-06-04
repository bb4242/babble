File.mkdir_p(Path.dirname(JUnitFormatter.get_report_file_path()))
ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])

Application.stop(:babble)
Port.open({:spawn, "epmd -daemon"}, [])
Node.start(:"test-primary@127.0.0.1", :longnames)
# TODO: Set random cookie for primary and slave nodes
#Node.set_cookie(Node.self(), :my_cookie)
Application.start(:babble)

ExUnit.start()
