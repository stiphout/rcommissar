require 'rule_book'

module RuleEnforcer
    def self.included(base)
        puts 'Init enforcer'
    end

    def update_attributes(attributes)
        puts "update_attributes: #{attributes}"
        result_card = RuleBook.instance.evaluate_applicable_rules self, "Save"
        translate_result_card_to_errors result_card
        if result_card.abort_event
            return false
        end
        super attributes
    end

    def save
        puts 'save'
        result_card = RuleBook.instance.evaluate_applicable_rules self, "Save"
        translate_result_card_to_errors result_card
        if result_card.abort_event
            return false
        end
        super
    end

    def translate_result_card_to_errors result_card
        puts "translate_result_card_to_errors"
        result_card.errors.each do |rule_result|
            puts "Adding error to @errors, error: #{rule_result.error_message}, field: #{rule_result.rule.field}"
            if rule_result.rule.field.nil?
                @errors.add_to_base rule_result.error_message
            else
                @errors.add rule_result.rule.field, rule_result.error_message
            end
        end
    end
 end
