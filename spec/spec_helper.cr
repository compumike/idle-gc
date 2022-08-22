require "spec"
require "../src/periodic-gc"

def alloc_string(size : UInt64) : String
  "*" * size
end
