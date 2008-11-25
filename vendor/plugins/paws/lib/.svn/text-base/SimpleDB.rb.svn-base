# Sample Ruby code for the O'Reilly book "Using AWS Infrastructure
# Services" by James Murty.
#
# This code was written for Ruby version 1.8.6 or greater.
#
# The SimpleDB module implements the Query API of the Amazon SimpleDB
# Service.

require 'AWS'
require 'bigdecimal'

class SimpleDB
  include AWS # Include the AWS module as a mixin

  ENDPOINT_URI = URI.parse("https://sdb.amazonaws.com/")
  API_VERSION = '2007-11-07'
  SIGNATURE_VERSION = '1'

  HTTP_METHOD = 'POST' # 'GET'

  attr_reader :prior_box_usage
  attr_reader :total_box_usage


  def do_sdb_query(parameters)
    response = do_query(HTTP_METHOD, ENDPOINT_URI, parameters)
    xml_doc = REXML::Document.new(response.body)

    @total_box_usage = 0 if @total_box_usage.nil?

    @prior_box_usage = xml_doc.elements['//BoxUsage'].text.to_f
    @total_box_usage += @prior_box_usage

    return xml_doc
  end


  def encode_boolean(value)
    if value
      return '!b'
    else
      return '!B'
    end
  end


  def decode_boolean(value_str)
    if value_str == '!B'
      return false
    elsif value_str == '!b'
      return true
    else
      raise "Cannot decode boolean from string: #{value_str}"
    end
  end


  def encode_date(value)
    return "!d" + value.getutc.iso8601
  end


  def decode_date(value_str)
    if value_str[0..1] == '!d'
      return Time.parse(value_str[2..-1])
    else
      raise "Cannot decode date from string: #{value_str}"
    end
  end


  def encode_integer(value, max_digits=18)
    upper_bound = (10 ** max_digits)

    if value >= upper_bound or value < -upper_bound
      raise "Integer #{value} is outside encoding range (-#{upper_bound} " +
        "to #{upper_bound - 1})"
    end

    if value < 0
      return "!I" + format("%0#{max_digits}d", upper_bound + value)
    else
      return "!i" + format("%0#{max_digits}d", value)
    end
  end


  def decode_integer(value_str)
    if value_str[0..1] == '!I'
      # Encoded value is a negative integer
      max_digits = value_str.size - 2
      upper_bound = (10 ** max_digits)

      return value_str[2..-1].to_i - upper_bound
    elsif value_str[0..1] == '!i'
      # Encoded value is a positive integer
      return value_str[2..-1].to_i
    else
      raise "Cannot decode integer from string: #{value_str}"
    end
  end


  def encode_float(value, max_exp_digits=2, max_precision_digits=15)
    exp_midpoint = (10 ** max_exp_digits) / 2

    sign, fraction, base, exponent = BigDecimal(value.to_s).split

    if exponent >= exp_midpoint or exponent < -exp_midpoint
      raise "Exponent #{exponent} is outside encoding range " +
        "(-#{exp_midpoint} " + "to #{exp_midpoint - 1})"
    end

    if fraction.size > max_precision_digits
      # Round fraction value if it exceeds allowed precision.
      fraction_str = fraction[0...max_precision_digits] + '.' +
                     fraction[max_precision_digits..-1]
      fraction = BigDecimal(fraction_str).round(0).split[1]
    elsif fraction.size < max_precision_digits
      # Right-pad fraction with zeros if it is too short.
      fraction = fraction + ('0' * (max_precision_digits - fraction.size))
    end

    # The zero value is a special case, for which the exponent must be 0
    exponent = -exp_midpoint if value == 0

    if sign == 1
      return format("!f%0#{max_exp_digits}d", exp_midpoint + exponent) +
        format("!%0#{max_precision_digits}d", fraction.to_i)
    else
      fraction_upper_bound = (10 ** max_precision_digits)
      diff_fraction = fraction_upper_bound - BigDecimal(fraction)
      return format("!F%0#{max_exp_digits}d", exp_midpoint - exponent) +
        format("!%0#{max_precision_digits}d", diff_fraction)
    end
  end


  def decode_float(value_str)
    prefix = value_str[0..1]

    if prefix != '!f' and prefix != '!F'
      raise "Cannot decode float from string: #{value_str}"
    end

    value_str =~ /![fF]([0-9]+)!([0-9]+)/
    exp_str = $1
    fraction_str = $2

    max_exp_digits = exp_str.size
    exp_midpoint = (10 ** max_exp_digits) / 2
    max_precision_digits = fraction_str.size

    if prefix == '!F'
      sign = -1
      exp = exp_midpoint - exp_str.to_i

      fraction_upper_bound = (10 ** max_precision_digits)
      fraction = fraction_upper_bound - BigDecimal(fraction_str)
    else
      sign = 1
      exp = exp_str.to_i - exp_midpoint

      fraction = BigDecimal(fraction_str)
    end

    return sign * "0.#{fraction.to_i}".to_f * (10 ** exp)
  end


  def encode_attribute_value(value)
    if value == true or value == false
      return encode_boolean(value)
    elsif value.is_a? Time
      return encode_date(value)
    elsif value.is_a? Integer
      return encode_integer(value)
    elsif value.is_a? Numeric
      return encode_float(value)
    else
      # No type-specific encoding is available, so we simply convert
      # the value to a string.
      return value.to_s
    end
  end


  def decode_attribute_value(value_str)
    return '' if value_str.nil?

    # Check whether the '!' flag is present to indicate an encoded value
    return value_str if value_str[0..0] != '!'

    prefix = value_str[0..1].downcase
    if prefix == '!b'
      return decode_boolean(value_str)
    elsif prefix == '!d'
      return decode_date(value_str)
    elsif prefix == '!i'
      return decode_integer(value_str)
    elsif prefix == '!f'
      return decode_float(value_str)
    else
      return value_str
    end
  end


  def list_domains(max_domains=100)
    more_domains = true
    next_token = nil
    domain_names = []

    while more_domains
      parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
        {
        'Action' => 'ListDomains',
        'MaxNumberOfDomains' => max_domains,
        'NextToken' => next_token
        })

      xml_doc = do_sdb_query(parameters)

      xml_doc.elements.each('//DomainName') do |name|
        domain_names << name.text
      end

      # If we receive a NextToken element, perform a follow-up operation
      # to retrieve the next set of domain names.
      next_token = xml_doc.elements['//NextToken/text()']
      more_domains = !next_token.nil?
    end

    return domain_names
  end


  def create_domain(domain_name)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'CreateDomain',
      'DomainName' => domain_name
      })

    do_sdb_query(parameters)
    return true
  end


  def delete_domain(domain_name)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'DeleteDomain',
      'DomainName' => domain_name
      })

    do_sdb_query(parameters)
    return true
  end


  def build_attribute_params(attributes={}, replace=false)
    attribute_params = {}
    index = 0

    attributes.each do |attrib_name, attrib_value|
      attrib_value = [attrib_value] if not attrib_value.is_a? Array

      attrib_value.each do |value|
        attribute_params["Attribute.#{index}.Name"] = attrib_name
        if not value.nil?
          if respond_to? :encode_attribute_value
            # Automatically encode attribute values if the method
            # encode_attribute_value is available in this class
            value = encode_attribute_value(value)
          end
          attribute_params["Attribute.#{index}.Value"] = value
        end
        # Add a Replace parameter for the attribute if the replace flag is set
        attribute_params["Attribute.#{index}.Replace"] = 'true' if replace
        index += 1
      end if attrib_value
    end

    return attribute_params
  end


  def put_attributes(domain_name, item_name, attributes, replace=false)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'PutAttributes',
      'DomainName' => domain_name,
      'ItemName' => item_name
      })

    parameters.merge!(build_attribute_params(attributes, replace))

    do_sdb_query(parameters)
    return true
  end


  def delete_attributes(domain_name, item_name, attributes={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'DeleteAttributes',
      'DomainName' => domain_name,
      'ItemName' => item_name
      })

    parameters.merge!(build_attribute_params(attributes))

    do_sdb_query(parameters)
    return true
  end


  def get_attributes(domain_name, item_name, attribute_name=nil)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetAttributes',
      'DomainName' => domain_name,
      'ItemName' => item_name,
      'AttributeName' => attribute_name
      })

    xml_doc = do_sdb_query(parameters)

    attributes = {}
    xml_doc.elements.each('//Attribute') do |attribute_node|
      attr_name = attribute_node.elements['Name'].text
      value = attribute_node.elements['Value'].text

      if respond_to? :decode_attribute_value
        # Automatically decode attribute values if the method
        # decode_attribute_value is available in this class
        value = decode_attribute_value(value)
      end

      # An empty attribute value is an empty string, not nil.
      value = '' if value.nil?

      if attributes.has_key?(attr_name)
        attributes[attr_name] << value
      else
        attributes[attr_name] = [value]
      end
    end

    if not attribute_name.nil?
      # If a specific attribute was requested, return only the values array
      # for this attribute.
      if not attributes[attribute_name]
        return []
      else
        return attributes[attribute_name]
      end
    else
      return attributes
    end
  end


  def query(domain_name, query_expression=nil, options={:fetch_all=>true})
    more_items = true
    next_token = nil
    item_names = []

    while more_items
      parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
        {
        'Action' => 'Query',
        'DomainName' => domain_name,
        'QueryExpression' => query_expression,
        'MaxNumberOfItems' => options[:max_items],
        'NextToken' => next_token
        })

      xml_doc = do_sdb_query(parameters)

      xml_doc.elements.each('//ItemName') do |item_name|
        item_names << item_name.text
      end

      if xml_doc.elements['//NextToken']
        next_token = xml_doc.elements['//NextToken'].text.gsub("\n","")
        more_items = options[:fetch_all]
      else
        more_items = false
      end
    end

    return item_names
  end

end
