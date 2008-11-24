require 'SimpleDbResource'
require 'rule_enforcer'

class Asset < SimpleDbResource::Base
  include(RuleEnforcer)
  def tracks
    @tracks ||= Track.find(:all, :asset_id=> self.id)
    @tracks
  end
end
