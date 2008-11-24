require 'test/unit'
require '../lib/result_card'
require '../lib/rule_result'

class TestRule
    attr_accessor :outcomes

    def initialize
        @outcomes = ["TestStatus"]
    end
end

class ResultCardTest < Test::Unit::TestCase
    def test_initialize
        result_card = ResultCard.new
    end

    def test_register_statuses_string
        result_card = ResultCard.new
        result_card.register_statuses "TestStatus"
        assert result_card.all_statuses[0] = "TestStatus"
    end

    def test_register_statuses_array
        result_card = ResultCard.new
        result_card.register_statuses ["TestStatus"]
        assert result_card.all_statuses[0] = "TestStatus"
    end

    def test_register_statuses_array_multiple
        result_card = ResultCard.new
        result_card.register_statuses ["TestStatus", "TestStatus2"]
        result_card.register_statuses ["TestStatus", "TestStatus3"]
        assert result_card.all_statuses[0] = "TestStatus"
        assert result_card.all_statuses[1] = "TestStatus2"
        assert result_card.all_statuses[2] = "TestStatus3"
    end

    def test_register_rule_result_failure
        result_card = ResultCard.new
        result_card.register_statuses "TestStatus"
        result_card.register_rule_result TestRule.new, "Error Message", false
        assert result_card.all_achieved_statuses.empty?
        assert_equal result_card.all_failed_statuses[0], "TestStatus"
    end

    def test_register_rule_result_pass
        result_card = ResultCard.new
        result_card.register_statuses "TestStatus"
        result_card.register_rule_result TestRule.new, nil, false
        assert_equal result_card.all_achieved_statuses[0], "TestStatus"
        assert result_card.all_failed_statuses.empty?
    end

    def test_status_progress_percentage
        result_card = ResultCard.new
        result_card.register_statuses "TestStatus"
        result_card.register_rule_result TestRule.new, "Error Message", false
        result_card.register_rule_result TestRule.new, nil, false
        result_card.register_rule_result TestRule.new, nil, false
        result_card.register_rule_result TestRule.new, nil, false
        assert_equal result_card.status_progress_percentage("TestStatus"), 75
    end

end