# Sample Ruby code for the O'Reilly book "Using AWS Infrastructure
# Services" by James Murty.
#
# This code was written for Ruby version 1.8.6 or greater.
#
# The SQS module implements the Query API of the Amazon Flexible Payments
# Service.
require 'AWS'

class FPS
  include AWS # Include the AWS module as a mixin

  ENDPOINT_URI = URI.parse("https://fps.sandbox.amazonaws.com/")
  PIPELINE_URI = URI.parse("https://authorize.payments-sandbox.amazon.com"+
                                             "/cobranded-ui/actions/start")

  API_VERSION = '2007-01-08'
  SIGNATURE_VERSION = '1'

  HTTP_METHOD = 'POST' # 'GET'


  class FpsServiceError < RuntimeError
    attr_accessor :code, :reason, :type, :retriable

    def initialize(xml_doc)
      errors = xml_doc.elements['*/Errors/Errors']

      code = errors.elements['ErrorCode'].text
      reason = errors.elements['ReasonText'].text
      type = errors.elements['ErrorType'].text
      retriable = errors.elements['IsRetriable'].text == 'true'

      # Initialize the RuntimeError superclass with the descriptive message
      super(code + " - " + reason)
    end
  end

  def do_fps_query(parameters)
    response = do_query(HTTP_METHOD, ENDPOINT_URI, parameters)
    xml_doc = REXML::Document.new(response.body)

    if xml_doc.elements['*/Status'].text != 'Success'
      raise FpsServiceError.new(xml_doc)
    end

    return xml_doc
  end

  def parse_transaction_response(elem)
    response = {
      :id => elem.elements['TransactionId'].text,
      :status => elem.elements['Status'].text
    }

    if elem.elements['StatusDetail']
      response[:status_detail] = elem.elements['StatusDetail'].text
    end

    if elem.elements['NewSenderTokenUsage']
      usage = []
      elem.elements.each('NewSenderTokenUsage') do |nstu|
        usage << parse_token_usage_limit(nstu)
      end
      response[:token_usage] = usage
    end
    return response
  end

  def parse_token_usage_limit(elem)
    limit = {}
    # Limit is either an Amount limit or a Count limit
    if elem.elements['Amount']
      limit[:type] = 'Amount'
      limit[:amount] = elem.elements['Amount/Amount'].text
      limit[:currency_code] = elem.elements['Amount/CurrencyCode'].text
      limit[:reset_amount] = elem.elements['LastResetAmount/Amount'].text
      limit[:reset_currency_code] = elem.elements['LastResetAmount/CurrencyCode'].text
    else
      limit[:type] = 'Count'
      limit[:count] = elem.elements['Count'].text
      limit[:reset_count] = elem.elements['LastResetCount'].text
    end
    if elem.elements['LastResetTimeStamp']
      limit[:reset_timestamp] = elem.elements['LastResetTimeStamp'].text
    end
    return limit
  end

  def parse_transaction(transaction_element)
    elems = transaction_element.elements
    t = {
      :id => elems['TransactionId'].text,
      :caller_date => elems['CallerTransactionDate'].text,
      :received_date => elems['DateReceived'].text,
      :transaction_amount => {
        :amount => elems['TransactionAmount/Amount'].text,
        :currency_code => elems['TransactionAmount/CurrencyCode'].text
      },
      :fees => {
        :amount => elems['Fees/Amount'].text,
        :currency_code => elems['Fees/CurrencyCode'].text
      },
      :operation => elems['Operation'].text,
      :method => elems['PaymentMethod'].text,
      :status => elems['Status'].text,
      :caller_name => elems['CallerName'].text
    }
    t[:sender_name] = elems['SenderName'].text if elems['SenderName']
    t[:recipient_name] = elems['RecipientName'].text if elems['RecipientName']
    t[:completed_date] = elems['DateCompleted'].text if elems['DateCompleted']
    t[:caller_token_id] =
      elems['CallerTokenId'].text if elems['CallerTokenId']
    t[:sender_token_id] =
      elems['SenderTokenId'].text if elems['SenderTokenId']
    t[:recipient_token_id] =
      elems['RecipientTokenId'].text if elems['RecipientTokenId']
    t[:error_code] = elems['ErrorCode'].text if elems['ErrorCode']
    t[:error_message] = elems['ErrorMessage'].text if elems['ErrorMessage']
    t[:metadata] = elems['Metadata'].text if elems['Metadata']
    t[:original_id] =
      elems['OriginalTransactionId'].text if elems['OriginalTransactionId']
    t[:balance] = {
        :amount => elems['Balance/Amount'].text,
        :currency_code => elems['Balance/CurrencyCode'].text
      } if elems['Balance']

    elems.each('TransactionParts') do |tp|
      t[:parts] ||= [] # Initialize the parts array the first time only
      part = {
        :id => tp.elements['AccountId'].text,
        :role => tp.elements['Role'].text
      }
      part[:name] = tp.elements['Name'].text if tp.elements['Name']
      part[:instrument_id] =
        tp.elements['InstrumentId'].text if tp.elements['InstrumentId']
      part[:description] =
        tp.elements['Description'].text if tp.elements['Description']
      part[:reference] =
        tp.elements['Reference'].text if tp.elements['Reference']
      part[:fee_paid] = {
        :amount => tp.elements['FeePaid/Amount'].text,
        :currency_code => tp.elements['FeePaid/CurrencyCode'].text
      } if tp.elements['FeePaid']
      t[:parts] << part
    end

    elems.each('RelatedTransactions') do |rt|
      t[:related_transaction_ids] ||= [] # Init array first time only
      t[:related_transaction_ids] << rt.elements['TransactionId'].text
    end

    elems.each('StatusHistory') do |sh|
      t[:status_history] ||= [] # Init array first time only
      status_change = {
        :date => sh.elements['Date'].text,
        :status => sh.elements['Status'].text
      }
      if sh.elements['Amount']
        status_change[:amount] = sh.elements['Amount/Amount'].text
        status_change[:currency_code] =
          sh.elements['Amount/CurrencyCode'].text
      end
      t[:status_history] << status_change
    end

    return t
  end


  # Start date is a Time object
  def get_account_activity(start_date, options={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetAccountActivity',
      'StartDate' => start_date.iso8601,

      # Settings
      'EndDate' => options[:end_date],
      'MaxBatchSize' => options[:max_batch_size],
      'SortOrderByDate' => options[:sort_order],
      'ResponseGroup' => options[:response_group],

      # Filters
      'Operation' => options[:operation],
      'PaymentMethod' => options[:payment_method],
      'Role' => options[:role],
      'Status' => options[:status],
      })

    xml_doc = do_fps_query(parameters)

    transactions = []
    xml_doc.elements.each('//Transactions') do |t|
      transactions << parse_transaction(t)
    end

    result = {
      :transactions => transactions,
      :batch_size => xml_doc.elements['//ResponseBatchSize'].text,
    }

    if xml_doc.elements['//StartTimeForNextTransaction']
      result[:next_start_time] =
        xml_doc.elements['//StartTimeForNextTransaction'].text
    end

    return result
  end


  def get_account_balance
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetAccountBalance'
      })

    xml_doc = do_fps_query(parameters)

    return {
      :total => {
        :amount => xml_doc.elements['//TotalBalance/Amount'].text,
        :currency => xml_doc.elements['//TotalBalance/CurrencyCode'].text
      },
      :pending_in =>{
        :amount => xml_doc.elements['//PendingInBalance/Amount'].text,
        :currency => xml_doc.elements['//PendingInBalance/CurrencyCode'].text
      },
      :pending_out => {
        :amount => xml_doc.elements['//PendingOutBalance/Amount'].text,
        :currency => xml_doc.elements['//PendingOutBalance/CurrencyCode'].text
      },
      :disburse_balance => {
        :amount => xml_doc.elements['//DisburseBalance/Amount'].text,
        :currency => xml_doc.elements['//DisburseBalance/CurrencyCode'].text
      },
      :refund_balance => {
        :amount => xml_doc.elements['//RefundBalance/Amount'].text,
        :currency => xml_doc.elements['//RefundBalance/CurrencyCode'].text
      }
    }
  end


  def install_payment_instruction(instructions, caller_ref,
                                  type='Unrestricted', options={})

    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'InstallPaymentInstruction',
      'PaymentInstruction' => instructions,
      'CallerReference' => caller_ref,
      'TokenType' =>  type,

      # Options
      'TokenFriendlyName' => options[:name],
      'PaymentReason' => options[:reason]
      })

    xml_doc = do_fps_query(parameters)

    return xml_doc.elements['//TokenId'].text
  end


  def get_payment_instruction(token_id)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetPaymentInstruction',
      'TokenId' => token_id
      })

    xml_doc = do_fps_query(parameters)

    token = xml_doc.elements['//Token']
    token_info = {
      :status => token.elements['Status'].text,
      :id => token.elements['TokenId'].text,
      :old_id => token.elements['OldTokenId'].text,
      :caller_installed => token.elements['CallerInstalled'].text,
      :date_installed => token.elements['DateInstalled'].text,
      :caller_ref => token.elements['CallerReference'].text,
      :type => token.elements['TokenType'].text,
    }

    if token.elements['FriendlyName']
      token_info[:name] = token.elements['FriendlyName'].text
    end

    if token.elements['PaymentReason']
      token_info[:reason] = token.elements['PaymentReason'].text
    end

    return {
      :token => token_info,
      :instruction => xml_doc.elements['//PaymentInstruction'].text,
      :account_id => xml_doc.elements['//AccountId'].text,
      :name => token_info[:name] # This is a duplicate of the token's name
    }
  end


  # Options are - :name, :caller_ref, :status
  def get_tokens(options={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetTokens',
      'TokenFriendlyName' => options[:name],
      'TokenStatus' => options[:status],
      'CallerReference' => options[:caller_ref]
      })

    xml_doc = do_fps_query(parameters)

    tokens = []
    xml_doc.elements.each('//Tokens') do |token|
      token_info = {
        :status => token.elements['Status'].text,
        :id => token.elements['TokenId'].text,
        :old_id => token.elements['OldTokenId'].text,
        :caller_installed => token.elements['CallerInstalled'].text,
        :date_installed => token.elements['DateInstalled'].text,
        :caller_ref => token.elements['CallerReference'].text,
        :type => token.elements['TokenType'].text,
      }

      if token.elements['FriendlyName']
        token_info[:name] = token.elements['FriendlyName'].text
      end

      tokens << token_info
    end

    return tokens
  end

  # Options must include one of - :id, :caller_ref
  def get_token_by_caller(options={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetTokenByCaller',
      'TokenId' => options[:id],
      'CallerReference' => options[:caller_ref]
      })

    xml_doc = do_fps_query(parameters)

    token = xml_doc.elements['//Token']
    token_info = {
      :status => token.elements['Status'].text,
      :id => token.elements['TokenId'].text,
      :old_id => token.elements['OldTokenId'].text,
      :caller_installed => token.elements['CallerInstalled'].text,
      :date_installed => token.elements['DateInstalled'].text,
      :caller_ref => token.elements['CallerReference'].text,
      :type => token.elements['TokenType'].text,
    }

    if token.elements['FriendlyName']
      token_info[:name] = token.elements['FriendlyName'].text
    end

    return token_info
  end


  def get_token_usage(token_id)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetTokenUsage',
      'TokenId' => token_id
      })

    xml_doc = do_fps_query(parameters)

    limits = []
    xml_doc.elements.each('//TokenUsageLimits') do |tul|
      limits << parse_token_usage_limit(tul)
    end

    return limits
  end


  def cancel_token(token_id, reason=nil)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'CancelToken',
      'TokenId' => token_id,
      'ReasonText' => reason
      })

    xml_doc = do_fps_query(parameters)
    return true;
  end


  def pay(recipient_token_id, sender_token_id, caller_token_id, caller_ref,
          amount, currency_code, charge_to, options={})

    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'Pay',
      'RecipientTokenId' => recipient_token_id,
      'SenderTokenId' => sender_token_id,
      'CallerTokenId' => caller_token_id,
      'CallerReference' => caller_ref,
      'TransactionAmount.Amount' => amount,
      'TransactionAmount.CurrencyCode' => currency_code,
      'ChargeFeeTo' => charge_to,

      # Options
      'TransactionDate' => options[:caller_date],
      'SenderReference' => options[:sender_ref],
      'RecipientReference' => options[:recipient_ref],
      'SenderDescription' => options[:sender_desc],
      'RecipientDescription' => options[:recipient_desc],
      'CallerDescription' => options[:caller_desc],
      'MetaData' => options[:metadata]
      })

    xml_doc = do_fps_query(parameters)

    transaction = xml_doc.elements["//*[local-name()='TransactionResponse']"]
    return parse_transaction_response(transaction)
  end


  # Options - :amount, :currency_code, :date
  def refund(refunder_token_id, caller_token_id, transaction_id,
             caller_ref, charge_to, options={})

    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'Refund',
      'CallerTokenId' => caller_token_id,
      'RefundSenderTokenId' => refunder_token_id,
      'TransactionId' => transaction_id,
      'ChargeFeeTo' => charge_to,
      'CallerReference' => caller_ref,

      # Options
      'RefundAmount.Amount' => options[:amount],
      'RefundAmount.CurrencyCode' => options[:currency_code],
      'TransactionDate' => options[:date],
      'RefundSenderReference' => options[:sender_ref],
      'RefundRecipientReference' => options[:recipient_ref],
      'RefundSenderDescription' => options[:sender_desc],
      'RefundRecipientDescription' => options[:recipient_desc],
      'CallerDescription' => options[:caller_desc],
      'MetaData' => options[:metadata]
      })

    xml_doc = do_fps_query(parameters)

    transaction = xml_doc.elements["//*[local-name()='TransactionResponse']"]
    return parse_transaction_response(transaction)
  end


  def reserve(recipient_token_id, sender_token_id, caller_token_id,
              caller_ref, amount, currency_code, charge_to, options={})

    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'Reserve',
      'CallerTokenId' => caller_token_id,
      'RecipientTokenId' => recipient_token_id,
      'SenderTokenId' => sender_token_id,
      'TransactionAmount.Amount' => amount,
      'TransactionAmount.CurrencyCode' => currency_code,
      'ChargeFeeTo' => charge_to,
      'CallerReference' => caller_ref,

      # Options
      'TransactionDate' => options[:date],
      'SenderReference' => options[:sender_ref],
      'RecipientReference' => options[:recipient_ref],
      'SenderDescription' => options[:sender_desc],
      'RecipientDescription' => options[:recipient_desc],
      'CallerDescription' => options[:caller_desc],
      'MetaData' => options[:metadata]
      })

    xml_doc = do_fps_query(parameters)

    transaction = xml_doc.elements["//*[local-name()='TransactionResponse']"]
    return parse_transaction_response(transaction)
  end


  def settle(transaction_id, options={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'Settle',
      'ReserveTransactionId' => transaction_id,

      # Options
      'TransactionAmount.Amount' => options[:amount],
      'TransactionAmount.CurrencyCode' => options[:currency_code],
      'TransactionDate' => options[:date],
      })

    xml_doc = do_fps_query(parameters)

    transaction = xml_doc.elements["//*[local-name()='TransactionResponse']"]
    return parse_transaction_response(transaction)
  end


  def get_transaction(transaction_id)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetTransaction',
      'TransactionId' => transaction_id
      })

    xml_doc = do_fps_query(parameters)

    transaction = xml_doc.elements["//*[local-name()='Transaction']"]
    return parse_transaction(transaction)
  end


  def retry_transaction(transaction_id)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'RetryTransaction',
      'OriginalTransactionId' => transaction_id
      })

    xml_doc = do_fps_query(parameters)

    transaction = xml_doc.elements["//*[local-name()='TransactionResponse']"]
    return parse_transaction_response(transaction)
  end


  # Options - :operation, :max_results
  def get_results(options={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetResults',
      'MaxResultsCount' => options[:max_results],
      'Operation' => options[:operation]
      })

    xml_doc = do_fps_query(parameters)

    transactions = []
    xml_doc.elements.each('//TransactionResults') do |result|
      transactions << {
        :id => result.elements['TransactionId'].text,
        :type => result.elements['Operation'].text,
        :caller_ref => result.elements['CallerReference'].text,
        :status => result.elements['Status'].text,
      }
    end

    return {
      :pending => xml_doc.elements['//NumberPending'].text,
      :transactions => transactions
    }
  end


  def discard_results(transaction_ids)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'DiscardResults',
      },{
      'TransactionIds' => transaction_ids
      })

    xml_doc = do_fps_query(parameters)

    if xml_doc.elements['//DiscardErrors']
      return xml_doc.elements['//DiscardErrors'].text
    end
    return nil
  end


  def fund_prepaid(fund_id, instrument_id, caller_token_id, caller_ref,
                   amount, currency_code, charge_to, options={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'FundPrepaid',
      'SenderTokenId' => fund_id,
      'PrepaidInstrumentId' => instrument_id,
      'CallerTokenId' => caller_token_id,
      'FundingAmount.Amount' => amount,
      'FundingAmount.CurrencyCode' => currency_code,
      'CallerReference' => caller_ref,
      'ChargeFeeTo' => charge_to,

      # Options
      'TransactionDate' => options[:date],
      'SenderReference' => options[:sender_ref],
      'RecipientReference' => options[:recipient_ref],
      'SenderDescription' => options[:sender_desc],
      'RecipientDescription' => options[:recipient_desc],
      'CallerDescription' => options[:caller_desc],
      'MetaData' => options[:metadata]
      })

    xml_doc = do_fps_query(parameters)

    transaction = xml_doc.elements["//*[local-name()='TransactionResponse']"]
    return parse_transaction_response(transaction)
  end


  def get_prepaid_balance(instrument_id)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetPrepaidBalance',
      'PrepaidInstrumentId' => instrument_id
      })

    xml_doc = do_fps_query(parameters)

    pb_elems = xml_doc.elements['//PrepaidBalance'].elements
    return {
      :available => {
        :amount => pb_elems['AvailableBalance/Amount'].text,
        :currency_code => pb_elems['AvailableBalance/CurrencyCode'].text
      },
      :pending_in => {
        :amount => pb_elems['PendingInBalance/Amount'].text,
        :currency_code => pb_elems['PendingInBalance/CurrencyCode'].text
      }
    }
  end


  def get_all_prepaid_instruments(status=nil)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetAllPrepaidInstruments',
      'InstrumentStatus' => status
      })

    xml_doc = do_fps_query(parameters)

    instrument_ids = []
    xml_doc.elements.each('//PrepaidInstrumentIds/InstrumentId') do |id|
      instrument_ids << id.text
    end
    return instrument_ids
  end


  def get_total_prepaid_liability()
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetTotalPrepaidLiability'
      })

    xml_doc = do_fps_query(parameters)

    opl_elems = xml_doc.elements['//OutstandingPrepaidLiability'].elements
    return {
      :outstanding => {
        :amount => opl_elems['OutstandingBalance/Amount'].text,
        :currency_code => opl_elems['OutstandingBalance/CurrencyCode'].text
      },
      :pending_in => {
        :amount => opl_elems['PendingInBalance/Amount'].text,
        :currency_code => opl_elems['PendingInBalance/CurrencyCode'].text
      }
    }
  end


  def settle_debt(settlement_token_id, instrument_id, caller_token_id,
                  caller_ref, amount, currency_code, options={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'SettleDebt',
      'SenderTokenId' => settlement_token_id,
      'CreditInstrumentId' => instrument_id,
      'CallerTokenId' => caller_token_id,
      'SettlementAmount.Amount' => amount,
      'SettlementAmount.CurrencyCode' => currency_code,
      'CallerReference' => caller_ref,
      'ChargeFeeTo' => 'Recipient', # Fee-payer is hard-coded to Recipient

      # Options
      'TransactionDate' => options[:date],
      'SenderReference' => options[:sender_ref],
      'RecipientReference' => options[:recipient_ref],
      'SenderDescription' => options[:sender_desc],
      'RecipientDescription' => options[:recipient_desc],
      'CallerDescription' => options[:caller_desc],
      'MetaData' => options[:metadata]
      })

    xml_doc = do_fps_query(parameters)

    transaction = xml_doc.elements["//*[local-name()='TransactionResponse']"]
    return parse_transaction_response(transaction)
  end


  def write_off_debt(instrument_id, caller_token_id, caller_ref, amount,
                     currency_code, options={})
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'WriteOffDebt',
      'CreditInstrumentId' => instrument_id,
      'CallerTokenId' => caller_token_id,
      'AdjustmentAmount.Amount' => amount,
      'AdjustmentAmount.CurrencyCode' => currency_code,
      'CallerReference' => caller_ref,

      # Options
      'TransactionDate' => options[:date],
      'SenderReference' => options[:sender_ref],
      'RecipientReference' => options[:recipient_ref],
      'SenderDescription' => options[:sender_desc],
      'RecipientDescription' => options[:recipient_desc],
      'CallerDescription' => options[:caller_desc],
      'MetaData' => options[:metadata]
      })

    xml_doc = do_fps_query(parameters)

    transaction = xml_doc.elements["//*[local-name()='TransactionResponse']"]
    return parse_transaction_response(transaction)
  end


  def get_all_credit_instruments(status=nil)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetAllCreditInstruments',
      'InstrumentStatus' => status
      })

    xml_doc = do_fps_query(parameters)

    instrument_ids = []
    xml_doc.elements.each('//CreditInstrumentIds/InstrumentId') do |id|
      instrument_ids << id.text
    end
    return instrument_ids
  end


  def get_debt_balance(instrument_id)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetDebtBalance',
      'CreditInstrumentId' => instrument_id
      })

    xml_doc = do_fps_query(parameters)

    db_elems = xml_doc.elements['//DebtBalance'].elements
    return {
      :available => {
        :amount => db_elems['AvailableBalance/Amount'].text,
        :currency_code => db_elems['AvailableBalance/CurrencyCode'].text
      },
      :pending_out => {
        :amount => db_elems['PendingOutBalance/Amount'].text,
        :currency_code => db_elems['PendingOutBalance/CurrencyCode'].text
      }
    }
  end


  def get_outstanding_debt_balance()
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'GetOutstandingDebtBalance'
      })

    xml_doc = do_fps_query(parameters)

    od_elems = xml_doc.elements['//OutstandingDebt'].elements
    return {
      :outstanding => {
        :amount => od_elems['OutstandingBalance/Amount'].text,
        :currency_code => od_elems['OutstandingBalance/CurrencyCode'].text
      },
      :pending_out => {
        :amount => od_elems['PendingOutBalance/Amount'].text,
        :currency_code => od_elems['PendingOutBalance/CurrencyCode'].text
      }
    }
  end


  # operation is one of: 'postTransactionResult', 'postTokenCancellation'
  def subscribe_for_caller_notification(operation, url)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'SubscribeForCallerNotification',
      'NotificationOperationName' => operation,
      'WebServiceAPIURL' => url
      })

    xml_doc = do_fps_query(parameters)
    return true
  end


  # operation is one of: 'TransactionResults', 'TokenDeletion'
  def unsubscribe_for_caller_notification(operation)
    parameters = build_query_params(API_VERSION, SIGNATURE_VERSION,
      {
      'Action' => 'UnSubscribeForCallerNotification',
      'NotificationOperationName' => operation
      })

    xml_doc = do_fps_query(parameters)
    return true
  end


  ###################################################################################################
  # URI-building methods for initiating UI Pipeline requests
  ###################################################################################################

  def generate_pipeline_uri(pipeline, return_url, params={})
    # Set mandatory parameters
    parameters = {
      'callerKey' => @aws_access_key,
      'pipelineName' => pipeline,
      'returnURL' => return_url
    }

    # Add any extra parameters, ignoring those with a nil value
    parameters.merge!(params.reject {|k,v| v.nil?})

    # Build CBUI pipeline URI with sorted parameters
    uri = PIPELINE_URI.clone
    uri.query = ''
    parameters.sort_by {|key_val| key_val[0].downcase}.each do |key_val|
      uri.query << '&' if uri.query != ''
      uri.query << key_val[0] << "=" << CGI::escape(key_val[1].to_s)
    end

    # Sign Pipeline URI
    req_desc = uri.path + "?" + uri.query
    signature = generate_signature(req_desc)
    uri.query << '&awsSignature=' << CGI::escape(signature)

    return uri
  end


  # Parse URI's parameters into a hash map
  def parse_uri_parameters(uri)
    params = {}
    return params if uri.query.nil?

    uri.query.split('&').each do |param_name_and_value|
      # Everything before first '=' is the parameter's name
      fragments = param_name_and_value.split('=')
      name = fragments[0]

      # Everything after first '=' is the parameter's value
      value = param_name_and_value[name.size + 1..-1]

      # Unescape parameter values, except for the signature
      value = CGI.unescape(value) if name != 'awsSignature'

      params[name] = value
    end

    return params
  end

  def verify_pipeline_uri(uri)
    params = parse_uri_parameters(uri)

    # Find the AWS signature and remove it from the parameters
    sig_received = params['awsSignature']
    params.delete('awsSignature')

    # Sort the remaining parameters into an array
    params = params.sort_by {|h| h[0].downcase}

    # Build our own request description string from the result URI
    req_desc = uri.path + "?"
    req_desc << params.collect {|n, v| n + "=" + CGI.escape(v)}.join("&")

    # Sign the result URI to generate the expected signature value
    sig_expected = generate_signature(req_desc)

    # Check whether the result URI's signature matches the expected one
    return sig_received == sig_expected
  end


  def uri_for_single_use_sender(caller_ref, amount, return_url, options={})
    parameters = {
      'callerReference' => caller_ref,
      'transactionAmount' => amount,

      # Options
      'paymentReason' => options[:reason],
      'paymentMethod' => options[:method],
      'recipientToken' => options[:recipient_token],
      'reserve' => options[:reserve]
    }

    return generate_pipeline_uri('SingleUse', return_url, parameters).to_s
  end


  def uri_for_multi_use_sender(caller_ref, amount_limit, return_url, options={})
    parameters = {
      'callerReference' => caller_ref,
      'globalAmountLimit' => amount_limit,

      # Options
      'paymentReason' => options[:reason],
      'paymentMethod' => options[:method],
      'recipientTokenList' => options[:recipient_tokens],
      'amountType' => options[:amount_type],
      'transactionAmount' =>  options[:amount],
      'validityStart' => options[:start_date],
      'validityExpiry' => options[:end_date],
    }

    if options[:usage_limits]
      limit_index = 1

      options[:usage_limits].each do |limit|
        parameters["usageLimitType#{limit_index}"] = limit[:type]
        parameters["usageLimitPeriod#{limit_index}"] = limit[:period]
        parameters["usageLimitValue#{limit_index}"] = limit[:value]

        limit_index += 1
      end
    end

    return generate_pipeline_uri('MultiUse', return_url, parameters).to_s
  end


  def uri_for_recurring_sender(caller_ref, amount, period, return_url, options={})
    parameters = {
      'callerReference' => caller_ref,
      'transactionAmount' => amount,
      'recurringPeriod' => period,

      # Options
      'paymentReason' => options[:reason],
      'recipientToken' => options[:recipient_token],
      'validityStart' => options[:start_date],
      'validityExpiry' => options[:end_date],
      'paymentMethod' => options[:method]
    }

    return generate_pipeline_uri('Recurring', return_url, parameters).to_s
  end


  def uri_for_recipient(caller_ref, caller_ref_refund, recipient_pays, return_url, options={})
    parameters = {
      'callerReference' => caller_ref,
      'callerReferenceRefund' => caller_ref_refund,
      'recipientPaysFee' => (recipient_pays ? 'True' : 'False'),

      # Options
      'validityStart' => options[:start_date],
      'validityExpiry' => options[:end_date],
      'paymentMethod' => options[:method]
    }

    return generate_pipeline_uri('Recipient', return_url, parameters).to_s
  end


  def uri_for_prepaid_instrument(caller_ref_sender, caller_ref_funding,
                                 amount, return_url, options={})
    parameters = {
      'callerReferenceSender' => caller_ref_sender,
      'callerReferenceFunding' => caller_ref_funding,
      'fundingAmount' => amount,

      # Options
      'paymentReason' => options[:reason],
      'paymentMethod' => options[:method],
      'validityStart' => options[:start_date],
      'validityExpiry' => options[:end_date]
    }

    return generate_pipeline_uri('SetupPrepaid', return_url, parameters).to_s
  end


  def uri_for_postpaid_instrument(caller_ref_sender, caller_ref_settlement,
                                  amount, max_amount, return_url, options={})
    parameters = {
      'callerReferenceSender' => caller_ref_sender,
      'callerReferenceSettlement' => caller_ref_settlement,
      'creditLimit' => amount,
      'globalAmountLimit' => max_charge_amount,

      # Options
      'paymentReason' => options[:reason],
      'paymentMethod' => options[:method],
      'validityStart' => options[:start_date],
      'validityExpiry' => options[:end_date]
    }

    if options[:usage_limits]
      limit_index = 1

      options[:usage_limits].each do |limit|
        parameters["usageLimitType#{limit_index}"] = limit[:type]
        parameters["usageLimitPeriod#{limit_index}"] = limit[:period]
        parameters["usageLimitValue#{limit_index}"] = limit[:value]

        limit_index += 1
      end
    end

    return generate_pipeline_uri('SetupPostpaid', return_url, parameters).to_s
  end


  def uri_for_editing_token(caller_ref, token_id, return_url, options={})
    parameters = {
      'callerReference' => caller_ref,
      'tokenID' => token_id,

      # Options
      'paymentMethod' => options[:method]
    }

    return generate_pipeline_uri('EditToken', return_url, parameters).to_s
  end


  def build_payment_widget(payments_account_id, amount, description,
                           extra_fields={})
    fields = extra_fields.clone

    # Mandatory fields
    fields['amazonPaymentsAccountId'] = payments_account_id
    fields['accessKey'] = @aws_access_key
    fields['amount'] = "USD #{amount}"
    fields['description'] = "#{description}"

    # Generate a widget description and sign it
    widget_desc = fields.sort.to_s
    fields['signature'] = generate_signature(widget_desc)

    # Combine all fields into a string
    fields_string = ''
    fields.each_pair do |n,v|
      fields_string += %{<input type="hidden" name="#{n}" value="#{v}">\n}
    end

    return %{<form method="post" action=
    "https://authorize.payments-sandbox.amazon.com/pba/paypipeline">
    #{fields_string}
    <input type="image" border="0" src=
    "https://authorize.payments-sandbox.amazon.com/pba/images/payNowButton.png">
    </form>
    }
  end

end
