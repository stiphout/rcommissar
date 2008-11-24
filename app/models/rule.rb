require 'SimpleDbResource'
require 'rule_template'

class Rule < SimpleDbResource::Base
    include(RuleTemplate)
end
