unless Node.alive?() do
  Node.start(:testrunner, :shortnames)
end

#Node.set_cookie(:testcookie)

ExUnit.start()
