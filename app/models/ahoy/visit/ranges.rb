module Ahoy::Visit::Ranges
  extend ActiveSupport::Concern

  class_methods do
    # Build canonical ranges (no trimming) and clamp intervals, matching Plausible.
    # Accepts optional query for date/from/to parameters.
    def range_and_interval_for(period, requested_interval = nil, query = nil)
      now = Time.zone.now
      range_override = query && query[:range_override]

      parse_time = lambda do |str|
        Time.zone.parse(str.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      date_param = (query && query[:date]).presence
      from_param = (query && query[:from]).presence
      to_param   = (query && query[:to]).presence

      case period
      when "realtime"
        range = (now - 30.minutes)..now
        allowed = %w[minute]
        default = "minute"

      when "day"
        d = date_param.present? ? (parse_time.call(date_param) || now) : now
        range = d.beginning_of_day..d.end_of_day
        allowed = %w[minute hour]
        default = "hour"

      when "7d"
        end_date = (date_param.present? ? (parse_time.call(date_param) || now) : now).to_date - 1.day
        start_date = end_date - 6.days
        range = start_date.beginning_of_day..end_date.end_of_day
        allowed = %w[hour day]
        default = "day"

      when "28d"
        end_date = (date_param.present? ? (parse_time.call(date_param) || now) : now).to_date - 1.day
        start_date = end_date - 27.days
        range = start_date.beginning_of_day..end_date.end_of_day
        allowed = %w[day week]
        default = "day"

      when "30d"
        end_date = (date_param.present? ? (parse_time.call(date_param) || now) : now).to_date - 1.day
        start_date = end_date - 29.days
        range = start_date.beginning_of_day..end_date.end_of_day
        allowed = %w[day week]
        default = "day"

      when "91d"
        end_date = (date_param.present? ? (parse_time.call(date_param) || now) : now).to_date - 1.day
        start_date = end_date - 90.days
        range = start_date.beginning_of_day..end_date.end_of_day
        allowed = %w[day week month]
        default = "day"

      when "month"
        d = date_param.present? ? (parse_time.call(date_param) || now) : now
        range = d.beginning_of_month..d.end_of_month
        allowed = %w[day week]
        default = "day"

      when "6mo"
        d = date_param.present? ? (parse_time.call(date_param) || now) : now
        end_date = (d.to_date - 1.month).end_of_month
        start_date = (end_date.to_date - 5.months).beginning_of_month
        range = start_date.beginning_of_day..end_date.end_of_day
        allowed = %w[day week month]
        default = "month"

      when "12mo"
        d = date_param.present? ? (parse_time.call(date_param) || now) : now
        end_date = (d.to_date - 1.month).end_of_month
        start_date = (end_date.to_date - 11.months).beginning_of_month
        range = start_date.beginning_of_day..end_date.end_of_day
        allowed = %w[day week month]
        default = "month"

      when "year"
        d = date_param.present? ? (parse_time.call(date_param) || now) : now
        range = d.beginning_of_year..d.end_of_year
        allowed = %w[day week month]
        default = "month"

      when "all"
        starts = [ Ahoy::Visit.minimum(:started_at), Ahoy::Event.minimum(:time) ].compact
        start_date = (starts.min || now).to_date
        end_date = now.to_date
        range = start_date.beginning_of_day..end_date.end_of_day
        months = ((end_date.year * 12 + end_date.month) - (start_date.year * 12 + start_date.month)).abs
        allowed = months > 12 ? %w[week month] : %w[day week month]
        default = months > 0 ? "month" : "day"

      when "custom"
        if from_param.present? && to_param.present?
          from = parse_time.call(from_param)
          to = parse_time.call(to_param)
          if from && to
            from = from.beginning_of_day
            to = to.end_of_day
            range = from..to
          else
            end_date = now.to_date - 1.day
            start_date = end_date - 6.days
            range = start_date.beginning_of_day..end_date.end_of_day
          end
        else
          end_date = now.to_date - 1.day
          start_date = end_date - 6.days
          range = start_date.beginning_of_day..end_date.end_of_day
        end

      else
        d = date_param.present? ? (parse_time.call(date_param) || now) : now
        range = d.beginning_of_day..d.end_of_day
        allowed = %w[minute hour]
        default = "hour"
      end

      interval = requested_interval.to_s.presence
      interval = default unless interval && allowed.include?(interval)
      range = range_override if range_override.is_a?(Range)
      [ range, interval ]
    end

    # Trim to "now" for the main graph only (Plausible's include.trim_relative_date_range behavior)
    def trim_range_to_now_if_applicable(range, period, comparison: nil)
      return range unless %w[day month year].include?(period.to_s)
      return range if comparison.present? && period.to_s == "day"

      now = Time.zone.now
      today = now.to_date
      case period.to_s
      when "day"
        if range.begin.to_date == today && range.end.to_date == today
          return range.begin..now.end_of_hour
        end
      when "month"
        month_start = today.beginning_of_month
        month_end   = today.end_of_month
        if range.begin.to_date == month_start && range.end.to_date == month_end
          return range.begin..today.end_of_day
        end
      when "year"
        year_start = Date.new(today.year, 1, 1)
        year_end   = Date.new(today.year, 12, 31)
        if range.begin.to_date == year_start && range.end.to_date == year_end
          return range.begin..today.end_of_day
        end
      end
      range
    end

    def previous_range(range)
      from_date = range.begin.to_date
      to_date   = range.end.to_date
      days_span = (to_date - from_date).to_i + 1 # inclusive number of days in source
      prev_from = (from_date - days_span).beginning_of_day
      prev_to   = (to_date   - days_span).end_of_day
      prev_from..prev_to
    end

    def year_over_year_range(range)
      (range.begin - 1.year)..(range.end - 1.year)
    end

    def custom_compare_range(query)
      cf = query[:compare_from]
      ct = query[:compare_to]

      if cf.present? && ct.present?
        from = Time.zone.parse(cf.to_s)
        to = Time.zone.parse(ct.to_s)

        if from && to
          from.beginning_of_day..to.end_of_day
        end
      end
    rescue ArgumentError, TypeError
      nil
    end

    def comparison_range_for(query, source_range, effective_source_range: source_range)
      case query[:comparison]
      when "year_over_year"
        range = Ahoy::Visit.year_over_year_range(source_range)
        if ActiveModel::Type::Boolean.new.cast(query[:match_day_of_week])
          range = Ahoy::Visit.align_comparison_weekday(range, source_range)
        end
        trim_comparison_range_to_source_progress(range, source_range, effective_source_range)
      when "custom"
        Ahoy::Visit.custom_compare_range(query)
      when "previous_period"
        range = Ahoy::Visit.previous_range(source_range)
        if ActiveModel::Type::Boolean.new.cast(query[:match_day_of_week])
          range = Ahoy::Visit.align_comparison_weekday(range, source_range)
        end
        trim_comparison_range_to_source_progress(range, source_range, effective_source_range)
      end
    end

    # When enabled, adjust the comparison range to start on the same weekday as the source range.
    def align_comparison_weekday(comparison_range, source_range)
      if comparison_range && source_range
        source_first = source_range.begin.to_date
        comp_first   = comparison_range.begin.to_date

        target_wday = source_first.wday # 0..6 (Sun..Sat)

        if comp_first.wday == target_wday
          comparison_range
        else
          next_occurring = begin
            delta = (target_wday - comp_first.wday) % 7
            delta = 7 if delta == 0
            comp_first + delta
          end

          prev_occurring = begin
            delta = (comp_first.wday - target_wday) % 7
            delta = 7 if delta == 0
            comp_first - delta
          end

          new_first_date = (next_occurring == source_first) ? prev_occurring : next_occurring
          days_shifted = (new_first_date - comp_first).to_i
          new_last_date = comparison_range.end.to_date + days_shifted

          new_begin = Time.zone.parse(new_first_date.to_s).beginning_of_day
          new_end   = Time.zone.parse(new_last_date.to_s).end_of_day
          new_begin..new_end
        end
      else
        comparison_range
      end
    end

    def trim_comparison_range_to_source_progress(comparison_range, source_range, effective_source_range)
      return comparison_range unless comparison_range && source_range && effective_source_range
      return comparison_range unless effective_source_range.end < source_range.end

      elapsed = effective_source_range.end - source_range.begin
      adjusted_end = comparison_range.begin + elapsed
      comparison_range.begin..[ adjusted_end, comparison_range.end ].min
    end

    # Build SQL for time bucketing in the app (site) timezone, then convert back to UTC.
    def bucket_sql_for(column, interval)
      zone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
      local = "((#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{zone})"
      truncated = case interval
      when "month" then "date_trunc('month', #{local})"
      when "week" then "date_trunc('week', #{local})"
      when "day" then "date_trunc('day', #{local})"
      when "hour" then "date_trunc('hour', #{local})"
      when "minute" then "date_trunc('minute', #{local})"
      else "date_trunc('hour', #{local})"
      end
      "(#{truncated} AT TIME ZONE #{zone})"
    end
  end
end
