# Sample Ruby code for the O'Reilly book "Using AWS Infrastructure
# Services" by James Murty.
#
# This code was written for Ruby version 1.8.6 or greater.
#
# The S3 module implements the REST API of the Amazon Simple Storage Service.
require 'AWS'
require 'digest/md5'

class S3
  include AWS # Include the AWS module as a mixin

  S3_ENDPOINT = "s3.amazonaws.com"
  XMLNS = 'http://s3.amazonaws.com/doc/2006-03-01/'

  def valid_dns_name(bucket_name)
    if bucket_name.size > 63 or bucket_name.size < 3
      return false
    end

    return false unless bucket_name =~ /^[a-z0-9][a-z0-9.-]+$/

    return false unless bucket_name =~ /[a-z]/ # Cannot be an IP address

    bucket_name.split('.').each do |fragment|
      return false if fragment =~ /^-/ or fragment =~ /-$/ or fragment =~ /^$/
    end

    return true
  end


  def generate_s3_uri(bucket_name='', object_name='', params=[])
    # Decide between the default and sub-domain host name formats
    if valid_dns_name(bucket_name)
      hostname = bucket_name + "." + S3_ENDPOINT
    else
      hostname = S3_ENDPOINT
    end

    # Build an initial secure or non-secure URI for the end point.
    request_uri = (@secure_http ? "https://" : "http://") + hostname;

    # Include the bucket name in the URI except for alternative hostnames
    if hostname == S3_ENDPOINT
      request_uri << '/' + URI.escape(bucket_name) if bucket_name != ''
    end

    # Add object name component to URI if present
    request_uri << '/' + URI.escape(object_name) if object_name != ''

    # Add request parameters to the URI. Each item in the params variable
    # is a hash dictionary containing multiple keys.
    query = ""
    params.each do |hash|
      hash.each do |name, value|
        query << '&' if query.length > 0

        if value.nil?
          query << "#{name}"
        else
          query << "#{name}=#{CGI::escape(value.to_s)}"
        end
      end
    end
    request_uri << "?" + query if query.length > 0

    return URI.parse(request_uri)
  end


  def list_buckets
    uri = generate_s3_uri()
    response = do_rest('GET', uri)
    buckets = []

    xml_doc = REXML::Document.new(response.body)

    xml_doc.elements.each('//Buckets/Bucket') do |bucket|
      buckets << {
        :name => bucket.elements['Name'].text,
        :creation_date => bucket.elements['CreationDate'].text
      }
    end

    return {
      :owner_id => xml_doc.elements['//Owner/ID'].text,
      :display_name => xml_doc.elements['//Owner/DisplayName'].text,
      :buckets => buckets
    }
  end

  def create_bucket(bucket_name, location=nil)
    uri = generate_s3_uri(bucket_name)

    if location
      xml_doc = REXML::Document.new("<CreateBucketConfiguration/>")
      xml_doc.root.add_attribute('xmlns', XMLNS)
      xml_doc.root.add_element('LocationConstraint').text = location
      do_rest('PUT', uri, xml_doc.to_s, {'Content-Type'=>'text/xml'})
    else
      do_rest('PUT', uri)
    end

    return true
  end

  def delete_bucket(bucket_name)
    uri = generate_s3_uri(bucket_name)
    do_rest('DELETE', uri)
    return true
  end

  def get_bucket_location(bucket_name)
    uri = generate_s3_uri(bucket_name, '', [:location=>nil])
    response = do_rest('GET', uri)

    xml_doc = REXML::Document.new(response.body)
    return xml_doc.elements['LocationConstraint'].text
  end

  def list_objects(bucket_name, *params)
    is_truncated = true

    objects = []
    prefixes = []

    while is_truncated
      uri = generate_s3_uri(bucket_name, '', params)
      response = do_rest('GET', uri)

      xml_doc = REXML::Document.new(response.body)

      xml_doc.elements.each('//Contents') do |contents|
        objects << {
          :key => contents.elements['Key'].text,
          :size => contents.elements['Size'].text,
          :last_modified => contents.elements['LastModified'].text,
          :etag => contents.elements['ETag'].text,
          :owner_id => contents.elements['Owner/ID'].text,
          :owner_name => contents.elements['Owner/DisplayName'].text
        }
      end

      cps = xml_doc.elements.to_a('//CommonPrefixes')
      if cps.length > 0
        cps.each do |cp|
          prefixes << cp.elements['Prefix'].text
        end
      end

      # Determine whether listing is truncated
      is_truncated = 'true' == xml_doc.elements['//IsTruncated'].text

      # Remove any existing marker value
      params.delete_if {|p| p[:marker]}

      # Set the marker parameter to the NextMarker if possible,
      # otherwise set it to the last key name in the listing
      next_marker_elem = xml_doc.elements['//NextMarker']
      last_key_elem = xml_doc.elements['//Contents/Key[last()]']

      if next_marker_elem
        params << {:marker => next_marker_elem.text}
      elsif last_key_elem
        params << {:marker => last_key_elem.text}
      else
        params << {:marker => ''}
      end

    end

    return {
      :bucket_name => bucket_name,
      :objects => objects,
      :prefixes => prefixes
    }
  end


  def create_object(bucket_name, object_key, opts={})
    # Initialize local variables for the provided option items
    data = (opts[:data] ? opts[:data] : '')
    headers = (opts[:headers] ? opts[:headers].clone : {})
    metadata = (opts[:metadata] ? opts[:metadata].clone : {})

    # The Content-Length header must always be set when data is uploaded.
    headers['Content-Length'] =
          (data.respond_to?(:stat) ? data.stat.size : data.size).to_s

    # Calculate an md5 hash of the data for upload verification
    if data.respond_to?(:stat)
      # Generate MD5 digest from file data one chunk at a time
      md5_digest = Digest::MD5.new
      File.open(data.path, 'rb') do |io|
        buffer = ''
        md5_digest.update(buffer) while io.read(4096, buffer)
      end
      md5_hash = md5_digest.digest
    else
      md5_hash = Digest::MD5.digest(data)
    end
    headers['Content-MD5'] = encode_base64(md5_hash)

    # Set the canned policy, may be: 'private', 'public-read',
    # 'public-read-write', 'authenticated-read'
    headers['x-amz-acl'] = opts[:policy] if opts[:policy]

    # Set an explicit content type if none is provided, otherwise the
    # ruby HTTP library will use its own default type
    # 'application/x-www-form-urlencoded'
    if not headers['Content-Type']
      headers['Content-Type'] =
        data.respond_to?(:to_str) ? 'text/plain' : 'application/octet-stream'
    end

    # Convert metadata items to headers using the
    # S3 metadata header name prefix.
    metadata.each do |n,v|
      headers["x-amz-meta-#{n}"] = v
    end

    uri = generate_s3_uri(bucket_name, object_key)
    do_rest('PUT', uri, data, headers)
    return true
  end

  def delete_object(bucket_name, object_key)
    uri = generate_s3_uri(bucket_name, object_key)
    do_rest('DELETE', uri)
    return true
  end

  def get_object_metadata(bucket_name, object_key, headers={})
    uri = generate_s3_uri(bucket_name, object_key)
    response = do_rest('HEAD', uri, nil, headers)

    response_headers = {}
    metadata = {}

    response.each_header do |name,value|
      if name.index('x-amz-meta-') == 0
        metadata[name['x-amz-meta-'.length..-1]] = value
      else
        response_headers[name] = value
      end
    end

    return {
      :metadata => metadata,
      :headers => response_headers
    }
  end

  def get_object(bucket_name, object_key, headers={})
    uri = generate_s3_uri(bucket_name, object_key)

    if block_given?
      response = do_rest('GET', uri, nil, headers) {|segment| yield(segment)}
    else
      response = do_rest('GET', uri, nil, headers)
    end

    response_headers = {}
    metadata = {}

    response.each_header do |name,value|
      if name.index('x-amz-meta-') == 0
        metadata[name['x-amz-meta-'.length..-1]] = value
      else
        response_headers[name] = value
      end
    end

    result = {
      :metadata => metadata,
      :headers => response_headers
    }
    result[:body] = response.body if not block_given?

    return result
  end

  def get_logging(bucket_name)
    uri = generate_s3_uri(bucket_name, '', [:logging=>nil])
    response = do_rest('GET', uri)

    xml_doc = REXML::Document.new(response.body)

    if xml_doc.elements['//LoggingEnabled']
      return {
        :target_bucket => xml_doc.elements['//TargetBucket'].text,
        :target_prefix => xml_doc.elements['//TargetPrefix'].text
      }
    else
      # Logging is not enabled
      return nil
    end
  end

  def set_logging(bucket_name, target_bucket=nil,
                  target_prefix="#{bucket_name}.")

    # Build BucketLoggingStatus XML document
    xml_doc = REXML::Document.new("<BucketLoggingStatus xmlns='#{XMLNS}'/>")

    if target_bucket
      logging_enabled = xml_doc.root.add_element('LoggingEnabled')
      logging_enabled.add_element('TargetBucket').text = target_bucket
      logging_enabled.add_element('TargetPrefix').text = target_prefix
    end

    uri = generate_s3_uri(bucket_name, '', [:logging=>nil])
    do_rest('PUT', uri, xml_doc.to_s, {'Content-Type'=>'application/xml'})
    return true
  end

  def get_acl(bucket_name, object_key='')
    uri = generate_s3_uri(bucket_name, object_key, [:acl=>nil])
    response = do_rest('GET', uri)

    xml_doc = REXML::Document.new(response.body)

    grants = []

    xml_doc.elements.each('//Grant') do |grant|
      grantee = {}

      grantee[:type] = grant.elements['Grantee'].attributes['type']

      if grantee[:type] == 'Group'
        grantee[:uri] = grant.elements['Grantee/URI'].text
      else
        grantee[:id] = grant.elements['Grantee/ID'].text
        grantee[:display_name] = grant.elements['Grantee/DisplayName'].text
      end

      grants << {
        :grantee => grantee,
        :permission => grant.elements['Permission'].text
      }
    end

    return {
      :owner_id => xml_doc.elements['//Owner/ID'].text,
      :owner_name => xml_doc.elements['//Owner/DisplayName'].text,
      :grants => grants
    }
  end

  def set_acl(owner_id, bucket_name, object_key='',
              grants=[owner_id=>'FULL_CONTROL'])

    xml_doc = REXML::Document.new("<AccessControlPolicy xmlns='#{XMLNS}'/>")
    xml_doc.root.add_element('Owner').add_element('ID').text = owner_id
    grant_list = xml_doc.root.add_element('AccessControlList')

    grants.each do |hash|
      hash.each do |grantee_id, permission|

        grant = grant_list.add_element('Grant')
        grant.add_element('Permission').text = permission

        # Grantee may be of type email, group, or canonical user
        if grantee_id.index('@')
          # Email grantee
          grantee = grant.add_element('Grantee',
            {'xmlns:xsi'=>'http://www.w3.org/2001/XMLSchema-instance',
             'xsi:type'=>'AmazonCustomerByEmail'})
          grantee.add_element('EmailAddress').text = grantee_id
        elsif grantee_id.index('://')
          # Group grantee
          grantee = grant.add_element('Grantee',
            {'xmlns:xsi'=>'http://www.w3.org/2001/XMLSchema-instance',
             'xsi:type'=>'Group'})
          grantee.add_element('URI').text = grantee_id
        else
          # Canonical user grantee
          grantee = grant.add_element('Grantee',
            {'xmlns:xsi'=>'http://www.w3.org/2001/XMLSchema-instance',
             'xsi:type'=>'CanonicalUser'})
          grantee.add_element('ID').text = grantee_id
        end
      end
    end

    uri = generate_s3_uri(bucket_name, object_key, [:acl=>nil])
    do_rest('PUT', uri, xml_doc.to_s, {'Content-Type'=>'application/xml'})
    return true
  end

  def set_canned_acl(canned_acl, bucket_name, object_key='')
    uri = generate_s3_uri(bucket_name, object_key, [:acl=>nil])
    response = do_rest('PUT', uri, nil, {'x-amz-acl'=>canned_acl})
    return true
  end

  def get_torrent(bucket_name, object_key, output)
    uri = generate_s3_uri(bucket_name, object_key, [:torrent=>nil])
    response = do_rest('GET', uri)
    output.write(response.body)
  end

  def sign_uri(method, expires, bucket_name, object_key='', opts={})
    parameters = opts[:parameters] || []
    headers = opts[:headers] || {}

    headers['Date'] = expires

    uri = generate_s3_uri(bucket_name, object_key, parameters)
    signature = generate_rest_signature(method, uri, headers)

    uri.query = (uri.query.nil? ? '' : "#{uri.query}&")
    uri.query << "Signature=" + CGI::escape(signature)
    uri.query << "&Expires=" + expires.to_s
    uri.query << "&AWSAccessKeyId=" + @aws_access_key

    uri.host = bucket_name if opts[:is_virtual_host]

    return uri.to_s
  end


  def build_post_policy(expiration_time, conditions)
    if expiration_time.nil? or not expiration_time.respond_to?(:getutc)
      raise 'Policy document must include a valid expiration Time object'
    end
    if conditions.nil? or not conditions.class == Hash
      raise 'Policy document must include a valid conditions Hash object'
    end

    # Convert conditions object mappings to condition statements
    conds = []
    conditions.each_pair do |name,test|
      if test.nil?
        # A nil condition value means allow anything.
        conds << %{["starts-with", "$#{name}", ""]}
      elsif test.is_a? String
        conds << %{{"#{name}": "#{test}"}}
      elsif test.is_a? Array
        conds << %{{"#{name}": "#{test.join(',')}"}}
      elsif test.is_a? Hash
        operation = test[:op]
        value = test[:value]
        conds << %{["#{operation}", "$#{name}", "#{value}"]}
      elsif test.is_a? Range
        conds << %{["#{name}", #{test.begin}, #{test.end}]}
      else
        raise "Unexpected value type for condition '#{name}': #{test.class}"
      end
    end

    return %{{"expiration": "#{expiration_time.getutc.iso8601}",
              "conditions": [#{conds.join(",")}]}}
  end

  def build_post_form(bucket_name, key, options={})
    fields = []

    # Form is only authenticated if a policy is specified.
    if options[:expiration] or options[:conditions]
      # Generate policy document
      policy = build_post_policy(options[:expiration], options[:conditions])
      puts "POST Policy\n===========\n#{policy}\n\n" if @debug

      # Add the base64-encoded policy document as the 'policy' field
      policy_b64 = encode_base64(policy)
      fields << %{<input type="hidden" name="policy" value="#{policy_b64}">}

      # Add the AWS access key as the 'AWSAccessKeyId' field
      fields << %{<input type="hidden" name="AWSAccessKeyId"
                                       value="#{@aws_access_key}">}

      # Add signature for encoded policy document as the 'AWSAccessKeyId' field
      signature = generate_signature(policy_b64)
      fields << %{<input type="hidden" name="signature" value="#{signature}">}
    end

    # Include any additional fields
    options[:fields].each_pair do |n,v|
      if v.nil?
        # Allow users to provide their own <input> fields as text.
        fields << n
      else
        fields << %{<input type="hidden" name="#{n}" value="#{v}">}
      end
    end if options[:fields]

    # Add the vital 'file' input item, which may be a textarea or file.
    if options[:text_input]
      # Use the text_input option which should specify a textarea or text
      # input field. For example:
      # '<textarea name="file" cols="80" rows="5">Default Text</textarea>'
      fields << options[:text_input]
    else
      fields << %{<input name="file" type="file">}
    end

    # Construct a sub-domain URL to refer to the target bucket. The
    # HTTPS protocol will be used if the secure HTTP option is enabled.
    url = "http#{@secure_http ? 's' : ''}://#{bucket_name}.s3.amazonaws.com/"

    # Construct the entire form.
    form = %{
      <form action="#{url}" method="post" enctype="multipart/form-data">
        <input type="hidden" name="key" value="#{key}">
        #{fields.join("\n")}
        <br>
        <input type="submit" value="Upload to Amazon S3">
      </form>
      }
    puts "POST Form\n=========\n#{form}\n" if @debug

    return form
  end

end
