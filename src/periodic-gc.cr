class PeriodicGC
  VERSION = "0.1.0"

  DEFAULT_POLL_INTERVAL = 1.second

  @@_instance : PeriodicGC?

  def self.start(poll_interval : Time::Span = DEFAULT_POLL_INTERVAL) : Nil
    return unless @@_instance.nil?

    @@_instance = PeriodicGC.new(
      poll_interval: poll_interval
    )
  end

  def self.stop : Nil
    @@_instance.try &.stop
    @@_instance = nil
  end

  @mu : Mutex
  @stop_requested : Bool
  @poll_interval : Time::Span

  protected def initialize(@poll_interval : Time::Span)
    @mu = Mutex.new
    @stop_requested = false

    spawn_loop
  end

  protected def stop
    @mu.synchronize { @stop_requested = true }
  end
  
  private def spawn_loop
    spawn do
      gc_stats = GC.stats

      loop do
        abort_before_run = false
        @mu.synchronize { abort_before_run = @stop_requested }
        break if abort_before_run

        collect_if_needed!

        sleep(@poll_interval)
      end
    end
  end

  private def collect_if_needed!
    GC.collect if GC.stats.bytes_since_gc > 0
  end
end
