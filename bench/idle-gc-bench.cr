require "digest/md5"
require "option_parser"

require "../src/idle-gc"

class IdleGCBench
  ALLOC_STRING_SIZE = 2000000u64

  @start = false
  getter sync_every : Bool = false
  getter request_limit : UInt64 = 0u64
  @requests = Array(Request).new

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
      s = "Hello, world!"
      st = Time.monotonic
      v = alloc_string(ALLOC_STRING_SIZE)
      1000.times { s = Digest::MD5.hexdigest(s) }

      String.build do |str|
        str << v
        str << s
      end
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

    def latency : Time::Span?
      return nil if @processing_ended_at.nil?

      @processing_ended_at.not_nil! - @requested_at
    end
  end


  def start
    1000.times do
      r = Request.new(self)
      @requests << r
      r.process
      Fiber.yield
    end

    puts GC.stats
  end

  def initialize
    puts "IdleGCBench: ARGV=#{ARGV}"

    OptionParser.parse do |parser|
      parser.on("--sync-every", "Synchronously GC after every request") { @sync_every = true }
      parser.on("--request-limit=N", "Set IdleGC::Request.request_limit and fire a request after every request") { |v| @request_limit = v.to_u64 }
      parser.on("--start", "Start IdleGC::Timer") { @start = true }
    end

    IdleGC.start if @start
  end
end

IdleGCBench.new.start
