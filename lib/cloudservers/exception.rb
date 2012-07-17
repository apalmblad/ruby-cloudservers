module CloudServers
  class Exception

    class CloudServersError < StandardError

      attr_reader :response_body
      attr_reader :response_code

      # ------------------------------------------------------------- initialize
      def initialize(message, code, response_body)
        @response_code=code
        @response_body=response_body
        super(message)
      end

    end
    
    class CloudServersFault           < CloudServersError # :nodoc:
    end
    class ServiceUnavailable          < CloudServersError # :nodoc:
    end
    class Unauthorized                < CloudServersError # :nodoc:
    end
    class BadRequest                  < CloudServersError # :nodoc:
    end
    class OverLimit                   < CloudServersError # :nodoc:
    end
    class BadMediaType                < CloudServersError # :nodoc:
    end
    class BadMethod                   < CloudServersError # :nodoc:
    end
    class ItemNotFound                < CloudServersError # :nodoc:
    end
    class BuildInProgress             < CloudServersError # :nodoc:
    end
    class ServerCapacityUnavailable   < CloudServersError # :nodoc:
    end
    class BackupOrResizeInProgress    < CloudServersError # :nodoc:
    end
    class ResizeNotAllowed            < CloudServersError # :nodoc:
    end
    class NotImplemented              < CloudServersError # :nodoc:
    end
    class Other                       < CloudServersError # :nodoc:
    end
    class JobFailure              < CloudServersError # :nodoc:
      attr_reader :sub_error
      # ------------------------------------------------------------- initialize
      def initialize( sub_error, response_body)
        @sub_error = sub_error
        @respose_body = response_body
        super( "Asynchronous Request Failure: #{sub_error.message}" )
      end

      # ---------------------------------------------------------- response_code
      def response_code
        sub_error.response_code
      end
    end
    
    # Plus some others that we define here
    
    class ExpiredAuthToken            < StandardError # :nodoc:
    end
    class MissingArgument             < StandardError # :nodoc:
    end
    class InvalidArgument             < StandardError # :nodoc:
    end
    class TooManyPersonalityItems     < StandardError # :nodoc:
    end
    class PersonalityFilePathTooLong  < StandardError # :nodoc:
    end
    class PersonalityFileTooLarge     < StandardError # :nodoc:
    end
    class Authentication              < CloudServersError # :nodoc:
    end
    class Connection                  < StandardError # :nodoc:
    end
    class DuplicateObject                  < CloudServersError # :nodoc:
    end
    class LoadBalancerNotReady < StandardError
    end
    CODE_MAP = { 422 => LoadBalancerNotReady, 409 => DuplicateObject }
        
    # In the event of a non-200 HTTP status code, this method takes the HTTP response, parses
    # the JSON from the body to get more information about the exception, then raises the
    # proper error.  Note that all exceptions are scoped in the CloudServers::Exception namespace.
    # ---------------------------------------------------------- from_job_result
    def self.from_job_result( response )
      error_data = JSON.parse( response.body )
      error = error_data['error']
      ex_class = CODE_MAP[error['code']]
      if ex_class.nil?
        ex_class = CloudServers::Exception::Other
      end
      return ex_class.new( error['message'], error['code'], error.to_json)
    end
    # ---------------------------------------------------------- raise_exception
    def self.raise_exception(response)
      return if response.code =~ /^20.$/
      begin
        data = JSON.parse( response.body )
        ex_class = CODE_MAP[data['code']]
        ex_class ||= CloudServers::Exception::Other
        raise CloudServers::Exception::Other.new("The server returned status #{response.code}", response.code, response.body)
      end
    end
    
  end
end

