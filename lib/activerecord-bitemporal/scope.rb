module ActiveRecord::Bitemporal
  module Relation
    if ActiveRecord.version < Gem::Version.new("6.1.0.alpha")
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
    end

    using Module.new {
      refine ActiveRecord::Relation::WhereClause do
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
            when Arel::Nodes::And
              select_operatable_node(node.left) + select_operatable_node(node.right)
            when Arel::Nodes::Grouping
              select_operatable_node(node.expr)
            end
          }.compact
        end

        def bitemporal_query_hash(*names)
          select_operatable_node
            .select { |node| names.include? node.left.name.to_s }
            .inject(Hash.new { |hash, key| hash[key] = {} }) { |result, node|
            value = node.right.try(:val) || node.right.try(:value).try(:value_before_type_cast)
            result[node.left.relation.name][node.left.name.to_s] = [node.operator, value]
            result
          }
        end
      end

      refine Relation do
        def bitemporal_clause(table_name = klass.table_name)
          node_hash = where_clause.bitemporal_query_hash("valid_from", "valid_to", "transaction_from", "transaction_to")
          valid_from = node_hash.dig(table_name, "valid_from", 1)
          valid_to   = node_hash.dig(table_name, "valid_to", 1)
          transaction_from = node_hash.dig(table_name, "transaction_from", 1)
          transaction_to   = node_hash.dig(table_name, "transaction_to", 1)
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

        refine Array do
          def delete_once(other)
            index(other).then { |i| delete_at(i) if i }
          end
        end
      }

      if ActiveRecord.version < Gem::Version.new("6.1.0.alpha")
        %i(valid_from valid_to transaction_from transaction_to).each { |column|
          scope :"ignore_#{column}", -> {
            unscope(where: "#{table.name}.#{column}")
              .tap { |relation| relation.merge!(bitemporal_value[:through].unscoped.public_send(:"ignore_#{column}")) if bitemporal_value[:through] }
          }

          scope :"except_#{column}", -> {
            all.tap { |relation|
              relation.where_clause = where_clause.except("#{table.name}.#{column}")
              relation.unscope_values.delete_once({ where: "#{table.name}.#{column}" })
            }
          }

          [
            :lt,    # column <  datetime
            :lteq,  # column <= datetime
            :gt,    # column >  datetime
            :gteq   # column >= datetime
          ].each { |op|
            scope :"#{column}_#{op}", -> (datetime) {
              target_datetime = datetime&.in_time_zone || Time.current
              public_send(:"ignore_#{column}").bitemporal_where_bind(column, op, target_datetime)
                .tap { |relation| relation.merge!(bitemporal_value[:through].unscoped.public_send(:"#{column}_#{op}", target_datetime)) if bitemporal_value[:through] }
            }
          }
        }
      else
        %w(valid_from valid_to transaction_from transaction_to).each { |column|
          scope :"ignore_#{column}", -> {
            unscope(where: :"#{table.name}.#{column}")
              .tap { |relation| relation.unscope!(where: bitemporal_value[:through].arel_table[column]) if bitemporal_value[:through] }
          }
          scope :"except_#{column}", -> {
            all.tap { |relation|
              relation.where_clause = where_clause.except("#{table.name}.#{column}")
              relation.unscope_values.delete_once({ where: "#{table.name}.#{column}" })
            }
          }

          [
            :lt,    # column <  datetime
            :lteq,  # column <= datetime
            :gt,    # column >  datetime
            :gteq   # column >= datetime
          ].each { |op|
            scope :"#{column}_#{op}", -> (datetime) {
              target_datetime = datetime&.in_time_zone || Time.current
              bitemporal_rewhere_bind(column, op, target_datetime)
                .tap { |relation| break relation.bitemporal_rewhere_bind(column, op, target_datetime, bitemporal_value[:through].arel_table) if bitemporal_value[:through] }
            }
          }
        }
      end

      # -------------------------------
      # NOTE: with_valid_datetime ~ without_transaction_datetime is private API
      scope :with_valid_datetime, -> {
        tap { |relation| relation.bitemporal_value[:with_valid_datetime] = true }
      }
      scope :without_valid_datetime, -> {
        tap { |relation| relation.bitemporal_value[:with_valid_datetime] = false }
      }
      scope :with_transaction_datetime, -> {
        tap { |relation| relation.bitemporal_value[:with_transaction_datetime] = true }
      }
      scope :without_transaction_datetime, -> {
        tap { |relation| relation.bitemporal_value[:with_transaction_datetime] = false }
      }
      # -------------------------------

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
      scope :except_valid_datetime, -> {
        except_valid_from.except_valid_to
      }

      # transaction_from <= datetime && datetime < transaction_to
      scope :transaction_at, -> (datetime) {
        datetime = Time.current if datetime.nil?
        transaction_from_lteq(datetime).transaction_to_gt(datetime).with_transaction_datetime
      }
      scope :ignore_transaction_datetime, -> {
        ignore_transaction_from.ignore_transaction_to
      }
      scope :except_transaction_datetime, -> {
        except_transaction_from.except_transaction_to
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
      scope :except_bitemporal_datetime, -> {
        except_transaction_datetime.except_valid_datetime
      }

      scope :bitemporal_default_scope, -> {
        datetime = Time.current
        relation = spawn

        relation = relation.transaction_at(datetime).without_transaction_datetime

        if !ActiveRecord::Bitemporal.ignore_valid_datetime?
          datetime = ActiveRecord::Bitemporal.valid_datetime || datetime
          relation = relation.valid_at(datetime)
        end

        if ActiveRecord::Bitemporal.valid_datetime
          relation.with_valid_datetime
        else
          relation.without_valid_datetime
        end
      }

      scope :except_bitemporal_default_scope, -> {
        scope = all
        scope = scope.except_valid_datetime unless bitemporal_value[:with_valid_datetime]
        scope = scope.except_transaction_datetime unless bitemporal_value[:with_transaction_datetime]
        scope
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

      if ActiveRecord.version < Gem::Version.new("6.1.0.alpha")
      else
        scope :bitemporal_rewhere_bind, -> (attr_name, operator, value, table = self.table) {
          rewhere(table[attr_name].public_send(operator, predicate_builder.build_bind_attribute(attr_name, value)))
        }
      end
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
