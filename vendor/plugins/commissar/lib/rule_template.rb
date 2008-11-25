require 'date'

module RuleTemplate
    attr_reader :passed, :abort_on_fail, :active_field, :outcomes
    attr_accessor :rule_code, :gate_code

    def self.included(base)
        puts 'Init enforcer'
    end

    def initialize_from_body
        instance_eval(self.body)
    end

    def check (*targets)
        @current_section = :target_entities
        @current_token = :check
        @targets = targets
    end

    def on(*events_that_trigger)
        @current_section = :target_events
        @current_token = :on
        @events = events_that_trigger
    end

    def with (field)
        @current_section = :gate_condition
        @current_token = :with
        @current_field = field
    end

    def has(field)
        @current_section = :rule_test
        @current_token = :has
        @current_field = field
        @active_field = field
    end

    def and(field)
        @current_token = :and
        @current_field = field
    end

    def or(field)
        @current_token = :or
        @current_field = field
    end

    def where_each(target_child)
      @target_child = target_child
    end

    # Helper method for casting dates.
    def date(date_string)
        Date.parse date_string
    end

    def for_outcome list_of_outcomes
        @current_section = :outcome
        @current_token = :for_outcome
        @outcomes = list_of_outcomes
    end

    def to_complete()
        @current_section = :outcome
        @current_token = :to_complete
        @abort_on_fail = true
    end

    def compares_to(value, operator)
        case
          when value.kind_of?(Date)
            %Q{entity.#{@current_field} #{operator} Date.parse('#{value}')}
          when value.kind_of?(Numeric)
            %Q{entity.#{@current_field} #{operator} #{value}}
          else # Assume a kind of string
            %Q{entity.#{@current_field} #{operator} '#{value}'}
        end
    end

    def equal_to(value)
        append_condition compares_to(value, '==')
    end

    def not_equal_to(value)
        append_condition compares_to(value, '!=')
    end

    def greater_than(value)
        append_condition compares_to(value, '>')
    end

    def greater_than_or_equal_to(value)
        append_condition compares_to(value, '>=')
    end

    def less_than(value)
        append_condition compares_to(value, '<')
    end

    def less_than_or_equal_to(value)
        append_condition compares_to(value, '<=')
    end

    def matching_pattern(value)
        append_condition %Q{(entity.#{@current_field} =~ /#{value}/) != nil}
    end

    def no_longer_than(value)
        append_condition %Q{(entity.#{@current_field}.length <= #{value})}
    end

    def append_condition(condition)
        if(@current_section == :gate_condition)
            if @current_token == :and
                self.gate_code << ' && '
            elsif @current_token == :or
                self.gate_code << ' || '
            else
                self.gate_code = ''
            end
            self.gate_code << condition
        elsif(@current_section == :rule_test)
            self.rule_code = condition
        else
            raise "Must be a part of a gate condition or rule test section."
        end
    end

    def has_required (field)
        @active_field = field
        self.rule_code = "!entity.#{field}.nil? && !entity.#{field}.empty?"
    end

    def has_unique(*fields)
      self.rule_code = %Q{
           unless entity.class.respond_to?(:find)
             return false
           end
           result = entity.class.find(:all}
        fields.each do |field|
           self.rule_code << ', :' << field.to_s << ' => entity.'  << field.to_s
        end
        self.rule_code << %Q{)
          if(result.length > 1 || (result.length == 1 && result[0].id != entity.id))
            return false
          end
          true
        }
    end

    def has_not_changed(field)
        self.rule_code = %Q{
           if entity.new_record?
              return true
           end
           result = entity.class.find(entity.id)
           return (result.nil? || result.#{field}.nil? || result.#{field}.empty? || result.#{field} == entity.#{field})
        }
    end

    def evaluate (entity, result_card)
      if @target_child.nil?
        rule = create_proc(self.rule_code)
      else
        # TODO: want to use inflector 'pluralize' method instead of 
        # #{@target_child}s but not sure how to 'require' it in the unit test context.
        apply_rule_to_children = %Q{
            @passed = true if @passed.nil?
            entity.#{@target_child}s.each do |#{@target_child}|
              child_rule = create_proc(self.rule_code)
              @passed = false unless child_rule.call(#{@target_child})
            end
            @passed
        }
        rule = create_proc(apply_rule_to_children)
        end
        @passed = rule.call entity
        if @passed
          result_card.register_rule_result self, nil, false
        else
          result_card.register_rule_result self, self.body, @abort_on_fail
        end
        @passed
    end

    def applicable? (entity, event)
        if !@events.include? event
            puts "event #{event} is not applicable to rule with events #{rule.events}"
            return false
        end
       @targets.each do |target|
           if relevant_entity?(target, entity)
               return passes_gate_conditions?(entity)
           end
       end
       false
    end

    def relevant_entity?(target, entity)
        Object.const_defined?(target) && entity.kind_of?(Kernel.const_get(target))
    end

    def passes_gate_conditions?(entity)
        if(self.gate_code.nil? || self.gate_code.empty?)
            return true
        end
        gate_condition = create_proc(self.gate_code)
        gate_condition.call entity
    end

    def create_proc(code)
      full_code = %Q{
      proc do |entity|
        #{code}
      end
      }
      instance_eval(full_code)
    end
end