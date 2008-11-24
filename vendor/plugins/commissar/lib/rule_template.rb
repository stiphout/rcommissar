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

    def equal_to(value)
        append_condition format_equal_to_condition(@current_field, value)
    end

    def matching_pattern(value)
        append_condition format_matches_pattern_condition(@current_field, value)
    end

    def no_longer_than(value)
        append_condition format_field_no_longer_than_condition(@current_field, value)
    end

    def append_condition(condition)
        if(@current_section == :gate_condition)
            if @current_token == :and
                self.gate_code << ' && '
            elsif @current_token == :or
                self.gate_code << ' && '
            else
                self.gate_code = ''
            end
            self.gate_code << condition
        elsif(@current_section == :rule_test)
            self.rule_code = %Q{
            def eval_rule(entity)
              #{condition}
            end
            }
        else
            puts "Must follow a 'with', 'and' or 'has' call."
        end
    end

    def format_equal_to_condition(field, value)
        %Q{entity.#{field} == '#{value}'}
    end

    def format_matches_pattern_condition(field, value)
        %Q{(entity.#{field} =~ /#{value}/) != nil}
    end

    def format_field_no_longer_than_condition(field, value)
        %Q{(entity.#{field}.length <= #{value})}
    end

    def has_required (field)
        @active_field = field
        self.rule_code = %Q{
        def eval_rule (entity)
           !entity.#{field}.nil? && !entity.#{field}.empty?
        end
        }
    end

    def has_unique(*fields)
        self.rule_code = %Q{
        def eval_rule (entity)
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
        end
        }
    end

    def has_not_changed(field)
        self.rule_code = %Q{
        def eval_rule (entity)
           if entity.new_record?
              return true
           end
           result = entity.class.find(entity.id)
           return (result.nil? || result.#{field}.nil? || result.#{field}.empty? || result.#{field} == entity.#{field})
        end
        }
    end

    def evaluate (entity, result_card)
        #puts self.rule_code
        instance_eval self.rule_code
        @passed = eval_rule entity
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
        self.gate_code = %Q{
            def eval_gate_condition(entity)
              #{self.gate_code}
            end
            }
        #puts self.gate_code
        instance_eval self.gate_code
        eval_gate_condition entity
    end
end