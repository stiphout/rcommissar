require 'rubygems'
require 'memcache'
require 'sdbclients/DirectClient'

# A SimpleDB client interface that interacts with the service through
# a memcached caching layer.
class MemcachedClient
  
  def initialize(domain, memcached_servers)
    @domain = domain
    @client = DirectClient.new(domain)
    @cache = MemCache.new(memcached_servers.split(','), 
                          :namespace=> @domain, :multithread => true)
    @expiry = 3600
    @mutex = Mutex.new
  end
  
  def find_item_ids(query, resource, is_single_item_only)
    query_ref = "Query[#{resource}]"      
    queries_by_resource = @cache.get(query_ref) || {}
    result = queries_by_resource[query]
    if not result
      result = @client.find_item_ids(query, resource, is_single_item_only)
      queries_by_resource.merge!({query => result})
      @cache.set(query_ref, queries_by_resource, @expiry)
    end
    result
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
    item_ref = "Item[#{id}]"
    
    result = nil
    @mutex.synchronize do
      # This call fails when threaded unless we manually apply a mutex
       result = @cache.get(item_ref)
    end
    
    if not result
      result = @client.get_item(id)
      @cache.set(item_ref, result, @expiry)
    end
    result
  end
  
  def save_item(id, attributes)
    result = @client.save_item(id, attributes)
    @cache.set("Item[#{id}]", {id => attributes}, @expiry)
    resource = attributes['_resource']
    @cache.delete("Query[#{resource}]")
    result
  end
  
  def delete_item(id, resource)      
    result = @client.delete_item(id, resource)
    @cache.delete("Item[#{id}]")
    @cache.delete("Query[#{resource}]")
    result
  end
  
  def encode_attribute(name, value)
    @client.encode_attribute(name, value)
  end
  
end
