unless Node.alive?() do
  System.cmd("epmd", ["-daemon"])
  Node.start(:testrunner, :shortnames)
end

# Node.set_cookie(:testcookie)

ExUnit.start()
