File.mkdir_p(Path.dirname(JUnitFormatter.get_report_file_path()))
ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])

Application.stop(:babble)
Node.start(:"test-primary@127.0.0.1", :longnames)
Application.start(:babble)
ExUnit.start()
