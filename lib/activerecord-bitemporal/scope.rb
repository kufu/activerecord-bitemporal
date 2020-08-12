module ActiveRecord::Bitemporal
  module Relation
    class WhereClauseWithCheckTable < ActiveRecord::Relation::WhereClause
      private

      def except_predicates(columns)
        columns = Array(columns)
        predicates.reject do |node|
          case node
          when Arel::Nodes::Between, Arel::Nodes::In, Arel::Nodes::NotIn, Arel::Nodes::Equality, Arel::Nodes::NotEqual, Arel::Nodes::LessThan, Arel::Nodes::LessThanOrEqual, Arel::Nodes::GreaterThan, Arel::Nodes::GreaterThanOrEqual
            subrelation = (node.left.kind_of?(Arel::Attributes::Attribute) ? node.left : node.right)
            # Add check table name
            columns.include?(subrelation.name.to_s) || columns.include?("#{subrelation.relation.name}.#{subrelation.name}")
          end
        end
      end
    end

    def where_clause
      WhereClauseWithCheckTable.new(super.send(:predicates))
    end

    using Module.new {
      refine WhereClauseWithCheckTable do
        using Module.new {
          refine Arel::Nodes::LessThan do
            def operator; :< ; end
          end
          refine Arel::Nodes::LessThanOrEqual do
            def operator; :<= ; end
          end
          refine Arel::Nodes::GreaterThan do
            def operator; :> ; end
          end
          refine Arel::Nodes::GreaterThanOrEqual do
            def operator; :>= ; end
          end
          refine Arel::Nodes::Node do
            def operator; nil ; end
          end
        }

        def select_operatable_node(nodes = predicates)
          Array(nodes).flat_map { |node|
            case node
            when Arel::Nodes::LessThan, Arel::Nodes::LessThanOrEqual, Arel::Nodes::GreaterThan, Arel::Nodes::GreaterThanOrEqual
              node && node.left.respond_to?(:relation) ? node : nil
            when Arel::Nodes::Or
              select_operatable_node(node.left) + select_operatable_node(node.right)
            when Arel::Nodes::Grouping
              select_operatable_node(node.expr)
            end
          }.compact
        end

        def bitemporal_query_hash
          select_operatable_node.inject(Hash.new { |hash, key| hash[key] = {} }) { |result, node|
            result[node.left.relation.name][node.left.name] = [node.operator, node.right.try(:val)]
            result
          }
        end
      end

      refine Relation do
        def bitemporal_clause(table_name = klass.table_name)
          node_hash = where_clause.bitemporal_query_hash
          valid_from = node_hash.dig(table_name, :valid_from, 1)
          valid_to   = node_hash.dig(table_name, :valid_to, 1)
          transaction_from = node_hash.dig(table_name, :transaction_from, 1)
          transaction_to   = node_hash.dig(table_name, :transaction_to, 1)
          {
            valid_from: valid_from,
            valid_to: valid_to,
            valid_datetime: valid_from == valid_to ? valid_from : nil,
            transaction_from: transaction_from,
            transaction_to: transaction_to,
            transaction_datetime: transaction_from == transaction_to ? transaction_from : nil,
            ignore_valid_datetime: valid_from.nil? && valid_to.nil? ? true : false
          }
        end
      end
    }

    def valid_datetime
      bitemporal_clause[:valid_datetime]&.in_time_zone
    end

    def transaction_datetime
      bitemporal_clause[:transaction_datetime]&.in_time_zone
    end

    def bitemporal_option
      ::ActiveRecord::Bitemporal.merge_by(bitemporal_value.merge bitemporal_clause)
    end

    def bitemporal_option_merge!(other)
      self.bitemporal_value = bitemporal_value.merge other
    end

    def bitemporal_value
      @values[:bitemporal_value] ||= {}
    end

    def bitemporal_value=(value)
      @values[:bitemporal_value] = value
    end
  end

  module Scope
    extend ActiveSupport::Concern

    included do
      using Module.new {
        refine ActiveRecord::Bitemporal::Optionable do
          def force_valid_datetime?
            bitemporal_option_storage[:force_valid_datetime]
          end

          def ignore_valid_datetime?
            bitemporal_option_storage[:ignore_valid_datetime]
          end
        end
      }

      %i(valid_from valid_to transaction_from transaction_to).each { |column|
        scope :"ignore_#{column}", -> {
          unscope(where: "#{table.name}.#{column}")
            .tap { |relation| relation.merge!(bitemporal_value[:through].unscoped.public_send(:"ignore_#{column}")) if bitemporal_value[:through] }
        }

        [
          :lt,    # column <  datetime
          :lteq,  # column <= datetime
          :gt,    # column >  datetime
          :gteq   # column >= datetime
        ].each { |op|
          scope :"#{column}_#{op}", -> (datetime) {
            target_datetime = datetime&.in_time_zone || Time.current
            public_send(:"ignore_#{column}").where(table[column].public_send(op, target_datetime))
              .tap { |relation| relation.merge!(bitemporal_value[:through].unscoped.public_send(:"#{column}_#{op}", target_datetime)) if bitemporal_value[:through] }
          }
        }
      }

      scope :with_valid_datetime, -> {
        tap { |relation| relation.bitemporal_value[:with_valid_datetime] = true }
      }

      scope :without_valid_datetime, -> {
        tap { |relation| relation.bitemporal_value[:with_valid_datetime] = false }
      }

      # valid_from <= datetime && datetime < valid_to
      scope :valid_at, -> (datetime) {
        if ActiveRecord::Bitemporal.force_valid_datetime?
          datetime = ActiveRecord::Bitemporal.valid_datetime
        end
        datetime = Time.current if datetime.nil?
        valid_from_lteq(datetime).valid_to_gt(datetime).with_valid_datetime
      }
      scope :ignore_valid_datetime, -> {
        ignore_valid_from.ignore_valid_to
      }

      # transaction_from <= datetime && datetime < transaction_to
      scope :transaction_at, -> (datetime) {
        datetime = Time.current if datetime.nil?
        transaction_from_lteq(datetime).transaction_to_gt(datetime)
      }
      scope :ignore_transaction_datetime, -> {
        ignore_transaction_from.ignore_transaction_to
      }

      scope :bitemporal_at, -> (datetime) {
        datetime = Time.current if datetime.nil?
        if ActiveRecord::Bitemporal.ignore_valid_datetime?
          transaction_at(datetime)
        else
          transaction_at(datetime).valid_at(ActiveRecord::Bitemporal.valid_datetime || datetime)
        end
      }
      scope :ignore_bitemporal_datetime, -> {
        ignore_transaction_datetime.ignore_valid_datetime
      }

      scope :bitemporal_default_scope, -> {
        datetime = Time.current
        relation = spawn
        relation.unscope_values += [{ where: ["#{table.name}.valid_from", "#{table.name}.valid_to", "#{table.name}.transaction_from", "#{table.name}.transaction_to"] }]

        relation.where!(table[:transaction_from].lteq(datetime))
                .where!(table[:transaction_to].gt(datetime))

        if !ActiveRecord::Bitemporal.ignore_valid_datetime?
          datetime = ActiveRecord::Bitemporal.valid_datetime || datetime
          relation.where!(table[:valid_from].lteq(datetime))
                  .where!(table[:valid_to].gt(datetime))
        end

        if ActiveRecord::Bitemporal.valid_datetime
          relation.with_valid_datetime
        else
          relation.without_valid_datetime
        end

#         if ActiveRecord::Bitemporal.valid_datetime
#           bitemporal_at(Time.current).with_valid_datetime
#         else
#           bitemporal_at(Time.current).without_valid_datetime
#         end
      }

      scope :within_deleted, -> {
        ignore_transaction_datetime
      }
      scope :without_deleted, -> {
        valid_at(Time.current)
      }

      scope :bitemporal_for, -> (id) {
        where(bitemporal_id: id)
      }

      scope :valid_in, -> (from: nil, to: nil) {
        ignore_valid_datetime
          .tap { |relation| break relation.bitemporal_where_bind("valid_to", :gteq, from.in_time_zone.to_datetime) if from }
          .tap { |relation| break relation.bitemporal_where_bind("valid_from", :lteq, to.in_time_zone.to_datetime) if to }
      }
      scope :valid_allin, -> (from: nil, to: nil) {
        ignore_valid_datetime
          .tap { |relation| break relation.bitemporal_where_bind("valid_from", :gteq, from.in_time_zone.to_datetime) if from }
          .tap { |relation| break relation.bitemporal_where_bind("valid_to", :lteq, to.in_time_zone.to_datetime) if to }
      }
      scope :bitemporal_where_bind, -> (attr_name, operator, value) {
        where(table[attr_name].public_send(operator, predicate_builder.build_bind_attribute(attr_name, value)))
      }
    end

    module Extension
      extend ActiveSupport::Concern

      included do
        scope :bitemporal_histories, -> (*ids) {
          ignore_valid_datetime.bitemporal_for(*ids)
        }
        def self.bitemporal_most_future(id)
          bitemporal_histories(id).order(valid_from: :asc).last
        end
        def self.bitemporal_most_past(id)
          bitemporal_histories(id).order(valid_from: :asc).first
        end
      end
    end

    module Experimental
      extend ActiveSupport::Concern
    end
  end
end
