require "./idle-gc/idle_detection"
require "./idle-gc/request"
require "./idle-gc/timer"

# IdleGC runs garbage collection periodically in order to keep memory usage low. It attempts to do so when the process is otherwise idle.
#
# To start, just call:
#
# ```
# IdleGC.start
# ```
#
# That is all that most use cases will need! Tweaks and tuning information are below.
#
# You may manually force a collection now (synchronously) with `IdleGC.collect`. Or, if you would like to manually run collection synchronously but only if idle, call `IdleGC.collect_if_idle`. To request a collection at the next idle opportunity, use `IdleGC.background_collect`.
#
# In addition to timer-based periodic operation which is started by `IdleGC.start`, you may wish to use request-based operation. For example, this could do background GC after every 100 web requests, or after every 10 MB served. To use this mode, first set `IdleGC::Request.request_limit = 100*1024*1024` (for example), and then call `IdleGC::Request.request(num_bytes)` to increment. This `IdleGC::Request` module will wait until the count overflows your limit, and will then fire off an `IdleGC.background_collect`.
#
# In the extremely unlikely case that your code does not yield or do any I/O, you may need to add explicit calls to `Fiber.yield` to allow IdleGC's background Fiber to have a chance to work.
#
# By default, IdleGC::Timer polls every 1 second, and if more than 0 bytes have been allocated on the heap, it runs garbage collection. To make IdleGC::Timer less aggressive (and use less CPU time, at the cost of higher memory usage), you may raise both of these settings, for example: `IdleGC::Timer.poll_interval = 5.seconds` and `IdleGC::Timer.bytes_since_gc_threshold = 128*1024`.
#
# Idle detection is based on a measurement of how long it takes `Fiber.yield` to return, and can be tuned with `IdleGC::IdleDetection.idle_threshold=`. If interactive performance (latency) is not a concern for your application, it is recommended that you disable idle detection with `IdleGC::IdleDetection.enabled = false`.
#
# Since idle detection may be inaccurate, there is a `IdleGC::Timer.force_gc_period=` which is set to force a collection every 2 minutes by default. You may disable this with `IdleGC::Timer.force_gc_period = nil`.
class IdleGC
  VERSION = "1.0.0"

  DEFAULT_BACKGROUND_COLLECT_POLL_INTERVAL = 10.milliseconds

  @@mu : Mutex = Mutex.new(Mutex::Protection::Reentrant)
  @@last_checked_at : Time::Span? = nil
  @@last_collected_at : Time::Span? = nil
  @@last_collected_duration : Time::Span? = nil
  @@background_collect_running : Atomic::Flag = Atomic::Flag.new
  @@background_collect_poll_interval_ns : Atomic(UInt64) = Atomic(UInt64).new(DEFAULT_BACKGROUND_COLLECT_POLL_INTERVAL.total_nanoseconds.to_u64)

  ### PUBLIC METHODS

  # Start a background Fiber that runs garbage collection periodically.
  #
  # (Also runs garbage collection immediately.)
  def self.start : Nil
    IdleGC::Timer.start
  end

  # Relative to Time.monotonic, when did IdleGC last check whether or not to run garbage collect?
  #
  # Returns nil if we've never checked.
  def self.last_checked_at : Time::Span?
    mu.synchronize do
      return @@last_checked_at
    end
  end

  # Relative to Time.monotonic, when did IdleGC last initiate GC.collect?
  #
  # Returns nil if we've never collected.
  def self.last_collected_at : Time::Span?
    mu.synchronize do
      return @@last_collected_at
    end
  end

  # How long did GC.collect take to run?
  #
  # Returns nil if we've never collected.
  def self.last_collected_duration : Time::Span?
    mu.synchronize do
      return @@last_collected_duration
    end
  end

  # Explicitly force collection now.
  def self.collect : Nil
    mu.synchronize do
      start_time = Time.monotonic
      GC.collect
      end_time = Time.monotonic

      @@last_checked_at = start_time
      @@last_collected_at = start_time
      @@last_collected_duration = end_time - start_time
    end
  end

  # Collect now, but only if process is idle.
  def self.collect_if_idle : Bool
    if IdleGC::IdleDetection.process_is_idle?
      collect
      true
    else
      false
    end
  end

  # How often should the background_collect Fiber check for idle?
  def self.background_collect_poll_interval=(v : Time::Span) : Nil
    @@background_collect_poll_interval_ns.set(v.total_nanoseconds.to_u64)
  end

  # Kick off a Fiber to do collection at the next idle opportunity.
  #
  # Returns true if a background collection was scheduled.
  # Returns false if there was already one scheduled.
  def self.background_collect : Bool
    should_spawn = @@background_collect_running.test_and_set
    return false unless should_spawn

    spawn_background_collect_fiber

    true
  end

  ### INTERNAL METHODS

  protected def self.mu : Mutex
    @@mu
  end

  protected def self.last_checked_at=(v : Time::Span?)
    @@last_checked_at = v
  end

  protected def self.spawn_background_collect_fiber : Nil
    requested_at = Time.monotonic

    spawn do
      do_collect = true

      poll_sleep_ns = @@background_collect_poll_interval_ns.get
      poll_sleep = poll_sleep_ns.nanoseconds

      loop do
        # Skip if there's been a collection in the meantime
        collected_at = mu.synchronize { @@last_collected_at }
        if collected_at && (collected_at > requested_at)
          do_collect = false
          break
        end

        break if IdleGC::IdleDetection.process_is_idle?

        sleep(poll_sleep)
      end

      collect if do_collect

      @@background_collect_running.clear
    end
  end
end
