Application.stop(:babble)
Node.start(:"test-primary@127.0.0.1", :longnames)
Application.start(:babble)
ExUnit.start()
