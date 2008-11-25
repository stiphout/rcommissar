# Sample Ruby code for the O'Reilly book "Using AWS Infrastructure
# Services" by James Murty.
#
# This code was written for Ruby version 1.8.6 or greater.
#
# The AWS module includes HTTP messaging and utility methods that handle
# communication with Amazon Web Services' REST or Query APIs. Service
# client implementations are built on top of this module.

require 'openssl'
require 'digest/sha1'
require 'base64'
require 'cgi'
require 'net/https'
require 'time'
require 'uri'
require 'rexml/document'

$KCODE = 'u' # Enable Unicode (international character) support

module AWS
  # Your Amazon Web Services Access Key credential.
  attr_accessor :aws_access_key

  # Your Amazon Web Services Secret Key credential.
  attr_accessor :aws_secret_key

  # Use only the Secure HTTP protocol (HTTPS)? When this value is true, all
  # requests are sent using HTTPS. When this value is false, standard HTTP
  # is used.
  attr_accessor :secure_http

  # Enable debugging messages? When this value is true, debug logging
  # messages describing AWS communication messages are printed to standard
  # output.
  attr_accessor :debug

  # The approximate difference in the current time between your computer and
  # Amazon's servers, measured in seconds.
  #
  # This value is 0 by default. Use the current_time method to obtain the
  # current time with this offset factor included, and the adjust_time
  # method to calculate an offset value for your computer based on a
  # response from an AWS server.
  attr_reader :time_offset

  #def initialize(access_key, secret_key, secure_http=true, debug=false)
  #  @aws_access_key = access_key
  #  @aws_secret_key = secret_key
  #  @time_offset = 0
  #  @secure_http = secure_http
  #  @debug = debug
  #end

  # Hard-coded credentials
  #def initialize(secure_http=true, debug=false)
  #  @aws_access_key = 'YOUR_AWS_ACCESS_KEY'
  #  @aws_secret_key = 'YOUR_AWS_SECRET_KEY'
  #  @time_offset = 0
  #  @secure_http = secure_http
  #  @debug = debug
  #end

  # Initialize AWS and set the service-specific variables: aws_access_key,
  # aws_secret_key, debug, and secure_http.
  def initialize(aws_access_key=ENV['AWS_ACCESS_KEY'],
                 aws_secret_key=ENV['AWS_SECRET_KEY'],
                 secure_http=true, debug=false)
    @aws_access_key = aws_access_key
    @aws_secret_key = aws_secret_key
    @time_offset = 0
    @secure_http = secure_http
    @debug = debug
  end


  # An exception object that captures information about an AWS service error.
  class ServiceError < RuntimeError
    attr_accessor :response, :aws_error_xml

    # Initialize a ServiceError object based on an HTTP Response
    def initialize(http_response)
      # Store the HTTP response as a class variable
      response = http_response

      # Add the HTTP status code and message to a descriptive message
      message = "HTTP Error: #{response.code} - #{response.message}"

      # If an AWS error message is available, add its code and message
      # to the overall descriptive message
      if response.body and response.body.index('<?xml') == 0
        aws_error_xml = REXML::Document.new(response.body)

        aws_error_code = aws_error_xml.elements['//Code'].text
        aws_error_message = aws_error_xml.elements['//Message'].text

        message += ", AWS Error: #{aws_error_code} - #{aws_error_message}"
      end

      # Initialize the RuntimeError superclass with the descriptive message
      super(message)
    end

  end


  # Generates an AWS signature value for the given request description.
  # The result value is a HMAC signature that is cryptographically signed
  # with the SHA1 algorithm using your AWS Secret Key credential. The
  # signature value is Base64 encoded before being returned.
  #
  # This method can be used to sign requests destined for the REST or
  # Query AWS API interfaces.
  def generate_signature(request_description)
    raise "aws_access_key is not set" if not @aws_access_key
    raise "aws_secret_key is not set" if not @aws_secret_key

    digest_generator = OpenSSL::Digest::Digest.new('sha1')
    digest = OpenSSL::HMAC.digest(digest_generator,
                                  @aws_secret_key,
                                  request_description)
    b64_sig = encode_base64(digest)
    return b64_sig
  end


  # Converts a minimal set of parameters destined for an AWS Query API
  # interface into a complete set necessary for invoking an AWS operation.
  #
  # Normal parameters are included in the resultant complete set as-is.
  #
  # Indexed parameters are converted into multiple parameter name/value
  # pairs, where the name starts with the given parameter name but has a
  # suffix value appended to it. For example, the input mapping
  #   'Name' => ['x','y']
  # will be converted to two parameters:
  #   'Name.1' => 'x'
  #   'Name.2' => 'y'
  def build_query_params(api_ver, sig_ver, params, indexed_params={}, indexed_start=1)
    # Set mandatory query parameters
    built_params = {
      'Version' => api_ver,
      'SignatureVersion' => sig_ver,
      'AWSAccessKeyId' => @aws_access_key
    }

    # Use current time as timestamp if no date/time value is already set
    if params['Timestamp'].nil? and params['Expires'].nil?
      params['Timestamp'] = current_time.getutc.iso8601
    end

    # Merge parameters provided with defaults after removing
    # any parameters without a value.
    built_params.merge!(params.reject {|name,value| value.nil?})

    # Add any indexed parameters as ParamName.1, ParamName.2, etc
    indexed_params.each do |param_name,value_array|
      index_count = indexed_start
      value_array.each do |value|
        built_params["#{param_name}.#{index_count}"] = value
        index_count += 1
      end if value_array
    end

    return built_params
  end


  # Sends a GET or POST request message to an AWS service's Query API
  # interface and returns the response result from the service. This method
  # signs the request message with your AWS credentials.
  #
  # If the AWS service returns an error message, this method will throw a
  # ServiceException describing the error.
  def do_query(method, uri, parameters)
    # Ensure the URI is using Secure HTTP protocol if the flag is set
    if @secure_http
      uri.scheme = 'https'
      uri.port = 443
    else
      uri.scheme = 'http'
      uri.port = 80
    end

    # Generate request description and signature, and add to the request
    # as the parameter 'Signature'
    req_desc = parameters.sort {|x,y| x[0].downcase <=> y[0].downcase}.to_s
    signature = generate_signature(req_desc)
    parameters['Signature'] = signature

    STDERR.puts "------------------We have req_desc: #{req_desc} and signature: #{signature}"
	

    case method
    when 'GET'
      # Create GET request with parameters in URI
      uri.query = ''
      parameters.each do |name, value|
        uri.query << "#{name}=#{CGI::escape(value.to_s)}&"
      end
      req = Net::HTTP::Get.new(uri.request_uri)
    when 'POST'
      # Create POST request with parameters in form data
      req = Net::HTTP::Post.new(uri.request_uri)
      req.set_form_data(parameters)
      req.set_content_type('application/x-www-form-urlencoded', 
        {'charset', 'utf-8'})
    else
      raise "Invalid HTTP Query method: #{method}"
    end

    # Setup HTTP connection, optionally with SSL security
    Net::HTTP.version_1_1
    http = Net::HTTP.new(uri.host, uri.port)
    if @secure_http
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    debug_request(method, uri, {}, parameters) if @debug

    response = http.request(req)

    debug_response(response) if @debug

    if response.is_a?(Net::HTTPSuccess)
      return response
    else
      raise ServiceError.new(response)
    end
  end


  # Generates a request description string for a request destined for a REST
  # AWS API interface, and returns a signature value for the request.
  #
  # This method will work for any REST AWS request, though it is intended
  # mainly for the S3 service's API and handles special cases required for
  # this service.
  def generate_rest_signature(method, uri, headers)
    # Set mandatory Date header if it is missing
    headers['Date'] = current_time.httpdate if not headers['Date']

    # Describe main components of REST request
    req_desc =
      "#{method}\n" +
      "#{headers['Content-MD5']}\n" +
      "#{headers['Content-Type']}\n" +
      "#{headers['Date']}\n"

    # Find any x-amz-* headers, sort them and append to the description
    amz_headers = headers.reject {|name,value| name.index('x-amz-') != 0}
    amz_headers = amz_headers.sort {|x, y| x[0] <=> y[0]}
    amz_headers.each {|name,value| req_desc << "#{name.downcase}:#{value}\n"}

    path = ''

    # Handle special case of S3 alternative hostname URIs. The bucket
    # portion of alternative hostnames must be included in the request
    # description's URI path.
    if not ['s3.amazonaws.com', 'queue.amazonaws.com'].include?(uri.host)
      if uri.host =~ /(.*).s3.amazonaws.com/
        path << '/' + $1
      else
        path << '/' + uri.host
      end
      # For alternative hosts, the path must end with a slash if there is
      # no object in the path.
      path << '/' if uri.path == ''
    end

    # Append the request's URI path to the description
    path << uri.path

    # Ensure the request description's URI path includes at least a slash.
    if path == ''
      req_desc << '/'
    else
      req_desc << path
    end

    # Append special S3 parameters to request description
    if uri.query
      uri.query.split('&').each do |param|
        if ['acl', 'torrent', 'logging', 'location'].include?(param)
          req_desc << "?" + param
        end
      end
    end

    if @debug
      puts "REQUEST DESCRIPTION\n======="
      puts "#{req_desc.gsub("\n","\\n\n")}\n\n"
    end

    # Generate signature
    return generate_signature(req_desc)
  end


  # Sends a GET, HEAD, DELETE or PUT request message to an AWS service's
  # REST API interface and returns the response result from the service. This
  # method signs the request message with your AWS credentials.
  #
  # If the AWS service returns an error message, this method will throw a
  # ServiceException describing the error. This method also includes support
  # for following Temporary Redirect responses (with HTTP response
  # codes 307).
  def do_rest(method, uri, data=nil, headers={})
    # Generate request description and signature, and add to the request
    # as the header 'Authorization'
    signature = generate_rest_signature(method, uri, headers)
    headers['Authorization'] = "AWS #{@aws_access_key}:#{signature}"

    # Ensure the Host header is always set
    headers['Host'] = uri.host

    # Tell service to confirm the request message is valid before it
    # accepts data. Confirmation is indicated by a 100 (Continue) message
    headers['Expect'] = '100-continue' if method == 'PUT'

    redirect_count = 0
    while redirect_count < 5 # Repeat requests after a 307 Temporary Redirect

      # Setup a new HTTP connection, optionally with secure HTTPS enabled
      Net::HTTP.version_1_1
      http = Net::HTTP.new(uri.host, uri.port)
      if @secure_http
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      debug_request(method, uri, headers, {}, data) if @debug

      # Perform the request. Uploads via the PUT method get special treatment
      if method == 'PUT'
        if data.respond_to?(:stat)
          # Special case for file uploads, these are streamed
          req = Net::HTTP::Put.new(uri.path, headers)
          req.body_stream=data
          response = http.request(req)
        else
          # Ensure HTTP content-length header is set to correct value
          headers['Content-Length'] = (data.nil? ? '0' : data.length.to_s)
          response = http.send_request(method, uri.request_uri, data, headers)
        end
      elsif method == 'GET' and block_given?
        # Special case for streamed downloads
        http.request_get(uri.request_uri, headers) do |response|
          response.read_body {|segment| yield(segment)}
        end
      else
        response = http.send_request(method, uri.request_uri, data, headers)
      end

      debug_response(response) if @debug

      if response.is_a?(Net::HTTPTemporaryRedirect) # 307 Redirect
        # Update the request to use the temporary redirect URI location
        uri = URI.parse(response.header['location'])
        redirect_count += 1 # Count to prevent infinite redirects
      elsif response.is_a?(Net::HTTPSuccess)
        return response
      else
        raise ServiceError.new(response)
      end

    end # End of while loop
  end


  # Prints detailed information about an HTTP request message to standard
  # output.
  def debug_request(method, uri, headers={}, query_parameters={}, data=nil)
    puts "REQUEST\n======="
    puts "Method : #{method}"

    # Print URI
    params = uri.to_s.split('&')
    puts "URI    : #{params.first}"
    params[1..-1].each {|p| puts "\t &#{p}"} if params.length > 1

    # Print Headers
    if headers.length > 0
      puts "Headers:"
      headers.each {|n,v| puts "  #{n}=#{v}"}
    end

    # Print Query Parameters
    if query_parameters.length > 0
      puts "Query Parameters:"
      query_parameters.each {|n,v| puts "  #{n}=#{v}"}
    end

    # Print Request Data
    if data
      puts "Request Body Data:"
      if headers['Content-Type'] == 'application/xml'
        # Pretty-print XML data
        REXML::Document.new(data).write($stdout, 2)
      else
        puts data
      end
      data.rewind if data.respond_to?(:stat)
      puts
    end
  end


  # Prints detailed information about an HTTP response message to standard
  # output.
  def debug_response(response)
    puts "\nRESPONSE\n========"
    puts "Status : #{response.code} #{response.message}"

    # Print Headers
    if response.header.length > 0
      puts "Headers:"
      response.header.each {|n,v| puts "  #{n}=#{v}"}
    end

    if response.body and response.body.respond_to?(:length)
      puts "Body:"
      if response.body.index('<?xml') == 0
        # Pretty-print XML data
        REXML::Document.new(response.body).write($stdout)
      else
        puts response.body
      end
    end
    puts
  end


  # Returns the current date and time, adjusted according to the time
  # offset between your computer and an AWS server (as set by the
  # adjust_time method.
  def current_time
    if @time_offset
      return Time.now + @time_offset
    else
      return Time.now
    end
  end


  # Sets a time offset value to reflect the time difference between your
  # computer's clock and the current time according to an AWS server. This
  # method returns the calculated time difference and also sets the
  # timeOffset variable in AWS.
  #
  # Ideally you should not rely on this method to overcome clock-related
  # disagreements between your computer and AWS. If you computer is set
  # to update its clock periodically and has the correct timezone setting
  # you should never have to resort to this work-around.
  def adjust_time(uri=URI.parse('http://aws.amazon.com/'))
    http = Net::HTTP.new(uri.host, uri.port)
    response = http.send_request('GET', uri.request_uri)

    local_time = Time.new
    aws_time = Time.httpdate(response.header['Date'])
    @time_offset = aws_time - local_time

    puts "Time offset for AWS requests: #{@time_offset} seconds" if @debug
    return @time_offset
  end


  # Base64-encodes a string, and removes the excess newline ('\n')
  # characters inserted by the default ruby encoder.
  def encode_base64(data)
    return nil if not data
    b64 = Base64.encode64(data)
    cleaned = b64.gsub("\n","")
    return cleaned
  end

end
