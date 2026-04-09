switch("define", "ssl")
switch("define", "chronicles_log_level=ERROR")

# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
