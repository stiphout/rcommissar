require 'SimpleDbResource'
require 'rule_enforcer'

class Product < SimpleDbResource::Base
  include(RuleEnforcer)
  def tracks
    @tracks ||= Track.find(:all, :product_id=> self.id)
    @tracks
  end
end

