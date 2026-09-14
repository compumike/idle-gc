require "spec"

require "../src/idle-gc"

STDOUT.sync = true

def alloc_string(size : UInt64) : String
  "*" * size
end
