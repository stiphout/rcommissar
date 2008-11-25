require 'test/unit'
require '../lib/rule_template'
require '../lib/result_card'
require '../lib/rule_result_template'
require 'date'

# Test implementation of the rule model
class Rule
    include(RuleTemplate)
    attr_accessor :body
end

# Test implementation of the rule result model
class RuleResult
    include(RuleResultTemplate)
end

# Mock target entity
class TestEntity
    attr_accessor :title, :artist_name, :id, :icpn, :component_number, :release_date, :new_record

    def self.find(*arguments)

      # Setup first test result...
      item1 = TestEntity.new
      item1.title = 'item'
      item1.artist_name = 'item1'
      item1.id = 'item1'
      item1.icpn = 'item1'

      # Fake a singl id find...
      if(arguments.length == 1)
          return item1 if arguments[0] == item1.id
          return nil
      end

      # Otherwise this is a param find so unpack the details...
      scope = arguments.slice!(0)
      options = arguments[0..-1][0]
      result = []

      if(options.length == 1)
          # If only one param supplied setup and second result so we can return multiple
          # i.e. not an exact match..
          item2 = TestEntity.new
          item2.title = 'item'
          item2.artist_name = 'item2'
          item2.id = 'item2'

          result = [item1, item2]
      elsif(options.length > 1)
          # If more than one param then treat as an exact match and return the one result...
          result = [item1]
      end

      result
    end

    def new_record?
      self.new_record
    end
end

class RuleTemplateTest < Test::Unit::TestCase
    def test_single_target_applies
        rule = Rule.new
        rule.check :TestEntity
        rule.on :save
        test_entity = TestEntity.new
        assert rule.applicable?(test_entity, :save)
    end

    def test_single_no_existing_target_fails_no_error
        rule = Rule.new
        rule.check :OtherTestEntity
        rule.on :save
        test_entity = TestEntity.new
        assert !rule.applicable?(test_entity, :save)
    end

    def test_multi_target_applies
        rule = Rule.new
        rule.check :OtherTestEntity, :TestEntity
        rule.on :save
        test_entity = TestEntity.new
        assert rule.applicable?(test_entity, :save)
    end

    def test_has_required_rule_passes
        rule = Rule.new
        rule.has_required :title

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card
    end

    # Not relevant because we are relying on SimpleDbResource to dynamically create
    # field accessor methods so they don't exist when respond_to is called
