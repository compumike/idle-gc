require "../src/idle-gc"

class IdleGCBench
  def initialize
    IdleGC.start
    puts "Hello, world! What's up? Let's GC."
    
    1000.times { IdleGC.collect }
  end
end

IdleGCBench.new
