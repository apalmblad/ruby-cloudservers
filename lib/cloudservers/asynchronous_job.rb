class CloudServers::AsynchronousJob
  RUNNING_STATUS = 'RUNNING'
  ERROR_STATUS = 'ERROR'
  COMPLETED_STATUS = "COMPLETED"
  attr_reader :last_response
  def initialize( connection, job_id, call_back )
    @connection = connection
    @job_id = job_id
    @call_back = URI.parse( call_back )
  end

  # ------------------------------------------------------------------ from_json
  def self.from_json( conn, json )
    data = JSON.parse( json )
    #result = data['asyncResponse']
    result = data
    new( conn, result['jobId'], result['callbackUrl'] )
  end
  # ---------------------------------------------------------------- successful?
  def successful?
    if @successful.nil?
      @successful = JSON.parse( @last_response.response.body )['status'] == COMPLETED_STATUS
    end
    return @successful 
  end
  # ----------------------------------------------------------- wait_for_results
  def wait_for_results( sleep_time = 1 )
    while !done?
      sleep( sleep_time )
    end
    if successful?
      return JSON.parse( last_response.response.body )
    else
      CloudServers::Exception.raise_exception( last_response )
    end
  end

  # ---------------------------------------------------------------------- done?
  def done?
    r = @connection.csreq( 'GET', @call_back.host, @call_back.path, @call_back.port, @call_back.scheme, { 'content-type' => 'application/json' } )
    if r.code.to_i == 202
      @last_response = r
      return false
    elsif r.code.to_i == 200
      @last_response = r
      result = JSON.parse( r.response.body )
      if result['status'] == RUNNING_STATUS
        return false
      elsif result['status'] == ERROR_STATUS
        url = URI.parse( result['callbackUrl'] )
        r = @connection.csreq( 'GET', url.host, url.path + '?showDetails=true', url.port, url.scheme )
        raise CloudServers::Exception::JobFailure.new( CloudServers::Exception.from_job_result( r.response ), r.response.body )
      elsif result['status'] == COMPLETED_STATUS
        url = URI.parse( result['callbackUrl'] )
        r = @connection.csreq( 'GET', url.host, url.path + '?showDetails=true', url.port, url.scheme )
        @last_response = r
        @successful = true
        return true
      else
        raise result.inspect
      end
    else r.code =~ /20./
      @last_response = r
      return true
    end
  end
end
