require 'SimpleDB'
require 'ThreadPool'

# A SimpleDB client interface that interacts directly with the service.
class DirectClient
  
  def initialize(domain)
    @domain = domain
  end

  def find_item_ids(query, resource, is_single_item_only)
    if is_single_item_only
      query_options = {:fetch_all => false, :max_items => 1}
    else
      query_options = {:fetch_all => true, :max_items => 250}
    end      
    PawsHelper::SDB.query(@domain, query, query_options)  
  end
  
  def get_items(ids)
    @thread_pool = ThreadPool.new(20)      
    results = {}
    ids.each do |id|
       @thread_pool.dispatch(id) do |id| 
        results.merge!(get_item(id))
      end
    end
    @thread_pool.shutdown
    results
  end

  def get_item(id)
    attributes = PawsHelper::SDB.get_attributes(@domain, id)
    return {id => attributes}
  end
  
  def save_item(id, attributes)
    PawsHelper::SDB.put_attributes(@domain, id, attributes, true)
  end
  
  def delete_item(id, resource)
    PawsHelper::SDB.delete_attributes(@domain, id)
  end      
  
  def encode_attribute(name, value)
    PawsHelper::SDB.encode_attribute_value(value)
  end
  
end
