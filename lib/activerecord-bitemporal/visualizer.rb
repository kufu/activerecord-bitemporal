# frozen_string_literal: true

module ActiveRecord::Bitemporal
  module Visualizer
    # Figure is a two-dimensional array holding plotted lines and columns
    class Figure < Array
      def print(str, line: 0, column: 0)
        self[line] ||= []
        str.each_char.with_index(column) do |c, i|
          # The `#` represents a zero-length rectangle and should not be overwritten with lines
          next if self[line][i] == '#' && (c == '+' || c == '|' || c == '-')

          self[line][i] = c
        end
      end

      def to_s
        map { |l| l&.map { |c| c || ' ' }&.join }.join("\n")
      end
    end

    module_function

    def visualize(record, height: 10, width: 40, highlight: true)
      histories = record.class.ignore_bitemporal_datetime.bitemporal_for(record).order(:transaction_from, :valid_from)

      if highlight
        visualize_records(histories, [record], height: height, width: width)
      else
        visualize_records(histories, height: height, width: width)
      end
    end

    # e.g. visualize_records(ActiveRecord::Relation, ActiveRecord::Relation)
    def visualize_records(*relations, height: 10, width: 40)
      raise 'More than 3 relations are not supported' if relations.size >= 3
      records = relations.flatten

      valid_times = (records.map(&:valid_from) + records.map(&:valid_to)).sort.uniq
      transaction_times = (records.map(&:transaction_from) + records.map(&:transaction_to)).sort.uniq
  
      time_length = Time.zone.now.strftime('%F %T.%3N').length
  
      columns = compute_positions(valid_times, length: width, left_margin: time_length + 1, outlier: ActiveRecord::Bitemporal::DEFAULT_VALID_TO)
      lines = compute_positions(transaction_times, length: height, outlier: ActiveRecord::Bitemporal::DEFAULT_TRANSACTION_TO)
  
      headers = Figure.new
      valid_times.each_with_object([]).with_index do |(valid_time, prev_valid_times), line|
        prev_valid_times.each do |valid_time|
          headers.print('|', line: line, column: columns[valid_time])
        end
        headers.print("| #{valid_time.strftime('%F %T.%3N')}", line: line, column: columns[valid_time])
        prev_valid_times << valid_time
      end
  
      body = Figure.new
      relations.each.with_index do |relation, idx|
        filler = idx == 0 ? ' ' : '*'

        relation.each do |record|
          line = lines[record.transaction_from]
          column = columns[record.valid_from]
    
          width = columns[record.valid_to] - columns[record.valid_from] - 1
          height = lines[record.transaction_to] - lines[record.transaction_from] - 1
    
          body.print("#{record.transaction_from.strftime('%F %T.%3N')} ", line: line)
          if width > 0
            if height > 0
              body.print('+' + '-' * width + '+', line: line, column: column)
            else
              body.print('|' + '#' * width + '|', line: line, column: column)
            end
          else
            body.print('#', line: line, column: column)
          end

          1.upto(height) do |i|
            if width > 0
              body.print('|' + filler * width + '|', line: line + i, column: column)
            else
              body.print('#', line: line + i, column: column)
            end
          end

          body.print("#{record.transaction_to.strftime('%F %T.%3N')} ", line: line + height + 1)
          if width > 0
            body.print('+' + '-' * width + '+', line: line + height + 1, column: column)
          else
            body.print('#', line: line + height + 1, column: column)
          end
        end
      end

      transaction_label = 'transaction_datetime'
      right_margin = time_length + 1 - transaction_label.size

      label = if right_margin >= 0
        "#{transaction_label + ' ' * right_margin}| valid_datetime"
      else
        "#{transaction_label[0...right_margin]}| valid_datetime"
      end

      "#{label}\n#{headers.to_s}\n#{body.to_s}"
    end
  
    # Compute a dictionary of where each time should be plotted.
    # The position is normalized to the actual length of time.
    #
    # Example:
    #
    #   t1     t2     t3                t4
    #   |------|------|-----------------|
    #
    #   f(t1, t2, t3, t4) -> { t1 => 0, t2 => 2, t3 => 4, t4 => 10 }
    #
    def compute_positions(times, length:, left_margin: 0, outlier: nil)
      lengths_from_beginning = compute_lengths_from_beginning(times, outlier: outlier)
      # times must be sorted in ascending order. This is caller's responsibility.
      # In that case, the last of lengths_from_beginning is equal to the total length.
      total = lengths_from_beginning.values.last
  
      times.each_with_object({}) do |time, ret|
        prev = ret.values.last
        pos = (lengths_from_beginning[time] / total * length).to_i + left_margin
  
        if prev
          # If the difference of times is too short, a position that have already been plotted may be computed.
          # But we still want to plot the time, so allocate the required number to plot the smallest area.
          if pos <= prev
            # | -> |*|
            #       ^^ 2 columns
            pos = prev + 2
          elsif pos == prev + 1
            # || -> |*|
            #        ^ 1 column
            pos += 1
          end
        end
        ret[time] = pos
      end
    end
  
    # Example:
    #
    #   t1          t2          t3          t4
    #   |-----------|-----------|-----------|
    #   <-----------> l1
    #   <-----------------------> l2
    #   <-----------------------------------> l3
    #
    #   f([t1, t2, t3, t4]) -> { t1 => 0, t2 => l1, t3 => l2, t4 => l3 }
    #
    def compute_lengths_from_beginning(times, outlier: nil)
      times.each_with_object({}) do |time, ret|
        ret[time] = if time == outlier && times.size > 2
                      # If it contains an extremely large value such as 9999-12-31,
                      # that point will have a large effect on the visualization,
                      # so adjust the length so that it is half of the whole.
                      ret.values.last * 2
                    else
                      time - times.min
                    end
      end
    end
  end
end
