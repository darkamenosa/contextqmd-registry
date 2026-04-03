# frozen_string_literal: true

module Analytics::HourlyBucketRange
  private
    def bucket_start_for(value)
      return if value.blank?

      normalize_time(value)&.beginning_of_hour
    rescue ArgumentError, TypeError
      nil
    end

    def bucket_window_for(range)
      return if range.blank?

      start_time = normalize_time(range.begin)
      end_time = effective_range_end(range)
      return if start_time.blank? || end_time.blank? || end_time < start_time

      start_time.beginning_of_hour..end_time.beginning_of_hour
    end

    def bucket_starts_for(range)
      window = bucket_window_for(range)
      return [] if window.blank?

      bucket_starts = []
      bucket_start = window.begin

      while bucket_start <= window.end
        bucket_starts << bucket_start
        bucket_start += 1.hour
      end

      bucket_starts
    end

    def full_hour_aligned_range?(range)
      return false if range.blank?

      start_time = normalize_time(range.begin)
      end_time = effective_range_end(range)
      return false if start_time.blank? || end_time.blank? || end_time < start_time

      start_on_hour_boundary?(start_time) && end_on_hour_boundary?(end_time)
    end

    def interior_bucket_window_for(range)
      return if range.blank?

      start_time = normalize_time(range.begin)
      end_time = effective_range_end(range)
      return if start_time.blank? || end_time.blank? || end_time < start_time

      bucket_start = start_time.beginning_of_hour
      bucket_start += 1.hour unless start_on_hour_boundary?(start_time)

      bucket_end = end_time.beginning_of_hour
      bucket_end -= 1.hour unless end_on_hour_boundary?(end_time)

      return if bucket_start > bucket_end

      bucket_start..bucket_end
    end

    def edge_ranges_for(range)
      return [] if range.blank?

      start_time = normalize_time(range.begin)
      end_time = effective_range_end(range)
      return [] if start_time.blank? || end_time.blank? || end_time < start_time

      if start_time.beginning_of_hour == end_time.beginning_of_hour
        return [ start_time..end_time ] unless full_hour_aligned_range?(range)

        return []
      end

      edge_ranges = []

      unless start_on_hour_boundary?(start_time)
        edge_ranges << (start_time..[ end_time, start_time.end_of_hour ].min)
      end

      unless end_on_hour_boundary?(end_time)
        edge_start = [ start_time, end_time.beginning_of_hour ].max
        edge_ranges << (edge_start..end_time)
      end

      edge_ranges
    end

    def expected_bucket_count_for(range)
      bucket_starts_for(range).size
    end

    def normalize_bucket_time(bucket_time)
      bucket_time.is_a?(Time) ? bucket_time.utc : bucket_time.to_time.utc
    end

    def effective_range_end(range)
      end_time = normalize_time(range.end)
      return if end_time.blank?

      range.exclude_end? ? (end_time - 1.microsecond) : end_time
    end

    def normalize_time(value)
      return if value.blank?

      value.respond_to?(:in_time_zone) ? value.in_time_zone : Time.zone.parse(value.to_s)
    end

    def start_on_hour_boundary?(time)
      normalized_time = normalize_time(time)
      normalized_time.present? && normalized_time == normalized_time.beginning_of_hour
    end

    def end_on_hour_boundary?(time)
      normalized_time = normalize_time(time)
      return false if normalized_time.blank?

      [ 0.000001, 1.second ].any? do |tick|
        next_time = normalized_time + tick
        next_time == next_time.beginning_of_hour
      end
    end
end
