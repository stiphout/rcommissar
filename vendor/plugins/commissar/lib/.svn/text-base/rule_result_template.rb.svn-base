module RuleResultTemplate
    attr_accessor :rule, :error_message

    def initialize rule, error_message
        @rule = rule
        @error_message = error_message
    end

    def passed
        if @error_message.nil?
            return true
        end
        false
    end
end