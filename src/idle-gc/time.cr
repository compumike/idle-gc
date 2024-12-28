require "c/sys/time"
require "c/time"

{% if flag?(:darwin) %}
  require "c/mach/mach_time"
{% end %}

class IdleGC
  class Time
		NANOSECONDS_PER_SECOND =   1_000_000_000

    def self.monotonic_timespec : {Int64, Int32}
      # Reimplement ::Crystal::System::Time.monotonic so that we aren't affected by Timecop, for example.
      # Mostly copied from https://github.com/crystal-lang/crystal/blob/master/src/crystal/system/unix/time.cr
      # but with added error handling.

			{% if flag?(:darwin) %}
				info = mach_timebase_info
				total_nanoseconds = LibC.mach_absolute_time * info.numer // info.denom
				seconds = total_nanoseconds // NANOSECONDS_PER_SECOND
				nanoseconds = total_nanoseconds.remainder(NANOSECONDS_PER_SECOND)
				{seconds.to_i64, nanoseconds.to_i32}
			{% else %}
        tp = LibC::Timespec.new # initialize to zero
        loop do # retry on EINTR
          ret = LibC.clock_gettime(LibC::CLOCK_MONOTONIC, pointerof(tp))
          return {tp.tv_sec.to_i64, tp.tv_nsec.to_i32} if ret == 0
          raise RuntimeError.from_errno("clock_gettime(CLOCK_MONOTONIC) in IdleGC::Time.monotonic_timespec") unless Errno.value == Errno::EINTR
        end
			{% end %}
    end

    def self.monotonic : ::Time::Span
      # Reimplement ::Time.monotonic so that we aren't affected by Timecop, for example.
			seconds, nanoseconds = monotonic_timespec
			::Time::Span.new(seconds: seconds, nanoseconds: nanoseconds)
    end
  end
end
