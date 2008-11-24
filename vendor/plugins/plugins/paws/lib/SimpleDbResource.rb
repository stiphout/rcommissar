require 'active_record'
require 'PawsHelper'

# Defines a SimpleDB resource class that emulates the basic behaviour
# of a Ruby on Rails ActiveRecord, with support for simple validations.
# This module also defines two client interfaces to SimpleDB, one direct
# and the other via memcached caching servers.
#
# This plugin module is configured through the paws_config.yml file which
# must be present in the Rails config directory. This file must contain
# the following settings:
#
# Settings required by PawsHelper:
#   aws_access_key : Your AWS access key
#   aws_secret_key : Your AWS secret key
#   s3_bucket : The S3 bucket to which files will be uploaded.
#
# Settings required by SimpleDbResource:
#   domain : The SimpleDB domain in which data resources will be stored,
#            for example: marketplace
# Optional settings:
#   memcached_servers : If present, communication with the SimpleDB
#                       service will pass through an intermediate
#                       memcached caching layer. Example settings 
#                       could be: localhost:11211
module SimpleDbResource

  CONFIG_FILE = File.join(RAILS_ROOT,'config','paws_config.yml')
  CONFIG = YAML.load_file(CONFIG_FILE)[RAILS_ENV] rescue {}
  # configuration via environment overrides config file
  CONFIG.merge!({
    'domain' => (ENV['DOMAIN'] || CONFIG['domain'])
  })

  if !CONFIG || [ CONFIG['domain'] ].any?(&:blank?)
    STDERR.puts "To use SimpleDbResource, please configure 'domain' in #{CONFIG_FILE} or your environment"
    exit 1
  end

  DOMAIN = CONFIG['domain']
  

  # If memcached settings are available, we will use the memcached
  # client for all SimpleDB interactions, otherwise we will use
  # the direct client.
  if CONFIG['memcached_servers']
    require 'sdbclients/MemcachedClient'
    SDB_CLIENT = MemcachedClient.new(DOMAIN, CONFIG['memcached_servers'])   
  else
    require 'sdbclients/DirectClient'
    SDB_CLIENT = DirectClient.new(DOMAIN)
  end  
                        
                      
  # This class defines a base for model objects that store their
  # data in the SimpleDB service instead of in a traditional
  # RDBMS (SQL database). 
  #
  # The class has a limited set of features compared with the
  # Ruby on Rails ActiveRecord, but it should implement most of
  # the behaviour of ActiveResource items along with some added 
  # features to support simple validations (drawn from ActiveRecord) 
  # and the extra human_name and type_cast declarative settings.
  #
  # Model objects based on this class are stored in SimpleDB with a
  # number of mandatory attributes:
  #   id : A UUID identifier which uniquely identifies an Item
  #        (Record) in SimpleDB.
  #   _resource : the model's class name in lowercase, used as a 
  #               simple scoping mechanism so that multiple model
  #               classes can be stored in a single SimpleDB domain.
  #   _created_timestamp : The UTC time when the model object was 
  #                        first stored in SimpleDB.
  #   _updated_timestamp : The UTC time when the model object was
  #                        last updated in SimpleDB.
  # 
  # Besides the mandatory attributes, a model object based on this
  # this class can contain arbitrary attributes because SimpleDB
  # does not impose a rigid data schema. You can therefore freely
  # add attributes to, or remove them from, existing Items. 
  # Attribute names are always text strings.
  #
  # Here are some example commands, assuming you have defined a
  # model class called User based on this class.
  #
  # >> u = User.new
  # => #<User:0x25727ac @current=false, @attributes={"_resource"=>"user"}>
  #
  # # Define arbitrary attributes
  # >> u.name = 'user123'
  # >> u[:password] = 'mypassword'
  # >> u['role'] = 'customer'
  #
  # >> u.attributes
  # => {"_resource"=>"user", "name"=>"user123", "password"=>"mypassword", 
  #     "role"=>"customer"}
  #
  # # Save the User in SimpleDB
  # >> u.current  # => false
  # >> u.save  # => true
  # >> u.attributes
  # => {"_resource"=>"user", "name"=>"user123", "password"=>"mypassword", 
  #     "role"=>"customer", "id"=>"65a63520-dd1e-012a-83bf-0016cb9d98ec", 
  #     "_created_timestamp"=>Wed Mar 26 04:52:44 UTC 2008, 
  #     "_updated_timestamp"=>Wed Mar 26 04:53:03 UTC 2008}
  #
  # # Retrieve a specific User
  # >> User.find(:first, :name => 'user123', :role => 'vendor')
  #
  # # Find all Users
  # >> User.find(:all).size  # => 5
  #
  # # Find Users with operations other than equality
  # >> User.find(:all, :role => ['!=', 'vendor'], :state => ['starts-with', 'W'])
  #
  # # To perform an arbitrary SimpleDB query, provide your own query string
  # >> User.find(:all, "['role' = 'vendor'] intersection [not 'state' starts-with 'A']")
  #
  # # Delete a User Item from SimpleDB
  # >> u.delete
  #
  #
  # The SimpleDbResource::Base class supports a subset of the validation macros
  # from ActiveRecord::Valdations. The supported macros are: validates_presence_of, 
  # validates_inclusion_of, validates_length_of, validates_numericality_of, and 
  # validates_each.
  #
  # In addition to the validation macros, this class supports two specialized
  # macros: human_name and type_cast.
  #   human_name: defines human-friendly names for attributes. These friendly names 
  #               will be printed in error messages displayed to a web site user. Eg,
  
  #               human_name :account_holder_last_name => "Surname"
  
  #   type_cast : specifies the data type an attribute should be converted to before
  #               it is stored in SimpleDB. Text attribute values can be converted 
  #               into into Float (f), Integer (i) or Time (time) variables. Eg,
  
  #               type_cast :price => 'f', :age => 'i', :birthdate => 'time'
  class Base
    require 'uuid'
  
    attr_accessor :current, :errors
    attr_reader :id, :_resource, :attributes
    
    def initialize(attributes = {})
      @attributes = {'_resource' => self.class.to_s.downcase}
      @attributes.merge!(Base.cleanup_attributes(attributes))
  
      @current = false            
      @errors = ActiveRecord::Errors.new(self)
    end
    
    def id
      @attributes['id']
    end
    
    def _resource
      @attributes['_resource']      
    end
    
    def attributes
      @attributes.clone
    end
    
    def Base.load(id, attributes)
      item = self.new(cleanup_attributes(attributes))
      item.id = id
      item.current = true
      return item
    end
    
    def Base.find(*arguments)
      scope = arguments.slice!(0)
      options = arguments[0..-1] || {}        
      
      resource = self.to_s.downcase
      query = "['_resource' = '#{resource}']"
      options.each do |option|
        if option.is_a? String
          query += " intersection #{option}"
        elsif option.is_a? Array
          name = option[0]
          value = SDB_CLIENT.encode_attribute(name, option[1])
          query += " intersection ['#{name.to_s}' = '#{value}']"
        elsif option.is_a? Hash
          option.each_pair do |name,value|
            if value.is_a? Array
              operation = value[0]
              value = SDB_CLIENT.encode_attribute(name, value[1])
            else
              operation = '='
              value = SDB_CLIENT.encode_attribute(name, value)
            end
            query += " intersection ['#{name}' #{operation} '#{value}']"
          end
        else
          raise "Find method does not understand options of type #{option.class}"
        end
      end

      if scope.is_a? String
        item = SDB_CLIENT.get_item(scope)
        if item.values.first.empty?
          return nil
        else
          return self.load(item.keys.first, item.values.first)
        end
      else
        one_result_only = true if scope == :first or scope == :one
        ids = SDB_CLIENT.find_item_ids(query, resource, one_result_only)
        results = SDB_CLIENT.get_items(ids)
        
        resources = []
        results.each_pair do |id, attributes|
          resources << self.load(id, attributes)
        end        
        
        if one_result_only
          return resources.first
        else
          return resources
        end
      end
    end
    
    def Base.cleanup_attributes(attributes = {})
      attributes.inject({}) do |atts, single_att|
        if single_att[1].is_a? Array and single_att[1].size == 1
          atts[single_att[0].to_s] = single_att[1].first
        else
          atts[single_att[0].to_s] = single_att[1]
        end
        atts
      end  
    end
    
    def Base.create(attributes = {})
      returning(self.new(attributes)) { |res| res.save }
    end
      
    def Base.delete(id)
      res = self.new({'id' => id})
      res.delete
    end
    
    def Base.exists(id)
      not SDB_CLIENT.get_item(id).values.first.empty?
    end
    
    def update_attributes(attributes = {})
      attributes.each_pair do |name, value|
        self[name] = value
      end
      save
    end
    
    def save()
      return false if @current
      
      @attributes['id'] = UUID.new unless @attributes['id']
            
      run_type_casts      
      
      @attributes['_updated_timestamp'] = Time.now.utc
      if not @attributes.has_key?('_created_timestamp')
        @attributes['_created_timestamp'] = Time.now.utc
      end
      
      @current = SDB_CLIENT.save_item(@attributes['id'], @attributes)
    end
    
    def new_record?
      id.nil?
    end
    
    def delete()
      if SDB_CLIENT.delete_item(id, _resource)
        @attributes.delete('id')
        @attributes.delete('_updated_timestamp')
        @attributes.delete('_created_timestamp')
        @current = false
        true
      else
        false
      end
    end
  
    def hash()
      if id
        id.hash
      else
        nil
      end
    end
    
    def to_param()
      id
    end
    
    def update_attribute(name, value)
      send(name.to_s + '=', value)
      save
    end
  
    def [](attr_name)
      @attributes[attr_name.to_s]
    end
    
    def []=(attr_name, value)
      if value.nil?
        @current = false
        @attributes.delete(attr_name.to_s)
        nil
      elsif @attributes[attr_name.to_s] != value
        @current = false
        @attributes[attr_name.to_s] = value
      end
    end  
      
    def method_missing(m, *args)
      if m.to_s.ends_with? '='       
        name = m.to_s[0..-2].to_s
        value = args[0]
        
        if value.nil?
          @current = false
          @attributes.delete(name)
        elsif @attributes[name] != value
          @current = false
          @attributes[name] = value
        end
      else
        @attributes[m.to_s]
      end
    end
    
    # Generate XML for element
    def to_xml(options={:dasherize => false})
      all_attributes = {'id' => id}.merge(@attributes)
      all_attributes.to_xml({:root => _resource}.merge(options))
    end
    
    alias_method :save!, :save
    alias_method :destroy, :delete
      

    # Include Validations module from ActiveRecord. Only the simpler
    # validations that do not rely on RDBMS table metadata are supported.
    include ActiveRecord::Validations    

        
    def Base.human_attribute_name(attr_name)
      human_names = read_inheritable_attribute(:human_names) || {}
      human_names[attr_name.to_sym] || attr_name
    end    

    
    def Base.store_attribute_in_class(class_attr_name, args)
      human_names = read_inheritable_attribute(class_attr_name) || {}
      args.each do |arg|
        arg.each_pair do |attr_name, human_name|
          human_names[attr_name.to_sym] = human_name
        end
      end
      write_inheritable_attribute(class_attr_name, human_names)
    end
    
    def Base.human_name(*args)
      store_attribute_in_class(:human_names, args)
    end

    def Base.type_cast(*args)
      store_attribute_in_class(:type_casts, args)
    end
        
    protected
      def run_type_casts
        type_casts = self.class.read_inheritable_attribute(:type_casts) || {}
        type_casts.each_pair do |attr_name, to_suffix|
          value = self[attr_name]
          self[attr_name] = value.send("to_#{to_suffix}") unless value.nil?
        end
      end          
    
  end  
                             
                             
end
