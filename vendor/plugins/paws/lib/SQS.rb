# Sample Ruby code for the O'Reilly book "Using AWS Infrastructure
# Services" by James Murty.
#
# This code was written for Ruby version 1.8.6 or greater.
#
# The SQS module implements the Query API of the Amazon Simple Queue
# Service.
require 'AWS'

class SQS
  include AWS # Include the AWS module as a mixin

  ENDPOINT_URI = URI.parse("https://queue.amazonaws.com/")
  API_VERSION = '2007-05-01'
  SIGNATURE_VERSION = '1'

  HTTP_METHOD = 'POST' # 'GET'


  def list_queues(queue_name_prefix=nil)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'ListQueues',
      'QueueNamePrefix' => queue_name_prefix
      })

    response = do_query(HTTP_METHOD, ENDPOINT_URI, parameters)

    queue_names = []
    xml_doc = REXML::Document.new(response.body)

    xml_doc.elements.each('//QueueUrl') do |queue_url|
      queue_names << queue_url.text
    end

    return queue_names
  end

  def create_queue(queue_name, visibility_timeout_secs=nil)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'CreateQueue',
      'QueueName' => queue_name,
      'DefaultVisibilityTimeout' => visibility_timeout_secs
      })

    response = do_query(HTTP_METHOD, ENDPOINT_URI, parameters)

    xml_doc = REXML::Document.new(response.body)
    return xml_doc.elements['//QueueUrl'].text
  end

  def delete_queue(queue_url, force_deletion=nil)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'DeleteQueue',
      'ForceDeletion' => force_deletion
      })

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    return true
  end

  def get_queue_attributes(queue_url, attribute='All')
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetQueueAttributes',
      'Attribute' => attribute
      })

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    attributes = {}
    xml_doc = REXML::Document.new(response.body)

    xml_doc.elements.each('//AttributedValue') do |att|
      name = att.elements['Attribute'].text
      # All currently supported attributes have integer values
      value = att.elements['Value'].text.to_i

      attributes[name] = value
    end

    return attributes
  end

  def set_queue_attribute(queue_url, value, attribute='VisibilityTimeout')
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'SetQueueAttributes',
      'Attribute' => attribute,
      'Value' => value
      })

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)
    return true
  end

  def send_message(queue_url, message_body, encode=false)
    message_body = encode_base64(message_body) if encode

    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'SendMessage',
      'MessageBody' => message_body
      })

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    xml_doc = REXML::Document.new(response.body)
    return xml_doc.elements['//MessageId'].text
  end

  def peek_message(queue_url, message_id)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'PeekMessage',
      'MessageId' => message_id
      })

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    xml_doc = REXML::Document.new(response.body)

    return {
      :id => xml_doc.elements['//MessageId'].text,
      :body => xml_doc.elements['//MessageBody'].text
    }
  end

  def receive_messages(queue_url, maximum=1, visibility_timeout=nil)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'ReceiveMessage',
      'NumberOfMessages' => maximum,
      'VisibilityTimeout' => visibility_timeout
      })

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    msgs = []

    xml_doc = REXML::Document.new(response.body)

    xml_doc.elements.each('//Message') do |msg|
      msgs << {
        :id => msg.elements['MessageId'].text,
        :body => msg.elements['MessageBody'].text
      }
    end

    return msgs
  end

  def delete_message(queue_url, message_id)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'DeleteMessage',
      'MessageId' => message_id
      })

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    return true
  end

  def change_message_visibility(queue_url, message_id, visibility_timeout=0)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'ChangeMessageVisibility',
      'MessageId' => message_id,
      'VisibilityTimeout' => visibility_timeout
      })

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    return true
  end

  def list_grants(queue_url, options={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'ListGrants'
      })

    if options[:permission]
      parameters['Permission'] = options[:permission]
    end

    if options[:grantee]
      if options[:grantee].index('@')
        parameters['Grantee.EmailAddress'] = options[:grantee]
      else
        parameters['Grantee.ID'] = options[:grantee]
      end
    end

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    grants = []

    xml_doc = REXML::Document.new(response.body)

    xml_doc.elements.each('//GrantList') do |grant|
      grants << {
        :id => grant.elements['Grantee/ID'].text,
        :display_name => grant.elements['Grantee/DisplayName'].text,
        :permission => grant.elements['Permission'].text
      }
    end

    return grants
  end

  def add_grant(queue_url, grantee, permission)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'AddGrant',
      'Permission' => permission
      })

    if grantee.index('@')
      parameters['Grantee.EmailAddress'] = grantee
    else
      parameters['Grantee.ID'] = grantee
    end

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    return true
  end

  def remove_grant(queue_url, grantee, permission)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'RemoveGrant',
      'Permission' => permission
      })

    if grantee.index('@')
      parameters['Grantee.EmailAddress'] = grantee
    else
      parameters['Grantee.ID'] = grantee
    end

    response = do_query(HTTP_METHOD, URI.parse(queue_url), parameters)

    return true
  end

  def receive_new_messages(msgs, queue_url, max_count=1)
    new_msgs = receive_messages(queue_url, max_count)
    new_msgs.each do |new|
      msgs << new unless msgs.find{|old| old[:id] == new[:id]}
    end
    return msgs
  end

end
