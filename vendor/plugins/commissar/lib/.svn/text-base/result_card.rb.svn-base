class ResultCard
    attr_accessor :errors, :achieved_statuses, :all_statuses, :abort_event, :rule_results

    def initialize
        @all_statuses = []
        @achieved_statuses = []
        @errors = []
        @rule_results = []
        @status_rule_results = {}
        @status_rule_errors = {}
    end

    def register_statuses *statuses
        @all_statuses |= statuses if !statuses.nil?
    end

    def register_rule_result rule, error_message, abort_event
        rule_result = RuleResult.new rule, error_message
        @rule_results << rule_result
        if !rule.outcomes.nil?
            rule.outcomes.each do |status|
                @status_rule_results[status] = [] if @status_rule_results[status].nil?
                @status_rule_results[status] << rule_result
                if !rule_result.passed
                    puts "Adding rule result to status_rule_errors for status #{status}"
                    @status_rule_errors[status] = [] if @status_rule_errors[status].nil?
                    @status_rule_errors[status] << rule_result
                end
            end
        end

        if !rule_result.passed
            puts "registering error: #{error_message}"
            @errors << rule_result
        end
        if(abort_event)
            @abort_event = abort_event
        end
    end

    def all_achieved_statuses
        result = []
        @all_statuses.each do |status|
            if @status_rule_errors[status].nil? or @status_rule_errors[status].empty?
                result << status
            end
        end
        result
    end

    def all_failed_statuses
        result = []
        @all_statuses.each do |status|
            if !@status_rule_errors[status].nil? and !@status_rule_errors[status].empty?
                result << status
            end
        end
        result
    end

    def status_progress_percentage status
        if @status_rule_results[status].length == 0
            puts "Returning 100 because there are no rule results for status #{status}"
            return 100
        end
        puts "@status_rule_errors[#{status}] : #{@status_rule_errors[status].inspect}"
        puts "@status_rule_results[#{status}] : #{@status_rule_results[status].inspect}"
        100 - (100 * @status_rule_errors[status].length) / @status_rule_results[status].length
    end
end