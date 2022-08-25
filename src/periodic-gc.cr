# PeriodicGC runs garbage collection periodically to keep memory usage low.
#
# To start, just call:
#
# ```
# PeriodicGC.start
# ```
class PeriodicGC
  VERSION = "0.1.0"

  DEFAULT_POLL_INTERVAL = 1.second
  DEFAULT_IDLE_THRESHOLD = 100.microseconds

  @@mu : Mutex = Mutex.new(Mutex::Protection::Reentrant)
  @@running : Channel(Nil)? = nil
  @@poll_interval : Time::Span = DEFAULT_POLL_INTERVAL
  @@idle_threshold : Time::Span = DEFAULT_IDLE_THRESHOLD
  @@last_checked_at : Time::Span? = nil
  @@last_collected_at : Time::Span? = nil
  @@last_collected_duration : Time::Span? = nil

  ### PUBLIC METHODS

  # Set the polling interval.
  #
  # Polling more frequently will keep memory usage lower, but will burn more CPU time on garbage collection.
  #
  # The sweet spot is probably seconds to minutes.
  def self.poll_interval=(v : Time::Span) : Nil
    @@mu.synchronize do
      return if @@poll_interval == v
      @@poll_interval = v

      # Restart if changed while running
      stop_channel = @@running
      if stop_channel
        stop_channel.close
        @@running = spawn_loop
      end
    end
  end

  # Set the idle threshold for comparing to `#fiber_yield_time`.
  #
  # Experimentally, I found ~5us when idle, and ~500us or more when busy.
  def self.idle_threshold=(v : Time::Span) : Nil
    @@mu.synchronize do
      @@idle_threshold = v
    end
  end

  # Start a background Fiber that runs garbage collection periodically.
  def self.start : Nil
    @@mu.synchronize do
      return if @@running

      @@running = spawn_loop
    end
  end

  # Stop periodic garbage collection.
  #
  # (You don't need to call this. Just let it die when your program exits.)
  def self.stop : Nil
    @@mu.synchronize do
      stop_channel = @@running
      if !stop_channel.nil?
        stop_channel.close
        @@running = nil
      end
    end
  end

  # Relative to Time.monotonic, when did PeriodicGC last check whether or not to run garbage collect?
  #
  # Returns nil if we've never checked.
  def self.last_checked_at : Time::Span?
    @@mu.synchronize do
      return @@last_checked_at
    end
  end

  # Relative to Time.monotonic, when did PeriodicGC last initiate GC.collect?
  #
  # Returns nil if we've never collected.
  def self.last_collected_at : Time::Span?
    @@mu.synchronize do
      return @@last_collected_at
    end
  end

  # How long did GC.collect take to run?
  #
  # Returns nil if we've never collected.
  def self.last_collected_duration : Time::Span?
    @@mu.synchronize do
      return @@last_collected_duration
    end
  end

  # Explicitly force collection now.
  def self.collect : Nil
    @@mu.synchronize do
      start_time = Time.monotonic
      GC.collect
      end_time = Time.monotonic

      @@last_checked_at = start_time
      @@last_collected_at = start_time
      @@last_collected_duration = end_time - start_time
    end
  end

  # How long does it take for Fiber.yield to return?
  #
  # This is a measure of whether there are other Fibers waiting to do work.
  def self.fiber_yield_time : Time::Span
    start_time = Time.monotonic
    Fiber.yield
    end_time = Time.monotonic

    end_time - start_time
  end

  # Return true if the process is idle, as determined by `#fiber_yield_time` compared to `#idle_threshold=`.
  def self.process_is_idle? : Bool
    @@mu.synchronize do
      return fiber_yield_time < @@idle_threshold
    end
  end

  ### INTERNAL METHODS
  
  protected def self.spawn_loop : Channel(Nil)
    stop_channel = Channel(Nil).new

    spawn do
      loop do
        break if stop_channel.closed?

        loop_callback
      end
    end

    stop_channel
  end

  protected def self.loop_callback : Nil
    sleep_period : Time::Span? = nil

    @@mu.synchronize do
      collect_if_needed!
      sleep_period = @@poll_interval
    end

    sleep(sleep_period.not_nil!)
  end

  protected def self.collect_if_needed!
    start_time = Time.monotonic
    @@last_checked_at = start_time
    return if GC.stats.bytes_since_gc == 0

    GC.collect
    end_time = Time.monotonic

    @@last_collected_at = start_time
    @@last_collected_duration = end_time - start_time
  end
end
