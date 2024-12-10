# frozen_string_literal: true

module ActiveRecord::Bitemporal
  module NodeBitemporalInclude
    refine String do
      def bitemporal_include?(*)
        false
      end
    end

    refine ::Arel::Nodes::Node do
      def bitemporal_include?(*columns)
        case self
        when Arel::Nodes::Between, Arel::Nodes::In, Arel::Nodes::NotIn, Arel::Nodes::Equality, Arel::Nodes::NotEqual, Arel::Nodes::LessThan, Arel::Nodes::LessThanOrEqual, Arel::Nodes::GreaterThan, Arel::Nodes::GreaterThanOrEqual
          if self.left.kind_of?(Arel::Attributes::Attribute)
            subrelation = self.left
            columns.include?(subrelation.name.to_s) || columns.include?("#{subrelation.relation.name}.#{subrelation.name}")
          elsif self.right.kind_of?(Arel::Attributes::Attribute)
            subrelation = self.right
            columns.include?(subrelation.name.to_s) || columns.include?("#{subrelation.relation.name}.#{subrelation.name}")
          end
        else
          false
        end
      end
    end
  end

  module Relation
    # see: https://github.com/rails/rails/pull/51492
    NARY_NODE = ActiveRecord.gem_version >= Gem::Version.new("7.2.0") ? Arel::Nodes::Nary : Arel::Nodes::And
    private_constant :NARY_NODE

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

        def each_operatable_node(nodes = predicates, &block)
          if block
            each_operatable_node(nodes).each(&block)
          else
            Enumerator.new { |y|
              Array(nodes).each { |node|
                case node
                when Arel::Nodes::LessThan, Arel::Nodes::LessThanOrEqual, Arel::Nodes::GreaterThan, Arel::Nodes::GreaterThanOrEqual
                  y << node if node && node.left.respond_to?(:relation)
                when NARY_NODE
                  each_operatable_node(node.children) { |node| y << node }
                when Arel::Nodes::Binary
                  each_operatable_node(node.left) { |node| y << node }
                  each_operatable_node(node.right) { |node| y << node }
                when Arel::Nodes::Unary
                  each_operatable_node(node.expr) { |node| y << node }
                end
              }
            }
          end
        end

        def bitemporal_query_hash(*names)
          each_operatable_node
            .select { |node| names.include? node.left.name.to_s }
            .inject(Hash.new { |hash, key| hash[key] = {} }) { |result, node|
              value = node.right.try(:val) || node.right.try(:value).then { |it| it.try(:value_before_type_cast) || it }
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
            valid_datetime: valid_from == valid_to ? valid_from : nil,
            transaction_from: transaction_from,
            transaction_to: transaction_to,
            transaction_datetime: transaction_from == transaction_to ? transaction_from : nil,
            ignore_valid_datetime: valid_from.nil? && valid_to.nil? ? true : false,
            ignore_transaction_datetime: transaction_from.nil? && transaction_to.nil? ? true : false
          }
        end
      end
    }

    module MergeWithExceptBitemporalDefaultScope
      using BitemporalChecker
      def merge(other)
        if other.is_a?(Relation) && other.klass.bi_temporal_model?
          super(other.except_bitemporal_default_scope)
        else
          super
        end
      end
    end

    def valid_datetime
      bitemporal_clause[:valid_datetime]&.in_time_zone
    end

    def valid_date
      valid_datetime&.to_date
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

  module CollectionProxy
    # Delegate to ActiveRecord::Bitemporal::Relation
    # @see https://github.com/rails/rails/blob/v7.1.3.4/activerecord/lib/active_record/associations/collection_proxy.rb#L1115-L1124
    #
    # In order to update the CollectionProxy state, `load` needs to be excluded.
    # The reason for using `@association` instead of delegating this method is to preserve state such as `loaded`.
    # @see https://github.com/rails/rails/blob/v7.1.3.4/activerecord/lib/active_record/associations/collection_proxy.rb#L44
    #
    # There is no need to delegate to `scope` as `ActiveRecord::Bitemporal::Relation::Finder`'s methods are delegated
    # by `ActiveRecord::Delegation`. This is not a problem because `scoping` used in this is delegated to `scope`.
    # @see https://github.com/rails/rails/blob/v7.1.3.4/activerecord/lib/active_record/relation/delegation.rb#L117
    delegate :bitemporal_value, :bitemporal_value=, :valid_datetime, :valid_date,
             :transaction_datetime, :bitemporal_option, :bitemporal_option_merge!,
             :build_arel, :primary_key, to: :scope
  end

  module Scope
    extend ActiveSupport::Concern

    module ActiveRecordRelationScope
      refine ::ActiveRecord::Relation do
        def bitemporal_where_bind(attr_name, operator, value)
          where(table[attr_name].public_send(operator, predicate_builder.build_bind_attribute(attr_name, value)))
        end

        def bitemporal_where_bind!(attr_name, operator, value)
          where!(table[attr_name].public_send(operator, predicate_builder.build_bind_attribute(attr_name, value)))
        end

        def with_valid_datetime
          tap { |relation| relation.bitemporal_value[:with_valid_datetime] = true }
        end

        def without_valid_datetime
          tap { |relation| relation.bitemporal_value[:with_valid_datetime] = false }
        end

        def with_transaction_datetime
          tap { |relation| relation.bitemporal_value[:with_transaction_datetime] = true }
        end

        def without_transaction_datetime
          tap { |relation| relation.bitemporal_value[:with_transaction_datetime] = false }
        end
      end
    end

    included do
      using Module.new {
        refine ActiveRecord::Bitemporal::Optionable do
          def force_valid_datetime?
            bitemporal_option_storage[:force_valid_datetime]
          end

          def ignore_valid_datetime?
            bitemporal_option_storage[:ignore_valid_datetime]
          end

          def force_transaction_datetime?
            bitemporal_option_storage[:force_transaction_datetime]
          end

          def ignore_transaction_datetime?
            bitemporal_option_storage[:ignore_transaction_datetime]
          end
        end
      }

      module ActiveRecordRelationScope
        module EqualAttributeName
          refine ::Object do
            def equal_attribute_name(*)
              false
            end
          end
          refine ::Hash do
            def equal_attribute_name(other)
              self[:where].equal_attribute_name(other)
            end
          end
          refine ::Array do
            def equal_attribute_name(other)
              first.equal_attribute_name(other)
            end
          end
          refine ::String do
            def equal_attribute_name(other)
              self == other.to_s
            end
          end
          refine ::Symbol do
            def equal_attribute_name(other)
              self.to_s == other.to_s
            end
          end
          refine ::Arel::Attributes::Attribute do
            def equal_attribute_name(other)
              "#{relation.name}.#{name}" == other.to_s
            end
          end
        end

        refine ::ActiveRecord::Relation do
          using EqualAttributeName
          using NodeBitemporalInclude

          def bitemporal_rewhere_bind(attr_name, operator, value, table = self.table)
            rewhere(table[attr_name].public_send(operator, predicate_builder.build_bind_attribute(attr_name, value)))
          end

          %i(valid_from valid_to transaction_from transaction_to).each { |column|
            module_eval <<-STR, __FILE__, __LINE__ + 1
              def _ignore_#{column}
                unscope(where: :"\#{table.name}.#{column}")
                  .tap { |relation| relation.unscope!(where: bitemporal_value[:through].arel_table["#{column}"]) if bitemporal_value[:through] }
              end

              def _except_#{column}
                return self unless where_clause.send(:predicates).find { |node|
                  node.bitemporal_include?("\#{table.name}.#{column}")
                }
                _ignore_#{column}.tap { |relation|
                  relation.unscope_values.reject! { |query| query.equal_attribute_name("\#{table.name}.#{column}") }
                }
              end
            STR

            [
              :lt,    # column <  datetime
              :lteq,  # column <= datetime
              :gt,    # column >  datetime
              :gteq   # column >= datetime
            ].each { |op|
              module_eval <<-STR, __FILE__, __LINE__ + 1
                def _#{column}_#{op}(datetime)
                  target_datetime = datetime&.in_time_zone || Time.current
                  bitemporal_rewhere_bind("#{column}", :#{op}, target_datetime)
                    .tap { |relation| break relation.bitemporal_rewhere_bind("#{column}", :#{op}, target_datetime, bitemporal_value[:through].arel_table) if bitemporal_value[:through] }
                end
              STR
            }
          }
        end
      end
      using ActiveRecordRelationScope

      %i(valid_from valid_to transaction_from transaction_to).each { |column|
        scope :"ignore_#{column}", -> {
          public_send(:"_ignore_#{column}")
        }

        scope :"except_#{column}", -> {
          public_send(:"_except_#{column}")
        }

        [
          :lt,    # column <  datetime
          :lteq,  # column <= datetime
          :gt,    # column >  datetime
          :gteq   # column >= datetime
        ].each { |op|
          scope :"#{column}_#{op}", -> (datetime) {
            public_send(:"_#{column}_#{op}", datetime)
          }
        }
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
        ignore_valid_from.ignore_valid_to.without_valid_datetime
      }
      scope :except_valid_datetime, -> {
        except_valid_from.except_valid_to.tap { |relation| relation.bitemporal_value.except! :with_valid_datetime }
      }

      # transaction_from <= datetime && datetime < transaction_to
      scope :transaction_at, -> (datetime) {
        if ActiveRecord::Bitemporal.force_transaction_datetime?
          datetime = ActiveRecord::Bitemporal.transaction_datetime
        end
        datetime = Time.current if datetime.nil?
        transaction_from_lteq(datetime).transaction_to_gt(datetime).with_transaction_datetime
      }
      scope :ignore_transaction_datetime, -> {
        ignore_transaction_from.ignore_transaction_to.without_transaction_datetime
      }
      scope :except_transaction_datetime, -> {
        except_transaction_from.except_transaction_to.tap { |relation| relation.bitemporal_value.except! :with_transaction_datetime }
      }

      scope :bitemporal_at, -> (datetime) {
        relation = self
        current_time = Time.current

        if !ActiveRecord::Bitemporal.ignore_transaction_datetime?
          relation = relation.transaction_at(datetime || ActiveRecord::Bitemporal.transaction_datetime || current_time)
        end

        if !ActiveRecord::Bitemporal.ignore_valid_datetime?
          relation = relation.valid_at(datetime || ActiveRecord::Bitemporal.valid_datetime || current_time)
        end

        relation
      }
      scope :ignore_bitemporal_datetime, -> {
        ignore_transaction_datetime.ignore_valid_datetime
      }
      scope :except_bitemporal_datetime, -> {
        except_transaction_datetime.except_valid_datetime
      }

      scope :bitemporal_default_scope, -> {
        datetime = Time.current
        relation = self

        if !ActiveRecord::Bitemporal.ignore_transaction_datetime?
          if ActiveRecord::Bitemporal.transaction_datetime
            transaction_datetime = ActiveRecord::Bitemporal.transaction_datetime
            relation.bitemporal_value[:with_transaction_datetime] = :default_scope_with_transaction_datetime
          else
            relation.bitemporal_value[:with_transaction_datetime] = :default_scope
          end

          relation = relation
            ._transaction_from_lteq(transaction_datetime || datetime)
            ._transaction_to_gt(transaction_datetime || datetime)
        else
          relation.tap { |relation| relation.without_transaction_datetime unless ActiveRecord::Bitemporal.transaction_datetime }
        end

        if !ActiveRecord::Bitemporal.ignore_valid_datetime?
          if ActiveRecord::Bitemporal.valid_datetime
            valid_datetime = ActiveRecord::Bitemporal.valid_datetime
            relation.bitemporal_value[:with_valid_datetime] = :default_scope_with_valid_datetime
          else
            relation.bitemporal_value[:with_valid_datetime] = :default_scope
          end

          relation = relation
            ._valid_from_lteq(valid_datetime || datetime)
            ._valid_to_gt(valid_datetime || datetime)
        else
          relation.tap { |relation| relation.without_valid_datetime unless ActiveRecord::Bitemporal.valid_datetime }
        end

        relation
      }

      scope :except_bitemporal_default_scope, -> {
        scope = all
        scope = scope.except_valid_datetime if bitemporal_value[:with_valid_datetime] == :default_scope || bitemporal_value[:with_valid_datetime] == :default_scope_with_valid_datetime
        scope = scope.except_transaction_datetime if bitemporal_value[:with_transaction_datetime] == :default_scope || bitemporal_value[:with_transaction_datetime] == :default_scope_with_transaction_datetime
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

      # from < valid_to AND valid_from < to
      scope :valid_in, -> (range = nil, from: nil, to: nil) {
        return valid_in(from...to) if range.nil?

        relation = ignore_valid_datetime
        begin_, end_ = range.begin, range.end

        # beginless range
        if begin_
          # from < valid_to
          relation = relation.bitemporal_where_bind("valid_to", :gt, begin_.in_time_zone.to_datetime)
        end

        # endless range
        if end_
          if range.exclude_end?
            # valid_from < to
            relation = relation.bitemporal_where_bind("valid_from", :lt, end_.in_time_zone.to_datetime)
          else
            # valid_from <= to
            relation = relation.bitemporal_where_bind("valid_from", :lteq, end_.in_time_zone.to_datetime)
          end
        end

        relation
      }

      # from <= valid_from AND valid_to <= to
      scope :valid_allin, -> (range = nil, from: nil, to: nil) {
        return valid_allin(from..to) if range.nil?

        relation = ignore_valid_datetime
        begin_, end_ = range.begin, range.end

        if begin_
          relation = relation.bitemporal_where_bind("valid_from", :gteq, begin_.in_time_zone.to_datetime)
        end

        if end_
          if range.exclude_end?
            raise 'Range with excluding end is not supported'
          else
            relation = relation.bitemporal_where_bind("valid_to", :lteq, end_.in_time_zone.to_datetime)
          end
        end

        relation
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
