require 'SimpleDbResource'

class Track < SimpleDbResource::Base
  def asset
    @asset ||= Asset.find(:first, :id=> self.asset_id)
    @asset
  end

  def product
    @product ||= Product.find(:first, :id=> self.product_id)
    @product
  end
end
