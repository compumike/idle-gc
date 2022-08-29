require "digest/md5"
require "option_parser"

require "../src/idle-gc"

class IdleGCBench
  ALLOC_STRING_SIZE = 1000000u64

  @start = false
  getter sync_every : Bool = false
  getter bg_every : Bool = false
  getter request_limit : UInt64 = 0u64
  @requests = Array(Request).new
  @latencies = Array(Float64).new

  class ArrayWithFinalizer
    @arr : Array(String) = Array(String).new
    def initialize
    end

    def <<(v : String) : Nil
      @arr << v
    end

    def join(sep : String = "") : String
      @arr.join(sep)
    end

    def finalize
      @arr.clear
    end
  end

  class Request
    @bench : IdleGCBench

    getter requested_at : Time::Span
    getter processing_started_at : Time::Span?
    getter processing_ended_at : Time::Span?
    property result : String?

    def alloc_string(size : UInt64) : String
      "*" * size
    end

    def do_work : String
      my_strings = ArrayWithFinalizer.new

      s = "Hello, world!"
      my_strings << s
      st = Time.monotonic
      v = alloc_string(ALLOC_STRING_SIZE)
      my_strings << v

      10.times do
        my_strings << alloc_string(ALLOC_STRING_SIZE)
      end

      1000.times do
        s = Digest::MD5.hexdigest(s)
        my_strings << s
      end

      my_strings.join(":")
    end

    def do_request : String
      String.build do |str|
        str << do_work
        sleep(1.millisecond)
        str << do_work
      end
    end

    def after_request : Nil
      @result = nil # remove pointer

      IdleGC.collect if @bench.sync_every
      IdleGC.collect if @bench.bg_every
      IdleGC::Request.request if @bench.request_limit > 0
    end

    def process
      @processing_started_at = Time.monotonic
      @result = do_request
      @processing_ended_at = Time.monotonic

      after_request
    end

    def initialize(@bench, requested_at : Time::Span? = nil)
      @requested_at = requested_at || Time.monotonic
    end

    def latency : Float64?
      return nil if @processing_ended_at.nil?

      (@processing_ended_at.not_nil! - @requested_at).total_seconds
    end
  end


  def start
    5.times { IdleGC.collect }

    start_time = Time.monotonic
    1000.times do
      r = Request.new(self)
      @requests << r
      r.process
      Fiber.yield
      @latencies << r.latency.not_nil!
    end
    end_time = Time.monotonic

    gc_stats = GC.stats
    @latencies.sort!
    runtime_s = (end_time - start_time).total_seconds
    heap_size_mib = gc_stats.heap_size.to_f64 / (1024.0*1024.0)

    puts "Runtime:     #{runtime_s.format(decimal_places: 2)} s"
    puts "Heap size:   #{heap_size_mib.format(decimal_places: 2)} MiB"
    puts "Max latency: #{@latencies.last} s"
  end

  def initialize
    puts "IdleGCBench: ARGV=#{ARGV}"

    OptionParser.parse do |parser|
      parser.on("--sync-every", "Synchronously GC after every request") { @sync_every = true }
      parser.on("--background-every", "Background GC after every request") { @bg_every = true }
      parser.on("--request-limit=N", "Set IdleGC::Request.request_limit and fire a request after every request") { |v| @request_limit = v.to_u64 }
      parser.on("--start", "Start IdleGC::Timer") { @start = true }
    end

    IdleGC.start if @start
  end
end

IdleGCBench.new.start
