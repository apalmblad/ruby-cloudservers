class CloudServers::AsynchronousJob
  attr_reader :last_response
  def initialize( connection, job_id, call_back )
    @connection = connection
    @job_id = job_id
    @call_back = URI.parse( call_back )
  end

  def self.from_json( conn, json )
    data = JSON.parse( json )
    #result = data['asyncResponse']
    result = data
    new( conn, result['jobId'], result['callbackUrl'] )
  end

  def done?
    r = @connection.csreq( 'GET', @call_back.host, @call_back.path + ".json", @call_back.port, @call_back.scheme )
    if r.code.to_i == 202
      return false
    else r.code =~ /20./
      @last_response = r
      return true
    end
  end
end
