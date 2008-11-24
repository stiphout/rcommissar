require 'singleton'

class RuleBook
  include Singleton

  def rules
      @rules = Rule.find(:all)
      @rules.each do |rule|
          rule.initialize_from_body
      end
      @rules
  end

  def evaluate_applicable_rules entity, event
      result_card = ResultCard.new
      rules.each do |rule|
          #we need to remember all the statuses that can potentially be achieved, so we can later
          #work out which ones we achieved
          puts ('Eval rule: ' + rule.to_s)
          result_card.register_statuses rule.outcomes
          if rule.applicable? entity, event
              puts "Running rule"
              rule.evaluate entity, result_card
          end
      end
      result_card
  end
      
end