#    def test_has_required_rule_fails_when_field_not_exists
#        rule = Rule.new
#        rule.has_required :title
#
#        test_entity = TestEntity.new
#
#        result_card = ResultCard.new
#
#        assert !rule.evaluate(test_entity, result_card)
#    end

    def test_has_required_rule_fails_when_field_exists_but_nil
        rule = Rule.new
        rule.has_required :title

        test_entity = TestEntity.new

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_required_rule_fails_when_field_exists_but_empty
        rule = Rule.new
        rule.has_required :title

        test_entity = TestEntity.new
        test_entity.title = ''

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_string_field_equal_to_rule_passes
        rule = Rule.new
        rule.has :title
        rule.equal_to 'Test'

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card
    end

    def test_has_string_field_equal_to_rule_fails
        rule = Rule.new
        rule.has :title
        rule.equal_to 'Test'

        test_entity = TestEntity.new
        test_entity.title = 'Fail'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_string_field_not_equal_to_rule_passes
        rule = Rule.new
        rule.has :title
        rule.not_equal_to 'Test1'

        test_entity = TestEntity.new
        test_entity.title = 'Test2'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card
    end

    def test_has_string_field_not_equal_to_rule_fails
        rule = Rule.new
        rule.has :title
        rule.not_equal_to 'Test'

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_string_field_greater_than_rule_passes
        rule = Rule.new
        rule.has :title
        rule.greater_than 'Test1'

        test_entity = TestEntity.new
        test_entity.title = 'Test2'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card
    end

    def test_has_string_field_greater_than_rule_fails
        rule = Rule.new
        rule.has :title
        rule.greater_than 'Test'

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_string_field_greater_than_or_equal_to_rule_passes
        rule = Rule.new
        rule.has :title
        rule.greater_than_or_equal_to 'Test'

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card
    end

    def test_has_string_field_greater_than_or_equal_to_rule_fails
        rule = Rule.new
        rule.has :title
        rule.greater_than_or_equal_to 'Test2'

        test_entity = TestEntity.new
        test_entity.title = 'Test1'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_string_field_less_than_rule_passes
        rule = Rule.new
        rule.has :title
        rule.less_than 'Test2'

        test_entity = TestEntity.new
        test_entity.title = 'Test1'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card
    end

    def test_has_string_field_less_than_rule_fails
        rule = Rule.new
        rule.has :title
        rule.less_than 'Test'

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_string_field_less_than_or_equal_to_rule_passes
        rule = Rule.new
        rule.has :title
        rule.less_than_or_equal_to 'Test'

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card
    end

    def test_has_string_field_less_than_or_equal_to_rule_fails
        rule = Rule.new
        rule.has :title
        rule.less_than_or_equal_to 'Test1'

        test_entity = TestEntity.new
        test_entity.title = 'Test2'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

   def test_has_numeric_field_equal_to_rule_passes
        rule = Rule.new

        rule.has :component_number
        rule.equal_to 666

        test_entity = TestEntity.new
        test_entity.component_number = 666
        test_entity.new_record = false;

        result_card = ResultCard.new

        assert rule.evaluate(test_entity, result_card)
   end

   def test_has_numeric_field_equal_to_rule_fails
        rule = Rule.new

        rule.has :component_number
        rule.equal_to 777

        test_entity = TestEntity.new
        test_entity.component_number = 666
        test_entity.new_record = false;

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
   end

   def test_has_numeric_field_equal_to_rule_fails_with_string_compare
        rule = Rule.new

        rule.has :component_number
        rule.equal_to '666'

        test_entity = TestEntity.new
        test_entity.component_number = 666
        test_entity.new_record = false;

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_date_field_equal_to_rule_passes
        rule = Rule.new

        rule.has :release_date
        rule.equal_to rule.date '2001-01-01'

        test_entity = TestEntity.new
        test_entity.release_date = Date.parse('2001-01-01')
        test_entity.new_record = false;

        result_card = ResultCard.new

        assert rule.evaluate(test_entity, result_card)
    end

    def test_has_date_field_equal_to_rule_fails_with_string_compare
        rule = Rule.new

        rule.has :release_date
        rule.equal_to '2001-01-01'

        test_entity = TestEntity.new
        test_entity.release_date = Date.parse('2001-01-01')
        test_entity.new_record = false;

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_with_field_equal_to_condition_passes
        rule = Rule.new
        rule.with :title
        rule.equal_to 'Test'

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert rule.passes_gate_conditions? test_entity
    end

    def test_with_field_equal_to_condition_fails
        rule = Rule.new
        rule.with :title
        rule.equal_to 'Test'

        test_entity = TestEntity.new
        test_entity.title = 'Fails'

        result_card = ResultCard.new

        assert !rule.passes_gate_conditions?(test_entity)
    end

    def test_with_field_equal_to_and_has_other_field_equal_to_resolves_correctly
        rule = Rule.new

        rule.with :title
        rule.equal_to 'TestTitle'
        rule.has :artist_name
        rule.equal_to 'TestArtist'

        test_entity = TestEntity.new
        test_entity.title = 'TestTitle'
        test_entity.artist_name = 'TestArtist'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card
        assert rule.passes_gate_conditions? test_entity
    end

    def test_with_field_equal_to_and_has_other_field_equal_to_fails_correctly
        rule = Rule.new

        rule.with :title
        rule.equal_to 'TestTitle'
        rule.has :artist_name
        rule.equal_to 'TestArtist'

        test_entity = TestEntity.new
        test_entity.title = 'TestArtist'
        test_entity.artist_name = 'TestTitle'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
        assert !rule.passes_gate_conditions?(test_entity)
    end

    def test_two_gate_conditions_linked_with_and_passes_on_both
        rule = Rule.new

        rule.with :title
        rule.equal_to 'TestTitle'
        rule.and :artist_name
        rule.equal_to 'TestArtist'

        test_entity = TestEntity.new
        test_entity.title = 'TestTitle'
        test_entity.artist_name = 'TestArtist'

        assert rule.passes_gate_conditions? test_entity
    end

    def test_two_gate_conditions_linked_with_and_fail_on_second
        rule = Rule.new

        rule.with :title
        rule.equal_to 'TestTitle'
        rule.and :artist_name
        rule.equal_to 'TestArtist'

        test_entity = TestEntity.new
        test_entity.title = 'TestTitle'
        test_entity.artist_name = 'BadTestArtist'

        assert !rule.passes_gate_conditions?(test_entity)
    end

    def test_two_gate_conditions_linked_with_and_fail_on_first
        rule = Rule.new

        rule.with :title
        rule.equal_to 'TestTitle'
        rule.and :artist_name
        rule.equal_to 'TestArtist'

        test_entity = TestEntity.new
        test_entity.title = 'BadTestTitle'
        test_entity.artist_name = 'TestArtist'

        assert !rule.passes_gate_conditions?(test_entity)
    end

    def test_two_gate_conditions_linked_with_or_passes_on_first
        rule = Rule.new

        rule.with :title
        rule.equal_to 'TestTitle'
        rule.or :artist_name
        rule.equal_to 'TestArtist'

        test_entity = TestEntity.new
        test_entity.title = 'TestTitle'
        test_entity.artist_name = 'TestArtist2'

        assert rule.passes_gate_conditions?(test_entity)
    end

    def test_two_gate_conditions_linked_with_or_passes_on_second
        rule = Rule.new

        rule.with :title
        rule.equal_to 'TestTitle'
        rule.or :artist_name
        rule.equal_to 'TestArtist'

        test_entity = TestEntity.new
        test_entity.title = 'TestTitle2'
        test_entity.artist_name = 'TestArtist'

        assert rule.passes_gate_conditions?(test_entity)
    end

    def test_two_gate_conditions_linked_with_or_fails_on_both
        rule = Rule.new

        rule.with :title
        rule.equal_to 'TestTitle'
        rule.or :artist_name
        rule.equal_to 'TestArtist'

        test_entity = TestEntity.new
        test_entity.title = 'TestTitle2'
        test_entity.artist_name = 'TestArtist2'

        assert !rule.passes_gate_conditions?(test_entity)
    end

    def test_rule_passes_evaluated_twice
        rule = Rule.new

        rule.has_required :title

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card

        test_entity.title = nil
        test_entity.artist_name = 'Test'

        rule.has :artist_name
        rule.equal_to 'Test'

        assert rule.evaluate test_entity, result_card
    end

    def test_rule_pass_flags_allow_to_complete
        rule = Rule.new

        rule.has_required :title
        rule.to_complete

        test_entity = TestEntity.new
        test_entity.title = 'Test'

        result_card = ResultCard.new

        assert rule.evaluate test_entity, result_card
        assert rule.abort_on_fail
    end

    def test_rule_fail_flags_allow_to_complete
        rule = Rule.new

        rule.has_required :title
        rule.to_complete

        test_entity = TestEntity.new
        test_entity.title = nil

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
        assert rule.abort_on_fail
    end

    def test_has_unique_rule_passes_with_id_match
        rule = Rule.new

        rule.has_unique :title, :artist_name

        test_entity = TestEntity.new
        test_entity.title = 'item'
        test_entity.artist_name = 'item1'
        test_entity.id = 'item1'

        result_card = ResultCard.new

        assert rule.evaluate(test_entity, result_card)
    end

    def test_has_unique_rule_fails
        rule = Rule.new

        rule.has_unique :title

        test_entity = TestEntity.new
        test_entity.title = 'item'
        test_entity.artist_name = 'item1'
        test_entity.id = 'item1'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_field_matching_pattern_passes
        pattern = '[0-9]{13}'

        rule = Rule.new

        rule.has :icpn
        rule.matching_pattern pattern

        test_entity = TestEntity.new
        test_entity.icpn = '1234567890123'

        result_card = ResultCard.new

        assert rule.evaluate(test_entity, result_card)
    end

    def test_has_field_matching_pattern_fails
        pattern = '[0-9]{13}'

        rule = Rule.new

        rule.has :icpn
        rule.matching_pattern pattern

        test_entity = TestEntity.new
        test_entity.icpn = '1234567890abc'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_field_no_longer_than_passes
        rule = Rule.new

        rule.has :title
        rule.no_longer_than 10

        test_entity = TestEntity.new
        test_entity.title = '1234567890'

        result_card = ResultCard.new

        assert rule.evaluate(test_entity, result_card)
    end


    def test_has_field_no_longer_than_fails
        rule = Rule.new

        rule.has :title
        rule.no_longer_than 10

        test_entity = TestEntity.new
        test_entity.title = '12345678901'

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end

    def test_has_not_changed_field_rule_passes_for_new_record
        rule = Rule.new

        rule.has_not_changed :icpn

        test_entity = TestEntity.new
        test_entity.title = 'item'
        test_entity.artist_name = 'item3'
        test_entity.id = 'item3'
        test_entity.icpn = 'item3'
        test_entity.new_record = true;

        result_card = ResultCard.new

        assert rule.evaluate(test_entity, result_card)
    end

    def test_has_not_changed_field_rule_passes_with_same_value
        rule = Rule.new

        rule.has_not_changed :icpn

        test_entity = TestEntity.new
        test_entity.title = 'item'
        test_entity.artist_name = 'item1'
        test_entity.id = 'item1'
        test_entity.icpn = 'item1'
        test_entity.new_record = false;

        result_card = ResultCard.new

        assert rule.evaluate(test_entity, result_card)
    end

    def test_has_not_changed_field_rule_fails_with_diff_value
        rule = Rule.new

        rule.has_not_changed :icpn

        test_entity = TestEntity.new
        test_entity.title = 'item'
        test_entity.artist_name = 'item1'
        test_entity.id = 'item1'
        test_entity.icpn = 'item4'
        test_entity.new_record = false;

        result_card = ResultCard.new

        assert !rule.evaluate(test_entity, result_card)
    end
end