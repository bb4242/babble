#!/bin/sh

# Launch in a script in a wrapper that detects stdin/stdout being closed,
# and exits when that occurs.
# See https://hexdocs.pm/elixir/Port.html#module-zombie-processes

"$@" &
pid=$!
while read line ; do
    :
done
kill -KILL $pid
